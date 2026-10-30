class_name VsRelay
extends Node
## Servidor del modo VS (headless): salas, emparejamiento y reenvío de los mensajes de la partida entre los dos
## jugadores de cada sala. Los clientes solo abren conexiones salientes, así que nadie tiene que abrir puertos.
##
##     godot --headless --path . --script tools/vs_server.gd [-- puerto] [--quiet]   (desde el proyecto)
##     ./poke-tactics-server.x86_64 --headless [-- puerto] [--quiet]                  (build "Linux Server")
##
## La build del preset "Linux Server" lleva la etiqueta `dedicated_server` y arranca en scenes/vs_server.tscn.
##
## - Saluda con las mismas reglas que un anfitrión (versión del protocolo y datos del juego) y da un token.
## - Salas: lista pública, privadas con código y emparejamiento rápido (entra en la primera pública que espera o
##   crea una). El que crea la sala es el lado 0 (elige el tablero).
## - Reenvía al rival los mensajes de la partida (`Protocol.GAME_TYPES`) sin mirarlos: no simula nada.
## - Si un jugador pierde la conexión en plena partida, guarda su sitio RECONNECT_TIME segundos: vuelve con su
##   token y los dos se reenvían lo que faltaba ("resume"). Si no vuelve, el rival gana por abandono.
## - Límites: clientes, salas, tamaño de paquete (Protocol.decode) y mensajes por segundo.
## Todos los plazos van con el reloj real (Time.get_ticks_msec), no con el delta del bucle.

const MAX_CLIENTS := 256
const MAX_ROOMS := 128
const HANDSHAKE_MS := 8000
const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const CODE_LEN := 5

var _peer := ENetMultiplayerPeer.new()
var _rng := RandomNumberGenerator.new()
## id -> {nick, ok, deadline, room, slot, token, win_start, win_count}
var _clients := {}
## código -> {code, name, public, quick, players: [{id, nick, token, gone_until}, ...]} (id 0 = desconectado)
var _rooms := {}
var _quiet := false


func _ready() -> void:
	_rng.randomize()
	var args := OS.get_cmdline_user_args()
	var port := int(args[0]) if not args.is_empty() else Protocol.DEFAULT_PORT
	_quiet = "--quiet" in args
	# Unas plazas de más para poder decirle "server_full" a quien llegue con el servidor lleno.
	var err := _peer.create_server(port, MAX_CLIENTS + 8)
	if err != OK:
		printerr("vs_server: no se pudo abrir el puerto %d: %s" % [port, error_string(err)])
		get_tree().quit(1)
		return
	_peer.peer_connected.connect(_on_connected)
	_peer.peer_disconnected.connect(_on_disconnected)
	_log("protocolo %d, datos %s, puerto %d" % [Protocol.VERSION, Protocol.data_hash(), port])


func _process(_delta: float) -> void:
	_peer.poll()
	var now := Time.get_ticks_msec()
	for id: int in _clients.keys():
		if not _clients[id].ok and now > _clients[id].deadline:
			_kick(id, "timeout")
	for code: String in _rooms.keys():
		_check_gone(code, now)
	while _peer.get_available_packet_count() > 0:
		var from := _peer.get_packet_peer()
		var msg := Protocol.decode(_peer.get_packet())
		if _clients.has(from) and _clients[from].ok != null and not _flooding(from, now):
			if not msg.is_empty():
				_handle(from, msg)


func _log(text: String) -> void:
	if not _quiet:
		print("vs_server: " + text)


# --- Clientes ------------------------------------------------------------------

func _on_connected(id: int) -> void:
	_clients[id] = {"nick": "", "ok": false, "deadline": Time.get_ticks_msec() + HANDSHAKE_MS, "room": "", "slot": -1,
		"token": "", "win_start": 0, "win_count": 0}
	if _clients.size() > MAX_CLIENTS:
		_kick(id, "server_full")


func _on_disconnected(id: int) -> void:
	if not _clients.has(id):
		return
	var c: Dictionary = _clients[id]
	if not c.room.is_empty():
		_lost(c.room, c.slot)
	_clients.erase(id)
	_log("%d se fue" % id)


## Demasiados mensajes en el último segundo: lo echa.
func _flooding(id: int, now: int) -> bool:
	var c: Dictionary = _clients[id]
	if now - c.win_start > 1000:
		c.win_start = now
		c.win_count = 0
	c.win_count += 1
	if c.win_count > Protocol.RATE_MAX:
		_kick(id, "flood")
		return true
	return false


func _handle(from: int, msg: Dictionary) -> void:
	var c: Dictionary = _clients[from]
	if not c.ok:
		if msg.t == "hello":
			_greet(from, msg)
		return
	match msg.t:
		"lobby_list":
			_put(from, {"t": "lobby_list", "rooms": _room_list(from)})
		"room_create":
			_leave(from)
			_create(from, Protocol.clean_text(str(msg.get("name", "")), Protocol.ROOM_NAME_MAX), msg.get("public", true) == true, false)
		"room_join":
			_leave(from)
			if msg.code.is_empty():
				_quick(from)
			else:
				_join(from, msg.code.to_upper())
		"room_leave":
			_leave(from)
		_:
			if msg.t in Protocol.GAME_TYPES and not c.room.is_empty():
				var other: Dictionary = _rooms[c.room].players[1 - c.slot] if _rooms[c.room].players.size() == 2 else {}
				if other.get("id", 0) != 0:
					_put(other.id, msg)


func _greet(from: int, msg: Dictionary) -> void:
	var c: Dictionary = _clients[from]
	var code := "version" if msg.v != Protocol.VERSION else ("data" if msg.data != Protocol.data_hash() else "")
	if not code.is_empty():
		_log("%d rechazado (%s)" % [from, code])
		_kick(from, code)
		return
	c.ok = true
	c.nick = Protocol.clean_nick(msg.nick)
	# ¿Vuelve a una partida en la que perdió la conexión?
	var token: Variant = msg.get("token")
	if token is String and not token.is_empty():
		for room_code: String in _rooms:
			var players: Array = _rooms[room_code].players
			for slot in players.size():
				if players[slot].token == token:
					_resume(from, room_code, slot)
					return
	c.token = _new_token()
	_put(from, {"t": "welcome", "v": Protocol.VERSION, "data": Protocol.data_hash(), "token": c.token, "resumed": false})
	_log("%d es %s" % [from, c.nick])


## Un jugador vuelve con su token: recupera su sitio y el rival se entera.
func _resume(from: int, code: String, slot: int) -> void:
	var p: Dictionary = _rooms[code].players[slot]
	if p.id != 0 and p.id != from and _clients.has(p.id):
		# La conexión vieja aún no se había dado por perdida: se cierra sin avisar al rival.
		_clients[p.id].room = ""
		_peer.disconnect_peer(p.id, true)
		_clients.erase(p.id)
	p.id = from
	p.gone_until = 0
	var c: Dictionary = _clients[from]
	c.room = code
	c.slot = slot
	c.token = p.token
	_put(from, {"t": "welcome", "v": Protocol.VERSION, "data": Protocol.data_hash(), "token": c.token, "resumed": true})
	var players: Array = _rooms[code].players
	if players.size() == 2 and players[1 - slot].id != 0:
		_put(players[1 - slot].id, {"t": "peer_back"})
	_log("%s vuelve a la sala %s" % [c.nick, code])


func _new_token() -> String:
	var bytes := PackedByteArray()
	for i in 16:
		bytes.append(_rng.randi() & 0xff)
	return bytes.hex_encode()


## Manda el motivo y desconecta cuando el paquete haya salido.
func _kick(id: int, code: String) -> void:
	_put(id, {"t": "reject", "code": code})
	_clients[id].ok = null  # ya no se le escucha
	_clients[id].deadline = 1 << 62
	var p := _peer.get_peer(id)
	if p:
		p.peer_disconnect_later()


func _put(id: int, msg: Dictionary) -> void:
	var p := _peer.get_peer(id)
	if not p or p.get_state() != ENetPacketPeer.STATE_CONNECTED:
		return
	_peer.set_target_peer(id)
	_peer.put_packet(Protocol.encode(msg))


# --- Salas -------------------------------------------------------------------

func _room_list(viewer: int) -> Array:
	var list := []
	for code: String in _rooms:
		var r: Dictionary = _rooms[code]
		if not r.public or r.players.is_empty():
			continue
		var host: Dictionary = r.players[0]
		var ping := -1
		if host.id != 0 and _peer.get_peer(host.id):
			ping = int(_peer.get_peer(host.id).get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
		list.append({"code": code, "name": r.name, "nick": host.nick, "players": r.players.size(), "ping": ping,
			"mine": host.id == viewer})
	return list


func _create(from: int, room_name: String, public: bool, quick: bool) -> void:
	if _rooms.size() >= MAX_ROOMS:
		_put(from, {"t": "lobby_error", "code": "rooms_full"})
		return
	var code := ""
	while code.is_empty() or _rooms.has(code):
		code = ""
		for i in CODE_LEN:
			code += CODE_CHARS[_rng.randi_range(0, CODE_CHARS.length() - 1)]
	var c: Dictionary = _clients[from]
	_rooms[code] = {"code": code, "name": room_name, "public": public, "quick": quick,
		"players": [{"id": from, "nick": c.nick, "token": c.token, "gone_until": 0}]}
	c.room = code
	c.slot = 0
	_put(from, {"t": "room", "code": code, "name": room_name, "public": public})
	_log("%s crea la sala %s (%s)" % [c.nick, code, "pública" if public else "privada"])


func _join(from: int, code: String) -> void:
	if not _rooms.has(code):
		_put(from, {"t": "lobby_error", "code": "not_found"})
		return
	var r: Dictionary = _rooms[code]
	if r.players.size() >= 2:
		_put(from, {"t": "lobby_error", "code": "room_full"})
		return
	var c: Dictionary = _clients[from]
	r.players.append({"id": from, "nick": c.nick, "token": c.token, "gone_until": 0})
	c.room = code
	c.slot = 1
	_put(from, {"t": "room", "code": code, "name": r.name, "public": r.public})
	var host: Dictionary = r.players[0]
	_put(host.id, {"t": "match", "nick": c.nick, "side": 0})
	_put(from, {"t": "match", "nick": host.nick, "side": 1})
	_log("partida en %s: %s contra %s" % [code, host.nick, c.nick])


## Emparejamiento rápido: la primera sala pública que espera rival o, si no hay, una nueva.
func _quick(from: int) -> void:
	for code: String in _rooms:
		var r: Dictionary = _rooms[code]
		if r.public and r.players.size() == 1 and r.players[0].id != 0 and r.players[0].id != from:
			_join(from, code)
			return
	_create(from, "", true, true)


## Sale de su sala a propósito: si había rival, se entera de que se fue.
func _leave(from: int) -> void:
	var c: Dictionary = _clients[from]
	if c.room.is_empty():
		return
	var code: String = c.room
	var r: Dictionary = _rooms[code]
	c.room = ""
	var other: Dictionary = r.players[1 - c.slot] if r.players.size() == 2 else {}
	_rooms.erase(code)
	if other.get("id", 0) != 0 and _clients.has(other.id):
		_clients[other.id].room = ""
		_put(other.id, {"t": "gone", "code": "left"})
	_log("%s sale de la sala %s" % [c.nick, code])


## Un jugador perdió la conexión. Con rival, se le guarda el sitio; sola, la sala se cierra.
func _lost(code: String, slot: int) -> void:
	var r: Dictionary = _rooms[code]
	if r.players.size() < 2:
		_rooms.erase(code)
		return
	var p: Dictionary = r.players[slot]
	p.id = 0
	p.gone_until = Time.get_ticks_msec() + Protocol.RECONNECT_TIME * 1000
	var other: Dictionary = r.players[1 - slot]
	if other.id == 0:
		_rooms.erase(code)
		return
	_put(other.id, {"t": "peer_lost"})
	_log("%s perdió la conexión en %s: se le espera %d s" % [p.nick, code, Protocol.RECONNECT_TIME])


## Sitio guardado que caduca: el rival gana por abandono.
func _check_gone(code: String, now: int) -> void:
	var r: Dictionary = _rooms[code]
	for slot in r.players.size():
		var p: Dictionary = r.players[slot]
		if p.id == 0 and p.gone_until > 0 and now > p.gone_until:
			_rooms.erase(code)
			var other: Dictionary = r.players[1 - slot] if r.players.size() == 2 else {}
			if other.get("id", 0) != 0 and _clients.has(other.id):
				_clients[other.id].room = ""
				_put(other.id, {"t": "gone", "code": "left"})
			_log("%s no volvió a %s" % [p.nick, code])
			return

extends Node
## Autoload "Net": conexión del modo VS con ENet. Tres formas de conectarse y una sola de hablar:
##   - `host(port)`: este PC aloja la partida y el rival se conecta a su IP (LAN o puerto abierto).
##   - `join(ip, port)`: se conecta a un anfitrión.
##   - `join_relay(address, port)`: se conecta al servidor de salas (tools/vs_server.gd), que empareja y reenvía.
## En los tres, `send(msg)` manda un mensaje al rival (o al servidor, los de salas) y `message` entrega los
## suyos: el resto del juego no sabe qué modo está activo. Los mensajes son los de `Protocol`.
##
## Los mensajes de la partida van numerados ("n"): si con el servidor se pierde la conexión en plena partida,
## Net vuelve a conectarse solo con su token durante Protocol.RECONNECT_TIME segundos y los dos lados se
## reenvían lo que el otro no llegó a recibir ("resume"). Los repetidos se descartan.

## Saludo aceptado por el otro lado (anfitrión, invitado o servidor).
signal connected
## Ya hay rival: `opponent` = {nick, side} y `side` es el lado propio (0 = anfitrión, 1 = invitado).
signal opponent_found
## Mensaje del rival o del servidor (ya validado por `Protocol.decode`).
signal message(msg: Dictionary)
## El rival se fue o se perdió su conexión (código para `Protocol.reason_text`).
signal opponent_left(code: String)
## No se pudo conectar, el saludo fue rechazado o se cayó la conexión: la red queda cerrada.
signal failed(code: String)
## Se cayó la conexión con el servidor en plena partida y Net intenta volver / ha vuelto.
signal reconnecting
signal reconnected
## El rival perdió la conexión y el servidor le espera / ha vuelto.
signal opponent_paused
signal opponent_back

enum Mode { OFF, HOST, JOIN, RELAY }

## Segundos para completar el saludo antes de rendirse.
const HANDSHAKE_TIMEOUT := 8.0
## Milisegundos entre intentos de reconexión.
const RETRY_MS := 3000
## Milisegundos que close() espera, como mucho, a que salgan los últimos mensajes.
const GOODBYE_MS := 300

var mode := Mode.OFF
var nick := ""
var side := -1
## Rival actual: {nick, side}; vacío si no hay.
var opponent := {}
## Sala del servidor en la que estás: {code, name, public}; vacío si no hay.
var room := {}

var _peer: ENetMultiplayerPeer
## Id ENet del otro extremo: el invitado (para el anfitrión) o 1 (el anfitrión o el servidor, para un cliente).
var _remote := 0
var _accepted := false
var _was_connected := false
## Instante (ms, tiempo real) en que se agota el saludo pendiente: no depende de Engine.time_scale ni de --fixed-fps.
var _deadline := 0
## Altas y bajas de ENet de este fotograma: se atienden después de `poll()`, porque cerrar el peer desde una
## señal emitida dentro de `poll()` tumba el motor.
var _events: Array[Array] = []
## Mensajes que llegaron sin nadie escuchando `message` (entre dos escenas): se entregan al conectarse alguien.
var _held: Array[Dictionary] = []
var _address := ""
var _port := 0
## Token del servidor para recuperar el sitio tras perder la conexión.
var _token := ""
## Numeración de los mensajes de la partida: último enviado, último recibido y los enviados (para reenviarlos).
var _send_seq := 0
var _recv_seq := 0
var _sent_log: Array[Dictionary] = []
## Reconectando: hasta cuándo se intenta (0 = no) y cuándo toca el siguiente intento.
var _reconnect_until := 0
var _retry_at := 0


func _ready() -> void:
	# La red sigue viva con el menú de pausa abierto (el rival no se para).
	process_mode = Node.PROCESS_MODE_ALWAYS


## Aloja una partida directa en `port`; espera a un solo rival.
func host(port := Protocol.DEFAULT_PORT) -> Error:
	return _open(Mode.HOST, "", port)


## Se conecta a un anfitrión por IP.
func join(ip: String, port := Protocol.DEFAULT_PORT) -> Error:
	return _open(Mode.JOIN, ip, port)


## Se conecta al servidor de salas; el rival llega cuando el servidor empareja.
func join_relay(address: String, port := Protocol.DEFAULT_PORT) -> Error:
	return _open(Mode.RELAY, address, port)


## Manda un mensaje al rival (o al servidor, si es de salas). Los de la partida se numeran y se guardan, para
## reenviarlos si el rival no los recibió; sin conexión aceptada, solo se guardan.
func send(msg: Dictionary) -> void:
	if msg.t in Protocol.GAME_TYPES and msg.t != "resume":
		msg = msg.duplicate()
		_send_seq += 1
		msg.n = _send_seq
		_sent_log.append(msg)
	if not _accepted or _remote == 0:
		return
	_put(_remote, msg)


## Cierra la conexión sin avisar con señales. En el servidor, sale antes de su sala (el rival se entera ya,
## sin esperar a una reconexión).
func close() -> void:
	var p := _peer
	_peer = null  # antes de cerrar: las señales que lleguen mientras tanto se ignoran
	if p:
		if mode == Mode.RELAY and _accepted and not room.is_empty():
			p.set_target_peer(1)
			p.put_packet(Protocol.encode({"t": "room_leave"}))
		_say_goodbye(p)
	mode = Mode.OFF
	side = -1
	opponent = {}
	room = {}
	_remote = 0
	_accepted = false
	_was_connected = false
	_held.clear()
	_token = ""
	_reset_seq()
	_reconnect_until = 0


## Desconexión ordenada: lo último que se mandó (salir de la sala, rendición, aviso de desincronización...)
## sale antes de cortar. Espera como mucho GOODBYE_MS.
func _say_goodbye(p: ENetMultiplayerPeer) -> void:
	if p.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and _remote != 0 and p.get_peer(_remote):
		p.get_peer(_remote).peer_disconnect_later()
		var until := Time.get_ticks_msec() + GOODBYE_MS
		while Time.get_ticks_msec() < until and p.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED \
				and p.get_peer(_remote) and p.get_peer(_remote).get_state() != ENetPacketPeer.STATE_DISCONNECTED:
			p.poll()
			OS.delay_msec(5)
	p.close()


## Sale de la sala del servidor (sin desconectarse): vuelve al vestíbulo.
func leave_room() -> void:
	if mode == Mode.RELAY and _accepted and not room.is_empty():
		_put(_remote, {"t": "room_leave"})
	room = {}
	opponent = {}
	side = -1


func is_online() -> bool:
	return mode != Mode.OFF


## Saludo aceptado por el anfitrión o el servidor.
func is_accepted() -> bool:
	return _accepted


func is_reconnecting() -> bool:
	return _reconnect_until > 0


## Tiempo de ida y vuelta con el otro extremo, en ms (-1 si no hay conexión).
func rtt() -> int:
	if not _peer or _remote == 0:
		return -1
	var p := _peer.get_peer(_remote)
	return int(p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)) if p else -1


func _open(new_mode: Mode, address: String, port: int) -> Error:
	close()
	nick = Protocol.clean_nick(nick)
	_address = address
	_port = port
	var err := _new_peer(new_mode)
	if err != OK:
		return err
	mode = new_mode
	_deadline = Time.get_ticks_msec() + int(HANDSHAKE_TIMEOUT * 1000.0)
	# Calcula ya la huella de los datos para no frenar el saludo.
	Protocol.data_hash()
	return OK


func _new_peer(new_mode: Mode) -> Error:
	_peer = ENetMultiplayerPeer.new()
	# Dos plazas: la segunda solo sirve para decirle a un tercero que la partida está llena.
	var err := _peer.create_server(_port, 2) if new_mode == Mode.HOST else _peer.create_client(_address, _port)
	if err != OK:
		_peer = null
		return err
	_peer.peer_connected.connect(func(id: int) -> void: _events.append([true, id]))
	_peer.peer_disconnected.connect(func(id: int) -> void: _events.append([false, id]))
	return OK


func _reset_seq() -> void:
	_send_seq = 0
	_recv_seq = 0
	_sent_log.clear()


func _process(_delta: float) -> void:
	if not _held.is_empty() and not message.get_connections().is_empty():
		var held := _held.duplicate()
		_held.clear()
		for msg in held:
			message.emit(msg)
	if _reconnect_until > 0 and not _retry():
		return
	if not _peer:
		return
	_events.clear()
	if _peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
		_peer.poll()
	for ev in _events:
		if not _peer:  # alguien cerró al atender un evento
			return
		if ev[0]:
			_on_peer_connected(ev[1])
		else:
			_on_peer_disconnected(ev[1])
	if not _peer:
		return
	if mode != Mode.HOST and _reconnect_until == 0 and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		_lost_link()
		return
	if not _accepted and _reconnect_until == 0 and (mode != Mode.HOST or _remote != 0):
		if Time.get_ticks_msec() > _deadline:
			if mode == Mode.HOST:  # el anfitrión despide al que no saluda y sigue esperando
				_reject(_remote, "timeout")
				_remote = 0
			else:
				# Sin respuesta de ENet no hay nadie en esa dirección; con ella, el otro no completó el saludo.
				_fail("timeout" if _was_connected else "unreachable")
				return
	while _peer and _peer.get_available_packet_count() > 0:
		var from := _peer.get_packet_peer()
		var msg := Protocol.decode(_peer.get_packet())
		if not msg.is_empty():
			_handle(from, msg)


## Reconectando: rinde la partida si se pasa el plazo y abre una conexión nueva cada RETRY_MS. Devuelve false
## si la red quedó cerrada.
func _retry() -> bool:
	var now := Time.get_ticks_msec()
	if now > _reconnect_until:
		_fail("lost")
		return false
	if now >= _retry_at and (not _peer or _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED):
		if _peer:
			_peer.close()
		_retry_at = now + RETRY_MS
		_new_peer(Mode.RELAY)
	return true


## Se cayó la conexión con el otro extremo. Con el servidor y en plena partida se intenta volver; si no, falla.
func _lost_link() -> void:
	if mode == Mode.RELAY and _accepted and not opponent.is_empty() and not _token.is_empty():
		var p := _peer
		_peer = null
		p.close()
		_accepted = false
		_remote = 0
		_reconnect_until = Time.get_ticks_msec() + Protocol.RECONNECT_TIME * 1000
		_retry_at = 0
		reconnecting.emit()
		return
	if mode == Mode.JOIN and _accepted and not opponent.is_empty():
		_fail("left")  # partida directa: el anfitrión se fue (o se cortó su conexión)
		return
	_fail("lost" if _accepted or _was_connected else "unreachable")


func _handle(from: int, msg: Dictionary) -> void:
	# El anfitrión solo escucha al invitado aceptado (o al que está saludando).
	if mode == Mode.HOST and _remote != 0 and from != _remote:
		return
	match msg.t:
		"hello":
			if mode == Mode.HOST and not _accepted:
				_greet(from, msg)
		"welcome":
			if mode != Mode.HOST and not _accepted:
				_welcomed(msg)
		"reject":
			_fail(msg.code)
		"match":
			if mode != Mode.HOST and _accepted:
				_reset_seq()
				side = clampi(msg.side, 0, 1)
				opponent = {"nick": Protocol.clean_nick(msg.nick), "side": 1 - side}
				opponent_found.emit()
		"gone":
			if mode == Mode.RELAY:
				opponent = {}
				room = {}
				opponent_left.emit(msg.code)
		"peer_lost":
			opponent_paused.emit()
		"peer_back":
			_put(_remote, {"t": "resume", "got": _recv_seq})
			opponent_back.emit()
		"resume":
			# El rival tiene hasta "got": se le reenvía lo siguiente.
			for sent in _sent_log:
				if sent.n > msg.got:
					_put(_remote, sent)
		_:
			if not _accepted:
				return
			if msg.t == "room":
				room = {"code": msg.code, "name": str(msg.get("name", "")), "public": msg.get("public", true) == true}
			if msg.get("n") is int:
				if msg.n <= _recv_seq:
					return  # repetido tras una reconexión
				_recv_seq = msg.n
			if message.get_connections().is_empty():
				_held.append(msg)
			else:
				message.emit(msg)


func _welcomed(msg: Dictionary) -> void:
	var code := _check(msg)
	if not code.is_empty():
		_fail(code)
		return
	if _reconnect_until > 0:
		if msg.get("resumed") != true:
			_fail("lost")  # el sitio ya no estaba guardado
			return
		_accepted = true
		_reconnect_until = 0
		_put(_remote, {"t": "resume", "got": _recv_seq})
		reconnected.emit()
		return
	_accepted = true
	_token = str(msg.get("token", ""))
	connected.emit()


## Saludo de un invitado al anfitrión: se acepta si la versión y los datos coinciden.
func _greet(from: int, msg: Dictionary) -> void:
	var code := _check(msg)
	if not code.is_empty():
		_reject(from, code)
		_remote = 0
		return
	_remote = from
	_accepted = true
	_reset_seq()
	_put(from, {"t": "welcome", "v": Protocol.VERSION, "data": Protocol.data_hash()})
	_put(from, {"t": "match", "nick": nick, "side": 1})
	side = 0
	opponent = {"nick": Protocol.clean_nick(msg.nick), "side": 1}
	connected.emit()
	opponent_found.emit()


## Código de rechazo si la versión o los datos del otro no coinciden; "" si todo cuadra.
func _check(msg: Dictionary) -> String:
	if msg.v != Protocol.VERSION:
		return "version"
	if msg.data != Protocol.data_hash():
		return "data"
	return ""


func _on_peer_connected(id: int) -> void:
	if mode == Mode.HOST:
		if _remote != 0:
			_reject(id, "full")
			return
		_remote = id
		_deadline = Time.get_ticks_msec() + int(HANDSHAKE_TIMEOUT * 1000.0)
	else:
		_was_connected = true
		_remote = 1
		var hello := {"t": "hello", "v": Protocol.VERSION, "data": Protocol.data_hash(), "nick": nick}
		if _reconnect_until > 0:
			hello.token = _token
		_put(1, hello)


func _on_peer_disconnected(id: int) -> void:
	if not _peer:
		return
	if mode == Mode.HOST:
		if id != _remote:
			return
		var had := _accepted
		_remote = 0
		_accepted = false
		opponent = {}
		side = -1
		if had:
			opponent_left.emit("left")
	elif id == 1 and _reconnect_until == 0:
		_lost_link()


## Rechaza a un peer: le manda el motivo y lo desconecta cuando el paquete haya salido.
func _reject(id: int, code: String) -> void:
	_put(id, {"t": "reject", "code": code})
	var p := _peer.get_peer(id)
	if p:
		p.peer_disconnect_later()


func _put(id: int, msg: Dictionary) -> void:
	_peer.set_target_peer(id)
	_peer.put_packet(Protocol.encode(msg))


func _fail(code: String) -> void:
	var had_opponent := not opponent.is_empty()
	close()
	if had_opponent and code in ["lost", "left"]:
		opponent_left.emit(code)
	failed.emit(code)

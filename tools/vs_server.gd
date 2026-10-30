extends SceneTree
## Servidor del modo VS (headless): saluda a los clientes con las mismas reglas que un anfitrión (versión y
## datos), los empareja y reenvía al rival los mensajes de la partida (`Protocol.GAME_TYPES`) sin mirarlos.
## Los clientes solo abren conexiones salientes, así que nadie tiene que abrir puertos en su router.
##
##     godot --headless --path . --script tools/vs_server.gd [-- puerto]
##
## De momento empareja por orden de llegada; las salas y los límites llegan en la fase F4.

const MAX_CLIENTS := 64
const HANDSHAKE_TIMEOUT := 8.0

var _peer := ENetMultiplayerPeer.new()
## Clientes conectados: id -> {nick, ok (saludo aceptado), wait (segundos para saludar), rival (id o 0)}.
var _clients := {}
## Clientes aceptados esperando rival, en orden de llegada.
var _queue: Array[int] = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var port := int(args[0]) if not args.is_empty() else Protocol.DEFAULT_PORT
	var err := _peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		printerr("vs_server: no se pudo abrir el puerto %d: %s" % [port, error_string(err)])
		quit(1)
		return
	_peer.peer_connected.connect(_on_connected)
	_peer.peer_disconnected.connect(_on_disconnected)
	print("vs_server: protocolo %d, datos %s, puerto %d" % [Protocol.VERSION, Protocol.data_hash(), port])


func _process(delta: float) -> bool:
	_peer.poll()
	for id: int in _clients.keys():
		var c: Dictionary = _clients[id]
		if not c.ok:
			c.wait -= delta
			if c.wait <= 0.0:
				_kick(id, "timeout")
	while _peer.get_available_packet_count() > 0:
		var from := _peer.get_packet_peer()
		var msg := Protocol.decode(_peer.get_packet())
		if not msg.is_empty() and _clients.has(from):
			_handle(from, msg)
	return false


func _handle(from: int, msg: Dictionary) -> void:
	var c: Dictionary = _clients[from]
	if not c.ok:
		if msg.t != "hello":
			return
		var code := "version" if msg.v != Protocol.VERSION else ("data" if msg.data != Protocol.data_hash() else "")
		if not code.is_empty():
			print("vs_server: %d rechazado (%s)" % [from, code])
			_kick(from, code)
			return
		c.ok = true
		c.nick = Protocol.clean_nick(msg.nick)
		_put(from, {"t": "welcome", "v": Protocol.VERSION, "data": Protocol.data_hash()})
		print("vs_server: %d es %s" % [from, c.nick])
		_queue.append(from)
		_pair()
	elif msg.t in Protocol.GAME_TYPES and c.rival != 0:
		_put(c.rival, msg)


## Empareja a los dos primeros de la cola: el primero en llegar hace de anfitrión (lado 0).
func _pair() -> void:
	while _queue.size() >= 2:
		var a: int = _queue.pop_front()
		var b: int = _queue.pop_front()
		_clients[a].rival = b
		_clients[b].rival = a
		_put(a, {"t": "match", "nick": _clients[b].nick, "side": 0})
		_put(b, {"t": "match", "nick": _clients[a].nick, "side": 1})
		print("vs_server: partida %s contra %s" % [_clients[a].nick, _clients[b].nick])


func _on_connected(id: int) -> void:
	_clients[id] = {"nick": "", "ok": false, "wait": HANDSHAKE_TIMEOUT, "rival": 0}


func _on_disconnected(id: int) -> void:
	if not _clients.has(id):
		return
	var rival: int = _clients[id].rival
	if rival != 0 and _clients.has(rival):
		_clients[rival].rival = 0
		_put(rival, {"t": "gone", "code": "left"})
	_clients.erase(id)
	_queue.erase(id)
	print("vs_server: %d se fue" % id)


## Manda el motivo y desconecta cuando el paquete haya salido.
func _kick(id: int, code: String) -> void:
	_put(id, {"t": "reject", "code": code})
	_clients[id].wait = INF
	var p := _peer.get_peer(id)
	if p:
		p.peer_disconnect_later()


func _put(id: int, msg: Dictionary) -> void:
	_peer.set_target_peer(id)
	_peer.put_packet(Protocol.encode(msg))

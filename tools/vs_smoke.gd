extends SceneTree
## Banco de pruebas de red del modo VS: un proceso aloja y otro se conecta por ENet; el cliente manda PINGS
## pings y mide el tiempo de ida y vuelta. Sin escenas ni autoloads del juego (no toca el guardado).
##
##     godot --headless --path . --script tools/vs_smoke.gd -- host [puerto]
##     godot --headless --path . --script tools/vs_smoke.gd -- join [ip] [puerto]
##
## Sale con código 0 si todos los pings vuelven, 1 si algo falla o pasa TIMEOUT segundos.

const PORT := 24680
const PINGS := 10
const TIMEOUT := 10.0

var _peer := ENetMultiplayerPeer.new()
var _host := false
var _sent := {}  # número de ping -> instante de envío (µs)
var _rtts: Array[float] = []
var _left := TIMEOUT
var _next := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_host = args.is_empty() or args[0] == "host"
	var err: Error
	if _host:
		var port := int(args[1]) if args.size() > 1 else PORT
		err = _peer.create_server(port, 1)
		print("[host] escuchando en el puerto %d" % port)
	else:
		var ip: String = args[1] if args.size() > 1 else "127.0.0.1"
		var port := int(args[2]) if args.size() > 2 else PORT
		err = _peer.create_client(ip, port)
		print("[join] conectando a %s:%d" % [ip, port])
	if err != OK:
		printerr("ENet no pudo arrancar: %s" % error_string(err))
		quit(1)
		return
	_peer.peer_connected.connect(func(id: int) -> void: print("[%s] conectado con %d" % [_tag(), id]))
	_peer.peer_disconnected.connect(_on_gone)


func _tag() -> String:
	return "host" if _host else "join"


func _process(delta: float) -> bool:
	_peer.poll()
	_left -= delta
	if _left <= 0.0:
		printerr("[%s] tiempo agotado (%d/%d pings)" % [_tag(), _rtts.size(), PINGS])
		quit(1)
		return true
	while _peer.get_available_packet_count() > 0:
		var msg: Variant = bytes_to_var(_peer.get_packet())
		if typeof(msg) != TYPE_DICTIONARY:
			continue
		match msg.get("t", ""):
			"ping":  # el anfitrión devuelve el ping tal cual
				_send({"t": "pong", "n": msg.n})
			"pong":
				_rtts.append((Time.get_ticks_usec() - _sent[msg.n]) / 1000.0)
				print("[join] pong %d: %.2f ms" % [msg.n, _rtts[-1]])
			"bye":
				print("[host] el cliente terminó")
				quit(0)
				return true
	# El cliente manda un ping cada vez que vuelve el anterior.
	if not _host and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		if _rtts.size() == PINGS:
			var avg := 0.0
			for r in _rtts:
				avg += r
			print("[join] RTT medio %.2f ms, mín %.2f, máx %.2f" % [avg / PINGS, _rtts.min(), _rtts.max()])
			_send({"t": "bye"})
			_peer.poll()
			quit(0)
			return true
		if _next == _rtts.size():
			_sent[_next] = Time.get_ticks_usec()
			_send({"t": "ping", "n": _next})
			_next += 1
	return false


func _send(msg: Dictionary) -> void:
	_peer.set_target_peer(MultiplayerPeer.TARGET_PEER_BROADCAST)
	_peer.put_packet(var_to_bytes(msg))


func _on_gone(id: int) -> void:
	# Si el otro se va sin despedirse ("bye"), la prueba falla.
	printerr("[%s] desconectado %d sin terminar" % [_tag(), id])
	quit(1)

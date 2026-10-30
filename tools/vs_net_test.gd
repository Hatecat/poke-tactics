extends SceneTree
## Prueba de consola de la red del modo VS (autoload `Net` y tools/vs_server.gd). Cada rol es un proceso:
##
##     godot --headless --path . --script tools/vs_net_test.gd -- <rol> [dirección] [puerto]
##
## Roles:
##   host           aloja con `Net.host` y devuelve los "intent" que le lleguen
##   join | relay   se conecta (`Net.join` / `Net.join_relay`), manda PINGS intents, mide el RTT y se despide
##   bad-version    saluda con otra versión del protocolo: espera el rechazo "version"
##   bad-data       saluda con otra huella de datos: espera el rechazo "data"
##   unreachable    se conecta a un puerto sin nadie: espera el fallo "unreachable"
##   idle           se conecta a un anfitrión y se queda quieto (para llenar la partida)
##   full           se conecta a un anfitrión que ya tiene rival: espera el rechazo "full"
##
## Sale con 0 si el rol termina como se espera y con 1 si no (o a los TIMEOUT segundos).

const PINGS := 5
const TIMEOUT := 20.0

var _net: Node
var _role := ""
var _left := TIMEOUT
var _sent := {}
var _rtts: Array[float] = []
var _raw: ENetMultiplayerPeer
var _quit_in := -1.0
var _code := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	_net = root.get_node("Net")
	var args := OS.get_cmdline_user_args()
	_role = args[0] if not args.is_empty() else "host"
	var address: String = args[1] if args.size() > 1 else "127.0.0.1"
	var port := int(args[2]) if args.size() > 2 else Protocol.DEFAULT_PORT
	if _role == "host" and args.size() > 1:
		port = int(args[1])
	_net.nick = "Prueba-" + _role
	_net.connected.connect(func() -> void: print("[%s] saludo aceptado (protocolo %d, datos %s)" % [_role, Protocol.VERSION, Protocol.data_hash()]))
	_net.opponent_found.connect(_on_opponent)
	_net.message.connect(_on_message)
	_net.opponent_left.connect(func(code: String) -> void: print("[%s] el rival se fue: %s" % [_role, Protocol.reason_text(code)]))
	_net.failed.connect(_on_failed)
	var err := OK
	match _role:
		"host":
			err = _net.host(port)
			print("[host] alojando en el puerto %d" % port)
		"join", "unreachable", "idle", "full":
			err = _net.join(address, port)
		"relay":
			err = _net.join_relay(address, port)
		"bad-version", "bad-data":
			_raw = ENetMultiplayerPeer.new()
			err = _raw.create_client(address, port)
			_raw.peer_connected.connect(func(_id: int) -> void:
				var bad := _role == "bad-version"
				_raw.put_packet(Protocol.encode({"t": "hello", "nick": "Tramposo", "v": Protocol.VERSION + (1 if bad else 0),
						"data": Protocol.data_hash() if bad else "0000000000000000"})))
	if err != OK:
		printerr("[%s] no se pudo abrir la conexión: %s" % [_role, error_string(err)])
		quit(1)


func _process(delta: float) -> bool:
	if _quit_in >= 0.0:
		_quit_in -= delta
		if _quit_in < 0.0:
			quit(_code)
		return false
	_left -= delta
	if _left <= 0.0:
		printerr("[%s] tiempo agotado" % _role)
		quit(1)
		return true
	if _raw:
		_raw.poll()
		while _raw.get_available_packet_count() > 0:
			var msg := Protocol.decode(_raw.get_packet())
			if msg.get("t") == "reject":
				var want := _role.trim_prefix("bad-")
				print("[%s] rechazado: %s (%s)" % [_role, msg.code, Protocol.reason_text(msg.code)])
				_finish(0 if msg.code == want else 1)
	return false


func _on_opponent() -> void:
	print("[%s] rival: %s, mi lado: %d" % [_role, _net.opponent.nick, _net.side])
	if _net.side == 1 and _role in ["join", "relay"]:
		_ping()


func _ping() -> void:
	var n := _rtts.size()
	_sent[n] = Time.get_ticks_usec()
	_net.send({"t": "intent", "n": n})


func _on_message(msg: Dictionary) -> void:
	match msg.t:
		"intent":
			if msg.get("echo", false):
				_rtts.append((Time.get_ticks_usec() - _sent[msg.n]) / 1000.0)
				if _rtts.size() < PINGS:
					_ping()
				else:
					var avg := 0.0
					for r in _rtts:
						avg += r
					print("[%s] %d intents de ida y vuelta: medio %.1f ms (ENet: %d ms)" % [_role, PINGS, avg / PINGS, _net.rtt()])
					_net.send({"t": "ready"})
					_finish(0)
			else:
				_net.send({"t": "intent", "n": msg.n, "echo": true})
		"ready":
			print("[%s] el rival terminó; RTT ENet %d ms" % [_role, _net.rtt()])
			_finish(0)


func _on_failed(code: String) -> void:
	if _quit_in >= 0.0:
		return
	print("[%s] red cerrada: %s (%s)" % [_role, code, Protocol.reason_text(code)])
	_finish(0 if _role in ["unreachable", "full"] and code == _role else 1)


## Termina tras medio segundo, para que salgan los últimos paquetes.
func _finish(code: int) -> void:
	_code = code
	_quit_in = 0.5

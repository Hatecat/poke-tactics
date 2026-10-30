extends Node
## Autoload "Net": conexión del modo VS con ENet. Tres formas de conectarse y una sola de hablar:
##   - `host(port)`: este PC aloja la partida y el rival se conecta a su IP (LAN o puerto abierto).
##   - `join(ip, port)`: se conecta a un anfitrión.
##   - `join_relay(address, port)`: se conecta al servidor de salas (tools/vs_server.gd), que empareja y reenvía.
## En los tres, `send(msg)` manda un mensaje al rival y `message` entrega los suyos: el resto del juego no sabe
## qué modo está activo. Los mensajes son los de `Protocol`.

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

enum Mode { OFF, HOST, JOIN, RELAY }

## Segundos para completar el saludo antes de rendirse.
const HANDSHAKE_TIMEOUT := 8.0

var mode := Mode.OFF
var nick := ""
var side := -1
## Rival actual: {nick, side}; vacío si no hay.
var opponent := {}

var _peer: ENetMultiplayerPeer
## Id ENet del otro extremo: el invitado (para el anfitrión) o 1 (el anfitrión o el servidor, para un cliente).
var _remote := 0
var _accepted := false
var _was_connected := false
var _wait := 0.0
## Altas y bajas de ENet de este fotograma: se atienden después de `poll()`, porque cerrar el peer desde una
## señal emitida dentro de `poll()` tumba el motor.
var _events: Array[Array] = []


## Aloja una partida directa en `port`; espera a un solo rival.
func host(port := Protocol.DEFAULT_PORT) -> Error:
	return _open(Mode.HOST, "", port)


## Se conecta a un anfitrión por IP.
func join(ip: String, port := Protocol.DEFAULT_PORT) -> Error:
	return _open(Mode.JOIN, ip, port)


## Se conecta al servidor de salas; el rival llega cuando el servidor empareja.
func join_relay(address: String, port := Protocol.DEFAULT_PORT) -> Error:
	return _open(Mode.RELAY, address, port)


## Manda un mensaje al rival (o al servidor, si es de salas). No hace nada sin conexión aceptada.
func send(msg: Dictionary) -> void:
	if not _accepted or _remote == 0:
		return
	_put(_remote, msg)


## Cierra la conexión sin avisar con señales.
func close() -> void:
	var p := _peer
	_peer = null  # antes de cerrar: las señales que lleguen mientras tanto se ignoran
	if p:
		p.close()
	mode = Mode.OFF
	side = -1
	opponent = {}
	_remote = 0
	_accepted = false
	_was_connected = false


func is_online() -> bool:
	return mode != Mode.OFF


## Tiempo de ida y vuelta con el otro extremo, en ms (-1 si no hay conexión).
func rtt() -> int:
	if not _peer or _remote == 0:
		return -1
	var p := _peer.get_peer(_remote)
	return int(p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)) if p else -1


func _open(new_mode: Mode, address: String, port: int) -> Error:
	close()
	nick = Protocol.clean_nick(nick)
	_peer = ENetMultiplayerPeer.new()
	# Dos plazas: la segunda solo sirve para decirle a un tercero que la partida está llena.
	var err := _peer.create_server(port, 2) if new_mode == Mode.HOST else _peer.create_client(address, port)
	if err != OK:
		_peer = null
		return err
	_peer.peer_connected.connect(func(id: int) -> void: _events.append([true, id]))
	_peer.peer_disconnected.connect(func(id: int) -> void: _events.append([false, id]))
	mode = new_mode
	_wait = HANDSHAKE_TIMEOUT
	# Calcula ya la huella de los datos para no frenar el saludo.
	Protocol.data_hash()
	return OK


func _process(delta: float) -> void:
	if not _peer:
		return
	_events.clear()
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
	if mode != Mode.HOST and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		_fail("lost" if _was_connected else "unreachable")
		return
	if not _accepted and (mode != Mode.HOST or _remote != 0):
		_wait -= delta
		if _wait <= 0.0:
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
				var code := _check(msg)
				if not code.is_empty():
					_fail(code)
					return
				_accepted = true
				connected.emit()
		"reject":
			_fail(msg.code)
		"match":
			if mode != Mode.HOST and _accepted:
				side = clampi(msg.side, 0, 1)
				opponent = {"nick": Protocol.clean_nick(msg.nick), "side": 1 - side}
				opponent_found.emit()
		"gone":
			if mode == Mode.RELAY:
				opponent = {}
				opponent_left.emit(msg.code)
		_:
			if _accepted:
				message.emit(msg)


## Saludo de un invitado al anfitrión: se acepta si la versión y los datos coinciden.
func _greet(from: int, msg: Dictionary) -> void:
	var code := _check(msg)
	if not code.is_empty():
		_reject(from, code)
		_remote = 0
		return
	_remote = from
	_accepted = true
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
		_wait = HANDSHAKE_TIMEOUT
	else:
		_was_connected = true
		_remote = 1
		_put(1, {"t": "hello", "v": Protocol.VERSION, "data": Protocol.data_hash(), "nick": nick})


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
	elif id == 1:
		_fail("lost" if _accepted else "unreachable")


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
	if had_opponent and code == "lost":
		opponent_left.emit(code)
	failed.emit(code)

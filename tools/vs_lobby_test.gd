extends SceneTree
## Prueba del servidor de salas (tools/vs_server.gd, que debe estar escuchando) con varios clientes `Net` en
## este mismo proceso: salas privadas y públicas, lista, unirse por código, errores, emparejamiento rápido,
## reconexión en plena partida (con los mensajes del corte reenviados una sola vez y en orden) y abandono.
##
##     godot --headless --path . --script tools/vs_lobby_test.gd [-- puerto]
##
## Sale con 0 si todo va bien. tools/vs_smoke.sh la lanza contra un servidor propio.

const STEP_MS := 8000

var _port := Protocol.DEFAULT_PORT
var _fails := 0
var _net_script: GDScript
## Por cliente: mensajes recibidos y señales vistas.
var _inbox := {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	_port = int(args[0]) if not args.is_empty() else Protocol.DEFAULT_PORT
	_net_script = load("res://scripts/net/net.gd")
	await _rooms()
	await _reconnect()
	print("vs_lobby_test: %s" % ("OK" if _fails == 0 else "%d fallos" % _fails))
	quit(0 if _fails == 0 else 1)


func _client(name: String) -> Node:
	var n: Node = _net_script.new()
	n.name = name
	root.add_child(n)
	n.nick = name
	_inbox[n] = []
	n.message.connect(func(m: Dictionary) -> void: _inbox[n].append(m))
	for sig in ["connected", "opponent_found", "reconnecting", "reconnected", "opponent_paused", "opponent_back"]:
		n.connect(sig, func() -> void: _inbox[n].append({"t": "@" + sig}))
	n.opponent_left.connect(func(code: String) -> void: _inbox[n].append({"t": "@opponent_left", "code": code}))
	n.failed.connect(func(code: String) -> void: _inbox[n].append({"t": "@failed", "code": code}))
	n.join_relay("127.0.0.1", _port)
	return n


## Espera hasta que `n` reciba un mensaje del tipo `t` (o señal "@nombre") y lo devuelve ({} si no llega).
func _wait_for(n: Node, t: String, ms := STEP_MS) -> Dictionary:
	var until := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < until:
		for i in _inbox[n].size():
			if _inbox[n][i].t == t:
				var m: Dictionary = _inbox[n][i]
				_inbox[n].remove_at(i)
				return m
		await process_frame
	return {}


func _check(ok: bool, what: String) -> void:
	print(("OK    " if ok else "FALLO ") + what)
	if not ok:
		_fails += 1


func _rooms() -> void:
	var a := _client("Ana")
	var b := _client("Bea")
	var c := _client("Ciro")
	for n in [a, b, c]:
		_check(not (await _wait_for(n, "@connected")).is_empty(), "%s conecta con el servidor" % n.nick)
	# Sala privada: no sale en la lista y se entra con su código.
	a.send({"t": "room_create", "name": "Privada de Ana", "public": false})
	var room: Dictionary = await _wait_for(a, "room")
	_check(room.get("code", "").length() == 5 and a.room.get("public") == false, "Ana crea una sala privada (%s)" % room.get("code", "?"))
	c.send({"t": "lobby_list"})
	var list: Dictionary = await _wait_for(c, "lobby_list")
	_check(list.has("rooms") and not list.rooms.any(func(r: Dictionary) -> bool: return r.code == room.get("code")), "la sala privada no sale en la lista")
	c.send({"t": "room_join", "code": "ZZZZZ"})
	_check((await _wait_for(c, "lobby_error")).get("code") == "not_found", "código que no existe: not_found")
	b.send({"t": "room_join", "code": room.get("code", "").to_lower()})
	_check(not (await _wait_for(b, "@opponent_found")).is_empty() and b.opponent.get("nick") == "Ana" and b.side == 1, "Bea entra con el código (en minúsculas) y su rival es Ana")
	_check(not (await _wait_for(a, "@opponent_found")).is_empty() and a.opponent.get("nick") == "Bea" and a.side == 0, "Ana tiene a Bea de rival y es el lado 0")
	c.send({"t": "room_join", "code": room.get("code", "")})
	_check((await _wait_for(c, "lobby_error")).get("code") == "room_full", "un tercero no cabe: room_full")
	# Los mensajes de la partida van y vienen por el servidor.
	a.send({"t": "intent", "a": {"kind": "wait"}, "d": 1})
	var got: Dictionary = await _wait_for(b, "intent")
	_check(got.get("n") == 1 and got.get("a", {}).get("kind") == "wait", "un intent de Ana llega a Bea con su número")
	# Sala pública y emparejamiento rápido.
	var d := _client("Dani")
	await _wait_for(d, "@connected")
	c.send({"t": "room_create", "name": "Pública de Ciro", "public": true})
	var pub: Dictionary = await _wait_for(c, "room")
	d.send({"t": "lobby_list"})
	list = await _wait_for(d, "lobby_list")
	var listed: Array = list.get("rooms", []).filter(func(r: Dictionary) -> bool: return r.code == pub.get("code"))
	_check(listed.size() == 1 and listed[0].name == "Pública de Ciro" and listed[0].nick == "Ciro" and listed[0].players == 1, "la sala pública sale en la lista con nombre y anfitrión")
	d.send({"t": "room_join", "code": ""})
	_check(not (await _wait_for(d, "@opponent_found")).is_empty() and d.opponent.get("nick") == "Ciro", "emparejamiento rápido: Dani entra en la sala de Ciro")
	# Abandono: Ciro sale y Dani se entera ya.
	c.close()
	_check((await _wait_for(d, "@opponent_left")).get("code") == "left", "Ciro sale: a Dani le llega que se fue")
	var e := _client("Eva")
	await _wait_for(e, "@connected")
	e.send({"t": "room_join", "code": ""})
	var quick: Dictionary = await _wait_for(e, "room")
	_check(not quick.is_empty() and e.opponent.is_empty(), "emparejamiento rápido sin salas libres: Eva crea una y espera")
	for n in [a, b, d, e]:
		n.close()
		n.queue_free()
	c.queue_free()
	await process_frame


## Ana y Bea en partida; a Ana se le corta la conexión de golpe mientras los dos siguen mandando mensajes.
func _reconnect() -> void:
	var a := _client("Ana2")
	var b := _client("Bea2")
	await _wait_for(a, "@connected")
	await _wait_for(b, "@connected")
	a.send({"t": "room_create", "name": "", "public": false})
	var room: Dictionary = await _wait_for(a, "room")
	b.send({"t": "room_join", "code": room.get("code", "")})
	await _wait_for(a, "@opponent_found")
	await _wait_for(b, "@opponent_found")
	a.send({"t": "intent", "i": 1})
	b.send({"t": "intent", "i": 1})
	await _wait_for(a, "intent")
	await _wait_for(b, "intent")
	# Corte brusco: se cierra el ENet de Ana sin avisar a nadie.
	a._peer.close()
	_check(not (await _wait_for(a, "@reconnecting")).is_empty(), "Ana nota el corte y empieza a reconectar")
	for i in range(2, 6):
		a.send({"t": "intent", "i": i})
		b.send({"t": "intent", "i": i})
	_check(not (await _wait_for(a, "@reconnected", 15000)).is_empty(), "Ana vuelve con su token")
	_check(not (await _wait_for(b, "@opponent_back")).is_empty(), "Bea se entera de que Ana ha vuelto")
	var seen_a := []
	var seen_b := []
	var until := Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < until:
		await process_frame
	for m in _inbox[a]:
		if m.t == "intent":
			seen_a.append(m.i)
	for m in _inbox[b]:
		if m.t == "intent":
			seen_b.append(m.i)
	_check(seen_a == [2, 3, 4, 5], "Ana recibe lo que Bea mandó durante el corte, una vez y en orden (%s)" % [seen_a])
	_check(seen_b == [2, 3, 4, 5], "Bea recibe lo que Ana mandó durante el corte, una vez y en orden (%s)" % [seen_b])
	a.close()
	_check((await _wait_for(b, "@opponent_left")).get("code") == "left", "Ana sale de la sala: Bea gana por abandono")
	b.close()

extends SceneTree
## Partidas VS entre dos procesos por la red, cada uno con su equipo en manos de la IA local (todo lo demás es
## el modo VS de verdad: "ready"/"start" con VsMatch, despliegue con "deploy", intenciones con huella, final y
## revancha). Encadena PARTIDAS revanchas y al final imprime una línea por partida.
##
##     POKE_TACTICS_NO_SAVE=1 godot --headless --fixed-fps 60 --path . --script tools/vs_match_test.gd -- host [partidas] [puerto] [semilla]
##     POKE_TACTICS_NO_SAVE=1 godot --headless --fixed-fps 60 --path . --script tools/vs_match_test.gd -- join [partidas] [puerto] [semilla]
##
## Un quinto argumento cambia lo que hace el invitado en la primera partida, para probar los finales: "abandona"
## (cierra la red en el turno 6), "rinde" (se rinde en el turno 6) o "mal" (usa otra semilla: se desincroniza).
##
## tools/vs_match.sh lanza los dos y compara sus resultados. Sale con 1 si alguna partida se desincroniza, no
## termina o se agota el tiempo.

const TEAM_SIZE := 3
const TIME_SCALE := 8.0
## Segundos reales por partida antes de darla por colgada.
const DEADLINE_PER_GAME := 240.0
## Turnos máximos por partida (si nadie gana antes, se corta y cuenta como fallo).
const MAX_TURNS := 150
## Segundos reales que se queda conectado al acabar, para que el rival termine su última partida.
const FINAL_WAIT := 15.0

var _game: Node
## VsMatch, cargado en tiempo de ejecución (usa el autoload Game, que no existe al compilar este script).
var _vm: GDScript
var _net: Node
var _role := ""
var _games := 1
var _results: Array[String] = []
var _team_data: Array = []
var _their_team: Variant = null
var _started := false
var _mode := ""


## Plazo en tiempo real (con --fixed-fps los temporizadores de Godot corren mucho más rápido que el reloj).
var _deadline_ms := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	_game = root.get_node("Game")
	_net = root.get_node("Net")
	_vm = load("res://scripts/net/vs_match.gd")
	var args := OS.get_cmdline_user_args()
	_role = args[0]
	_games = int(args[1]) if args.size() > 1 else 3
	var port := int(args[2]) if args.size() > 2 else Protocol.DEFAULT_PORT
	var team_seed := int(args[3]) if args.size() > 3 else 1
	_mode = args[4] if args.size() > 4 and _role == "join" else ""
	_deadline_ms = Time.get_ticks_msec() + int((DEADLINE_PER_GAME * _games + 30.0) * 1000.0)
	# Equipo al azar (distinto para cada lado) y la IA en Normal (la Fácil usa el RNG del combate).
	var rng := RandomNumberGenerator.new()
	rng.seed = team_seed * 2 + (1 if _role == "join" else 0)
	var team: Array[TeamMember] = []
	for i in TEAM_SIZE:
		team.append(TeamMember.random(_game.roster[rng.randi_range(0, _game.roster.size() - 1)], rng))
	_team_data = _vm.team_data(team)
	_game.difficulty = 1
	_game.battle_speed = _game.BATTLE_SPEED_MAX
	_net.nick = "IA-" + _role
	_net.opponent_found.connect(func() -> void:
		print("[%s] rival: %s" % [_role, _net.opponent.nick])
		_net.send({"t": "ready", "team": _team_data}))
	_net.message.connect(_on_message)
	_net.failed.connect(func(code: String) -> void:
		if _results.size() < _games:
			printerr("[%s] red: %s" % [_role, code])
			_finish(1))
	var err: Error = _net.host(port) if _role == "host" else _net.join("127.0.0.1", port)
	if err != OK:
		printerr("[%s] no se pudo abrir la red" % _role)
		_finish(1)
		return
	# Espera a que empiece la primera partida y juega todas.
	while not _started:
		await process_frame
	_net.message.disconnect(_on_message)
	for g in _games:
		var line: String = await _play_one()
		_results.append(line)
		print("[%s] partida %d: %s" % [_role, g + 1, line])
		if line.begins_with("FALLO"):
			_finish(1)
			return
		if g + 1 < _games:
			current_scene._ask_rematch()
			# Espera a que se cargue el combate nuevo.
			var old: Node = current_scene
			while current_scene == old or current_scene == null:
				await process_frame
	print("[%s] RESUMEN %s" % [_role, " | ".join(_results)])
	# El otro puede ir aún por la última animación: se espera a que se vaya él o a FINAL_WAIT segundos.
	var until := Time.get_ticks_msec() + int(FINAL_WAIT * 1000.0)
	while not _net.opponent.is_empty() and Time.get_ticks_msec() < until:
		await process_frame
	_finish(0)


func _on_message(msg: Dictionary) -> void:
	print("[%s] mensaje %s" % [_role, msg.t])
	match msg.t:
		"ready":
			_their_team = msg.team
			if _role == "host":
				var start: Dictionary = _vm.make_start(_team_data, _their_team, randi() % 2, -1, [_net.nick, _net.opponent.nick])
				_net.send(start)
				_begin(start, 0)
		"start":
			if _role == "join":
				_begin(msg, 1)


func _begin(msg: Dictionary, side: int) -> void:
	var why: String = _vm.apply_start(msg, side)
	if _mode == "mal":
		_game.vs.seed += 1
	if not why.is_empty():
		printerr("[%s] start no válido: %s" % [_role, why])
		_finish(1)
		return
	change_scene_to_file("res://scenes/battle.tscn")
	_started = true


## Juega el combate cargado (la IA lleva el equipo propio). Devuelve el resumen o "FALLO ...".
func _play_one() -> String:
	while current_scene == null or not current_scene.has_method("apply_intent"):
		await process_frame
	var b = current_scene
	Engine.time_scale = TIME_SCALE
	b.drivers[0] = b.Driver.AI
	while b.state != b.State.DEPLOY and b._vs_result.is_empty():
		await process_frame
	print("[%s] despliegue (lado %d, semilla %d)" % [_role, _game.vs.side, _game.vs.seed])
	b._finish_deploy()
	var shown := -1
	while b._vs_result.is_empty() and b._turn_count <= MAX_TURNS:
		await process_frame
		if _mode in ["abandona", "rinde"] and b._turn_count >= 6:
			print("[%s] %s en el turno %d" % [_role, _mode, b._turn_count])
			if _mode == "abandona":
				_net.close()
				_finish(0)
				return "abandona"
			b._surrender()
			_mode = ""
		if b._turn_count != shown and b._turn_count % 10 == 0:
			shown = b._turn_count
			print("[%s] turno %d, estado %d, %d intenciones, %d en cola" % [_role, shown, b.state, b.intent_log.size(), b._remote_queue.size()])
	if b._vs_result.is_empty():
		return "FALLO: sin terminar tras %d turnos" % b._turn_count
	if b._vs_result == "desync":
		return "FALLO: desincronizada en el turno %d (%d intenciones)" % [b._turn_count, b.intent_log.size()]
	# El resultado visto desde el anfitrión, para comparar las dos salidas.
	var result: String = b._vs_result
	if _game.vs.side == 1:
		result = {"win": "lose", "lose": "win"}.get(result, result)
	return "gana %s, %d turnos, %d intenciones, huella %d, semilla %d" % [
		{"win": "anfitrión", "lose": "invitado"}.get(result, result), b._turn_count, b.intent_log.size(),
		b.state_digest(), _game.vs.seed]


func _finish(code: int) -> void:
	# Un momento (real) para que salgan los últimos paquetes.
	var until := Time.get_ticks_msec() + 500
	while Time.get_ticks_msec() < until:
		await process_frame
	_net.close()
	quit(code)


func _process(_delta: float) -> bool:
	if _deadline_ms > 0 and Time.get_ticks_msec() > _deadline_ms:
		_deadline_ms = 0
		printerr("[%s] tiempo agotado tras %d partidas" % [_role, _results.size()])
		_finish(1)
	return false

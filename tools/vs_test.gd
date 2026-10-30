extends SceneTree
## Prueba de determinismo del modo VS. Para cada semilla:
##   1. juega una Partida rápida IA contra IA (equipos, bioma, tablero y clima sacados de la semilla) y graba sus
##      intenciones con la huella del estado tras cada una (`battle.intent_log`);
##   2. la repite con la misma semilla y los dos equipos en manos del "jugador", aplicando la lista grabada con
##      `apply_intent` (como hará el rival por red), y compara la huella tras cada intención.
##
##     POKE_TACTICS_NO_SAVE=1 godot --headless --fixed-fps 60 --path . --script tools/vs_test.gd [-- 1,2,3 [turnos [mal]]]
##
## Sale con 0 si todas las semillas se repiten igual y con 1 si alguna intención se rechaza o su huella cambia.
## Con "mal", la repetición usa otra semilla: sirve para ver que el test detecta la desincronización (debe fallar).

const TEAM_SIZE := 3
const MAX_TURNS := 80
## Velocidad del reloj del juego: las animaciones duran menos fotogramas (las reglas no miran el tiempo).
const TIME_SCALE := 8.0
## Segundos reales por semilla antes de darlo por colgado (un error de script no cierra Godot).
const DEADLINE_PER_SEED := 300.0

var _game: Node
var _fails := 0


## Plazo en tiempo real (con --fixed-fps los temporizadores de Godot corren mucho más rápido que el reloj).
var _deadline_ms := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	_game = root.get_node("Game")
	var args := OS.get_cmdline_user_args()
	var seeds: Array = Array(args[0].split(",")).map(func(s: String) -> int: return int(s)) if not args.is_empty() else [1, 2, 3]
	var max_turns := int(args[1]) if args.size() > 1 else MAX_TURNS
	var bad := args.size() > 2 and args[2] == "mal"
	_deadline_ms = Time.get_ticks_msec() + int((DEADLINE_PER_SEED * seeds.size()) * 1000.0)
	for s: int in seeds:
		_setup(s)
		var log: Variant = await _play(s, max_turns, null)
		if not log is Array or log.is_empty():
			print("semilla %d: la partida no grabó ninguna intención" % s)
			_fails += 1
			continue
		var result: Dictionary = await _play(s + 1 if bad else s, max_turns, log)
		print("semilla %d: %d intenciones, %s" % [s, log.size(), result.get("text", "")])
		if not result.get("ok", false):
			_fails += 1
	_game.battle_seed = 0
	print("vs_test: %s" % ("OK" if _fails == 0 else "%d semillas fallan" % _fails))
	quit(0 if _fails == 0 else 1)


## Equipos, bioma, tablero y clima de la semilla `s`.
func _setup(s: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	_game.rng.seed = s
	_game.player_team.clear()
	for i in TEAM_SIZE:
		_game.player_team.append(TeamMember.random(_game.roster[rng.randi_range(0, _game.roster.size() - 1)], rng))
	_game.roll_enemy_team()
	_game.map = null
	_game.mode = "quick"
	_game.biome = Biome.random_kind(rng)
	_game.topology = rng.randi_range(0, 1)
	_game.weather = -1
	_game.difficulty = 1
	_game.battle_speed = _game.BATTLE_SPEED_MAX
	_game.battle_seed = s


## Juega un combate. Sin `replay`, IA contra IA: devuelve la lista grabada. Con `replay`, aplica esas intenciones
## y devuelve {"ok", "text"} con la comparación.
func _play(s: int, max_turns: int, replay: Variant) -> Variant:
	_game.battle_seed = s
	change_scene_to_file("res://scenes/battle.tscn")
	for i in 3:
		await process_frame
	var b = current_scene
	Engine.time_scale = TIME_SCALE
	b.drivers.assign([b.Driver.HUMAN, b.Driver.HUMAN] if replay != null else [b.Driver.AI, b.Driver.AI])
	while b.state != b.State.DEPLOY:
		await process_frame
	b._finish_deploy()
	var next := 0
	var frames := 0
	while b.state != b.State.GAME_OVER and b._turn_count <= max_turns and frames < 60 * 60 * 30:
		await process_frame
		frames += 1
		if replay == null or b.state not in [b.State.MENU, b.State.FACING]:
			continue
		if next >= replay.size():
			break
		var want: Dictionary = replay[next]
		var action := want.duplicate()
		action.erase("digest")
		var ok: bool = await b.apply_intent(action)
		if not ok:
			return {"ok": false, "text": "RECHAZADA la intención %d: %s" % [next, want]}
		var got: Dictionary = b.intent_log[-1]
		if got.digest != want.digest:
			return {"ok": false, "text": "DESINCRONIZADA en la intención %d (%s): %d ≠ %d" % [next, want, got.digest, want.digest]}
		next += 1
	if replay == null:
		return b.intent_log.duplicate(true)
	if next < replay.size():
		return {"ok": false, "text": "solo se aplicaron %d de %d" % [next, replay.size()]}
	return {"ok": true, "text": "repetida igual (%d turnos, %s)" % [b._turn_count, "terminada" if b.state == b.State.GAME_OVER else "cortada"]}


func _process(_delta: float) -> bool:
	if _deadline_ms > 0 and Time.get_ticks_msec() > _deadline_ms:
		_deadline_ms = 0
		printerr("vs_test: tiempo agotado")
		quit(1)
	return false

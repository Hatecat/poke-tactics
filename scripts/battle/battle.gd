extends Node3D
## Controlador de la batalla: monta el tablero, gestiona turnos, input, IA y UI.

enum State { BUSY, DEPLOY, MENU, PICK_MOVE, PICK_TARGET, FACING, GAME_OVER }

## Tamaño de los tableros generados al azar.
const BOARD_SIZE := Vector2i(20, 20)
const COLOR_ACTIVE := Color(1.0, 1.0, 1.0, 0.35)
const COLOR_MOVE := Color(0.3, 0.6, 1.0, 0.5)
const COLOR_RANGE := Color(1.0, 0.75, 0.2, 0.4)
const COLOR_AREA := Color(1.0, 0.2, 0.15, 0.65)
const COLOR_HOVER := Color(1.0, 1.0, 1.0, 0.55)
const STEP_TIME := 0.22
const TURN_PREVIEW := 8
## Puntos que la IA resta a los ataques sobre sí misma (equivale al CT de actuar).
const SELF_MOVE_COST := 12.0
## Alcance de las Poké Balls (Torre).
const BALL_RANGE := 4
const COLOR_BALL_RANGE := Color(1.0, 1.0, 1.0, 0.16)
## Duración de cada sacudida de la Poké Ball.
const BALL_SHAKE_TIME := 0.9
## Fuerza del viento en el terreno según el clima (árboles, hierba y agua).
const WIND := {Weather.Kind.SUN: 0.6, Weather.Kind.RAIN: 1.8, Weather.Kind.SAND: 2.4, Weather.Kind.HAIL: 1.6}
## Color de la Poké Ball de la que salen los Pokémon al empezar el combate.
const POKE_BALL_COLOR := Color(0.85, 0.12, 0.12)
## Fácil: probabilidad de elegir una acción aceptable al azar en vez de la mejor.
const EASY_MISTAKE := 0.35
## Difícil: cuánto pesa el daño que podría recibir en el destino.
const HARD_DANGER_WEIGHT := 0.35
## Valor aproximado para la IA de dejar a un rival con cada estado volátil.
const VOLATILE_VALUE := {"wrapped": 14.0, "vortex": 16.0, "confusion": 18.0, "leechseed": 16.0, "yawn": 14.0, "taunt": 8.0, "nightmare": 12.0, "curse": 22.0}
## Filas de despliegue de cada equipo en tableros aleatorios (jugador abajo, rival arriba).
## Pausa entre golpes de un multigolpe.
const MULTIHIT_DELAY := 0.28
const DEPLOY_ROWS := 4
const COLOR_DEPLOY := Color(0.3, 0.6, 1.0, 0.3)

## Equipos y tablero salen del autoload Game (menú principal / editor de equipo).
var topology: BoardGrid.Topology
var player_team: Array[TeamMember] = []
var enemy_team: Array[TeamMember] = []

var grid: BoardGrid
var units: Array[Unit] = []
var turns := TurnManager.new()
var active: Unit
var moved := false
var acted := false
var state := State.BUSY
var selected_move: MoveData
var hover_cell := Vector2i(-1, -1)
var rng := RandomNumberGenerator.new()

var _reach := {} # celda -> celda anterior (para reconstruir caminos)
var _destinations: Array[Vector2i] = []
var _targets: Array[Vector2i] = []
var _deploy_selected: Unit
var _zones: Array[Dictionary] = [{}, {}] # equipo -> {celda: true}
## Clima de fondo del combate y clima actual (un ataque puede cambiarlo unos turnos).
var base_weather := Weather.Kind.CLEAR
var weather := Weather.Kind.CLEAR
var _weather_turns := 0
var _weather_fx: WeatherFx
var _weather_label: RichTextLabel
var _extra_ct := 0.0
## Estados volátiles, efectos de campo y habilidades (scripts/battle/effects.gd).
var effects: Effects

var _board: BoardView
var _units_root: Node3D
var _cam_rig: CameraRig
var _camera: Camera3D

var _info_label: RichTextLabel
var _move_button: Button
var _wait_button: Button
var _attack_buttons: Array[Button] = []
var _actions_box: VBoxContainer
var _order_box: VBoxContainer
var _log_label: RichTextLabel
var _hint_label: Label
var _banner: Label
var _banner_box: VBoxContainer
var _turn_flash: Label
var _deploy_box: VBoxContainer
var _preview_label: RichTextLabel
var _tile_label: RichTextLabel
var _pause: PauseMenu
var _banner_buttons: HBoxContainer
var _action_separators: Array[Control] = []
## Torre: Balls lanzadas en este combate ({tipo: cantidad}), la que se está apuntando y Pokémon capturados.
var _balls_used := {}
var _ball_kind := "poke"
var _caught: Array[TeamMember] = []
var _throwing := false
var _ball_reach: Array[Vector2i] = []


func _ready() -> void:
	rng.randomize()
	Engine.time_scale = Game.battle_time_scale()
	if _tower():
		# Torre de Batallas: equipo, rivales salvajes, campo y clima los decide el piso.
		topology = Game.tower.topology
		player_team = Game.tower.party.duplicate()
		enemy_team = Game.tower.enemies.duplicate()
	else:
		topology = Game.topology
		player_team = Game.player_team.duplicate()
		if Game.enemy_team.is_empty():
			Game.roll_enemy_team()
		enemy_team = Game.enemy_team.duplicate()
	_cam_rig = CameraRig.new()
	add_child(_cam_rig)
	_camera = _cam_rig.camera
	_weather_fx = WeatherFx.new()
	_weather_fx.follow = _cam_rig
	add_child(_weather_fx)
	_build_ui()
	_board = BoardView.new()
	add_child(_board)
	_units_root = Node3D.new()
	add_child(_units_root)
	_start_battle()


## Fuera del combate, los menús van siempre a velocidad normal.
func _exit_tree() -> void:
	Engine.time_scale = 1.0


# --- Montaje -----------------------------------------------------------------

func _start_battle() -> void:
	for u in units:
		u.queue_free()
	units.clear()
	active = null
	effects = Effects.new(self)
	var map := Game.map
	var zones: Array = []
	if map:
		grid = map.to_grid()
		zones = [map.player_zone, map.enemy_zone]
	else:
		grid = BoardGrid.new(topology, BOARD_SIZE.x, BOARD_SIZE.y)
		zones = [MapData.default_zone(grid.width, grid.height, 0, DEPLOY_ROWS),
			MapData.default_zone(grid.width, grid.height, 1, DEPLOY_ROWS)]
		var clear: Array[Vector2i] = []
		clear.append_array(zones[0])
		clear.append_array(zones[1])
		Biome.generate(grid, Game.tower.biome if _tower() else Game.biome, rng, clear, zones[0], zones[1])
	for team in 2:
		_zones[team] = {}
		for c: Vector2i in zones[team]:
			_zones[team][c] = true
	_reset_environment()
	_board.build(grid)
	if map:
		base_weather = map.weather
	elif _tower():
		base_weather = Game.tower.weather
	elif Game.weather >= 0:
		base_weather = Game.weather
	else:
		base_weather = Weather.roll(grid.biome, rng)
	_set_weather(base_weather, 0)
	effects.refresh_visuals()
	Audio.music(Audio.battle_music(grid.biome))

	var p_anchor := _zone_center(0)
	for i in player_team.size():
		_spawn(player_team[i], 0, p_anchor + Vector2i((i - player_team.size() / 2) * 3, 0))
	if map and not map.enemies.is_empty():
		for e: Dictionary in map.enemies:
			var member := TeamMember.from_dict(e, Game.find_species)
			if member:
				_spawn(member, 1, e.get("cell", _zone_center(1)), false)
	else:
		var e_anchor := _zone_center(1)
		for i in enemy_team.size():
			_spawn(enemy_team[i], 1, e_anchor + Vector2i((i - enemy_team.size() / 2) * 3, 0))
	_banner_box.visible = false
	_log_label.clear()
	var where: String = map.map_name if map else Biome.NAMES[grid.biome]
	_log("%s · tablero %s · %s %s. Coloca a tu equipo en la zona azul." % [where,
		"cuadrado" if grid.topology == BoardGrid.Topology.SQUARE else "hexagonal",
		Weather.ICONS[weather], Weather.NAMES[weather]])
	if _trainer_battle():
		var t: Dictionary = Game.tower.trainer
		_log("[b]¡%s quiere luchar![/b] (%s) Sus Pokémon no se pueden capturar." % [Trainers.full_name(t), Trainers.types_text(t.types)])
		_flash_turn("¡%s quiere luchar!" % Trainers.full_name(t), Color(1.0, 0.8, 0.3) if t.leader else Color(1.0, 0.6, 0.5))
	await _send_out_intro()
	_begin_deploy()


## Al empezar, cada Pokémon sale de su Poké Ball (en todos los modos): primero los rivales y luego los tuyos.
## Los salvajes de la Torre no salen de ninguna bola: ya están ahí, como en los juegos.
func _send_out_intro() -> void:
	state = State.BUSY
	_deploy_box.visible = false
	_actions_box.visible = false
	var wild := _tower() and not _trainer_battle()
	var center := grid.to_world(Vector2i(grid.width / 2, grid.height / 2))
	var teams: Array[Array] = []
	for team in [1, 0]:
		var members := units.filter(func(u: Unit) -> bool: return u.team == team and not (team == 1 and wild))
		for u: Unit in members:
			u.visible = false
		if not members.is_empty():
			teams.append(members)
	for members in teams:
		_focus_camera(grid.to_world(_zone_center(members[0].team)))
		await _wait(0.45)
		for u: Unit in members:
			# La bola llega desde fuera del tablero, por detrás de su bando.
			var away := u.position - center
			away.y = 0.0
			var from := u.position + away.normalized() * 3.0 + Vector3.UP * 2.5
			BallFx.send_out(self, u, POKE_BALL_COLOR, from)
			await _wait(0.3)
		await _wait(1.1)


## Cambia el clima. `turns` = turnos (de cualquier Pokémon) que dura; 0 = permanente.
func _set_weather(kind: Weather.Kind, turns: int) -> void:
	weather = kind
	Combat.weather = effects.effective_weather(kind) if effects else kind
	Audio.ambience(Audio.weather_ambience(Combat.weather))
	if turns > 0:
		Audio.sfx("weather", -4.0)
	_weather_turns = turns
	_weather_fx.apply(kind, self)
	_board.set_wind(WIND.get(kind, 1.0))
	_board.set_rain(kind == Weather.Kind.RAIN)
	_board.set_hail(kind == Weather.Kind.HAIL)
	_refresh_weather_label()


func _refresh_weather_label() -> void:
	if _weather_label == null:
		return
	var left := ""
	if _weather_turns > 0:
		var alive := maxi(1, units.filter(func(u: Unit) -> bool: return u.is_alive()).size())
		left = "  [color=#aaaaaa](~%d rondas)[/color]" % ceili(float(_weather_turns) / alive)
	var shown: String = Weather.NAMES[weather] if Combat.weather == weather else "%s (anulado)" % Weather.NAMES[weather]
	var extra := ""
	if effects:
		var alive := maxi(1, units.filter(func(u: Unit) -> bool: return u.is_alive()).size())
		var summary := effects.field.summary(alive)
		if summary:
			extra = "\n[font_size=14]%s[/font_size]" % summary
		for team in 2:
			if effects.field.tailwind[team] > 0:
				extra += "\n[font_size=14]Viento Afín (%s)[/font_size]" % ("tuyo" if team == 0 else "rival")
	_weather_label.text = "%s %s%s%s" % [Weather.ICONS[weather], shown, left, extra]
	_weather_label.tooltip_text = Weather.effects_text(Combat.weather)


func _reset_environment() -> void:
	for n in ["WorldEnvironment", "Sun"]:
		var old := get_node_or_null(n)
		if old:
			remove_child(old)
			old.queue_free()
	CameraRig.build_environment(self, grid.biome)
	_cam_rig.rotation_step = 90.0 if grid.topology == BoardGrid.Topology.SQUARE else 60.0


## Celda central (aprox.) de la zona de despliegue de un equipo.
func _zone_center(team: int) -> Vector2i:
	var cells: Array = _zones[team].keys()
	if cells.is_empty():
		return Vector2i(grid.width / 2, grid.height - 2 if team == 0 else 1)
	var sum := Vector2.ZERO
	for c: Vector2i in cells:
		sum += Vector2(c)
	sum /= cells.size()
	return Vector2i(roundi(sum.x), roundi(sum.y))


## `in_zone`: buscar el hueco dentro de la zona de despliegue (los rivales fijos de un
## escenario se colocan donde diga el mapa).
func _spawn(member: TeamMember, team: int, near: Vector2i, in_zone := true) -> void:
	var u := Unit.new()
	_units_root.add_child(u)
	u.set_meta("member", member)
	var level: int = member.level if _tower() else (Unit.LEVEL if team == 0 else Game.DIFFICULTY_LEVELS[Game.difficulty])
	u.setup(member, team, level)
	var allowed := _in_zone.bind(team) if in_zone else func(c: Vector2i) -> bool: return true
	_place(u, _find_free_anchor(u, near, allowed))
	u.position = grid.footprint_center(u.footprint)
	u.face_towards(grid.to_world(Vector2i(grid.width / 2, grid.height / 2)))
	u.ct = rng.randf_range(0.0, 20.0)
	u.fainted.connect(func(x: Unit) -> void:
		_log("¡%s se debilitó!" % x.display_name())
		Audio.sfx("faint", -4.0)
		Audio.cry(x.data, 0.7, -6.0))
	u.add_to_group("units")  # la hierba se aparta a su alrededor (BoardView)
	units.append(u)


## Ancla válida más cercana a `near` (por si el terreno o un aliado la bloquean).
## `allowed` filtra celdas (por ejemplo, la zona de despliegue).
func _find_free_anchor(u: Unit, near: Vector2i, allowed: Callable) -> Vector2i:
	var cells := grid.all_cells()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return grid.distance(a, near) < grid.distance(b, near))
	for c in cells:
		if _can_stand(u, c) and grid.footprint(c, u.data.size).all(allowed):
			return c
	return near


func _in_zone(c: Vector2i, team: int) -> bool:
	return _zones[team].has(c)


func _zone_cells(team: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for c in grid.all_cells():
		if _in_zone(c, team):
			cells.append(c)
	return cells


# --- Despliegue --------------------------------------------------------------

func _begin_deploy() -> void:
	state = State.DEPLOY
	_deploy_selected = null
	_actions_box.visible = false
	_deploy_box.visible = true
	UiKit.clear(_order_box)
	_hint_label.text = "Despliegue: clic en uno de tus Pokémon y luego en una casilla de la zona azul"
	_focus_camera(grid.to_world(_zone_center(0)))
	_refresh_deploy()


func _refresh_deploy() -> void:
	_board.clear_highlights()
	_board.highlight(_zone_cells(0), COLOR_DEPLOY)
	if _deploy_selected:
		_board.highlight(_deploy_selected.footprint, COLOR_ACTIVE)
		if _can_deploy(_deploy_selected, hover_cell):
			_board.highlight(grid.footprint(hover_cell, _deploy_selected.data.size), COLOR_HOVER)
	for u in units:
		u.set_active(u == _deploy_selected)


func _can_deploy(u: Unit, anchor: Vector2i) -> bool:
	return _can_stand(u, anchor) and grid.footprint(anchor, u.data.size).all(_in_zone.bind(0))


func _deploy_click(c: Vector2i) -> void:
	var clicked := _unit_at(c)
	if clicked and clicked.team == 0:
		_deploy_selected = clicked if clicked != _deploy_selected else null
		if _deploy_selected:
			Audio.cry(clicked.data, 1.0, -8.0)
	elif _deploy_selected and _can_deploy(_deploy_selected, c):
		Audio.sfx("ui_place", -4.0)
		_place(_deploy_selected, c)
		_deploy_selected.position = grid.footprint_center(_deploy_selected.footprint)
		_deploy_selected = null
	if _deploy_selected:
		_refresh_info(_deploy_selected)
	_refresh_deploy()


func _finish_deploy() -> void:
	if state != State.DEPLOY:
		return
	_deploy_selected = null
	for u in units:
		u.set_active(false)
	_deploy_box.visible = false
	_actions_box.visible = true
	_board.clear_highlights()
	_log("¡Comienza el combate!")
	_next_turn.call_deferred()


func _place(u: Unit, anchor: Vector2i) -> void:
	u.cell = anchor
	u.footprint = grid.footprint(anchor, u.data.size)


## La huella cabe en el tablero, no pisa a otro Pokémon y el suelo es lo bastante llano.
func _can_stand(u: Unit, anchor: Vector2i) -> bool:
	return _fits(u, anchor) and _others_at(u, grid.footprint(anchor, u.data.size)).is_empty()


func _fits(u: Unit, anchor: Vector2i) -> bool:
	var cells := grid.footprint(anchor, u.data.size)
	var lo := 99
	var hi := 0
	var no_water := effects != null and effects.water_blocked(u)
	for c in cells:
		if not grid.is_inside(c) or grid.is_blocked(c):
			return false
		if no_water and grid.tiles.get(c, 0) == Biome.Tile.WATER:
			return false
		lo = mini(lo, grid.get_height(c))
		hi = maxi(hi, grid.get_height(c))
	return hi - lo <= u.data.jump


## Pokémon vivos (distintos de `u`) que ocupan alguna de `cells`.
func _others_at(u: Unit, cells: Array[Vector2i]) -> Array[Unit]:
	var found: Array[Unit] = []
	for c in cells:
		var other := _unit_at(c)
		if other and other != u and other not in found:
			found.append(other)
	return found


# --- Bucle de turnos ---------------------------------------------------------

func _next_turn() -> void:
	state = State.BUSY
	_board.clear_highlights()
	if _check_game_over():
		return
	var previous := active
	if previous:
		previous.set_active(false)
	active = turns.advance(units)
	active.set_active(true)
	if _weather_turns > 0:
		_weather_turns -= 1
		if _weather_turns == 0:
			_log("El %s terminó." % Weather.NAMES[weather].to_lower())
			_set_weather(base_weather, 0)
		_refresh_weather_label()
	var ended := effects.field.tick()
	if not ended.is_empty():
		_log("Terminó: %s." % ", ".join(ended))
		effects.refresh_visuals()
	Combat.weather = effects.effective_weather(weather)
	moved = false
	acted = false
	_extra_ct = 0.0
	_refresh_turn_order()
	_focus_camera(active.position)
	var again := active == previous
	_log("[b]— Turno de %s%s —[/b]" % [active.display_name(), " (otra vez)" if again else ""])
	_flash_turn("¡%s vuelve a actuar!" % active.display_name() if again else "Turno de %s" % active.display_name(),
		Unit.TEAM_COLORS[active.team].lightened(0.4))
	Audio.sfx("turn_player" if active.team == 0 else "turn_enemy", -6.0, 1.0, 0.0)
	Audio.cry(active.data, 1.0, -12.0)
	_refresh_info(active)
	if not await _start_of_turn(active):
		# Aunque pierda el turno (dormido, paralizado...), el veneno y el clima le afectan igual.
		if active.is_alive():
			await _end_of_turn(active)
		turns.end_turn(active, true, true)
		await _wait(0.6)
		_next_turn.call_deferred()
		return
	if active.team == 0:
		_show_menu()
	else:
		_set_actions_enabled(false)
		await _run_ai(active)
		_ai_face(active)
		_end_turn()


## Al empezar el turno: lo que decide si puede actuar (sueño, congelación, parálisis,
## confusión...). El daño residual va en _end_of_turn. Devuelve false si pierde el turno.
func _start_of_turn(u: Unit) -> bool:
	var expired := u.tick_stages()
	if not expired.is_empty():
		_log("Los cambios de %s de %s se disiparon." % [", ".join(expired), u.display_name()])
	if not await effects.start_of_turn(u):
		return false
	match u.status:
		MoveData.Status.SLEEP:
			if u.status_turns > 0:
				u.status_turns -= 1
				_popup(u, "Zzz", Color(0.7, 0.8, 1.0))
				_log("%s está dormido." % u.display_name())
				return false
			u.status = MoveData.Status.NONE
			u.refresh_label()
			_log("%s se despertó." % u.display_name())
		MoveData.Status.FREEZE:
			if rng.randf() < 0.2:
				u.status = MoveData.Status.NONE
				u.refresh_label()
				_log("¡%s se descongeló!" % u.display_name())
			else:
				_popup(u, "❄", Color(0.7, 0.9, 1.0))
				_log("%s está congelado." % u.display_name())
				return false
		MoveData.Status.PARALYSIS:
			if rng.randf() < 0.25:
				_popup(u, "¡PAR!", Color(1.0, 0.9, 0.2))
				_log("%s está paralizado y no puede moverse." % u.display_name())
				return false
	return true


## Daño y curación residuales después de actuar: volátiles, objetos y habilidades
## (effects.end_of_turn), clima y veneno/quemadura. Se aplica aunque haya perdido el turno.
func _end_of_turn(u: Unit) -> void:
	await effects.end_of_turn(u)
	if not u.is_alive():
		return
	var chip := Weather.chip_fraction(Combat.weather, u.data.types)
	if Abilities.weather_immune(u, Combat.weather) or not Abilities.takes_indirect(u):
		chip = 0.0
	if chip > 0.0:
		var dmg := maxi(1, int(u.max_hp * chip))
		u.take_damage(dmg)
		_popup(u, str(dmg), Color(0.85, 0.75, 0.55))
		_log("%s sufre por el %s." % [u.display_name(), Weather.NAMES[weather].to_lower()])
		await _wait(0.4)
		if not u.is_alive():
			return
	if u.status in [MoveData.Status.POISON, MoveData.Status.BURN] and Abilities.takes_indirect(u):
		var frac := 8 if u.status == MoveData.Status.POISON else 16
		var dmg := maxi(1, u.max_hp / frac)
		if u.status == MoveData.Status.BURN:  # se resiente de la quemadura: una llamarada lo envuelve
			Fx.burst(self, u.global_position + Vector3.UP * u.data.model_height * 0.5, "fire", 0.8)
		u.take_damage(dmg)
		_popup(u, str(dmg), Color(0.75, 0.4, 1.0))
		_log("%s sufre por estar %s." % [u.display_name(), Combat.STATUS_NAMES[u.status]])
		await _wait(0.5)


func _end_turn() -> void:
	state = State.BUSY
	_set_actions_enabled(false)
	_board.clear_highlights()
	if active.is_alive():
		await _end_of_turn(active)
	await effects.eat_pending()
	turns.end_turn(active, moved, acted, _extra_ct)
	if active.is_alive() and Items.effect(active) == "quick_claw" and rng.randf() < Items.param(active, "chance", 0.2):
		active.ct += Items.param(active, "ct", 30)
		_log("¡La Garra Rápida de %s le hará actuar antes!" % active.display_name())
	_board.clear_highlights()
	_next_turn.call_deferred()


func _after_action() -> void:
	if _check_game_over():
		return
	_refresh_turn_order()
	if not active.is_alive():
		# Se debilitó con su propio ataque (Doble Filo, Explosión...): no hay nada que orientar.
		_end_turn()
	elif moved and acted:
		_choose_facing()
	else:
		_show_menu()


## Último paso del turno del jugador: elegir hacia dónde mira (decide los flanqueos).
func _choose_facing() -> void:
	if not active.is_alive():
		_end_turn()
		return
	state = State.FACING
	_set_actions_enabled(false)
	_board.clear_highlights()
	_board.highlight(active.footprint, COLOR_ACTIVE)
	var around: Array[Vector2i] = []
	for c in active.footprint:
		for n in grid.neighbors(c):
			if n not in active.footprint and n not in around:
				around.append(n)
	_board.highlight(around, COLOR_MOVE)
	_hint_label.text = "¿Hacia dónde mira %s? Clic en una casilla · Enter: dejarlo así" % active.data.species_name


func _face_cell(u: Unit, c: Vector2i) -> void:
	var dir := grid.direction_towards(u.cell, c)
	u.face_towards(grid.to_world(grid.step(u.cell, dir)) + (u.position - grid.to_world(u.cell)))


## La IA mira hacia el rival más cercano.
func _ai_face(u: Unit) -> void:
	var foe := effects._nearest_foe(u)
	if foe and u.is_alive():
		_face_cell(u, foe.cell)


func _check_game_over() -> bool:
	for team in 2:
		if not units.any(func(u: Unit) -> bool: return u.team == team and u.is_alive()):
			state = State.GAME_OVER
			_set_actions_enabled(false)
			_banner.text = "¡Victoria!" if team == 1 else "Derrota..."
			if _tower():
				_banner.text = ("¡Piso %d superado!" if team == 1 else "Derrota en el piso %d...") % Game.tower.floor_number
				if team == 1 and _trainer_battle():
					_banner.text = "¡Has vencido a %s!" % Trainers.full_name(Game.tower.trainer)
			_fill_banner_buttons(team == 1)
			_banner_box.visible = true
			Audio.music("")
			Audio.ambience("")
			Audio.sfx("victory" if team == 1 else "defeat", 0.0, 1.0, 0.0)
			if active:
				active.set_active(false)
			return true
	return false


# --- Acciones del jugador ----------------------------------------------------

func _show_menu() -> void:
	state = State.MENU
	selected_move = null
	_board.clear_highlights()
	_board.highlight(active.footprint, COLOR_ACTIVE)
	_set_actions_enabled(true)
	_hint_label.text = "Elige una acción para %s" % active.data.species_name
	_refresh_info(active)


func _begin_pick_move() -> void:
	if state == State.BUSY or state == State.GAME_OVER or moved or not active.can_move():
		return
	state = State.PICK_MOVE
	_throwing = false
	_preview_label.text = ""
	_compute_reach(active)
	_board.clear_highlights()
	_board.highlight(_destinations, COLOR_MOVE)
	_hint_label.text = "Elige una casilla de destino (clic derecho: cancelar)"


func _begin_pick_target(move: MoveData) -> void:
	if state == State.BUSY or state == State.GAME_OVER or acted:
		return
	state = State.PICK_TARGET
	# Si venía de apuntar una Poké Ball, deja de lanzarla.
	_throwing = false
	_preview_label.text = ""
	selected_move = move
	_targets = _move_targets(active, move, active.footprint)
	_board.clear_highlights()
	_board.highlight(_targets, COLOR_RANGE)
	_hint_label.text = "%s: elige el objetivo (clic derecho: cancelar)" % move.display_name


func _on_cell_clicked(c: Vector2i) -> void:
	match state:
		State.FACING:
			_face_cell(active, c)
			_end_turn()
		State.DEPLOY:
			_deploy_click(c)
		State.PICK_MOVE:
			if c in _destinations:
				state = State.BUSY
				_set_actions_enabled(false)
				_board.clear_highlights()
				await _move_unit(active, _path_to(c))
				moved = true
				_after_action()
		State.PICK_TARGET:
			if c in _targets and _throwing:
				state = State.BUSY
				_throwing = false
				_set_actions_enabled(false)
				await _throw_ball(c)
				acted = true
				_after_action()
			elif c in _targets:
				state = State.BUSY
				_set_actions_enabled(false)
				await _use_move(active, selected_move, c)
				acted = true
				_after_action()


func _on_hover(c: Vector2i) -> void:
	if c == hover_cell:
		return
	hover_cell = c
	var hovered := _unit_at(c)
	_refresh_info(hovered if hovered else (active if active else _deploy_selected))
	_preview_label.text = ""
	_tile_label.text = effects.tile_info(c)
	match state:
		State.FACING:
			_face_cell(active, c)
		State.DEPLOY:
			_refresh_deploy()
		State.PICK_MOVE:
			_board.clear_highlights()
			_board.highlight(_destinations, COLOR_MOVE)
			if c in _destinations:
				_board.highlight(_path_to(c), COLOR_HOVER)
				_board.highlight(grid.footprint(c, active.data.size), COLOR_HOVER)
		State.PICK_TARGET:
			_board.clear_highlights()
			_board.highlight(_targets, COLOR_RANGE)
			if _throwing:
				_board.clear_highlights()
				_board.highlight(_ball_reach, COLOR_BALL_RANGE)
				_board.highlight(_targets, COLOR_RANGE)
			if c in _targets and _throwing:
				var t := _unit_at(c)
				if t:
					_board.highlight(t.footprint, COLOR_AREA)
					_preview_label.text = "%s: %d%% de captura · %s: %d" % [t.display_name(), roundi(TowerRun.catch_chance(t, _ball_kind) * 100),
						TowerRun.BALLS[_ball_kind].name, _balls_left(_ball_kind)]
			elif c in _targets:
				var res := _resolve(active, active.footprint, selected_move, c)
				var area: Array[Vector2i] = res.area
				var path: Array[Vector2i] = res.path
				_board.highlight(path, COLOR_HOVER)
				_board.highlight(area, COLOR_AREA)
				if selected_move.special:
					_preview_label.text = _special_preview(selected_move, c)
				else:
					_preview_label.text = _blocker_note(res, c) + _effect_preview(selected_move, area)


func _cancel() -> void:
	_throwing = false
	if state == State.FACING:
		_end_turn()
		return
	if state == State.PICK_MOVE or state == State.PICK_TARGET:
		_preview_label.text = ""
		_show_menu()


## Área real de un ataque lanzado desde `from` (celdas del atacante) hacia `target`:
## los proyectiles se detienen en el primer obstáculo o Pokémon del camino.
## Devuelve {"area", "impact", "blocker" ("", "obstacle", "unit"), "path"}.
func _resolve(u: Unit, from: Array[Vector2i], move: MoveData, target: Vector2i) -> Dictionary:
	var empty: Array[Vector2i] = []
	if not move.projectile:
		return {"area": Combat.area_cells(grid, move, from, target), "impact": target, "blocker": "", "path": empty}
	var unit_at := func(c: Vector2i) -> Unit:
		var other := _unit_at(c)
		return other if other != u else null
	var hit := Combat.trace(grid, from, target, unit_at)
	return {"area": Combat.area_cells(grid, move, from, hit.cell), "impact": hit.cell, "blocker": hit.blocker, "path": hit.path}


func _blocker_note(res: Dictionary, target: Vector2i) -> String:
	if res.blocker == "obstacle":
		return "[color=#ffb060]¡Hay algo en medio! El ataque chocará antes.[/color]\n"
	if res.blocker == "unit" and res.impact != target:
		var who := _unit_at(res.impact)
		return "[color=#ffb060]¡%s está en la línea de tiro![/color]\n" % (who.display_name() if who else "Alguien")
	return ""


## Texto con la efectividad y el daño estimado contra cada Pokémon del área.
## Todos los ataques dañan también a los aliados.
func _effect_preview(move: MoveData, area: Array[Vector2i]) -> String:
	var lines := PackedStringArray()
	for t in _others_at(active, area):
		var who := "[color=#%s]%s[/color]" % [Unit.TEAM_COLORS[t.team].lightened(0.4).to_html(false), t.display_name()]
		var chance := _hit_chance(active, t, move)
		if t.volatiles.has("protect"):
			lines.append("%s: [color=#99ccff]está protegido[/color]" % who)
			continue
		var absorbed := Abilities.absorb(active, t, move, Combat.move_type(move))
		if absorbed:
			lines.append("%s: [color=#999999]su %s lo anula[/color]" % [who, Abilities.display_name(t.ability)])
			continue
		if move.power <= 0 and move.fixed_damage <= 0:
			if move.volatile and not (move.volatile == "curse" and "ghost" not in active.data.types):
				lines.append("%s: %s (%d%% de acierto)" % [who, Unit.VOLATILE_SHORT.get(move.volatile, move.volatile), chance])
				continue
			if not move.stat_changes.is_empty():
				lines.append("%s: %s (%d%% de acierto)" % [who, Combat._stages_text(move.stat_changes), chance])
				continue
			var why := effects.can_status(active, t, move.status) if move.status else ""
			lines.append("%s: %s" % [who, "%d%% de acierto" % chance if why == "" else "[color=#999999]%s[/color]" % why])
			continue
		var eff := Abilities.effectiveness(active, Combat.move_type(move), t.data.types)
		var lo := _damage(active, t, move, 0.85)
		var hi := _damage(active, t, move, 1.0)
		# Multigolpe: daño por golpe × golpes posibles.
		var hits_min := move.hits_min
		var hits_max := move.hits_max
		if hits_max > 1 and (hits_min == hits_max or active.ability == "skilllink"):
			hits_min = hits_max
		if move.id == "tripleaxel":
			hi = hi * 6
			lo = lo * 6
		elif hits_max > 1:
			lo *= hits_min
			hi *= hits_max
		var tag := "[color=#888888]sin efecto[/color]" if eff == 0.0 else \
			("[color=#7ee07e]×%s muy eficaz[/color]" % ("4" if eff >= 4.0 else "2") if eff > 1.0 else \
			("[color=#e08a7e]×%s poco eficaz[/color]" % ("¼" if eff <= 0.25 else "½") if eff < 1.0 else "×1"))
		var ko := "  [color=#ffcc44]¡puede debilitarlo![/color]" if hi >= t.hp else ""
		var ally := "  [color=#ff7070](¡aliado!)[/color]" if t.team == active.team else ""
		var acc := "" if chance >= 100 else " · %d%%" % chance
		var crit_p := Combat.crit_chance(active, move, t)
		if crit_p > 0.05:
			acc += " · crít. %d%%" % roundi(crit_p * 100)
		if move.flinch_chance > 0:
			acc += " · retroceso %d%%" % move.flinch_chance
		var side := effects.flank(active, t)
		if side > 0:
			acc += " · [color=#ffcc66]%s[/color]" % Effects.FLANK_NAMES[side]
		var dh := effects.height_diff(active, t)
		if dh != 0:
			acc += " · %s" % ("desde arriba" if dh > 0 else "desde abajo")
		if hits_max > 1:
			acc += " · %s golpes" % (str(hits_max) if hits_min == hits_max else "%d-%d" % [hits_min, hits_max])
		lines.append("%s: %s · %d-%d de daño (PS %d)%s%s%s" % [who, tag, lo, hi, t.hp, acc, ko, ally])
	if move.targets_self:
		var parts := PackedStringArray()
		var heal := Weather.heal_fraction(weather, move)
		if heal > 0.0:
			parts.append("recupera %d PS" % mini(int(active.max_hp * heal), active.max_hp - active.hp))
		var stages := Weather.self_stages(weather, move)
		if not stages.is_empty():
			parts.append(Combat._stages_text(stages))
		if move.hp_cost > 0.0:
			parts.append("pierde %d PS" % int(active.max_hp * move.hp_cost))
		if move.sets_weather:
			parts.append("el clima pasa a %s" % Weather.NAMES[move.sets_weather])
		if move.self_volatile:
			parts.append(Unit.VOLATILE_SHORT.get(move.self_volatile, move.self_volatile))
		if move.field_effect:
			parts.append(FieldState.NAMES.get(move.field_effect, move.display_name))
		return "%s: %s" % [active.display_name(), ", ".join(parts)]
	if lines.is_empty():
		return "[color=#aaaaaa]Nadie en el área[/color]"
	return "\n".join(lines)


# --- Movimiento --------------------------------------------------------------

## Casillas alcanzables. El agua cuesta el doble salvo a los que nadan o vuelan, y los de tipo Agua
## nadan el doble de rápido (sin penalización por peso). El coste es la fracción del movimiento gastada.
func _compute_reach(u: Unit) -> void:
	_reach = {u.cell: u.cell}
	var cost := {u.cell: 0.0}
	var frontier: Array[Vector2i] = [u.cell]
	var swims := effects.swims(u)
	var land_step := 1.0 / u.move_range()
	var swim_step := 1.0 / u.swim_range() if u.swim_range() > 0 else land_step
	while not frontier.is_empty():
		frontier.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return cost[a] < cost[b])
		var c: Vector2i = frontier.pop_front()
		for n in grid.neighbors(c):
			if not _fits(u, n):
				continue
			var n_cells := grid.footprint(n, u.data.size)
			var dh := grid.footprint_height(n_cells) - grid.footprint_height(grid.footprint(c, u.data.size))
			if dh > u.data.jump or -dh > u.data.jump + 1:
				continue
			# Se puede atravesar a los aliados, pero no a los rivales.
			if _others_at(u, n_cells).any(func(o: Unit) -> bool: return o.team != u.team):
				continue
			var step := land_step
			if n_cells.all(func(x: Vector2i) -> bool: return grid.tiles.get(x, 0) == Biome.Tile.WATER):
				step = swim_step if swims else land_step * 2.0
			elif not swims and n_cells.any(func(x: Vector2i) -> bool: return grid.tiles.get(x, 0) == Biome.Tile.WATER):
				step = land_step * 2.0
			var total: float = cost[c] + step
			if total > 1.0 + 0.001 or total >= cost.get(n, INF) - 0.001:
				continue
			cost[n] = total
			_reach[n] = c
			frontier.append(n)
	_destinations.clear()
	for c: Vector2i in _reach:
		if c != u.cell and _can_stand(u, c):
			_destinations.append(c)


func _move_text(u: Unit) -> String:
	return "%d (%d nadando)" % [u.move_range(), u.swim_range()] if u.swim_range() > 0 else str(u.move_range())


func _path_to(c: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	while _reach.get(c, c) != c:
		path.push_front(c)
		c = _reach[c]
	return path


func _move_unit(u: Unit, path: Array[Vector2i]) -> void:
	if path.is_empty():
		return
	u.play("walk")
	for c in path:
		var from := u.position
		var to := grid.footprint_center(grid.footprint(c, u.data.size))
		u.face_towards(to)
		var tw := create_tween()
		if absf(to.y - from.y) > 0.01:
			tw.tween_method(func(t: float) -> void:
				u.position = from.lerp(to, t) + Vector3.UP * sin(t * PI) * 0.4, 0.0, 1.0, STEP_TIME * 1.5)
		else:
			tw.tween_property(u, "position", to, STEP_TIME)
		_focus_camera(to)
		await tw.finished
		# Trampas: se activan al pisar cada casilla del camino.
		_place(u, c)
		Audio.step(grid.tiles.get(c, Biome.Tile.GRASS))
		effects.enter_cells(u, u.footprint)
		if not u.is_alive():
			return
	u.play("idle")


# --- Ataques -----------------------------------------------------------------

func _use_move(user: Unit, move: MoveData, target: Vector2i) -> void:
	if move.item_effect == "fling":
		if user.item == null:
			_log("%s no tiene nada que lanzar." % user.display_name())
			await _end_move(user)
			return
		move = move.duplicate()
		move.power = user.item.fling_power
	if Items.effect(user) == "choice" and user.choice_lock == null:
		user.choice_lock = move
	# Maldición sin ser Fantasma: mejora sus propios stats en vez de maldecir.
	var self_curse := move.volatile == "curse" and "ghost" not in user.data.types
	var res := _resolve(user, user.footprint, move, target)
	var area: Array[Vector2i] = res.area
	if not move.targets_self and not self_curse:
		user.face_towards(grid.to_world(target))
	_log("%s usó [b]%s[/b]." % [user.display_name(), move.display_name])
	_board.clear_highlights()
	_board.highlight(area, COLOR_AREA)
	var anim_len := user.play(move.animation, move.anim_variant, move.id)
	await _wait(clampf(anim_len * 0.4, 0.25, 0.6))
	_extra_ct += Weather.extra_ct(Combat.weather, move)
	user.spend_pp(move)
	if move.special:
		await _special_move(user, move, target)
		await _end_move(user)
		return
	var hp_cost := move.hp_cost if not (move.volatile == "curse" and not self_curse) else 0.5
	if hp_cost > 0.0:
		var cost := int(user.max_hp * hp_cost)
		if user.hp <= cost:
			_log("¡Pero %s no tiene PS suficientes!" % user.display_name())
			await _end_move(user)
			return
		user.take_damage(cost)
		_popup(user, str(cost), Color(1.0, 0.6, 0.4))
	if move.self_ko and units.any(func(u: Unit) -> bool: return u.is_alive() and u.ability == "damp"):
		_log("¡Humedad impide %s!" % move.display_name)
		await _end_move(user)
		return
	if move.self_volatile and not effects.apply_self_volatile(user, move.self_volatile):
		await _end_move(user)
		return
	_play_launch_sound(move)
	await _play_move_fx(user, move, res)
	if res.blocker == "obstacle":
		Audio.sfx("hit_rock", -4.0)
		_log("¡El ataque chocó contra un obstáculo!")
	elif res.blocker == "unit" and res.impact != target:
		var who := _unit_at(res.impact)
		if who:
			_log("¡%s se interpuso en la trayectoria!" % who.display_name())

	var type := Combat.move_type(move)
	var dealt := 0
	var targets: Array[Unit] = [user]
	if not move.targets_self and not self_curse:
		targets = _others_at(user, area)
	if move.field_effect in ["haze", "perishsong"]:
		targets.clear()
	if targets.any(func(t: Unit) -> bool: return t.team != user.team and t.ability == "pressure"):
		user.spend_pp(move)
	# Un Pokémon grande recibe el golpe una sola vez aunque el área cubra varias de sus celdas.
	for t in targets:
		var block := effects.blocks_move(user, t, move)
		if block == "protect":
			Audio.sfx("protect", -4.0)
			_popup(t, "¡Protegido!", Color(0.6, 0.9, 1.0))
			_log("¡%s se protegió!" % t.display_name())
			continue
		if block == "substitute":
			_log("¡El sustituto de %s lo bloqueó!" % t.display_name())
			continue
		var absorbed := Abilities.absorb(user, t, move, type)
		if absorbed == "" and Items.floats(t) and type == "ground" and move.category != MoveData.Category.STATUS:
			absorbed = "balloon"
		if absorbed:
			await _ability_absorb(t, absorbed)
			continue
		if t != user and rng.randi_range(1, 100) > _hit_chance(user, t, move):
			Audio.sfx("miss", -4.0)
			_popup(t, "Falló", Color.WHITE)
			_log("¡%s esquivó el ataque!" % t.display_name())
			continue
		var damaging := move.power > 0 or move.fixed_damage > 0
		if damaging:
			# Multigolpe: la precisión ya se tiró; cada golpe hace su daño y sus efectos de contacto.
			var hits := _roll_hits(user, move)
			if Abilities.effectiveness(user, type, t.data.types) == 0.0:
				hits = 1
			var landed := 0
			var total := 0
			for i in hits:
				if not t.is_alive() or not user.is_alive():
					break
				if i > 0:
					await _wait(MULTIHIT_DELAY)
				var hit_move := move
				if move.id == "tripleaxel":
					hit_move = move.duplicate()
					hit_move.power = move.power * (i + 1)
				var got := _hit_once(user, t, hit_move, type, i, hits > 1)
				total += got
				landed += 1
				# La baya (Aranja, Zidra...) se come entre golpe y golpe, con pausas para que se vea.
				await effects.eat_pending()
			dealt += total
			if hits > 1:
				_log("¡Golpeó %d %s! %s recibe %d de daño en total." % [landed, "vez" if landed == 1 else "veces", t.display_name(), total])
				await _wait(MULTIHIT_DELAY * 2.0)
				_popup(t, "¡%d golpes!" % landed if landed > 1 else "1 golpe", Color(1.0, 0.8, 0.5), 1.2)
			if type == "electric":
				user.volatiles.erase("charge")
		var chance_of := func(c: int) -> int: return Abilities.secondary_chance(user, t, c) if damaging else c
		if t.is_alive() and move.status != MoveData.Status.NONE and rng.randi_range(1, 100) <= chance_of.call(move.status_chance):
			var why := effects.can_status(user, t, move.status)
			if why == "":
				Fx.aura(self, t.position, TypeChart.color(move.type), t.data.model_height)
				effects.set_status(user, t, move.status)
			elif move.category == MoveData.Category.STATUS:
				_log("No tiene efecto en %s: %s." % [t.display_name(), why])
		if t.is_alive() and move.volatile and not self_curse and rng.randi_range(1, 100) <= chance_of.call(move.volatile_chance):
			if not effects.apply_volatile(user, t, move.volatile) and move.category == MoveData.Category.STATUS:
				_log("No tiene efecto en %s." % t.display_name())
		if t.is_alive() and t != user and not move.stat_changes.is_empty() and rng.randi_range(1, 100) <= chance_of.call(move.stat_chance):
			if move.opposite_gender and not user.opposite_gender(t):
				_log("No afecta a %s (mismo sexo o sin género)." % t.display_name())
			else:
				effects.drop_stats(user, t, move.stat_changes)
		if move.item_effect and t != user:
			_item_move(user, t, move)
		if t.is_alive() and t != user and move.knockback > 0:
			await _knockback(user, t, move.knockback)
	if targets.is_empty() and not move.field_effect:
		_log("...pero no había nadie.")

	# Efectos sobre el propio usuario.
	if move.item_effect == "fling" and user.item:
		_log("%s lanzó su %s." % [user.display_name(), user.item.display_name])
		user.lose_item(false)
	if move.item_effect == "recycle":
		if user.item == null and user.consumed_item:
			user.item = user.consumed_item
			user.consumed_item = null
			_log("¡%s recuperó su %s!" % [user.display_name(), user.item.display_name])
		else:
			_log("¡Pero falló!")
	if dealt > 0 and Items.effect(user) == "shell_bell":
		_heal(user, maxi(1, int(dealt * Items.param(user, "amount", 0.125))))
	if dealt > 0 and Items.effect(user) == "life_orb" and Abilities.takes_indirect(user):
		effects._hurt(user, maxi(1, int(user.max_hp * Items.param(user, "cost", 0.1))), "La Vidasfera daña a %s." % user.display_name(), Color(0.9, 0.4, 0.6))
	if move.drain > 0.0 and dealt > 0:
		var drained := maxi(1, int(dealt * move.drain * (Items.param(user, "mult", 1.0) if Items.effect(user) == "big_root" else 1.0)))
		if targets.any(func(t: Unit) -> bool: return t.ability == "liquidooze"):
			effects._hurt(user, drained, "¡%s absorbió Viscosecreción!" % user.display_name(), Color(0.7, 0.4, 0.9))
		else:
			_heal(user, drained)
	var heal := Weather.heal_fraction(Combat.weather, move)
	if heal > 0.0:
		_heal(user, maxi(1, int(user.max_hp * heal)))
	var self_stages := Weather.self_stages(Combat.weather, move)
	if not self_stages.is_empty() and (dealt > 0 or move.category == MoveData.Category.STATUS) \
			and (move.volatile != "curse" or self_curse) and user.is_alive():
		effects.drop_stats(user, user, self_stages)
	if move.recoil > 0.0 and dealt > 0 and user.ability != "rockhead" and Abilities.takes_indirect(user):
		var recoil := maxi(1, int(dealt * move.recoil))
		effects._hurt(user, recoil, "%s sufre %d de daño por el retroceso." % [user.display_name(), recoil], Color(1.0, 0.6, 0.4))
	if move.self_ko and user.is_alive():
		Audio.sfx("explosion")
		user.take_damage(user.hp)
	if move.sets_weather:
		var alive := units.filter(func(u: Unit) -> bool: return u.is_alive()).size()
		_set_weather(move.sets_weather, Items.weather_rounds(user, move.sets_weather, Weather.MOVE_ROUNDS) * alive)
		_log("¡El clima cambió: %s %s!" % [Weather.ICONS[weather], Weather.NAMES[weather]])
	if move.field_effect:
		effects.apply_field(user, move, area)
	await _end_move(user)


## Sonido al lanzar el ataque (los de contacto solo suenan al golpear).
func _play_launch_sound(move: MoveData) -> void:
	if move.targets_self:
		Audio.sfx("status" if move.category == MoveData.Category.STATUS else "launch_special", -6.0)
	elif move.area_shape == MoveData.AreaShape.LINE:
		Audio.sfx("launch_beam", -4.0)
	elif move.projectile:
		Audio.sfx("launch_projectile", -6.0)
	elif move.category == MoveData.Category.SPECIAL:
		Audio.sfx("launch_special", -6.0)


## Casillas a las que se puede apuntar `move` desde `origin` (las de los ataques especiales se filtran:
## Teletransporte solo a casillas libres, Transformación a cualquier casilla de otro Pokémon,
## para que los grandes como Onix se puedan elegir aunque su casilla ancla quede fuera de alcance).
func _move_targets(u: Unit, move: MoveData, origin: Array[Vector2i]) -> Array[Vector2i]:
	var cells := Combat.target_cells(grid, move, origin)
	match move.special:
		"teleport":
			return cells.filter(func(c: Vector2i) -> bool: return _can_stand(u, c))
		"transform":
			return cells.filter(func(c: Vector2i) -> bool:
				var t := _unit_at(c)
				return t != null and t != u)
	return cells


func _special_preview(move: MoveData, c: Vector2i) -> String:
	if move.special == "splash":
		return "No pasará nada."
	if move.special == "transform":
		var t := _unit_at(c)
		return "Se transformará en %s: tipos, stats, habilidad y ataques." % TeamMember.display(t.data, t.gender) if t else ""
	return "Aparecerá aquí al instante."


func _special_move(user: Unit, move: MoveData, target: Vector2i) -> void:
	match move.special:
		"splash":
			var base := user.position
			var tw := create_tween()
			for i in 2:
				tw.tween_property(user, "position:y", base.y + 0.45, 0.16).set_ease(Tween.EASE_OUT)
				tw.tween_property(user, "position:y", base.y, 0.16).set_ease(Tween.EASE_IN)
			await tw.finished
			_log("¡Pero no pasó nada!")
		"teleport":
			var color := TypeChart.color(move.type)
			Fx.aura(self, user.position, color, user.data.model_height)
			Audio.sfx("ui_confirm", -6.0)
			var tw := create_tween()
			tw.tween_property(user, "scale", Vector3(0.05, 1.8, 0.05), 0.25)
			await tw.finished
			_place(user, target)
			user.position = grid.footprint_center(user.footprint)
			_focus_camera(user.position)
			Fx.aura(self, user.position, color, user.data.model_height, false)
			tw = create_tween()
			tw.tween_property(user, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			await tw.finished
			_log("¡%s se teletransportó!" % user.display_name())
			effects.enter_cells(user, user.footprint)
			effects.check_binds()
		"transform":
			var t := _unit_at(target)
			if t == null or t == user or t.volatiles.has("substitute"):
				_log("¡Pero falló!")
				return
			await _transform(user, t)


## Transformación (el ataque o la habilidad Impostor).
func _transform(user: Unit, t: Unit) -> void:
	user.face_towards(t.position)
	Fx.smoke(self, user.position + Vector3.UP * 0.3)
	Audio.sfx("ui_confirm", -6.0)
	var tw := create_tween()
	tw.tween_property(user, "scale", Vector3(1.3, 0.05, 1.3), 0.25)
	await tw.finished
	user.transform_into(t)
	tw = create_tween()
	tw.tween_property(user, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tw.finished
	_log("¡%s se transformó en %s!" % [user.display_name(), TeamMember.display(t.data, t.gender)])
	if user == active:
		_rebuild_attack_buttons(user)
		_refresh_info(user)


## Valor para la IA de Teletransporte (huir cuando está herido o no tiene otra cosa) y
## Transformación (copiar al Pokémon más fuerte, una sola vez).
func _special_value(u: Unit, from: Array[Vector2i], move: MoveData, target: Vector2i) -> float:
	match move.special:
		"transform":
			var t := _unit_at(target)
			if t == null or u.is_transformed() or t.base_data == u.base_data:
				return -1.0
			var total := t.data.base_attack + t.data.base_defense + t.data.base_sp_attack \
				+ t.data.base_sp_defense + t.data.base_speed
			return 40.0 + total / 10.0
		"teleport":
			var hurt := 1.0 - float(u.hp) / u.max_hp
			var only_option := u.usable_moves().all(func(m: MoveData) -> bool: return m.special == "teleport")
			if hurt < 0.5 and not only_option:
				return -1.0
			var at := grid.footprint(target, u.data.size)
			var gain := _distance_to_foe(u, at) - _distance_to_foe(u, from)
			return gain * (8.0 if hurt >= 0.5 else 1.5) - SELF_MOVE_COST
	return -1.0


func _end_move(user: Unit) -> void:
	await effects.eat_pending()
	await _wait(0.6)
	if user.is_alive():
		user.play("idle")
	_board.clear_highlights()


## Habilidades que absorben un ataque (Levitación, Absorbe Agua, Pararrayos...).
func _ability_absorb(t: Unit, kind: String) -> void:
	var name := Abilities.display_name(t.ability)
	match kind:
		"immune":
			_popup(t, name, Color(0.8, 0.9, 1.0))
			_log("¡%s de %s lo hace inmune!" % [name, t.display_name()])
		"heal":
			_log("¡%s de %s absorbe el ataque!" % [name, t.display_name()])
			_heal(t, maxi(1, t.max_hp / 4))
		"flashfire":
			t.volatiles["flashfire"] = {}
			t.refresh_label()
			_log("¡%s de %s potencia sus ataques de fuego!" % [name, t.display_name()])
		"spa_up":
			_log("¡%s de %s atrae el ataque!" % [name, t.display_name()])
			effects.drop_stats(t, t, {"sp_attack": 1})
		"balloon":
			_popup(t, "Globo Helio", Color(0.8, 0.9, 1.0))
			_log("¡%s flota con su Globo Helio!" % t.display_name())


## Precisión con los modificadores de posición (flanqueo, altura, arena).
func _hit_chance(att: Unit, def: Unit, move: MoveData) -> int:
	var base := Combat.hit_chance(att, def, move)
	if base >= 100:
		return 100
	return clampi(roundi(base * effects.accuracy_mult(att, def) * Items.accuracy_mult(att, def)), 1, 100)


## Daño con los modificadores que dependen de la posición (pantallas, terreno...).
func _damage(att: Unit, def: Unit, move: MoveData, roll: float, crit := false) -> int:
	var extra := 1.0
	if move.item_effect == "knockoff" and def.item and def.ability != "stickyhold":
		extra = 1.5
	return Combat.damage(att, def, move, roll, crit, effects.situational(att, def, move, crit) * extra)


## Golpes que da este uso: fijos, 2-5 sorteados, o siempre el máximo con Encadenado.
func _roll_hits(user: Unit, move: MoveData) -> int:
	if move.hits_max <= 1:
		return 1
	if move.hits_min == move.hits_max or user.ability == "skilllink":
		return move.hits_max
	var r := rng.randf()
	for i in Combat.HIT_WEIGHTS.size():
		r -= Combat.HIT_WEIGHTS[i]
		if r < 0.0:
			return mini(move.hits_min + i, move.hits_max)
	return move.hits_max


## Un golpe de un ataque de daño: crítico, daño, número flotante, retroceso y efectos de contacto.
## `index` = número de golpe (0 el primero); `multi` = forma parte de un multigolpe (registro más corto).
func _hit_once(user: Unit, t: Unit, move: MoveData, type: String, index: int, multi: bool) -> int:
	var crit := rng.randf() < Combat.crit_chance(user, move, t)
	var dmg := _damage(user, t, move, rng.randf_range(0.85, 1.0), crit)
	var eff := Abilities.effectiveness(user, type, t.data.types)
	dmg = int(dmg * effects.resist_berry(user, t, type, eff))
	if crit and dmg > 0:
		_log("¡Golpe crítico!")
	if eff == 0.0:
		_log("No afecta a %s..." % t.display_name())
	elif multi:
		if index == 0 and move.fixed_damage == 0 and eff != 1.0:
			_log("¡Es muy eficaz!" if eff > 1.0 else "No es muy eficaz...")
	elif eff > 1.0 and move.fixed_damage == 0:
		_log("¡Es muy eficaz! (%d)" % dmg)
	elif eff < 1.0 and move.fixed_damage == 0:
		_log("No es muy eficaz... (%d)" % dmg)
	else:
		_log("%s recibe %d de daño." % [t.display_name(), dmg])
	var real := 0
	if dmg > 0:
		real = effects.absorb_damage(user, t, dmg)
		Audio.hit(type, crit)
		if real > 0:
			t.take_damage(real)
			if crit:
				_popup(t, "¡%d!" % real, Color(1.0, 0.45, 0.2), 1.5)
			else:
				_popup(t, str(real), Color(1.0, 0.95, 0.4))
			_shake(t)
			var flinch := effects.flinch_chance(user, t, move)
			if t.is_alive() and t != user and flinch > 0 and rng.randi_range(1, 100) <= flinch:
				t.ct -= TurnManager.FLINCH_DELAY
				_log("¡%s retrocedió! Su turno se retrasa." % t.display_name())
				_popup(t, "¡Retrocede!", Color(0.8, 0.85, 1.0))
				if t.ability == "steadfast":
					effects.drop_stats(t, t, {"speed": 1})
		effects.after_hit(user, t, move, crit)
	return real


## Daño medio esperado contando los golpes de un multigolpe (para la IA).
func _expected_damage(att: Unit, def: Unit, move: MoveData) -> float:
	return _damage(att, def, move, 0.925) * Combat.expected_hits(att, move)


## Ataques que roban, quitan, intercambian o se comen el objeto del objetivo.
func _item_move(user: Unit, t: Unit, move: MoveData) -> void:
	var sticky := t.ability == "stickyhold"
	match move.item_effect:
		"steal":
			if user.item == null and t.item and not sticky and user.is_alive():
				_log("¡%s robó la %s de %s!" % [user.display_name(), t.item.display_name, t.display_name()])
				user.item = t.item
				t.lose_item(false)
		"knockoff":
			if t.item and not sticky:
				_log("¡%s perdió su %s!" % [t.display_name(), t.item.display_name])
				t.lose_item(false)
		"swap":
			if (user.item or t.item) and not sticky and user.ability != "stickyhold":
				var mine := user.item
				user.item = t.item
				t.item = mine
				user.choice_lock = null
				t.choice_lock = null
				_log("¡%s intercambió objetos con %s!" % [user.display_name(), t.display_name()])
			else:
				_log("¡Pero falló!")
		"eatberry":
			if t.item and t.item.category == ItemData.Category.BERRY and not sticky:
				_log("¡%s se comió la %s de %s!" % [user.display_name(), t.item.display_name, t.display_name()])
				var berry := t.item
				t.lose_item(false)
				var saved := user.item
				user.item = berry
				# Se aplica como si fuera suya, sin condición de PS.
				if berry.effect in ["heal_flat", "heal_frac"]:
					_heal(user, berry.params.amount if berry.effect == "heal_flat" else int(user.max_hp * berry.params.amount))
					user.item = saved
				else:
					if effects.berry_ready(user):
						effects.apply_berry(user)
					# Se la haya comido o no, recupera su propio objeto.
					if user.item == berry or user.item == null:
						user.item = saved
		"burnberry":
			if t.item and t.item.category == ItemData.Category.BERRY and not sticky:
				_log("¡La %s de %s se quemó!" % [t.item.display_name, t.display_name()])
				t.lose_item(false)
	t.refresh_label()
	user.refresh_label()


## Partículas del ataque: proyectil o rayo hasta el impacto y explosión en el área.
func _play_move_fx(user: Unit, move: MoveData, res: Dictionary) -> void:
	if move.targets_self or not is_inside_tree():
		return
	var area: Array[Vector2i] = res.area
	var start := user.position + Vector3.UP * user.data.model_height * 0.55
	if move.projectile:
		var points: Array[Vector3] = [start]
		var path: Array[Vector2i] = res.path
		for c in path:
			points.append(_aim_point(c))
		await Fx.projectile(self, points, Combat.move_type(move)).finished
	elif move.area_shape == MoveData.AreaShape.LINE and not area.is_empty():
		Fx.beam(self, start, _aim_point(area.back()), Combat.move_type(move))
		await _wait(0.2)
	var strength := 1.0 if area.size() <= 1 else 0.45
	for c in area:
		Fx.burst(self, _aim_point(c), Combat.move_type(move), strength)
	if move.category == MoveData.Category.STATUS:
		return
	await _wait(0.1)


## Punto al que apuntar en una celda: el cuerpo del Pokémon que la ocupa o algo sobre el suelo.
func _aim_point(c: Vector2i) -> Vector3:
	var u := _unit_at(c)
	if u:
		return u.position + Vector3.UP * u.data.model_height * 0.5
	return grid.to_world(c) + Vector3.UP * 0.35


func _heal(u: Unit, amount: int) -> void:
	amount = mini(amount, u.max_hp - u.hp)
	if amount <= 0:
		return
	Audio.sfx("heal", -6.0)
	u.heal(amount)
	Fx.aura(self, u.position, Fx.HEAL_COLOR, u.data.model_height)
	_popup(u, "+%d" % amount, Color(0.4, 1.0, 0.5))
	_log("%s recupera %d PS." % [u.display_name(), amount])


func _knockback(src: Unit, t: Unit, cells: int) -> void:
	if t.volatiles.has("ingrain"):
		_log("¡%s está arraigado y no se mueve!" % t.display_name())
		return
	var dir := grid.direction_towards(src.cell, t.cell)
	var dest := t.cell
	# Sobre hielo resbala una casilla más.
	if t.footprint.any(func(x: Vector2i) -> bool: return grid.tiles.get(x, 0) == Biome.Tile.ICE):
		cells += 1
	for i in cells:
		var nxt := grid.step(dest, dir)
		var nxt_cells := grid.footprint(nxt, t.data.size)
		if not _can_stand(t, nxt) or grid.footprint_height(nxt_cells) > grid.footprint_height(grid.footprint(dest, t.data.size)):
			break
		dest = nxt
	if dest == t.cell:
		return
	_place(t, dest)
	var tw := create_tween()
	tw.tween_property(t, "position", grid.footprint_center(t.footprint), 0.2).set_ease(Tween.EASE_OUT)
	await tw.finished
	effects.enter_cells(t, t.footprint)
	effects.check_binds()


# --- IA ----------------------------------------------------------------------

## IA sencilla: prueba cada casilla alcanzable × ataque × objetivo y se queda con
## la mejor puntuación. Si no puede atacar, se acerca al rival más cercano.
func _run_ai(u: Unit) -> void:
	await _wait(0.4)
	_compute_reach(u)
	if not u.can_move():
		_destinations.clear()
	var options: Array[Vector2i] = _destinations.duplicate()
	options.append(u.cell)
	var best_score := 0.0
	var best_dest := u.cell
	var best_move: MoveData = null
	var best_target := Vector2i.ZERO
	var moves: Array[MoveData] = u.usable_moves() if u.can_attack() else []
	var candidates: Array = []
	# Para valorar altura y flanqueo, se coloca un momento en cada destino posible.
	var home := u.cell
	var home_pos := u.position
	for dest in options:
		var at := grid.footprint(dest, u.data.size)
		_place(u, dest)
		u.position = grid.footprint_center(at)
		var danger := _danger_at(u) if Game.difficulty == Game.Difficulty.HARD else 0.0
		for move in moves:
			for target in _move_targets(u, move, at):
				var score := _score_action(u, at, move, target)
				if Game.difficulty == Game.Difficulty.HARD:
					score -= danger
				if score > 0.0 and Game.difficulty == Game.Difficulty.EASY:
					candidates.append([dest, move, target])
				if score > best_score:
					best_score = score
					best_dest = dest
					best_move = move
					best_target = target
	_place(u, home)
	u.position = home_pos
	# Fácil: a veces elige otra acción aceptable al azar.
	if Game.difficulty == Game.Difficulty.EASY and not candidates.is_empty() and rng.randf() < EASY_MISTAKE:
		var pick: Array = candidates[rng.randi_range(0, candidates.size() - 1)]
		best_dest = pick[0]
		best_move = pick[1]
		best_target = pick[2]
	if best_move == null:
		best_dest = _closest_to_enemy(u, options)
	if best_dest != u.cell:
		await _move_unit(u, _path_to(best_dest))
		moved = true
	if best_move:
		await _use_move(u, best_move, best_target)
		acted = true


## Difícil: cuánto peligro corre `u` en su posición actual (rivales que pueden alcanzarlo
## en su próximo turno, con más peso si llegarían por la espalda).
func _danger_at(u: Unit) -> float:
	var danger := 0.0
	for foe in units:
		if foe.team == u.team or not foe.is_alive():
			continue
		var steps := foe.move_range() if foe.can_move() else 0
		var reach := steps
		for mv in foe.usable_moves():
			reach = maxi(reach, steps + mv.range_max)
		if grid.distance_to_set(u.footprint, foe.cell) > reach:
			continue
		var hit := 0.0
		for mv in foe.usable_moves():
			hit = maxf(hit, _expected_damage(foe, u, mv))
		danger += minf(hit, u.hp) * HARD_DANGER_WEIGHT
	return danger


func _score_action(u: Unit, from: Array[Vector2i], move: MoveData, target: Vector2i) -> float:
	var score := 0.0
	if move.special:
		return _special_value(u, from, move, target)
	if move.targets_self:
		# Curarse vale más cuanto más herido. Mejorar stats solo compensa cerca del rival
		# (las mejoras duran pocos turnos) y si aún no lo hizo mucho.
		score += Weather.heal_fraction(weather, move) * (u.max_hp - u.hp) * 0.8
		var near := 1.0 if _distance_to_foe(u, from) <= u.move_range() + 2 else 0.15
		var stages := Weather.self_stages(weather, move)
		for key: String in stages:
			if key == "crit":
				# Vale el daño extra esperado de sus próximos golpes (+0,5 × la subida de probabilidad).
				var now := clampi(u.stages.get("crit", 0), 0, 3)
				var after := clampi(now + int(stages[key]), 0, 3)
				score += (Combat.CRIT_CHANCES[after] - Combat.CRIT_CHANCES[now]) * 0.5 * _best_damage(u) * 1.5 * near
			else:
				score += maxf(0.0, 12.0 - 4.0 * u.stages.get(key, 0)) * stages[key] * near
		if move.hp_cost > 0.0:
			score -= u.max_hp * move.hp_cost * 0.5 if u.hp > u.max_hp * move.hp_cost else 999.0
		if move.sets_weather and move.sets_weather != weather:
			score += _weather_value(u.team, move.sets_weather) - _weather_value(u.team, weather)
		score += _self_effect_value(u, from, move) * near
		# Actuar cuesta CT extra frente a solo moverse: solo compensa si el efecto vale la pena.
		return score - SELF_MOVE_COST
	if move.self_ko:
		score -= u.hp
	var area: Array[Vector2i] = _resolve(u, from, move, target).area
	if move.field_effect:
		score += _field_value(u, move, area)
	if move.volatile == "curse" and "ghost" not in u.data.types:
		return -1.0
	for t in _others_at(u, area):
		# Dañar a un aliado resta (un poco más de lo que sumaría dañar a un rival).
		var sign := 1.0 if t.team != u.team else -1.2
		if t.volatiles.has("protect") or Abilities.absorb(u, t, move, Combat.move_type(move)):
			score -= 5.0 * sign
			continue
		var chance := _hit_chance(u, t, move) / 100.0
		var dmg := _expected_damage(u, t, move) * chance * (1.0 + (Combat.CRIT_MULT - 1.0) * Combat.crit_chance(u, move, t))
		var value := minf(dmg, t.hp)
		if dmg >= t.hp:
			value += 80.0 if Game.difficulty == Game.Difficulty.HARD else 50.0
		if move.status != MoveData.Status.NONE and effects.can_status(u, t, move.status) == "":
			value += 25.0 * move.status_chance / 100.0 * chance
		if move.volatile and not t.volatiles.has(move.volatile):
			value += VOLATILE_VALUE.get(move.volatile, 10.0) * move.volatile_chance / 100.0 * chance
		for key: String in move.stat_changes:
			value += -6.0 * move.stat_changes[key] * move.stat_chance / 100.0 * chance
		value += 8.0 * move.flinch_chance / 100.0 * chance
		score += sign * value
	return score


## Valor para la IA de los efectos sobre uno mismo (Protección, Sustituto, Arraigo...).
func _self_effect_value(u: Unit, from: Array[Vector2i], move: MoveData) -> float:
	var hurt := 1.0 - float(u.hp) / u.max_hp
	var close := _distance_to_foe(u, from) <= 3
	match move.self_volatile:
		"protect": return 14.0 if close and u.protect_streak == 0 and hurt > 0.4 else -5.0
		"endure": return 12.0 if close and u.protect_streak == 0 and u.hp < u.max_hp / 4 else -5.0
		"substitute": return 18.0 if not u.volatiles.has("substitute") and hurt < 0.4 else -5.0
		"ingrain", "aquaring": return 6.0 + hurt * 20.0 if not u.volatiles.has(move.self_volatile) else -5.0
		"destinybond": return 20.0 if close and hurt > 0.7 else -5.0
		"charge":
			return 10.0 if u.moves.any(func(m: MoveData) -> bool: return m.type == "electric" and m.power > 0) else -5.0
		"magnetrise": return 4.0 if not u.volatiles.has("magnetrise") else -5.0
	return 0.0


## Valor para la IA de un efecto de campo según cuántos aliados/rivales afecta.
func _field_value(u: Unit, move: MoveData, area: Array[Vector2i]) -> float:
	var allies := units.filter(func(o: Unit) -> bool: return o.is_alive() and o.team == u.team)
	var foes := units.filter(func(o: Unit) -> bool: return o.is_alive() and o.team != u.team)
	match move.field_effect:
		"reflect", "lightscreen", "auroraveil", "safeguard", "mist":
			if effects.field.zone_at(move.field_effect, u.team, u.footprint):
				return -10.0
			return 8.0 * allies.filter(func(o: Unit) -> bool: return grid.distance_to_set(u.footprint, o.cell) <= FieldState.ZONE_RADIUS).size()
		"tailwind":
			return -10.0 if effects.field.tailwind[u.team] > 0 else 6.0 * allies.size()
		"spikes", "toxicspikes", "stealthrock":
			var near := foes.filter(func(o: Unit) -> bool: return grid.distance_to_set(area, o.cell) <= 3).size()
			return 6.0 * near
		"trickroom":
			var mine := 0.0
			for o: Unit in allies:
				mine += o.effective_speed()
			var theirs := 0.0
			for o: Unit in foes:
				theirs += o.effective_speed()
			var slower := mine / maxi(1, allies.size()) < theirs / maxi(1, foes.size())
			return (15.0 if slower else -15.0) * (1.0 if effects.field.trick_room == 0 else -1.0)
		"electricterrain", "grassyterrain", "psychicterrain":
			if effects.field.terrain == move.field_effect:
				return -10.0
			var type: String = FieldState.TERRAIN_TYPES[move.field_effect]
			var value := 0.0
			for o: Unit in allies + foes:
				var count := o.moves.filter(func(m: MoveData) -> bool: return m.type == type and m.power > 0).size()
				value += count * (5.0 if o.team == u.team else -5.0)
			return value
		"mistyterrain":
			return -10.0 if effects.field.terrain == move.field_effect else 4.0
		"gravity":
			return 2.0
		"haze":
			var value := 0.0
			for o: Unit in _others_at(u, area) + [u]:
				for key: String in o.stages:
					value += o.stages[key] * (4.0 if o.team != u.team else -4.0)
			return value
	return 0.0


## Cuánto le conviene un clima a un equipo: potencia de los ataques de sus Pokémon
## (y de los rivales, en contra) y daño de arena/granizo.
func _weather_value(team: int, kind: Weather.Kind) -> float:
	var value := 0.0
	for u in units:
		if not u.is_alive():
			continue
		var sign := 1.0 if u.team == team else -1.0
		for mv in u.moves:
			if mv.power > 0:
				value += sign * (Weather.power_mult(kind, mv) - 1.0) * 10.0
		value -= sign * Weather.chip_fraction(kind, u.data.types) * 120.0
	return value


## Daño medio del mejor ataque de `u` contra un rival vivo cualquiera (referencia para la IA).
func _best_damage(u: Unit) -> float:
	var best := 0.0
	for foe in units:
		if foe.team != u.team and foe.is_alive():
			for mv in u.usable_moves():
				best = maxf(best, _expected_damage(u, foe, mv))
			break
	return best


func _distance_to_foe(u: Unit, from: Array[Vector2i]) -> int:
	var best := 1 << 30
	for foe in units:
		if foe.team != u.team and foe.is_alive():
			for c in foe.footprint:
				best = mini(best, grid.distance_to_set(from, c))
	return best


func _closest_to_enemy(u: Unit, options: Array[Vector2i]) -> Vector2i:
	var best := u.cell
	var best_d := INF
	for dest in options:
		var at := grid.footprint(dest, u.data.size)
		for foe in units:
			if foe.team != u.team and foe.is_alive():
				var d := INF
				for c in foe.footprint:
					d = minf(d, grid.distance_to_set(at, c))
				if d < best_d:
					best_d = d
					best = dest
	return best


# --- Utilidades --------------------------------------------------------------

func _unit_at(c: Vector2i) -> Unit:
	for u in units:
		if u.is_alive() and c in u.footprint:
			return u
	return null


func _wait(seconds: float) -> void:
	# Si se abandonó la batalla a mitad de una animación, la corrutina queda colgada aquí.
	if not is_inside_tree():
		await Signal(self, "tree_entered")
	# process_always = false: los temporizadores se detienen con el menú de pausa.
	await get_tree().create_timer(seconds, false).timeout


func _focus_camera(target: Vector3) -> void:
	_cam_rig.focus(target)


func _popup(u: Unit, text: String, color: Color, size := 1.0) -> void:
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0015
	label.font_size = int(36 * size)
	label.outline_size = 10
	label.modulate = color
	label.position = u.position + Vector3.UP * (u.data.model_height + 0.1)
	add_child(label)
	var tw := create_tween().set_parallel()
	tw.tween_property(label, "position:y", label.position.y + 0.6, 0.9)
	tw.tween_property(label, "modulate:a", 0.0, 0.9).set_delay(0.3)
	tw.chain().tween_callback(label.queue_free)


func _shake(u: Unit) -> void:
	var base := u.position
	var tw := create_tween()
	for i in 4:
		tw.tween_property(u, "position", base + Vector3(0.06 if i % 2 == 0 else -0.06, 0, 0), 0.04)
	tw.tween_property(u, "position", base, 0.04)


func _pick_cell(screen_pos: Vector2) -> Variant:
	var hit := _cam_rig.pick(screen_pos)
	if hit.is_empty():
		return null
	var collider: Object = hit.collider
	if collider.has_meta("unit"):
		# Celda de la huella más cercana al punto donde se hizo clic.
		var u: Unit = collider.get_meta("unit")
		var best := u.cell
		var best_d := INF
		for c in u.footprint:
			var w := grid.to_world(c)
			var d := Vector2(w.x - hit.position.x, w.z - hit.position.z).length()
			if d < best_d:
				best_d = d
				best = c
		return best
	if collider.has_meta("cell"):
		return collider.get_meta("cell")
	return null


# --- Input -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _cam_rig.handle_input(event):
		return
	if event is InputEventMouseMotion:
		var c: Variant = _pick_cell(event.position)
		if c != null:
			_on_hover(c)
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				var c: Variant = _pick_cell(event.position)
				if c != null:
					_on_cell_clicked(c)
			MOUSE_BUTTON_RIGHT:
				_cancel()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				# Esc cancela lo que se esté eligiendo; si no hay nada, abre la pausa.
				if state == State.FACING:
					_end_turn()
				elif state == State.PICK_MOVE or state == State.PICK_TARGET:
					_cancel()
				else:
					_pause.open()
			KEY_ENTER, KEY_KP_ENTER:
				if state == State.FACING:
					_end_turn()
			KEY_R:
				if state == State.GAME_OVER:
					_start_battle()


# --- UI ----------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiKit.theme()
	layer.add_child(root)

	# Panel izquierdo: info de la unidad y acciones.
	var left := _panel(root, Vector2(16, 16), Vector2(300, 0))
	var left_box := VBoxContainer.new()
	left_box.add_theme_constant_override("separation", 8)
	left.add_child(left_box)
	_info_label = RichTextLabel.new()
	_info_label.bbcode_enabled = true
	_info_label.fit_content = true
	_info_label.scroll_active = false
	_info_label.custom_minimum_size.x = 300
	left_box.add_child(_info_label)
	left_box.add_child(HSeparator.new())
	_actions_box = VBoxContainer.new()
	left_box.add_child(_actions_box)
	_move_button = _button("Mover", _begin_pick_move)
	_actions_box.add_child(_move_button)
	_wait_button = _button("Terminar turno", func() -> void:
		if state == State.MENU: _choose_facing())

	_deploy_box = VBoxContainer.new()
	_deploy_box.add_theme_constant_override("separation", 8)
	_deploy_box.visible = false
	left_box.add_child(_deploy_box)
	var deploy_help := UiKit.label("Elige un Pokémon tuyo y luego\nuna casilla azul para moverlo.", 15, Color(1, 1, 1, 0.75))
	_deploy_box.add_child(deploy_help)
	var go := UiKit.button("¡Comenzar combate!", _finish_deploy, 20)
	go.custom_minimum_size.y = 48
	_deploy_box.add_child(go)
	_pause = PauseMenu.new()
	_pause.quit_text = "Volver al editor" if Game.testing_map else \
		("Salir (el piso se reintenta después)" if _tower() else "Abandonar (volver al menú)")
	_pause.quit_requested.connect(_go_to_menu)
	add_child(_pause)

	# Panel derecho: orden de turnos.
	var right := _panel(root, Vector2(0, 16), Vector2(220, 0))
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.offset_left = -236
	right.offset_right = -16
	var right_box := VBoxContainer.new()
	right.add_child(right_box)
	_weather_label = RichTextLabel.new()
	_weather_label.bbcode_enabled = true
	_weather_label.fit_content = true
	_weather_label.scroll_active = false
	_weather_label.custom_minimum_size.x = 196
	right_box.add_child(_weather_label)
	right_box.add_child(HSeparator.new())
	var title := Label.new()
	title.text = "Orden si terminas ahora"
	right_box.add_child(title)
	right_box.add_child(HSeparator.new())
	_order_box = VBoxContainer.new()
	right_box.add_child(_order_box)

	# Log inferior.
	var bottom := _panel(root, Vector2.ZERO, Vector2(560, 170))
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_top = -186
	bottom.offset_bottom = -16
	bottom.offset_left = 16
	bottom.offset_right = 576
	_log_label = RichTextLabel.new()
	_log_label.bbcode_enabled = true
	_log_label.scroll_following = true
	_log_label.add_theme_font_size_override("normal_font_size", 15)
	_log_label.add_theme_font_size_override("bold_font_size", 15)
	bottom.add_child(_log_label)

	_preview_label = RichTextLabel.new()
	_preview_label.bbcode_enabled = true
	_preview_label.fit_content = true
	_preview_label.scroll_active = false
	_preview_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_preview_label.offset_top = 120
	_preview_label.offset_left = -330
	_preview_label.offset_right = 330
	_preview_label.add_theme_constant_override("outline_size", 6)
	_preview_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_preview_label.add_theme_font_size_override("normal_font_size", 18)
	_preview_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_preview_label)

	_tile_label = RichTextLabel.new()
	_tile_label.bbcode_enabled = true
	_tile_label.fit_content = true
	_tile_label.scroll_active = false
	_tile_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_tile_label.offset_left = -760
	_tile_label.offset_right = -16
	_tile_label.offset_top = -96
	_tile_label.offset_bottom = -44
	_tile_label.add_theme_font_size_override("normal_font_size", 14)
	_tile_label.add_theme_constant_override("outline_size", 5)
	_tile_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_tile_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_tile_label)

	_hint_label = Label.new()
	_hint_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_hint_label.offset_top = 16
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint_label.add_theme_constant_override("outline_size", 6)
	_hint_label.add_theme_color_override("font_outline_color", Color.BLACK)
	root.add_child(_hint_label)

	var keys := Label.new()
	keys.text = "Clic: seleccionar · Clic der.: cancelar · Esc: pausa · Q/E: rotar · Rueda: zoom · WASD/botón central: mover cámara"
	keys.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	keys.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	keys.grow_vertical = Control.GROW_DIRECTION_BEGIN
	keys.offset_right = -16
	keys.offset_bottom = -16
	keys.add_theme_font_size_override("font_size", 14)
	keys.add_theme_constant_override("outline_size", 5)
	keys.add_theme_color_override("font_outline_color", Color.BLACK)
	root.add_child(keys)

	_banner_box = VBoxContainer.new()
	_banner_box.set_anchors_preset(Control.PRESET_CENTER)
	_banner_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	_banner_box.add_theme_constant_override("separation", 16)
	_banner_box.visible = false
	root.add_child(_banner_box)
	_banner = Label.new()
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 56)
	_banner.add_theme_constant_override("outline_size", 14)
	_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	_banner_box.add_child(_banner)
	_banner_buttons = HBoxContainer.new()
	_banner_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_banner_buttons.add_theme_constant_override("separation", 12)
	_banner_box.add_child(_banner_buttons)

	_turn_flash = Label.new()
	_turn_flash.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_turn_flash.offset_top = 70
	_turn_flash.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_turn_flash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_turn_flash.add_theme_font_size_override("font_size", 30)
	_turn_flash.add_theme_constant_override("outline_size", 10)
	_turn_flash.add_theme_color_override("font_outline_color", Color.BLACK)
	_turn_flash.modulate.a = 0.0
	root.add_child(_turn_flash)


func _tower() -> bool:
	return Game.mode == "tower" and Game.tower != null


func _fill_banner_buttons(victory: bool) -> void:
	UiKit.clear(_banner_buttons)
	if _tower():
		_banner_buttons.add_child(UiKit.button("Continuar", _finish_tower.bind(victory), 22))
		return
	_banner_buttons.add_child(UiKit.button("Revancha", _start_battle, 22))
	_banner_buttons.add_child(UiKit.button("Nuevo rival", func() -> void:
		Game.roll_enemy_team()
		enemy_team = Game.enemy_team.duplicate()
		_start_battle(), 22))
	_banner_buttons.add_child(UiKit.button("Volver al editor" if Game.testing_map else "Menú principal", _go_to_menu, 22))


## Torre: experiencia, capturas y vuelta a la pantalla de gestión.
func _finish_tower(victory: bool) -> void:
	var beaten: Array[int] = []
	for u in units:
		if u.team == 1 and not u.is_alive():
			beaten.append(u.level)
	for kind: String in _balls_used:
		Game.tower.balls[kind] = Game.tower.ball_count(kind) - _balls_used[kind]
	# Lo que pasó con los objetos en combate se queda: bayas comidas, objetos robados o quitados.
	for u in units:
		if u.team == 0 and u.has_meta("member"):
			var m: TeamMember = u.get_meta("member")
			m.item = u.item
	Game.tower.finish_floor(victory, beaten, _caught)
	Game.save()
	get_tree().change_scene_to_file("res://scenes/tower.tscn")


# --- Poké Balls (Torre) -----------------------------------------------------------

## Torre contra un entrenador o líder: no se puede capturar.
func _trainer_battle() -> bool:
	return _tower() and not Game.tower.trainer.is_empty()


func _balls_left(kind: String) -> int:
	return Game.tower.ball_count(kind) - _balls_used.get(kind, 0) if _tower() else 0


func _begin_pick_ball(kind: String) -> void:
	if state == State.BUSY or state == State.GAME_OVER or acted or _balls_left(kind) <= 0 or _trainer_battle():
		return
	state = State.PICK_TARGET
	_throwing = true
	_ball_kind = kind
	selected_move = null
	_targets.clear()
	for foe in units:
		if foe.team == 1 and foe.is_alive():
			for c in foe.footprint:
				if grid.distance_to_set(active.footprint, c) <= BALL_RANGE:
					_targets.append(c)
	var reach: Array[Vector2i] = []
	for c in active.footprint:
		for n in grid.cells_in_range(c, 1, BALL_RANGE):
			if n not in reach and n not in active.footprint:
				reach.append(n)
	_ball_reach = reach
	_board.clear_highlights()
	_board.highlight(_ball_reach, COLOR_BALL_RANGE)
	_board.highlight(_targets, COLOR_RANGE)
	_hint_label.text = "%s: elige un Pokémon salvaje (alcance %d · clic derecho: cancelar)" % [TowerRun.BALLS[kind].name, BALL_RANGE]


func _throw_ball(target: Vector2i) -> void:
	var kind := _ball_kind
	var ball_name: String = TowerRun.BALLS[kind].name
	_balls_used[kind] = _balls_used.get(kind, 0) + 1
	_log("¡%s lanza una %s!" % [active.display_name(), ball_name])
	var origin := active.footprint
	var hit := Combat.trace(grid, origin, target, func(c: Vector2i) -> Unit:
		var o := _unit_at(c)
		return o if o != active else null)
	# Sale de encima de su cabeza (no de dentro del modelo) y sin sus letras de por medio.
	var points: Array[Vector3] = [BallFx.above(active, 1.0)]
	var path: Array[Vector2i] = hit.path
	for c in path:
		points.append(_aim_point(c))
	Audio.sfx("launch_projectile", -6.0, 1.4)
	# Vuela la Poké Ball de verdad, en arco, siguiendo la trayectoria del lanzamiento.
	var pokeball := BallFx.new_ball(self, TowerRun.BALLS[kind].color)
	var dist := points[0].distance_to(points[-1])
	var t := _unit_at(hit.cell)
	var on_target: bool = hit.blocker != "obstacle" and t != null and t.team == 1
	# Las letras del que lanza y del objetivo se apartan mientras la bola vuela por encima.
	var thrower_label := active.show_label(false)
	if on_target:
		BallFx.hide_label(t)
		# Llega por encima de su cabeza (no contra su cuerpo), donde se abrirá.
		points[-1] = BallFx.above(t, 1.0)
	await BallFx.throw_path(self, pokeball, points, 0.4 + 0.12 * dist, clampf(dist * 0.09, 0.3, 0.9))
	active.show_label(thrower_label)
	if not on_target:
		_log("La %s no llegó a ningún Pokémon salvaje..." % ball_name)
		Audio.sfx("ui_error", -6.0)
		Fx.smoke(self, pokeball.global_position)
		pokeball.queue_free()
		return
	var chance := TowerRun.catch_chance(t, kind)
	# Como en los juegos: la bola se abre, el Pokémon entra como energía roja, cae al suelo dando botes y se
	# sacude hasta tres veces con el botón parpadeando.
	await BallFx.absorb(self, pokeball, t, grid.footprint_center(t.footprint))
	await _wait(0.3)
	var escaped := false
	for i in 3:
		await BallFx.wobble(pokeball, i, BALL_SHAKE_TIME)
		await _wait(BALL_SHAKE_TIME * 0.3)
		if rng.randf() > pow(chance, 1.0 / 3.0):
			escaped = true
			break
	if escaped:
		await BallFx.escape(self, pokeball, t)
		_popup(t, "¡Se escapó!", Color(1.0, 0.6, 0.5))
		_log("¡%s se escapó de la %s!" % [t.display_name(), ball_name])
		Audio.sfx("ui_error", -6.0)
		Audio.cry(t.data, 1.1, -8.0)
		return
	await BallFx.caught(self, pokeball)
	_log("¡%s ha sido capturado!" % t.display_name())
	_popup(t, "¡Capturado!", Color(1.0, 0.9, 0.4), 1.3)
	Audio.sfx("ui_confirm")
	var fade := create_tween()
	fade.tween_interval(0.6)
	fade.tween_property(pokeball, "scale", Vector3.ONE * 0.01, 0.3)
	fade.tween_callback(pokeball.queue_free)
	var member := TeamMember.create(t.base_data, t.base_moves)
	member.ability = t.ability
	member.gender = t.gender
	member.level = t.level
	member.known = TeamMember.moves_up_to(t.base_data, t.level)
	member.item = t.item
	_caught.append(member)
	t.hp = 0
	t.refresh_label()
	t.hide_overlays()


func _go_to_menu() -> void:
	get_tree().paused = false
	if Game.testing_map:
		Game.testing_map = false
		Game.map = null
		get_tree().change_scene_to_file("res://scenes/map_editor.tscn")
		return
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _panel(parent: Control, pos: Vector2, min_size: Vector2) -> PanelContainer:
	var panel := UiKit.panel()
	panel.position = pos
	panel.custom_minimum_size = min_size
	parent.add_child(panel)
	return panel


func _button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(callback)
	return b


func _rebuild_attack_buttons(u: Unit) -> void:
	for b in _attack_buttons:
		b.queue_free()
	_attack_buttons.clear()
	for sep in _action_separators:
		sep.queue_free()
	_action_separators.clear()
	if _wait_button.get_parent():
		_actions_box.remove_child(_wait_button)
	# Grupos: Mover | ataques | Poké Ball | Terminar turno, separados por líneas.
	_add_action_separator()
	var list: Array[MoveData] = u.moves.duplicate()
	if u.usable_moves().size() == 1 and u.usable_moves()[0].id == "struggle":
		list = u.usable_moves()
	for move in list:
		var left: int = u.pp.get(move, move.pp)
		var pp_text := "" if move.id == "struggle" else "   PP %d/%d" % [left, move.pp]
		var shown_type := Combat.move_type(move)
		var b := _button("%s  [%s]%s" % [move.display_name, Combat.TYPE_NAMES.get(shown_type, shown_type), pp_text],
			_begin_pick_target.bind(move))
		b.set_meta("no_pp", left <= 0)
		var accent := StyleBoxFlat.new()
		accent.bg_color = Color(0.18, 0.22, 0.3)
		accent.border_color = TypeChart.color(shown_type)
		accent.border_width_left = 6
		accent.set_corner_radius_all(6)
		accent.content_margin_left = 14
		accent.content_margin_top = 8
		accent.content_margin_bottom = 8
		b.add_theme_stylebox_override("normal", accent)
		b.tooltip_text = Combat.describe(move)
		_actions_box.add_child(b)
		_attack_buttons.append(b)
	if _tower() and not _trainer_battle():
		_add_action_separator()
		for kind: String in TowerRun.BALL_KINDS:
			if kind != "poke" and _balls_left(kind) <= 0:
				continue
			var ball := _button("%s  (%d)" % [TowerRun.BALLS[kind].name, _balls_left(kind)], _begin_pick_ball.bind(kind))
			ball.icon = TowerRun.BALLS[kind].icon
			ball.add_theme_constant_override("icon_max_width", 24)
			ball.set_meta("no_pp", _balls_left(kind) <= 0)
			ball.tooltip_text = "Intenta capturar a un Pokémon salvaje (mejor si está herido o dormido). %s" % TowerRun.BALLS[kind].desc
			_actions_box.add_child(ball)
			_attack_buttons.append(ball)
	_add_action_separator()
	_actions_box.add_child(_wait_button)


func _add_action_separator() -> void:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 10)
	_actions_box.add_child(sep)
	_action_separators.append(sep)


func _set_actions_enabled(enabled: bool) -> void:
	if enabled and active:
		_rebuild_attack_buttons(active)
	var stuck := active != null and not active.can_move()
	_move_button.disabled = not enabled or moved or stuck
	_move_button.text = "Mover  (inmovilizado)" if stuck else "Mover"
	for b in _attack_buttons:
		b.disabled = not enabled or acted or b.get_meta("no_pp", false) or (active != null and not active.can_attack())
	_wait_button.disabled = not enabled
	if not enabled:
		_hint_label.text = "" if state == State.GAME_OVER else "Turno rival..." if active and active.team == 1 else ""


func _refresh_info(u: Unit) -> void:
	if u == null:
		return
	var types := PackedStringArray()
	for t in u.data.types:
		types.append(UiKit.type_bbcode(t))
	var weak := PackedStringArray()
	var profile := TypeChart.defensive_profile(u.data.types)
	for t: String in profile:
		if profile[t] > 1.0:
			weak.append(UiKit.type_bbcode(t) + (" ×4" if profile[t] >= 4.0 else ""))
	var st: String = Combat.STATUS_NAMES.get(u.status, "")
	var boosts := PackedStringArray()
	for key: String in u.stages:
		if u.stages[key] != 0:
			boosts.append("[color=#%s]%s %+d[/color] (%d t.)" % ["ffaa55" if u.stages[key] > 0 else "6fa0ff",
				Unit.STAT_SHORT[key], u.stages[key], u.stage_turns.get(key, 0)])
	var vols := u.volatiles_text()
	_info_label.text = "[b]%s[/b]  Nv.%d\n%s\n[font_size=14]Habilidad: %s · Objeto: %s[/font_size]\nPS %d/%d%s\n%sAtq %d · Def %d\nAtE %d · DfE %d\nVel %d · CT %d\nMov %s · Salto %d · Talla %s\n%s[font_size=14]Débil a: %s[/font_size]" % [
		u.display_name(), u.level, " / ".join(types), Abilities.display_name(u.ability), u.item.display_name if u.item else "—", u.hp, u.max_hp,
		("  (" + st + ")") if st else "", ("[color=#cc99ff]%s[/color]\n" % vols) if vols else "",
		u.stats.attack, u.stats.defense, u.stats.sp_attack, u.stats.sp_defense,
		u.stats.speed, int(u.ct), _move_text(u), u.data.jump, u.data.size_label(),
		("Mejoras: " + ", ".join(boosts) + "\n") if not boosts.is_empty() else "",
		", ".join(weak) if not weak.is_empty() else "—",
	]


func _refresh_turn_order() -> void:
	for child in _order_box.get_children():
		child.queue_free()
	# Predicción de lo que pasaría si el activo terminara el turno ahora mismo.
	var saved_ct := active.ct
	active.ct -= TurnManager.cost(moved, acted)
	var order: Array[Unit] = [active]
	order.append_array(turns.predict(units, TURN_PREVIEW - 1))
	active.ct = saved_ct
	for i in order.size():
		var l := Label.new()
		l.text = "%s%d. %s" % ["▶ " if i == 0 else "   ", i + 1, order[i].display_name()]
		l.add_theme_color_override("font_color", Unit.TEAM_COLORS[order[i].team].lightened(0.3))
		_order_box.add_child(l)


func _flash_turn(text: String, color: Color) -> void:
	_turn_flash.text = text
	_turn_flash.add_theme_color_override("font_color", color)
	var tw := create_tween()
	tw.tween_property(_turn_flash, "modulate:a", 1.0, 0.15)
	tw.tween_interval(1.0)
	tw.tween_property(_turn_flash, "modulate:a", 0.0, 0.4)


func _log(text: String) -> void:
	_log_label.append_text(text + "\n")

extends Node3D
## Controlador de la batalla: monta el tablero, gestiona turnos, input, IA y UI.

enum State { BUSY, DEPLOY, MENU, PICK_MOVE, PICK_TARGET, GAME_OVER }

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
## Valor aproximado para la IA de dejar a un rival con cada estado volátil.
const VOLATILE_VALUE := {"confusion": 18.0, "leechseed": 16.0, "yawn": 14.0, "taunt": 8.0, "nightmare": 12.0, "curse": 22.0}
## Filas de despliegue de cada equipo en tableros aleatorios (jugador abajo, rival arriba).
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


func _ready() -> void:
	rng.randomize()
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
		Biome.generate(grid, Game.biome, rng, clear, zones[0], zones[1])
	for team in 2:
		_zones[team] = {}
		for c: Vector2i in zones[team]:
			_zones[team][c] = true
	_reset_environment()
	_board.build(grid)
	if map:
		base_weather = map.weather
	elif Game.weather >= 0:
		base_weather = Game.weather
	else:
		base_weather = Weather.roll(grid.biome, rng)
	_set_weather(base_weather, 0)
	effects.refresh_visuals()

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
	_begin_deploy()


## Cambia el clima. `turns` = turnos (de cualquier Pokémon) que dura; 0 = permanente.
func _set_weather(kind: Weather.Kind, turns: int) -> void:
	weather = kind
	Combat.weather = effects.effective_weather(kind) if effects else kind
	_weather_turns = turns
	_weather_fx.apply(kind, self)
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
	u.setup(member, team)
	var allowed := _in_zone.bind(team) if in_zone else func(c: Vector2i) -> bool: return true
	_place(u, _find_free_anchor(u, near, allowed))
	u.position = grid.footprint_center(u.footprint)
	u.face_towards(grid.to_world(Vector2i(grid.width / 2, grid.height / 2)))
	u.ct = rng.randf_range(0.0, 20.0)
	u.fainted.connect(func(x: Unit) -> void: _log("¡%s se debilitó!" % x.display_name()))
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
	elif _deploy_selected and _can_deploy(_deploy_selected, c):
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
	for c in cells:
		if not grid.is_inside(c) or grid.is_blocked(c):
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
	_refresh_info(active)
	if not await _start_of_turn(active):
		turns.end_turn(active, true, true)
		await _wait(0.6)
		_next_turn.call_deferred()
		return
	if active.team == 0:
		_show_menu()
	else:
		_set_actions_enabled(false)
		await _run_ai(active)
		_end_turn()


## Aplica efectos de estado al empezar el turno. Devuelve false si pierde el turno.
func _start_of_turn(u: Unit) -> bool:
	var expired := u.tick_stages()
	if not expired.is_empty():
		_log("Los cambios de %s de %s se disiparon." % [", ".join(expired), u.display_name()])
	if not await effects.start_of_turn(u):
		return false
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
			return false
	match u.status:
		MoveData.Status.POISON, MoveData.Status.BURN:
			if not Abilities.takes_indirect(u):
				return true
			var frac := 8 if u.status == MoveData.Status.POISON else 16
			var dmg := maxi(1, u.max_hp / frac)
			u.take_damage(dmg)
			_popup(u, str(dmg), Color(0.75, 0.4, 1.0))
			_log("%s sufre por estar %s." % [u.display_name(), Combat.STATUS_NAMES[u.status]])
			await _wait(0.5)
			return u.is_alive()
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


func _end_turn() -> void:
	state = State.BUSY
	_set_actions_enabled(false)
	turns.end_turn(active, moved, acted, _extra_ct)
	_board.clear_highlights()
	_next_turn.call_deferred()


func _after_action() -> void:
	if _check_game_over():
		return
	_refresh_turn_order()
	if moved and acted:
		_end_turn()
	else:
		_show_menu()


func _check_game_over() -> bool:
	for team in 2:
		if not units.any(func(u: Unit) -> bool: return u.team == team and u.is_alive()):
			state = State.GAME_OVER
			_set_actions_enabled(false)
			_banner.text = "¡Victoria!" if team == 1 else "Derrota..."
			_banner_box.visible = true
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
	if state == State.BUSY or state == State.GAME_OVER or moved or active.volatiles.has("ingrain"):
		return
	state = State.PICK_MOVE
	_compute_reach(active)
	_board.clear_highlights()
	_board.highlight(_destinations, COLOR_MOVE)
	_hint_label.text = "Elige una casilla de destino (clic derecho: cancelar)"


func _begin_pick_target(move: MoveData) -> void:
	if state == State.BUSY or state == State.GAME_OVER or acted:
		return
	state = State.PICK_TARGET
	selected_move = move
	_targets = Combat.target_cells(grid, move, active.footprint)
	_board.clear_highlights()
	_board.highlight(_targets, COLOR_RANGE)
	_hint_label.text = "%s: elige el objetivo (clic derecho: cancelar)" % move.display_name


func _on_cell_clicked(c: Vector2i) -> void:
	match state:
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
			if c in _targets:
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
	match state:
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
			if c in _targets:
				var res := _resolve(active, active.footprint, selected_move, c)
				var area: Array[Vector2i] = res.area
				var path: Array[Vector2i] = res.path
				_board.highlight(path, COLOR_HOVER)
				_board.highlight(area, COLOR_AREA)
				_preview_label.text = _blocker_note(res, c) + _effect_preview(selected_move, area)


func _cancel() -> void:
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
		var chance := Combat.hit_chance(active, t, move)
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

func _compute_reach(u: Unit) -> void:
	_reach = {u.cell: u.cell}
	var dist := {u.cell: 0}
	var frontier: Array[Vector2i] = [u.cell]
	while not frontier.is_empty():
		var c: Vector2i = frontier.pop_front()
		if dist[c] >= u.move_range():
			continue
		for n in grid.neighbors(c):
			if dist.has(n) or not _fits(u, n):
				continue
			var n_cells := grid.footprint(n, u.data.size)
			var dh := grid.footprint_height(n_cells) - grid.footprint_height(grid.footprint(c, u.data.size))
			if dh > u.data.jump or -dh > u.data.jump + 1:
				continue
			# Se puede atravesar a los aliados, pero no a los rivales.
			if _others_at(u, n_cells).any(func(o: Unit) -> bool: return o.team != u.team):
				continue
			dist[n] = dist[c] + 1
			_reach[n] = c
			frontier.append(n)
	_destinations.clear()
	for c: Vector2i in _reach:
		if c != u.cell and _can_stand(u, c):
			_destinations.append(c)


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
		effects.enter_cells(u, u.footprint)
		if not u.is_alive():
			return
	u.play("idle")


# --- Ataques -----------------------------------------------------------------

func _use_move(user: Unit, move: MoveData, target: Vector2i) -> void:
	# Maldición sin ser Fantasma: mejora sus propios stats en vez de maldecir.
	var self_curse := move.volatile == "curse" and "ghost" not in user.data.types
	var res := _resolve(user, user.footprint, move, target)
	var area: Array[Vector2i] = res.area
	if not move.targets_self and not self_curse:
		user.face_towards(grid.to_world(target))
	_log("%s usó [b]%s[/b]." % [user.display_name(), move.display_name])
	_board.clear_highlights()
	_board.highlight(area, COLOR_AREA)
	var anim_len := user.play(move.animation)
	await _wait(clampf(anim_len * 0.4, 0.25, 0.6))
	_extra_ct += Weather.extra_ct(Combat.weather, move)
	user.spend_pp(move)
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
	await _play_move_fx(user, move, res)
	if res.blocker == "obstacle":
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
			_popup(t, "¡Protegido!", Color(0.6, 0.9, 1.0))
			_log("¡%s se protegió!" % t.display_name())
			continue
		if block == "substitute":
			_log("¡El sustituto de %s lo bloqueó!" % t.display_name())
			continue
		var absorbed := Abilities.absorb(user, t, move, type)
		if absorbed:
			await _ability_absorb(t, absorbed)
			continue
		if t != user and rng.randi_range(1, 100) > Combat.hit_chance(user, t, move):
			_popup(t, "Falló", Color.WHITE)
			_log("¡%s esquivó el ataque!" % t.display_name())
			continue
		var damaging := move.power > 0 or move.fixed_damage > 0
		if damaging:
			var crit := rng.randf() < Combat.crit_chance(user, move, t)
			var dmg := _damage(user, t, move, rng.randf_range(0.85, 1.0), crit)
			var eff := Abilities.effectiveness(user, type, t.data.types)
			if crit and dmg > 0:
				_log("¡Golpe crítico!")
			if eff == 0.0:
				_log("No afecta a %s..." % t.display_name())
			elif eff > 1.0 and move.fixed_damage == 0:
				_log("¡Es muy eficaz! (%d)" % dmg)
			elif eff < 1.0 and move.fixed_damage == 0:
				_log("No es muy eficaz... (%d)" % dmg)
			else:
				_log("%s recibe %d de daño." % [t.display_name(), dmg])
			if dmg > 0:
				var real := effects.absorb_damage(user, t, dmg)
				if real > 0:
					t.take_damage(real)
					dealt += real
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
			effects.drop_stats(user, t, move.stat_changes)
		if t.is_alive() and t != user and move.knockback > 0:
			await _knockback(user, t, move.knockback)
	if targets.is_empty() and not move.field_effect:
		_log("...pero no había nadie.")

	# Efectos sobre el propio usuario.
	if move.drain > 0.0 and dealt > 0:
		var drained := maxi(1, int(dealt * move.drain))
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
		user.take_damage(user.hp)
	if move.sets_weather:
		var alive := units.filter(func(u: Unit) -> bool: return u.is_alive()).size()
		_set_weather(move.sets_weather, Weather.MOVE_ROUNDS * alive)
		_log("¡El clima cambió: %s %s!" % [Weather.ICONS[weather], Weather.NAMES[weather]])
	if move.field_effect:
		effects.apply_field(user, move, area)
	await _end_move(user)


func _end_move(user: Unit) -> void:
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


## Daño con los modificadores que dependen de la posición (pantallas, terreno...).
func _damage(att: Unit, def: Unit, move: MoveData, roll: float, crit := false) -> int:
	return Combat.damage(att, def, move, roll, crit, effects.situational(att, def, move, crit))


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


# --- IA ----------------------------------------------------------------------

## IA sencilla: prueba cada casilla alcanzable × ataque × objetivo y se queda con
## la mejor puntuación. Si no puede atacar, se acerca al rival más cercano.
func _run_ai(u: Unit) -> void:
	await _wait(0.4)
	_compute_reach(u)
	if u.volatiles.has("ingrain"):
		_destinations.clear()
	var options: Array[Vector2i] = _destinations.duplicate()
	options.append(u.cell)
	var best_score := 0.0
	var best_dest := u.cell
	var best_move: MoveData = null
	var best_target := Vector2i.ZERO
	for dest in options:
		var at := grid.footprint(dest, u.data.size)
		for move in u.usable_moves():
			for target in Combat.target_cells(grid, move, at):
				var score := _score_action(u, at, move, target)
				if score > best_score:
					best_score = score
					best_dest = dest
					best_move = move
					best_target = target
	if best_move == null:
		best_dest = _closest_to_enemy(u, options)
	if best_dest != u.cell:
		await _move_unit(u, _path_to(best_dest))
		moved = true
	if best_move:
		await _use_move(u, best_move, best_target)
		acted = true


func _score_action(u: Unit, from: Array[Vector2i], move: MoveData, target: Vector2i) -> float:
	var score := 0.0
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
		var chance := Combat.hit_chance(u, t, move) / 100.0
		var dmg := _damage(u, t, move, 0.925) * chance * (1.0 + (Combat.CRIT_MULT - 1.0) * Combat.crit_chance(u, move, t))
		var value := minf(dmg, t.hp)
		if dmg >= t.hp:
			value += 50.0
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
				best = maxf(best, _damage(u, foe, mv, 0.925))
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
	await get_tree().create_timer(seconds).timeout


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
				_cancel()
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
		if state == State.MENU: _end_turn())

	_deploy_box = VBoxContainer.new()
	_deploy_box.add_theme_constant_override("separation", 8)
	_deploy_box.visible = false
	left_box.add_child(_deploy_box)
	var deploy_help := UiKit.label("Elige un Pokémon tuyo y luego\nuna casilla azul para moverlo.", 15, Color(1, 1, 1, 0.75))
	_deploy_box.add_child(deploy_help)
	var go := UiKit.button("¡Comenzar combate!", _finish_deploy, 20)
	go.custom_minimum_size.y = 48
	_deploy_box.add_child(go)
	left_box.add_child(HSeparator.new())
	left_box.add_child(_button("Volver al editor" if Game.testing_map else "Abandonar (volver al menú)", _go_to_menu))

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

	_hint_label = Label.new()
	_hint_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_hint_label.offset_top = 16
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint_label.add_theme_constant_override("outline_size", 6)
	_hint_label.add_theme_color_override("font_outline_color", Color.BLACK)
	root.add_child(_hint_label)

	var keys := Label.new()
	keys.text = "Clic: seleccionar · Clic der./Esc: cancelar · Q/E: rotar · Rueda: zoom · WASD/botón central: mover cámara"
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
	var banner_buttons := HBoxContainer.new()
	banner_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	banner_buttons.add_theme_constant_override("separation", 12)
	_banner_box.add_child(banner_buttons)
	banner_buttons.add_child(UiKit.button("Revancha", _start_battle, 22))
	banner_buttons.add_child(UiKit.button("Nuevo rival", func() -> void:
		Game.roll_enemy_team()
		enemy_team = Game.enemy_team.duplicate()
		_start_battle(), 22))
	banner_buttons.add_child(UiKit.button("Volver al editor" if Game.testing_map else "Menú principal", _go_to_menu, 22))

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


func _go_to_menu() -> void:
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
	if _wait_button.get_parent():
		_actions_box.remove_child(_wait_button)
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
	_actions_box.add_child(_wait_button)


func _set_actions_enabled(enabled: bool) -> void:
	if enabled and active:
		_rebuild_attack_buttons(active)
	_move_button.disabled = not enabled or moved or (active != null and active.volatiles.has("ingrain"))
	for b in _attack_buttons:
		b.disabled = not enabled or acted or b.get_meta("no_pp", false)
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
	_info_label.text = "[b]%s[/b]  Nv.%d\n%s\n[font_size=14]Habilidad: %s[/font_size]\nPS %d/%d%s\n%sAtq %d · Def %d\nAtE %d · DfE %d\nVel %d · CT %d\nMov %d · Salto %d · Tamaño %d\n%s[font_size=14]Débil a: %s[/font_size]" % [
		u.display_name(), Unit.LEVEL, " / ".join(types), Abilities.display_name(u.ability), u.hp, u.max_hp,
		("  (" + st + ")") if st else "", ("[color=#cc99ff]%s[/color]\n" % vols) if vols else "",
		u.stats.attack, u.stats.defense, u.stats.sp_attack, u.stats.sp_defense,
		u.stats.speed, int(u.ct), u.move_range(), u.data.jump, u.data.size,
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

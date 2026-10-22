extends Node3D
## Controlador de la batalla: monta el tablero, gestiona turnos, input, IA y UI.

enum State { BUSY, DEPLOY, MENU, PICK_MOVE, PICK_TARGET, GAME_OVER }

const BOARD_SIZE := Vector2i(20, 20)
const COLOR_ACTIVE := Color(1.0, 1.0, 1.0, 0.35)
const COLOR_MOVE := Color(0.3, 0.6, 1.0, 0.5)
const COLOR_RANGE := Color(1.0, 0.75, 0.2, 0.4)
const COLOR_AREA := Color(1.0, 0.2, 0.15, 0.65)
const COLOR_HOVER := Color(1.0, 1.0, 1.0, 0.55)
const STEP_TIME := 0.22
const TURN_PREVIEW := 8
## Filas de despliegue de cada equipo (jugador abajo, rival arriba).
const DEPLOY_ROWS := 4
const COLOR_DEPLOY := Color(0.3, 0.6, 1.0, 0.3)

## Equipos y tablero salen del autoload Game (menú principal / editor de equipo).
var topology: BoardGrid.Topology
var player_team: Array[PokemonData] = []
var enemy_team: Array[PokemonData] = []

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

var _board: BoardView
var _units_root: Node3D
var _cam_rig: Node3D
var _camera: Camera3D
var _cam_yaw := 45.0

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
	_build_environment()
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
	grid = BoardGrid.new(topology, BOARD_SIZE.x, BOARD_SIZE.y)
	_generate_terrain()
	_board.build(grid)
	active = null
	for i in player_team.size():
		_spawn(player_team[i], 0, Vector2i(2 + i * 3, BOARD_SIZE.y - 3))
	for i in enemy_team.size():
		_spawn(enemy_team[i], 1, Vector2i(BOARD_SIZE.x - 3 - i * 3, 1))
	_banner_box.visible = false
	_log_label.clear()
	_log("Tablero %s. Coloca a tu equipo en la zona azul." % ("cuadrado" if topology == BoardGrid.Topology.SQUARE else "hexagonal"))
	_begin_deploy()


## Colinas generadas con ruido (alturas 0-3), distintas en cada partida.
func _generate_terrain() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.07
	for c in grid.all_cells():
		var w := grid.to_world(c)
		grid.heights[c] = clampi(floori((noise.get_noise_2d(w.x, w.z) + 0.25) * 4.0), 0, 3)


func _spawn(data: PokemonData, team: int, near: Vector2i) -> void:
	var u := Unit.new()
	_units_root.add_child(u)
	u.setup(data, team)
	_place(u, _find_free_anchor(u, near, _in_zone.bind(team)))
	u.position = grid.footprint_center(u.footprint)
	u.face_towards(grid.to_world(Vector2i(BOARD_SIZE.x / 2, BOARD_SIZE.y / 2)))
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
	return c.y >= BOARD_SIZE.y - DEPLOY_ROWS if team == 0 else c.y < DEPLOY_ROWS


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
	var center := grid.to_world(Vector2i(BOARD_SIZE.x / 2, BOARD_SIZE.y - DEPLOY_ROWS / 2))
	_focus_camera(center)
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
		if not grid.is_inside(c):
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


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.35, 0.55, 0.85)
	sky_mat.sky_horizon_color = Color(0.75, 0.85, 0.95)
	sky_mat.ground_horizon_color = Color(0.6, 0.7, 0.75)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.1
	add_child(sun)

	_cam_rig = Node3D.new()
	add_child(_cam_rig)
	var pitch := Node3D.new()
	pitch.rotation_degrees.x = -35.0
	_cam_rig.add_child(pitch)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 12.0
	_camera.position = Vector3(0, 0, 25)
	_camera.far = 100.0
	pitch.add_child(_camera)
	_cam_rig.rotation_degrees.y = _cam_yaw


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
	moved = false
	acted = false
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
	match u.status:
		MoveData.Status.POISON, MoveData.Status.BURN:
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
		MoveData.Status.PARALYSIS:
			if rng.randf() < 0.25:
				_popup(u, "¡PAR!", Color(1.0, 0.9, 0.2))
				_log("%s está paralizado y no puede moverse." % u.display_name())
				return false
	return true


func _end_turn() -> void:
	state = State.BUSY
	_set_actions_enabled(false)
	turns.end_turn(active, moved, acted)
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
	if state == State.BUSY or state == State.GAME_OVER or moved:
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
				var area := Combat.area_cells(grid, selected_move, active.footprint, c)
				_board.highlight(area, COLOR_AREA)
				_preview_label.text = _effect_preview(selected_move, area)


func _cancel() -> void:
	if state == State.PICK_MOVE or state == State.PICK_TARGET:
		_preview_label.text = ""
		_show_menu()


## Texto con la efectividad y el daño estimado contra cada Pokémon del área.
func _effect_preview(move: MoveData, area: Array[Vector2i]) -> String:
	var lines := PackedStringArray()
	for t in _others_at(active, area):
		if t.team == active.team and not move.hits_allies:
			continue
		var who := "[color=#%s]%s[/color]" % [Unit.TEAM_COLORS[t.team].lightened(0.4).to_html(false), t.display_name()]
		if move.power <= 0:
			var ok := Combat.can_receive_status(t, move.status)
			lines.append("%s: %s" % [who, "%d%% de acierto" % move.accuracy if ok else "[color=#999999]no tendrá efecto[/color]"])
			continue
		var eff := TypeChart.effectiveness(move.type, t.data.types)
		var lo := Combat.damage(active, t, move, 0.85)
		var hi := Combat.damage(active, t, move, 1.0)
		var tag := "[color=#888888]sin efecto[/color]" if eff == 0.0 else \
			("[color=#7ee07e]×%s muy eficaz[/color]" % ("4" if eff >= 4.0 else "2") if eff > 1.0 else \
			("[color=#e08a7e]×%s poco eficaz[/color]" % ("¼" if eff <= 0.25 else "½") if eff < 1.0 else "×1"))
		var ko := "  [color=#ffcc44]¡puede debilitarlo![/color]" if hi >= t.hp else ""
		lines.append("%s: %s · %d-%d de daño (PS %d)%s" % [who, tag, lo, hi, t.hp, ko])
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
	_place(u, path.back())
	u.play("idle")


# --- Ataques -----------------------------------------------------------------

func _use_move(user: Unit, move: MoveData, target: Vector2i) -> void:
	var area := Combat.area_cells(grid, move, user.footprint, target)
	user.face_towards(grid.to_world(target))
	_log("%s usó [b]%s[/b]." % [user.display_name(), move.display_name])
	_board.clear_highlights()
	_board.highlight(area, COLOR_AREA)
	var anim_len := user.play(move.animation)
	await _wait(clampf(anim_len * 0.5, 0.3, 0.8))

	var dealt := 0
	var hit_anything := false
	# Un Pokémon grande recibe el golpe una sola vez aunque el área cubra varias de sus celdas.
	for t in _others_at(user, area):
		if t.team == user.team and not move.hits_allies:
			continue
		hit_anything = true
		if rng.randi_range(1, 100) > move.accuracy:
			_popup(t, "Falló", Color.WHITE)
			_log("¡%s esquivó el ataque!" % t.display_name())
			continue
		if move.power > 0:
			var dmg := Combat.damage(user, t, move, rng.randf_range(0.85, 1.0))
			var eff := TypeChart.effectiveness(move.type, t.data.types)
			if eff == 0.0:
				_log("No afecta a %s..." % t.display_name())
			elif eff > 1.0:
				_log("¡Es muy eficaz! (%d)" % dmg)
			elif eff < 1.0:
				_log("No es muy eficaz... (%d)" % dmg)
			else:
				_log("%s recibe %d de daño." % [t.display_name(), dmg])
			t.take_damage(dmg)
			dealt += dmg
			_popup(t, str(dmg), Color(1.0, 0.95, 0.4))
			_shake(t)
		if t.is_alive() and move.status != MoveData.Status.NONE and rng.randi_range(1, 100) <= move.status_chance:
			if Combat.can_receive_status(t, move.status):
				t.status = move.status
				t.status_turns = rng.randi_range(1, 3) if move.status == MoveData.Status.SLEEP else 0
				t.refresh_label()
				_log("¡%s está %s!" % [t.display_name(), Combat.STATUS_NAMES[move.status]])
			elif move.power == 0:
				_log("No tiene efecto en %s." % t.display_name())
		if t.is_alive() and move.knockback > 0:
			await _knockback(user, t, move.knockback)
	if not hit_anything:
		_log("...pero no había nadie.")
	if move.drain > 0.0 and dealt > 0:
		var heal := maxi(1, int(dealt * move.drain))
		user.heal(heal)
		_popup(user, "+%d" % heal, Color(0.4, 1.0, 0.5))
	await _wait(0.6)
	user.play("idle")
	_board.clear_highlights()


func _knockback(src: Unit, t: Unit, cells: int) -> void:
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


# --- IA ----------------------------------------------------------------------

## IA sencilla: prueba cada casilla alcanzable × ataque × objetivo y se queda con
## la mejor puntuación. Si no puede atacar, se acerca al rival más cercano.
func _run_ai(u: Unit) -> void:
	await _wait(0.4)
	_compute_reach(u)
	var options: Array[Vector2i] = _destinations.duplicate()
	options.append(u.cell)
	var best_score := 0.0
	var best_dest := u.cell
	var best_move: MoveData = null
	var best_target := Vector2i.ZERO
	for dest in options:
		var at := grid.footprint(dest, u.data.size)
		for move in u.data.moves:
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
	for t in _others_at(u, Combat.area_cells(grid, move, from, target)):
		var sign := 1.0 if t.team != u.team else (-1.0 if move.hits_allies else 0.0)
		var dmg := Combat.damage(u, t, move, 0.925) * move.accuracy / 100.0
		var value := minf(dmg, t.hp)
		if dmg >= t.hp:
			value += 50.0
		if move.status != MoveData.Status.NONE and Combat.can_receive_status(t, move.status):
			value += 25.0 * move.status_chance / 100.0 * move.accuracy / 100.0
		score += sign * value
	return score


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
	await get_tree().create_timer(seconds).timeout


func _focus_camera(target: Vector3) -> void:
	# Con zoom lejano casi no se mueve (se ve todo el tablero); con zoom cercano sigue a la unidad.
	var follow := remap(clampf(_camera.size, 6.0, 26.0), 6.0, 26.0, 1.0, 0.2)
	var tw := create_tween()
	tw.tween_property(_cam_rig, "position", Vector3(target.x, 0.0, target.z) * follow, 0.4).set_trans(Tween.TRANS_SINE)


func _popup(u: Unit, text: String, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0015
	label.font_size = 36
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
	var from := _camera.project_ray_origin(screen_pos)
	var to := from + _camera.project_ray_normal(screen_pos) * 200.0
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
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
			MOUSE_BUTTON_WHEEL_UP:
				_camera.size = maxf(5.0, _camera.size - 0.8)
			MOUSE_BUTTON_WHEEL_DOWN:
				_camera.size = minf(26.0, _camera.size + 0.8)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Q:
				_rotate_camera(-1)
			KEY_E:
				_rotate_camera(1)
			KEY_ESCAPE:
				_cancel()
			KEY_R:
				if state == State.GAME_OVER:
					_start_battle()


func _rotate_camera(dir: int) -> void:
	_cam_yaw += dir * (90.0 if topology == BoardGrid.Topology.SQUARE else 60.0)
	create_tween().tween_property(_cam_rig, "rotation_degrees:y", _cam_yaw, 0.3).set_trans(Tween.TRANS_SINE)


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
	left_box.add_child(_button("Abandonar (volver al menú)", _go_to_menu))

	# Panel derecho: orden de turnos.
	var right := _panel(root, Vector2(0, 16), Vector2(220, 0))
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.offset_left = -236
	right.offset_right = -16
	var right_box := VBoxContainer.new()
	right.add_child(right_box)
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
	keys.text = "Clic: seleccionar · Clic der./Esc: cancelar · Q/E: rotar · Rueda: zoom"
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
	banner_buttons.add_child(UiKit.button("Menú principal", _go_to_menu, 22))

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
	for move in u.data.moves:
		var b := _button("%s  [%s]" % [move.display_name, Combat.TYPE_NAMES.get(move.type, move.type)],
			_begin_pick_target.bind(move))
		var accent := StyleBoxFlat.new()
		accent.bg_color = Color(0.18, 0.22, 0.3)
		accent.border_color = TypeChart.color(move.type)
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
	_move_button.disabled = not enabled or moved
	for b in _attack_buttons:
		b.disabled = not enabled or acted
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
	_info_label.text = "[b]%s[/b]  Nv.%d\n%s\nPS %d/%d%s\nAtq %d · Def %d\nAtE %d · DfE %d\nVel %d · CT %d\nMov %d · Salto %d · Tamaño %d\n[font_size=14]Débil a: %s[/font_size]" % [
		u.display_name(), Unit.LEVEL, " / ".join(types), u.hp, u.max_hp,
		("  (" + st + ")") if st else "",
		u.stats.attack, u.stats.defense, u.stats.sp_attack, u.stats.sp_defense,
		u.stats.speed, int(u.ct), u.move_range(), u.data.jump, u.data.size,
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

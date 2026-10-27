extends Node3D
## Escena del modo historia (scenes/story.tscn): muestra el paso actual de Game.story.
## - "titulo": rótulo de capítulo a pantalla completa.
## - "escena": monta el lugar en 3D (StoryRun.build_grid), coloca a los actores (Pokémon con su modelo,
##   personas con StoryFigure) y ejecuta el guion. Al terminar pasa al siguiente paso.
## Órdenes del guion (cada una es un diccionario; la clave principal dice qué hace):
##   {"decir": id, "texto"}            línea de diálogo con retrato (la cámara va hacia quien habla)
##   {"siente": id, "texto"}           lo que Cristina percibe de Gengar (cursiva, sin palabras)
##   {"narrar": texto}                 narración, sin retrato
##   {"mover": id, "a": [x, y]}        camina hasta la casilla; "paralelo": true no espera a que llegue
##   {"mirar": id, "a": id | [x, y]}
##   {"emocion": id, "simbolo": "!"}   bocadillo sobre la cabeza
##   {"anim": id, "clip": "hit"}       clip del Pokémon (idle, walk, fight_b, fight_d, hit, ko) o "salto"
##   {"aparecer": id, "efecto": "sombra" | "normal"}   actor que empezaba "oculto"
##   {"irse": id, "a": [x, y]}         (opcional "a") camina y desaparece
##   {"camara": id | [x, y], "zoom"}   {"esperar": segundos}   {"fundido": "negro" | "abrir"}
## El lugar admite "hora": "atardecer" (luz anaranjada) o "noche" (luz azul y faroles encendidos).
## Además de Pokémon ("especie") y personas, un actor puede ser un objeto: {"objeto": "pantalla"} (la
## pantalla flotante de una videollamada).
##   {"musica": nombre}  {"sonido": nombre}  {"grito": id}  {"temblor": id}

const ZOOM := 6.5
const STEP_TIME := 0.28
const TITLE_TIME := 4.0

var grid: BoardGrid
var _story: StoryRun
var _step: Dictionary
var _board: BoardView
var _cam_rig: CameraRig
var _units_root: Node3D
var _actors := {} # id -> Unit o StoryFigure
var _cells := {} # id -> Vector2i
var _dialogue: DialogueBox
var _fade: ColorRect
var _place_label: Label
var _last_speaker := ""
var _done := false


func _ready() -> void:
	_story = Game.story
	if _story == null or _story.finished():
		get_tree().change_scene_to_file.call_deferred("res://scenes/main_menu.tscn")
		return
	_step = _story.current()
	_build_ui()
	match _step.get("tipo", ""):
		"titulo":
			await _show_report()
			await _learn_moves()
			await _title_card()
		"escena":
			_build_place()
			await _show_report()
			await _learn_moves()
			await _run(_step.get("guion", []))
	_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	_story.advance()
	Game.save()
	_story.go(get_tree())


# --- Montaje -----------------------------------------------------------------

func _build_place() -> void:
	var place: Dictionary = _step.get("lugar", {})
	var built := StoryRun.build_grid(place)
	grid = built.grid
	# Los actores necesitan suelo libre donde están y por donde caminan.
	for c in _scripted_cells():
		if grid.is_inside(c):
			Biome._clear_prop(grid, c)
	_cam_rig = CameraRig.new()
	_cam_rig.camera.size = float(place.get("zoom", ZOOM))
	add_child(_cam_rig)
	CameraRig.build_environment(self, grid.biome)
	if place.get("hora", "") == "atardecer":
		_sunset()
	_board = BoardView.new()
	_board.batching = true
	add_child(_board)
	_board.build(grid)
	if place.get("hora", "") == "noche":
		_night()
	var weather := StoryRun.weather_kind(place)
	if weather != Weather.Kind.CLEAR:
		var fx := WeatherFx.new()
		fx.follow = _cam_rig
		add_child(fx)
		fx.apply(weather, self)
		_board.set_rain(weather == Weather.Kind.RAIN)
	Audio.ambience(Audio.weather_ambience(weather))
	_units_root = Node3D.new()
	add_child(_units_root)
	for a: Dictionary in _step.get("actores", []):
		_spawn(a)
	for a: Dictionary in _step.get("actores", []):
		if a.has("mira"):
			_face(a.id, a.mira)
	Audio.music(_step.get("musica", "editor"))
	var center: Variant = _step.get("camara", null)
	_cam_rig.position = _point(center) if center != null else _actors_center()
	_cam_rig.position.y = 0.0
	if place.has("nombre"):
		_place_label.text = tr(place.nombre)
		var tw := create_tween()
		tw.tween_property(_place_label, "modulate:a", 1.0, 0.6)
		tw.tween_interval(3.0)
		tw.tween_property(_place_label, "modulate:a", 0.0, 1.0)


## Luz de atardecer: sol bajo y anaranjado y cielo más cálido.
func _sunset() -> void:
	var sun: DirectionalLight3D = get_node_or_null("Sun")
	if sun:
		sun.light_color = Color(1.0, 0.62, 0.4)
		sun.light_energy *= 0.75
		sun.rotation_degrees.x = -18.0
	var world: WorldEnvironment = get_node_or_null("WorldEnvironment")
	if world and world.environment.sky and world.environment.sky.sky_material is ProceduralSkyMaterial:
		var sky: ProceduralSkyMaterial = world.environment.sky.sky_material
		sky.sky_top_color = Color(0.35, 0.3, 0.55)
		sky.sky_horizon_color = Color(1.0, 0.6, 0.42)
		sky.ground_horizon_color = Color(0.7, 0.45, 0.4)


## Noche: luna azulada, cielo oscuro y una luz cálida en cada farola.
func _night() -> void:
	var sun: DirectionalLight3D = get_node_or_null("Sun")
	if sun:
		sun.light_color = Color(0.55, 0.65, 1.0)
		sun.light_energy *= 0.3
	var world: WorldEnvironment = get_node_or_null("WorldEnvironment")
	if world:
		world.environment.ambient_light_energy *= 0.45
		if world.environment.sky and world.environment.sky.sky_material is ProceduralSkyMaterial:
			var sky: ProceduralSkyMaterial = world.environment.sky.sky_material
			sky.sky_top_color = Color(0.03, 0.04, 0.12)
			sky.sky_horizon_color = Color(0.12, 0.12, 0.28)
			sky.ground_horizon_color = Color(0.08, 0.08, 0.16)
			sky.ground_bottom_color = Color(0.02, 0.02, 0.05)
	for c: Vector2i in grid.props:
		if grid.props[c] == Biome.Prop.LAMP:
			var light := OmniLight3D.new()
			light.light_color = Color(1.0, 0.8, 0.5)
			light.light_energy = 1.6
			light.omni_range = 4.0
			light.position = grid.to_world(c) + Vector3(0.2, 1.0, 0.0)
			add_child(light)


## Casillas en que hay actores o a las que alguno va a caminar.
func _scripted_cells() -> Array[Vector2i]:
	var list: Array[Vector2i] = []
	for a: Dictionary in _step.get("actores", []):
		list.append(_cell(a.en))
	for cmd: Dictionary in _step.get("guion", []):
		if cmd.has("a") and cmd.a is Array and (cmd.has("mover") or cmd.has("irse")):
			var to := _cell(cmd.a)
			# El camino recto entre la casilla anterior y la nueva también.
			list.append(to)
	return list


func _spawn(a: Dictionary) -> void:
	var id: String = a.id
	var c := _cell(a.en)
	_cells[id] = c
	var node: Node3D
	if a.has("especie"):
		var m := StoryRun.member(a, Game.rng)
		if m == null:
			return
		var u := Unit.new()
		_units_root.add_child(u)
		u.setup(m, 0, m.level)
		u.hide_battle_marks()
		u.position = _stand_point(u, c)
		u.play("idle")
		node = u
	elif a.has("objeto"):
		node = _object(a.objeto)
		_units_root.add_child(node)
		node.position = _stand_point(node, c)
	else:
		var f := StoryFigure.new()
		_units_root.add_child(f)
		f.setup(_story.character(id).get("figura", {}))
		f.position = _stand_point(f, c)
		node = f
	node.visible = not a.get("oculto", false)
	_actors[id] = node


## Objetos de escena. "pantalla": la de una videollamada, flotando y con luz propia.
func _object(kind: String) -> Node3D:
	var root := Node3D.new()
	if kind == "pantalla":
		var screen := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.62, 0.4, 0.03)
		screen.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.35, 0.65, 1.0, 0.85)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		mat.emission = Color(0.3, 0.6, 1.0)
		mat.emission_energy_multiplier = 1.4
		screen.material_override = mat
		screen.position.y = 1.05
		root.add_child(screen)
		var light := OmniLight3D.new()
		light.light_color = Color(0.5, 0.75, 1.0)
		light.light_energy = 0.8
		light.omni_range = 2.0
		light.position.y = 1.05
		root.add_child(light)
		var tw := root.create_tween().set_loops()
		tw.tween_property(screen, "position:y", 1.12, 1.2).set_trans(Tween.TRANS_SINE)
		tw.tween_property(screen, "position:y", 1.05, 1.2).set_trans(Tween.TRANS_SINE)
	return root


func _cell(v: Variant) -> Vector2i:
	return Vector2i(int(v[0]), int(v[1])) if v is Array else Vector2i.ZERO


## Punto del mundo de un actor (id) o de una casilla ([x, y]).
func _point(target: Variant) -> Vector3:
	if target is String and _actors.has(target):
		return _actors[target].global_position
	return _stand_point(null, _cell(target))


## Dónde queda un actor plantado en la casilla `c` (los Pokémon grandes ocupan varias).
func _stand_point(node: Node3D, c: Vector2i) -> Vector3:
	var size: int = node.data.size if node is Unit else 1
	return grid.footprint_center(grid.footprint(c, size))


func _actors_center() -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for id: String in _actors:
		if _actors[id].visible:
			sum += _actors[id].position
			n += 1
	return sum / n if n > 0 else grid.to_world(Vector2i(grid.width / 2, grid.height / 2))


func _who(id: String) -> Dictionary:
	var who := _story.character(id).duplicate()
	who["id"] = id
	return who


# --- Guion -------------------------------------------------------------------

func _run(commands: Array) -> void:
	for cmd: Dictionary in commands:
		if _done:
			return
		if cmd.has("decir") or cmd.has("siente"):
			var id: String = cmd.get("decir", cmd.get("siente", ""))
			if id != _last_speaker and _actors.has(id) and _actors[id].visible:
				_cam_rig.focus(_point(id), 1.0)
			_last_speaker = id
			if cmd.has("emocion"):
				_emote(id, cmd.emocion)
			await _dialogue.say(_who(id), cmd.get("texto", ""), cmd.has("siente"))
			continue
		if cmd.has("narrar"):
			await _dialogue.say({}, cmd.narrar)
			continue
		_dialogue.close()
		_last_speaker = ""
		if cmd.has("mover"):
			if cmd.get("paralelo", false):
				_walk(cmd.mover, _cell(cmd.a))
			else:
				await _walk(cmd.mover, _cell(cmd.a))
		elif cmd.has("mirar"):
			_face(cmd.mirar, cmd.a)
		elif cmd.has("emocion"):
			await _emote(cmd.emocion, cmd.get("simbolo", "!"))
		elif cmd.has("anim"):
			await _anim(cmd.anim, cmd.get("clip", "idle"))
		elif cmd.has("aparecer"):
			await _appear(cmd.aparecer, cmd.get("efecto", "normal"))
		elif cmd.has("irse"):
			await _leave(cmd.irse, cmd.get("a", null))
		elif cmd.has("camara"):
			if cmd.has("zoom"):
				create_tween().tween_property(_cam_rig.camera, "size", float(cmd.zoom), 0.6).set_trans(Tween.TRANS_SINE)
			_cam_rig.focus(_point(cmd.camara), 1.0)
			await _wait(0.5)
		elif cmd.has("esperar"):
			await _wait(float(cmd.esperar))
		elif cmd.has("fundido"):
			await _fade_to(1.0 if cmd.fundido == "negro" else 0.0)
		elif cmd.has("musica"):
			Audio.music(cmd.musica)
		elif cmd.has("sonido"):
			Audio.sfx(cmd.sonido)
		elif cmd.has("grito"):
			var u: Variant = _actors.get(cmd.grito)
			if u is Unit:
				Audio.cry(u.data)
		elif cmd.has("temblor"):
			await _tremble(cmd.temblor)
	_dialogue.close()


func _walk(id: String, to: Vector2i) -> void:
	var node: Node3D = _actors.get(id)
	if node == null:
		return
	var path := _path(_cells.get(id, to), to)
	_set_walking(node, true)
	for c in path:
		var p := _stand_point(node, c)
		node.face_towards(p)
		var tw := create_tween()
		tw.tween_property(node, "position", p, STEP_TIME)
		await tw.finished
	_cells[id] = to
	_set_walking(node, false)


func _set_walking(node: Node3D, on: bool) -> void:
	if node is Unit:
		node.play("walk" if on else "idle")
	elif node is StoryFigure:
		node.walking = on


## Camino por casillas sin obstáculos (en anchura); si no hay, va directo.
func _path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var prev := {from: from}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		if c == to:
			break
		for n in grid.neighbors(c):
			if not prev.has(n) and (n == to or not grid.is_blocked(n)):
				prev[n] = c
				queue.append(n)
	var path: Array[Vector2i] = []
	if not prev.has(to):
		return [to]
	var c := to
	while c != from:
		path.push_front(c)
		c = prev[c]
	return path


func _face(id: String, target: Variant) -> void:
	var node: Node3D = _actors.get(id)
	if node and node.has_method("face_towards"):
		node.face_towards(_point(target))
	elif node:
		node.look_at(Vector3(_point(target).x, node.global_position.y, _point(target).z), Vector3.UP, true)


func _emote(id: String, symbol: String) -> void:
	var node: Node3D = _actors.get(id)
	if node == null:
		return
	var bubble := Label3D.new()
	bubble.text = symbol
	bubble.font_size = 96
	bubble.outline_size = 18
	bubble.modulate = Color(1.0, 0.95, 0.6)
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.no_depth_test = true
	var top: float = (node.data.model_height if node is Unit else StoryFigure.HEIGHT) + 0.35
	bubble.position = node.position + Vector3.UP * top
	bubble.scale = Vector3.ONE * 0.01
	_units_root.add_child(bubble)
	Audio.sfx("ui_place", -6.0, 1.4)
	var tw := create_tween()
	tw.tween_property(bubble, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.9)
	tw.tween_property(bubble, "modulate:a", 0.0, 0.3)
	tw.tween_callback(bubble.queue_free)
	await _wait(0.5)


func _anim(id: String, clip: String) -> void:
	var node: Node3D = _actors.get(id)
	if node is Unit:
		var t: float = node.play(clip)
		await _wait(minf(t, 1.5))
		node.play("idle")
	elif node is StoryFigure:
		var base := node.position
		var tw := create_tween()
		tw.tween_property(node, "position", base + Vector3.UP * 0.25, 0.12).set_ease(Tween.EASE_OUT)
		tw.tween_property(node, "position", base, 0.14).set_ease(Tween.EASE_IN)
		await tw.finished


## "sombra": surge del suelo como una mancha oscura (los fantasmas); "normal": aparece sin más.
func _appear(id: String, effect: String) -> void:
	var node: Node3D = _actors.get(id)
	if node == null:
		return
	_cam_rig.focus(node.position, 1.0)
	if node is Unit and effect == "sombra":
		await (node as Unit).materialize(node.global_position + Vector3.DOWN * 0.6, 0.9, Color(0.45, 0.2, 0.7))
	else:
		node.visible = true
		await _wait(0.3)


func _leave(id: String, to: Variant) -> void:
	var node: Node3D = _actors.get(id)
	if node == null:
		return
	if to != null:
		await _walk(id, _cell(to))
	var tw := create_tween()
	tw.tween_property(node, "scale", Vector3.ONE * 0.01, 0.3)
	await tw.finished
	node.visible = false
	node.scale = Vector3.ONE


func _tremble(id: String) -> void:
	var node: Node3D = _actors.get(id)
	if node == null:
		return
	var base := node.position
	for i in 8:
		node.position = base + Vector3(randf_range(-0.04, 0.04), 0.0, randf_range(-0.04, 0.04))
		await _wait(0.04)
	node.position = base


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _fade_to(alpha: float) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", alpha, 0.7)
	await tw.finished


## Lo que dejó pendiente el último combate (experiencia, niveles, ataques nuevos).
func _show_report() -> void:
	if _story.report.is_empty():
		return
	for line in _story.report:
		await _dialogue.say({}, line)
	_story.report = PackedStringArray()
	_dialogue.close()


## Ataques nuevos que no cabían: como en los juegos, se elige cuál olvidar (o no aprenderlo).
func _learn_moves() -> void:
	for p: Dictionary in _story.pending_moves:
		var i: int = p.get("member", -1)
		var path := TeamMember.MOVES_DIR + "%s.tres" % p.get("move", "")
		if i < 0 or i >= _story.party.size() or not ResourceLoader.exists(path):
			continue
		var m := _story.party[i]
		var mv: MoveData = load(path)
		if mv in m.moves:
			continue
		var who := TeamMember.display(m.data, m.gender)
		var options := PackedStringArray()
		for old in m.moves:
			options.append(tr("Olvidar %s") % tr(old.display_name))
		options.append(tr("No aprender %s") % tr(mv.display_name))
		var pick := await _dialogue.choose({}, tr("%s quiere aprender %s, pero ya conoce cuatro ataques. ¿Cuál olvida?") % [who, tr(mv.display_name)], options)
		if pick < m.moves.size():
			var old := m.moves[pick]
			m.moves[pick] = mv
			await _dialogue.say({}, tr("1, 2 y... ¡listo! %s olvidó %s y aprendió %s.") % [who, tr(old.display_name), tr(mv.display_name)])
		else:
			await _dialogue.say({}, tr("%s no aprendió %s.") % [who, tr(mv.display_name)])
	_story.pending_moves = []
	_dialogue.close()


func _title_card() -> void:
	_fade.color.a = 1.0
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.modulate.a = 0.0
	_fade.add_child(box)
	for line: Array in [[_step.get("titulo", ""), 54, UiKit.ACCENT], [_step.get("subtitulo", ""), 26, Color(1, 1, 1, 0.85)]]:
		if line[0] == "":
			continue
		var l := UiKit.label(tr(line[0]), line[1], line[2])
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_constant_override("outline_size", 10)
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		box.add_child(l)
	Audio.music(_step.get("musica", "menu"))
	var tw := create_tween()
	tw.tween_property(box, "modulate:a", 1.0, 1.0)
	await _wait(TITLE_TIME)
	tw = create_tween()
	tw.tween_property(box, "modulate:a", 0.0, 0.8)
	await tw.finished


# --- UI ----------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiKit.theme()
	layer.add_child(root)
	_fade = ColorRect.new()
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fade)
	_place_label = UiKit.label("", 30, UiKit.ACCENT)
	_place_label.position = Vector2(40, 32)
	_place_label.add_theme_constant_override("outline_size", 10)
	_place_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_place_label.modulate.a = 0.0
	root.add_child(_place_label)
	_dialogue = DialogueBox.new()
	root.add_child(_dialogue)
	var skip := UiKit.button(tr("Saltar escena ▸▸"), _finish, 16)
	skip.anchor_left = 1.0
	skip.anchor_right = 1.0
	skip.offset_left = -200
	skip.offset_right = -24
	skip.offset_top = 24
	skip.offset_bottom = 60
	skip.focus_mode = Control.FOCUS_NONE
	root.add_child(skip)


func _unhandled_input(event: InputEvent) -> void:
	if _cam_rig and _cam_rig.handle_input(event):
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_finish()

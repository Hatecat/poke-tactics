extends Node3D
## Editor de escenarios: tamaño, tipo de tablero y de campo, alturas, suelos,
## obstáculos, zonas de despliegue y rivales fijos. Guarda MapData para el modo historia.

enum Tool { HEIGHT, TILE, PROP, PLAYER_ZONE, ENEMY_ZONE, ENEMY }

const COLOR_PLAYER_ZONE := Color(0.3, 0.6, 1.0, 0.4)
const COLOR_ENEMY_ZONE := Color(1.0, 0.35, 0.3, 0.4)
const COLOR_BRUSH := Color(1.0, 1.0, 1.0, 0.55)
const TOOL_HELP := { # i18n
	Tool.HEIGHT: "Clic izq.: subir · Clic der.: bajar (arrastra para pintar)",
	Tool.TILE: "Clic izq.: pintar el suelo elegido",
	Tool.PROP: "Clic izq.: colocar obstáculo · Clic der.: quitarlo",
	Tool.PLAYER_ZONE: "Clic izq.: añadir a la zona azul · Clic der.: quitar",
	Tool.ENEMY_ZONE: "Clic izq.: añadir a la zona roja · Clic der.: quitar",
	Tool.ENEMY: "Clic izq.: colocar el rival elegido (con sus ataques por defecto) · Clic der.: quitarlo",
}

var map: MapData
var grid: BoardGrid
var rng := RandomNumberGenerator.new()

var _board: BoardView
var _cam: CameraRig
var _enemies_root: Node3D
var _tool := Tool.HEIGHT
var _brush := 0
var _hover := Vector2i(-1, -1)
var _painting := 0 # 0 = no, 1 = botón izq., -1 = botón der.
var _stroke := {} # celdas ya tocadas en este trazo

var _name_edit: LineEdit
var _width: SpinBox
var _height: SpinBox
var _topology: OptionButton
var _biome: OptionButton
## Panel de herramientas de la izquierda (la cámara encuadra el tablero a su derecha).
var _panel: PanelContainer
var _gym: OptionButton  # estilo del gimnasio (tipo)
var _weather: OptionButton
var _tile_pick: OptionButton
var _prop_pick: OptionButton
var _enemy_pick: OptionButton
var _brush_pick: OptionButton
var _load_pick: OptionButton
var _map_paths := PackedStringArray()
var _status: Label
var _help: Label
var _tool_buttons := {}


func _ready() -> void:
	rng.randomize()
	Audio.music("editor")
	Audio.ambience("")
	_cam = CameraRig.new()
	add_child(_cam)
	_board = BoardView.new()
	add_child(_board)
	_enemies_root = Node3D.new()
	add_child(_enemies_root)
	_build_ui()
	if Game.editor_map:
		_open(Game.editor_map)
	else:
		_new_map(true)


# --- Mapa ----------------------------------------------------------------------

func _new_map(generate: bool) -> void:
	var m := MapData.new()
	m.map_name = _name_edit.text if _name_edit.text else tr("Nuevo escenario")
	m.width = int(_width.value)
	m.height = int(_height.value)
	m.topology = _topology.selected
	m.biome = _biome.selected
	m.player_zone = MapData.default_zone(m.width, m.height, 0)
	m.enemy_zone = MapData.default_zone(m.width, m.height, 1)
	var g := BoardGrid.new(m.topology, m.width, m.height)
	g.biome = m.biome
	g.gym_type = Biome.GYM_TYPES[_gym.selected]
	if generate:
		var clear: Array[Vector2i] = []
		clear.append_array(m.player_zone)
		clear.append_array(m.enemy_zone)
		Biome.generate(g, m.biome, rng, clear, m.player_zone, m.enemy_zone)
	else:
		for c in g.all_cells():
			g.tiles[c] = Biome.default_tile(m.biome)
	m.store_grid(g)
	_open(m)
	_set_status(tr("Escenario generado.") if generate else tr("Escenario vacío creado."))


func _open(m: MapData) -> void:
	map = m
	Game.editor_map = m
	grid = m.to_grid()
	_name_edit.text = m.map_name
	_width.set_value_no_signal(m.width)
	_height.set_value_no_signal(m.height)
	_topology.select(m.topology)
	_biome.select(m.biome)
	_gym.select(maxi(0, Biome.GYM_TYPES.find(m.gym_type)))
	_weather.select(m.weather)
	for n in ["WorldEnvironment", "Sun"]:
		var old := get_node_or_null(n)
		if old:
			remove_child(old)
			old.queue_free()
	CameraRig.build_environment(self, grid.biome)
	_cam.rotation_step = 90.0 if grid.topology == BoardGrid.Topology.SQUARE else 60.0
	# Como en combate: el mapa a pantalla completa, con el campo de su bioma alrededor y encuadrado entero
	# junto al panel de herramientas
	_board.scenery = true
	_board.build(grid)
	_cam.safe_left = _panel.position.x + _panel.get_combined_minimum_size().x
	_cam.frame(_board.board_box(), _board.scenery_reach)
	_rebuild_enemies()
	_refresh_highlights()


## Vuelca el tablero editado en el MapData.
func _commit() -> void:
	map.map_name = _name_edit.text.strip_edges() if _name_edit.text.strip_edges() else tr("Sin nombre")
	map.store_grid(grid)
	map.weather = _weather.selected


func _rebuild_enemies() -> void:
	for child in _enemies_root.get_children():
		child.queue_free()
	for e: Dictionary in map.enemies:
		var member := TeamMember.from_dict(e, Game.find_species)
		if member == null:
			continue
		var u := Unit.new()
		_enemies_root.add_child(u)
		u.setup(member, 1)
		var cells := grid.footprint(e.cell, member.data.size)
		u.position = grid.footprint_center(cells)
		u.face_towards(grid.to_world(Vector2i(grid.width / 2, grid.height - 1)))
		u.set_meta("cell", e.cell)


# --- Edición -------------------------------------------------------------------

func _brush_cells(center: Vector2i) -> Array[Vector2i]:
	if _brush > 0 and _tool != Tool.ENEMY:
		return grid.cells_in_range(center, 0, _brush)
	var cells: Array[Vector2i] = []
	if grid.is_inside(center):
		cells.append(center)
	return cells


func _apply(c: Vector2i, button: int) -> void:
	var cells := _brush_cells(c)
	if _tool == Tool.ENEMY:
		_edit_enemy(c, button)
		return
	for cell in cells:
		if _stroke.has(cell):
			continue
		_stroke[cell] = true
		match _tool:
			Tool.HEIGHT:
				grid.heights[cell] = clampi(grid.get_height(cell) + button, 0, 6)
			Tool.TILE:
				grid.tiles[cell] = _tile_pick.selected
			Tool.PROP:
				grid.props[cell] = (_prop_pick.selected + 1) if button > 0 else Biome.Prop.NONE
			Tool.PLAYER_ZONE:
				_set_zone(map.player_zone, cell, button > 0)
				if button > 0:
					map.enemy_zone.erase(cell)
			Tool.ENEMY_ZONE:
				_set_zone(map.enemy_zone, cell, button > 0)
				if button > 0:
					map.player_zone.erase(cell)
		if _tool in [Tool.HEIGHT, Tool.TILE, Tool.PROP]:
			_board.refresh_cell(cell)
	if _tool in [Tool.HEIGHT, Tool.PROP]:
		_rebuild_enemies()
	_refresh_highlights()


func _set_zone(zone: Array[Vector2i], c: Vector2i, add: bool) -> void:
	if add and c not in zone:
		zone.append(c)
	elif not add:
		zone.erase(c)


func _edit_enemy(c: Vector2i, button: int) -> void:
	# Quitar el rival que ocupe esta celda (si hay).
	for e: Dictionary in map.enemies.duplicate():
		var p := Game.find_species(e.species)
		if p and c in grid.footprint(e.cell, p.size):
			map.enemies.erase(e)
			_rebuild_enemies()
			_set_status(tr("Rival quitado."))
			return
	if button < 0:
		return
	var species := Game.roster[_enemy_pick.selected]
	var cells := grid.footprint(c, species.size)
	for cell in cells:
		if not grid.is_inside(cell) or grid.is_blocked(cell):
			_set_status(tr("%s no cabe ahí.") % species.species_name)
			return
	map.enemies.append(TeamMember.create(species).to_dict().merged({"cell": c}))
	_rebuild_enemies()
	_set_status(tr("%s colocado (%d rivales).") % [species.species_name, map.enemies.size()])


func _refresh_highlights() -> void:
	_board.clear_highlights()
	_board.highlight(map.player_zone, COLOR_PLAYER_ZONE)
	_board.highlight(map.enemy_zone, COLOR_ENEMY_ZONE)
	if grid.is_inside(_hover):
		if _tool == Tool.ENEMY:
			_board.highlight(grid.footprint(_hover, Game.roster[_enemy_pick.selected].size), COLOR_BRUSH)
		else:
			_board.highlight(_brush_cells(_hover), COLOR_BRUSH)


func _pick(screen: Vector2) -> Variant:
	var hit := _cam.pick(screen)
	if hit.is_empty():
		return null
	var col: Object = hit.collider
	if col.has_meta("cell"):
		return col.get_meta("cell")
	if col.get_parent() and col.get_parent().has_meta("cell"):
		return col.get_parent().get_meta("cell")
	return null


func _unhandled_input(event: InputEvent) -> void:
	if _cam.handle_input(event):
		return
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		if event.pressed:
			_painting = 1 if event.button_index == MOUSE_BUTTON_LEFT else -1
			_stroke.clear()
			var c: Variant = _pick(event.position)
			if c != null:
				_apply(c, _painting)
		else:
			_painting = 0
	elif event is InputEventMouseMotion:
		var c: Variant = _pick(event.position)
		if c != null and c != _hover:
			_hover = c
			if _painting != 0 and _tool != Tool.ENEMY:
				_apply(c, _painting)
			else:
				_refresh_highlights()


# --- Guardar / cargar / probar ------------------------------------------------

func _save() -> void:
	_commit()
	if not _validate():
		return
	var path := Game.save_map(map)
	_set_status(tr("Guardado en %s") % path if path else tr("No se pudo guardar."))
	_refresh_load_list()


func _validate() -> bool:
	if map.player_zone.is_empty():
		_set_status(tr("Falta la zona azul (despliegue del jugador)."))
		return false
	if map.enemy_zone.is_empty() and map.enemies.is_empty():
		_set_status(tr("Falta la zona roja o algún rival colocado."))
		return false
	return true


func _load_selected() -> void:
	if _load_pick.selected < 0 or _map_paths.is_empty():
		return
	var m: MapData = load(_map_paths[_load_pick.selected]).duplicate(true)
	_open(m)
	_set_status(tr("Cargado: %s") % m.map_name)


func _refresh_load_list() -> void:
	_load_pick.clear()
	_map_paths = Game.list_maps()
	for path in _map_paths:
		_load_pick.add_item(path.get_file().get_basename())


func _test() -> void:
	_commit()
	if not _validate():
		return
	Game.map = map
	Game.mode = "quick"
	Game.testing_map = true
	Game.roll_enemy_team()
	get_tree().change_scene_to_file("res://scenes/battle.tscn")


func _set_status(text: String) -> void:
	_status.text = text


# --- UI -------------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.theme = UiKit.theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	# Barra superior: volver, título, nombre, guardar, cargar y probar.
	var bar := UiKit.panel()
	bar.position = Vector2(16, 12)
	root.add_child(bar)
	var top := UiKit.screen_header(tr("Editor de escenarios"), tr("← Menú"), func() -> void:
		Game.editor_map = null
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	top.add_theme_constant_override("separation", UiKit.SPACE_3)
	bar.add_child(top)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = tr("Nombre del escenario")
	_name_edit.custom_minimum_size.x = 260
	top.add_child(_name_edit)
	top.add_child(UiKit.primary_button(tr("💾 Guardar"), _save, 17))
	_load_pick = OptionButton.new()
	_load_pick.custom_minimum_size.x = 200
	top.add_child(_load_pick)
	top.add_child(UiKit.button(tr("Cargar"), _load_selected))
	top.add_child(UiKit.button(tr("▶ Probar"), _test))
	for c in top.get_children():
		(c as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var panel := UiKit.panel()
	panel.position = Vector2(16, 96)
	panel.custom_minimum_size.x = 300
	_panel = panel
	root.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)

	col.add_child(_section(tr("Tablero")))
	var size_row := HBoxContainer.new()
	col.add_child(size_row)
	_width = _spin(10, 30, 20)
	_height = _spin(10, 30, 20)
	size_row.add_child(UiKit.label(tr("Ancho "), 15, UiKit.TEXT_DIM))
	size_row.add_child(_width)
	size_row.add_child(UiKit.label(tr("  Alto "), 15, UiKit.TEXT_DIM))
	size_row.add_child(_height)
	_topology = OptionButton.new()
	_topology.add_item(tr("▦ Cuadrícula"))
	_topology.add_item(tr("⬢ Hexágonos"))
	col.add_child(_topology)
	_biome = OptionButton.new()
	for kind: int in Biome.NAMES:
		_biome.add_item("%s %s" % [Biome.ICONS[kind], tr(Biome.NAMES[kind])])
	col.add_child(_biome)
	_gym = OptionButton.new()
	for type in Biome.GYM_TYPES:
		_gym.add_item(tr("Gimnasio: %s") % (tr(Combat.TYPE_NAMES[type]) if type else tr("neutral")))
	_gym.tooltip_text = tr("Estilo del gimnasio (solo cuenta en el campo Gimnasio)")
	# Cambia el estilo del escenario abierto al momento
	_gym.item_selected.connect(func(i: int) -> void:
		if grid:
			grid.gym_type = Biome.GYM_TYPES[i]
			_board.build(grid)
			_refresh_highlights())
	col.add_child(_gym)
	_weather = OptionButton.new()
	for kind: int in Weather.NAMES:
		_weather.add_item("%s %s" % [Weather.ICONS[kind], tr(Weather.NAMES[kind])])
	col.add_child(_weather)
	var gen_row := HBoxContainer.new()
	gen_row.add_theme_constant_override("separation", 6)
	col.add_child(gen_row)
	gen_row.add_child(UiKit.button(tr("Generar al azar"), _new_map.bind(true)))
	gen_row.add_child(UiKit.button(tr("Vacío"), _new_map.bind(false)))
	col.add_child(UiKit.hint(tr("Cambiar tamaño o tablero rehace el mapa.")))

	col.add_child(HSeparator.new())
	col.add_child(_section(tr("Herramienta")))
	var group := ButtonGroup.new()
	var tools := [[Tool.HEIGHT, tr("⛰ Altura")], [Tool.TILE, tr("🟩 Suelo")], [Tool.PROP, tr("🌲 Obstáculo")],
		[Tool.PLAYER_ZONE, tr("🔵 Zona jugador")], [Tool.ENEMY_ZONE, tr("🔴 Zona rival")], [Tool.ENEMY, tr("👾 Rival")]]
	var tool_grid := GridContainer.new()
	tool_grid.columns = 2
	tool_grid.add_theme_constant_override("h_separation", UiKit.SPACE_1 + 2)
	tool_grid.add_theme_constant_override("v_separation", UiKit.SPACE_1 + 2)
	col.add_child(tool_grid)
	for t in tools:
		var b := UiKit.button(t[1], _set_tool.bind(t[0]), 15)
		b.theme_type_variation = UiKit.CARD_BUTTON
		b.toggle_mode = true
		b.button_group = group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.x = 136
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tool_grid.add_child(b)
		_tool_buttons[t[0]] = b
	_brush_pick = _option(col, tr("Pincel"), [tr("1 casilla"), tr("Radio 1"), tr("Radio 2")])
	_brush_pick.item_selected.connect(func(i: int) -> void: _brush = i)
	_tile_pick = _option(col, tr("Suelo"), Biome.TILE_NAMES.values().map(tr))
	var props: Array = Biome.PROP_NAMES.values().slice(1)
	_prop_pick = _option(col, tr("Obstáculo"), props.map(tr))
	_enemy_pick = _option(col, tr("Rival"), Game.roster.map(func(p: PokemonData) -> String: return "#%03d %s" % [p.dex_number, p.species_name]))
	_enemy_pick.item_selected.connect(func(_i: int) -> void: _set_tool(Tool.ENEMY))

	# Barra inferior: ayuda de la herramienta y estado (crece hacia arriba desde el borde).
	var hud := UiKit.panel()
	hud.anchor_left = 0.5
	hud.anchor_right = 0.5
	hud.anchor_top = 1.0
	hud.anchor_bottom = 1.0
	hud.offset_bottom = -16
	hud.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hud.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud)
	var hud_col := VBoxContainer.new()
	hud_col.add_theme_constant_override("separation", 2)
	hud.add_child(hud_col)
	_help = UiKit.label("", 15)
	_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_col.add_child(_help)
	_status = UiKit.label("", 15, UiKit.NEON)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_col.add_child(_status)
	var keys_panel := UiKit.panel(UiKit.CARD)
	keys_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	keys_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	keys_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	keys_panel.offset_right = -16
	keys_panel.offset_bottom = -16
	keys_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	keys_panel.self_modulate = Color(1, 1, 1, 0.85)
	root.add_child(keys_panel)
	keys_panel.add_child(UiKit.hint(tr("Q/E: rotar · Rueda: zoom · WASD/botón central: mover cámara"), 14))

	_refresh_load_list()
	_set_tool(Tool.HEIGHT)


func _section(text: String) -> Label:
	var l := UiKit.section(text, 18)
	l.add_theme_color_override("font_color", UiKit.ACCENT)
	return l


func _spin(lo: int, hi: int, value: int) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.value = value
	return s


func _option(parent: Control, caption: String, items: Array) -> OptionButton:
	var row := HBoxContainer.new()
	var l := UiKit.label(caption, 15, UiKit.TEXT_DIM)
	l.custom_minimum_size.x = 84
	row.add_child(l)
	var o := OptionButton.new()
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.fit_to_longest_item = false
	for it in items:
		o.add_item(str(it))
	row.add_child(o)
	parent.add_child(row)
	return o


func _set_tool(t: Tool) -> void:
	_tool = t
	_tool_buttons[t].button_pressed = true
	_help.text = tr(TOOL_HELP[t])
	if grid:
		_refresh_highlights()

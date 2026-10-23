extends Control
## Menú principal: partida rápida (tablero, campo, clima o escenario), editores y tabla de tipos.

const SHOWCASE_TIME := 3.5
const RANDOM_BIOME := -1
const RANDOM_WEATHER := -1

var _preview: PokemonPreview
var _preview_name: Label
var _showcase_index := 0
var _map_dialog: Control
var _play_button: Button
var _topology_buttons: Array[Button] = []
var _biome_buttons := {} # Biome.Kind o RANDOM_BIOME -> Button
var _map_select: OptionButton
var _map_paths := PackedStringArray()
var _random_options: Control
var _selected_biome := RANDOM_BIOME
var _team_select: OptionButton
var _team_hint: Label
var _difficulty_buttons: Array[Button] = []
var _difficulty_hint: Label
var _go_button: Button
var _weather_buttons := {} # Weather.Kind o RANDOM_WEATHER -> Button


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.background())

	var left := VBoxContainer.new()
	left.position = Vector2(120, 140)
	left.add_theme_constant_override("separation", 14)
	add_child(left)
	var title := UiKit.label("POKÉ TACTICS", 72, UiKit.ACCENT)
	title.add_theme_constant_override("outline_size", 14)
	title.add_theme_color_override("font_outline_color", Color(0.1, 0.15, 0.35))
	left.add_child(title)
	left.add_child(UiKit.label("Prototipo · Godot 4 · %d Pokémon" % Game.roster.size(), 18, Color(1, 1, 1, 0.6)))
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 20
	left.add_child(spacer)
	_play_button = _menu_button(left, "Partida rápida", _open_map_dialog)
	_menu_button(left, "Editor de equipo", _go.bind("team_editor"))
	_menu_button(left, "Editor de escenarios", _go.bind("map_editor"))
	_menu_button(left, "Tabla de tipos", _go.bind("type_chart"))
	_menu_button(left, "Salir", func() -> void: get_tree().quit())
	var team_info := UiKit.label("", 16, Color(1, 1, 1, 0.7))
	team_info.text = "%s: %s" % [Game.teams[Game.current_team].name, ", ".join(Game.player_team.map(func(m: TeamMember) -> String: return m.data.species_name)) if not Game.player_team.is_empty() else "vacío"]
	left.add_child(team_info)

	_preview = PokemonPreview.new()
	_preview.position = Vector2(820, 120)
	_preview.size = Vector2(660, 620)
	add_child(_preview)
	_preview_name = UiKit.label("", 28)
	_preview_name.position = Vector2(820, 740)
	_preview_name.size = Vector2(660, 40)
	_preview_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_preview_name)
	_next_showcase()
	var timer := Timer.new()
	timer.wait_time = SHOWCASE_TIME
	timer.autostart = true
	timer.timeout.connect(_next_showcase)
	add_child(timer)

	_build_map_dialog()


func _go(scene: String) -> void:
	get_tree().change_scene_to_file("res://scenes/%s.tscn" % scene)


func _menu_button(parent: Control, text: String, callback: Callable) -> Button:
	var b := UiKit.button(text, callback, 24)
	b.custom_minimum_size = Vector2(340, 54)
	parent.add_child(b)
	return b


func _next_showcase() -> void:
	var list: Array = Game.player_team.map(func(m: TeamMember) -> PokemonData: return m.data) if not Game.player_team.is_empty() else Game.roster
	if list.is_empty():
		return
	var p: PokemonData = list[_showcase_index % list.size()]
	_showcase_index += 1
	_preview.show_pokemon(p)
	_preview_name.text = "#%03d %s" % [p.dex_number, p.species_name]


# --- Diálogo de partida --------------------------------------------------------

func _build_map_dialog() -> void:
	_map_dialog = ColorRect.new()
	(_map_dialog as ColorRect).color = Color(0, 0, 0, 0.6)
	_map_dialog.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_dialog.visible = false
	add_child(_map_dialog)

	var panel := UiKit.panel()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_map_dialog.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	var title := UiKit.label("Partida rápida", 30, UiKit.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var team_row := HBoxContainer.new()
	team_row.add_theme_constant_override("separation", 8)
	var team_caption := UiKit.label("Tu equipo:", 18)
	team_caption.custom_minimum_size.x = 110
	team_row.add_child(team_caption)
	_team_select = OptionButton.new()
	_team_select.custom_minimum_size.x = 380
	_team_select.item_selected.connect(func(i: int) -> void:
		Game.select_team(i)
		_refresh_dialog())
	team_row.add_child(_team_select)
	box.add_child(team_row)
	_team_hint = UiKit.label("", 14, Color(1, 1, 1, 0.6))
	box.add_child(_team_hint)

	var diff_row := HBoxContainer.new()
	diff_row.add_theme_constant_override("separation", 8)
	var diff_caption := UiKit.label("Dificultad:", 18)
	diff_caption.custom_minimum_size.x = 110
	diff_row.add_child(diff_caption)
	for i in Game.DIFFICULTY_NAMES.size():
		var b := UiKit.button(Game.DIFFICULTY_NAMES[i], func() -> void:
			Game.difficulty = i
			_refresh_dialog(), 18)
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(150, 42)
		diff_row.add_child(b)
		_difficulty_buttons.append(b)
	box.add_child(diff_row)
	_difficulty_hint = UiKit.label("", 14, Color(1, 1, 1, 0.6))
	box.add_child(_difficulty_hint)
	box.add_child(HSeparator.new())

	var map_row := HBoxContainer.new()
	var map_caption := UiKit.label("Escenario:", 18)
	map_caption.custom_minimum_size.x = 110
	map_row.add_child(map_caption)
	_map_select = OptionButton.new()
	_map_select.custom_minimum_size.x = 380
	_map_select.item_selected.connect(func(_i: int) -> void: _refresh_dialog())
	map_row.add_child(_map_select)
	box.add_child(map_row)

	_random_options = VBoxContainer.new()
	_random_options.add_theme_constant_override("separation", 12)
	box.add_child(_random_options)
	_random_options.add_child(UiKit.label("Tablero", 18, Color(1, 1, 1, 0.75)))
	var topo_row := HBoxContainer.new()
	topo_row.add_theme_constant_override("separation", 12)
	_random_options.add_child(topo_row)
	for item in [["▦  Cuadrícula", BoardGrid.Topology.SQUARE], ["⬢  Hexágonos", BoardGrid.Topology.HEX]]:
		var b := UiKit.button(item[0], func() -> void:
			Game.topology = item[1]
			_refresh_dialog(), 20)
		b.custom_minimum_size = Vector2(290, 50)
		b.toggle_mode = true
		topo_row.add_child(b)
		_topology_buttons.append(b)

	_random_options.add_child(UiKit.label("Campo", 18, Color(1, 1, 1, 0.75)))
	var biome_grid := GridContainer.new()
	biome_grid.columns = 3
	biome_grid.add_theme_constant_override("h_separation", 8)
	biome_grid.add_theme_constant_override("v_separation", 8)
	_random_options.add_child(biome_grid)
	var options: Array = [[RANDOM_BIOME, "🎲  Aleatorio"]]
	for kind: int in Biome.NAMES:
		options.append([kind, "%s  %s" % [Biome.ICONS[kind], Biome.NAMES[kind]]])
	for item in options:
		var b := UiKit.button(item[1], func() -> void:
			_selected_biome = item[0]
			_refresh_dialog(), 18)
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(190, 44)
		biome_grid.add_child(b)
		_biome_buttons[item[0]] = b

	_random_options.add_child(UiKit.label("Clima", 18, Color(1, 1, 1, 0.75)))
	var weather_row := HBoxContainer.new()
	weather_row.add_theme_constant_override("separation", 8)
	_random_options.add_child(weather_row)
	var weathers: Array = [[RANDOM_WEATHER, "🎲 Aleatorio"]]
	for kind: int in Weather.NAMES:
		weathers.append([kind, "%s %s" % [Weather.ICONS[kind], Weather.NAMES[kind].split(" ")[0] if kind != Weather.Kind.SAND else "Arena"]])
	for item in weathers:
		var b := UiKit.button(item[1], func() -> void:
			Game.weather = item[0]
			_refresh_dialog(), 16)
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(92, 40)
		weather_row.add_child(b)
		_weather_buttons[item[0]] = b

	box.add_child(UiKit.label("El rival se genera al azar (Pokémon y ataques), con tantos Pokémon como tu equipo.", 14, Color(1, 1, 1, 0.6)))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(actions)
	actions.add_child(UiKit.button("Cancelar", func() -> void: _map_dialog.visible = false))
	_go_button = UiKit.button("¡A combatir!", _start_game, 22)
	_go_button.custom_minimum_size.x = 260
	actions.add_child(_go_button)


func _open_map_dialog() -> void:
	if Game.teams.all(func(t) -> bool: return t.members.is_empty()):
		_play_button.text = "Partida rápida (¡arma tu equipo!)"
		return
	_team_select.clear()
	for t in Game.teams:
		_team_select.add_item("%s  (%d Pokémon)" % [t.name, t.members.size()])
	_team_select.select(Game.current_team)
	_map_select.clear()
	_map_select.add_item("Generado al azar")
	_map_paths = Game.list_maps()
	for path in _map_paths:
		var m: MapData = load(path)
		_map_select.add_item("%s  (%s, %s)" % [m.map_name, Biome.NAMES[m.biome], Weather.NAMES[m.weather]])
	_refresh_dialog()
	_map_dialog.visible = true


func _refresh_dialog() -> void:
	var members: Array = Game.player_team.map(func(m: TeamMember) -> String: return m.data.species_name + TeamMember.GENDER_SYMBOLS[m.gender])
	_team_hint.text = ", ".join(members) if not members.is_empty() else "Este equipo está vacío: elige otro o complétalo en el editor."
	_go_button.disabled = members.is_empty()
	for i in _difficulty_buttons.size():
		_difficulty_buttons[i].button_pressed = i == Game.difficulty
	_difficulty_hint.text = Game.DIFFICULTY_DESC[Game.difficulty]
	_random_options.modulate.a = 1.0 if _map_select.selected <= 0 else 0.35
	for b in _topology_buttons:
		b.button_pressed = _topology_buttons.find(b) == Game.topology
	for kind: int in _biome_buttons:
		_biome_buttons[kind].button_pressed = kind == _selected_biome
	for kind: int in _weather_buttons:
		_weather_buttons[kind].button_pressed = kind == Game.weather


func _start_game() -> void:
	if _map_select.selected > 0:
		Game.map = load(_map_paths[_map_select.selected - 1])
	else:
		Game.map = null
		Game.biome = _selected_biome if _selected_biome != RANDOM_BIOME else Game.rng.randi_range(0, Biome.NAMES.size() - 1)
	Game.save()
	Game.roll_enemy_team()
	_go("battle")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _map_dialog.visible:
		_map_dialog.visible = false

extends Control
## Menú principal: jugar (eligiendo tablero), editor de equipo y tabla de tipos.

const SHOWCASE_TIME := 3.5

var _preview: PokemonPreview
var _preview_name: Label
var _showcase_index := 0
var _map_dialog: Control
var _play_button: Button


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.background())

	var left := VBoxContainer.new()
	left.position = Vector2(120, 170)
	left.add_theme_constant_override("separation", 14)
	add_child(left)
	var title := UiKit.label("POKÉ TACTICS", 72, UiKit.ACCENT)
	title.add_theme_constant_override("outline_size", 14)
	title.add_theme_color_override("font_outline_color", Color(0.1, 0.15, 0.35))
	left.add_child(title)
	left.add_child(UiKit.label("Prototipo · Godot 4", 18, Color(1, 1, 1, 0.6)))
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 30
	left.add_child(spacer)
	_play_button = _menu_button(left, "Jugar", _open_map_dialog)
	_menu_button(left, "Editor de equipo", func() -> void: get_tree().change_scene_to_file("res://scenes/team_editor.tscn"))
	_menu_button(left, "Tabla de tipos", func() -> void: get_tree().change_scene_to_file("res://scenes/type_chart.tscn"))
	_menu_button(left, "Salir", func() -> void: get_tree().quit())
	var team_info := UiKit.label("", 16, Color(1, 1, 1, 0.7))
	team_info.text = "Tu equipo: " + (", ".join(Game.player_team.map(func(p: PokemonData) -> String: return p.species_name)) if not Game.player_team.is_empty() else "vacío")
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


func _menu_button(parent: Control, text: String, callback: Callable) -> Button:
	var b := UiKit.button(text, callback, 24)
	b.custom_minimum_size = Vector2(340, 56)
	parent.add_child(b)
	return b


func _next_showcase() -> void:
	var list: Array[PokemonData] = Game.player_team if not Game.player_team.is_empty() else Game.roster
	if list.is_empty():
		return
	var p := list[_showcase_index % list.size()]
	_showcase_index += 1
	_preview.show_pokemon(p)
	_preview_name.text = "#%03d %s" % [p.dex_number, p.species_name]


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
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)
	var title := UiKit.label("Elige el tablero", 30, UiKit.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	row.add_child(_map_option("▦", "Cuadrícula", "4 direcciones.\nLíneas y cruces clásicas.", BoardGrid.Topology.SQUARE))
	row.add_child(_map_option("⬢", "Hexágonos", "6 direcciones.\nMás flanqueos y ángulos.", BoardGrid.Topology.HEX))
	var cancel := UiKit.button("Cancelar", func() -> void: _map_dialog.visible = false)
	box.add_child(cancel)


func _map_option(icon: String, title: String, desc: String, topology: BoardGrid.Topology) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(260, 230)
	b.pressed.connect(_start_game.bind(topology))
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(box)
	for l in [UiKit.label(icon, 80, UiKit.ACCENT), UiKit.label(title, 26), UiKit.label(desc, 15, Color(1, 1, 1, 0.7))]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(l)
	return b


func _open_map_dialog() -> void:
	if Game.player_team.is_empty():
		_play_button.text = "Jugar (¡arma tu equipo primero!)"
		return
	_map_dialog.visible = true


func _start_game(topology: BoardGrid.Topology) -> void:
	Game.topology = topology
	Game.save()
	Game.roll_enemy_team()
	get_tree().change_scene_to_file("res://scenes/battle.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _map_dialog.visible:
		_map_dialog.visible = false

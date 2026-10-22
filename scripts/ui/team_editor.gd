extends Control
## Editor de equipo: roster a la izquierda, ficha del Pokémon al centro y equipo (máx. 6) a la derecha.

const STAT_MAX := 160.0

var _selected: PokemonData
var _preview: PokemonPreview
var _detail: VBoxContainer
var _team_box: VBoxContainer
var _team_title: Label
var _add_button: Button
var _moves_box: VBoxContainer


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.background())

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 16
	root.offset_top = 16
	root.offset_right = -16
	root.offset_bottom = -16
	root.add_theme_constant_override("separation", 12)
	add_child(root)

	var top := HBoxContainer.new()
	root.add_child(top)
	top.add_child(UiKit.button("← Menú", func() -> void: get_tree().change_scene_to_file("res://scenes/main_menu.tscn")))
	var title := UiKit.label("  Editor de equipo", 30, UiKit.ACCENT)
	top.add_child(title)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 12)
	root.add_child(columns)

	# Roster
	var roster_panel := UiKit.panel()
	roster_panel.custom_minimum_size.x = 470
	columns.add_child(roster_panel)
	var roster_col := VBoxContainer.new()
	roster_panel.add_child(roster_col)
	roster_col.add_child(UiKit.label("Pokémon disponibles (%d)" % Game.roster.size(), 20))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	roster_col.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	for p in Game.roster:
		grid.add_child(_card(p, _select.bind(p), 212))

	# Ficha
	var detail_panel := UiKit.panel()
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(detail_panel)
	var detail_scroll := ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_panel.add_child(detail_scroll)
	var detail_col := VBoxContainer.new()
	detail_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_col.add_theme_constant_override("separation", 8)
	detail_scroll.add_child(detail_col)
	var preview_row := HBoxContainer.new()
	detail_col.add_child(preview_row)
	_preview = PokemonPreview.new()
	_preview.custom_minimum_size = Vector2(260, 260)
	preview_row.add_child(_preview)
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 6)
	preview_row.add_child(_detail)
	_add_button = UiKit.button("Agregar al equipo", _add_selected, 20)
	detail_col.add_child(_add_button)
	_moves_box = VBoxContainer.new()
	_moves_box.add_theme_constant_override("separation", 6)
	detail_col.add_child(_moves_box)

	# Equipo
	var team_panel := UiKit.panel()
	team_panel.custom_minimum_size.x = 380
	columns.add_child(team_panel)
	var team_col := VBoxContainer.new()
	team_col.add_theme_constant_override("separation", 8)
	team_panel.add_child(team_col)
	_team_title = UiKit.label("", 20)
	team_col.add_child(_team_title)
	_team_box = VBoxContainer.new()
	_team_box.add_theme_constant_override("separation", 8)
	team_col.add_child(_team_box)
	team_col.add_child(UiKit.label("Clic en un Pokémon para ver su ficha.\nEl orden del equipo es el orden de despliegue.", 14, Color(1, 1, 1, 0.55)))

	_refresh_team()
	_select(Game.player_team[0] if not Game.player_team.is_empty() else Game.roster[0])



## Tarjeta clicable con número, nombre y tipos.
func _card(p: PokemonData, callback: Callable, width: float) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(width, 62)
	b.pressed.connect(callback)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 10
	box.offset_top = 6
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 3)
	b.add_child(box)
	var name := UiKit.label("#%03d %s%s" % [p.dex_number, p.species_name, "  ◆" if p.size > 1 else ""], 16)
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name)
	box.add_child(UiKit.type_row(p.types, true))
	return b


func _select(p: PokemonData) -> void:
	_selected = p
	_preview.show_pokemon(p)
	UiKit.clear(_detail)
	_detail.add_child(UiKit.label("#%03d %s" % [p.dex_number, p.species_name], 28))
	_detail.add_child(UiKit.type_row(p.types))

	var stats := UiKit.base_stats(p)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	_detail.add_child(grid)
	for i in stats.size():
		grid.add_child(UiKit.label(UiKit.STAT_NAMES[i], 15, Color(1, 1, 1, 0.75)))
		var bar := ProgressBar.new()
		bar.max_value = STAT_MAX
		bar.value = stats[i]
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(170, 14)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color.from_hsv(clampf(stats[i] / STAT_MAX, 0.0, 1.0) * 0.33, 0.7, 0.9)
		fill.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("fill", fill)
		grid.add_child(bar)
		grid.add_child(UiKit.label(str(stats[i]), 15))
	var tiles := clampi(2 + roundi(p.base_speed / 45.0), 2, 6) + p.move_modifier
	_detail.add_child(UiKit.label("Movimiento %d · Salto %d · Tamaño %d" % [tiles, p.jump, p.size], 15, UiKit.ACCENT))

	# Debilidades / resistencias
	var profile := TypeChart.defensive_profile(p.types)
	for group in [["Débil a", [4.0, 2.0]], ["Resiste", [0.5, 0.25]], ["Inmune a", [0.0]]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var any := false
		for mult: float in group[1]:
			for t: String in profile:
				if is_equal_approx(profile[t], mult):
					var suffix := " ×4" if mult == 4.0 else (" ×¼" if mult == 0.25 else "")
					row.add_child(UiKit.type_chip(t, true, suffix))
					any = true
		if any:
			var line := HBoxContainer.new()
			var l := UiKit.label(group[0] + ":", 15, Color(1, 1, 1, 0.75))
			l.custom_minimum_size.x = 80
			line.add_child(l)
			line.add_child(row)
			_detail.add_child(line)

	UiKit.clear(_moves_box)
	_moves_box.add_child(UiKit.label("Ataques", 20, UiKit.ACCENT))
	for m in p.moves:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var head := VBoxContainer.new()
		head.custom_minimum_size.x = 150
		head.add_child(UiKit.label(m.display_name, 17))
		head.add_child(UiKit.type_chip(m.type, true))
		row.add_child(head)
		row.add_child(UiKit.label(Combat.describe(m), 14, Color(1, 1, 1, 0.8)))
		_moves_box.add_child(row)
		_moves_box.add_child(HSeparator.new())
	_refresh_add_button()


func _add_selected() -> void:
	if _selected and Game.add_to_team(_selected):
		_refresh_team()


func _refresh_team() -> void:
	UiKit.clear(_team_box)
	_team_title.text = "Tu equipo (%d/%d)" % [Game.player_team.size(), Game.MAX_TEAM]
	for i in Game.MAX_TEAM:
		if i < Game.player_team.size():
			var p := Game.player_team[i]
			var row := HBoxContainer.new()
			var card := _card(p, _select.bind(p), 270)
			row.add_child(card)
			var remove := UiKit.button("✕", func() -> void:
				Game.remove_from_team(i)
				_refresh_team())
			remove.tooltip_text = "Quitar del equipo"
			remove.custom_minimum_size = Vector2(52, 62)
			row.add_child(remove)
			_team_box.add_child(row)
		else:
			var empty := UiKit.panel()
			empty.custom_minimum_size = Vector2(330, 62)
			empty.self_modulate = Color(1, 1, 1, 0.35)
			var l := UiKit.label("— vacío —", 15, Color(1, 1, 1, 0.5))
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			empty.add_child(l)
			_team_box.add_child(empty)
	_refresh_add_button()


func _refresh_add_button() -> void:
	if _add_button == null:
		return
	var full := Game.player_team.size() >= Game.MAX_TEAM
	_add_button.disabled = full or _selected == null
	_add_button.text = "Equipo completo (6/6)" if full else "Agregar %s al equipo" % (_selected.species_name if _selected else "")

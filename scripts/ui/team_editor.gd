extends Control
## Editor de equipo: roster (con buscador) a la izquierda, ficha al centro y equipo (máx. 6)
## a la derecha. Al elegir un miembro del equipo se editan sus 4 ataques.

const STAT_MAX := 160.0
const CATEGORY_SHORT := ["Fís", "Esp", "Est"]

var _species: PokemonData
## Miembro del equipo que se está editando (null = viendo una especie del roster).
var _member: TeamMember
var _preview: PokemonPreview
var _detail: VBoxContainer
var _roster_grid: GridContainer
var _roster_search: LineEdit
var _team_box: VBoxContainer
var _team_title: Label
var _add_button: Button
var _moves_box: VBoxContainer
var _learn_box: VBoxContainer
var _learn_list: ItemList
var _learn_search: LineEdit
var _learn_type: OptionButton
var _learn_items: Array[MoveData] = []
var _learn_hint: Label


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
	top.add_child(UiKit.label("  Editor de equipo", 30, UiKit.ACCENT))

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 12)
	root.add_child(columns)

	# Roster
	var roster_panel := UiKit.panel()
	roster_panel.custom_minimum_size.x = 440
	columns.add_child(roster_panel)
	var roster_col := VBoxContainer.new()
	roster_col.add_theme_constant_override("separation", 8)
	roster_panel.add_child(roster_col)
	roster_col.add_child(UiKit.label("Pokémon disponibles (%d)" % Game.roster.size(), 20))
	_roster_search = LineEdit.new()
	_roster_search.placeholder_text = "Buscar por nombre, número o tipo…"
	_roster_search.clear_button_enabled = true
	_roster_search.text_changed.connect(func(_t: String) -> void: _filter_roster())
	roster_col.add_child(_roster_search)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	roster_col.add_child(scroll)
	_roster_grid = GridContainer.new()
	_roster_grid.columns = 2
	_roster_grid.add_theme_constant_override("h_separation", 8)
	_roster_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_roster_grid)
	for p in Game.roster:
		var card := _card(p, _select_species.bind(p), 196)
		card.set_meta("species", p)
		_roster_grid.add_child(card)

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
	_preview.custom_minimum_size = Vector2(240, 240)
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
	_build_learnset_box(detail_col)

	# Equipo
	var team_panel := UiKit.panel()
	team_panel.custom_minimum_size.x = 360
	columns.add_child(team_panel)
	var team_col := VBoxContainer.new()
	team_col.add_theme_constant_override("separation", 8)
	team_panel.add_child(team_col)
	_team_title = UiKit.label("", 20)
	team_col.add_child(_team_title)
	_team_box = VBoxContainer.new()
	_team_box.add_theme_constant_override("separation", 8)
	team_col.add_child(_team_box)
	team_col.add_child(UiKit.label("Clic en un miembro del equipo para\nelegir sus ataques. El orden del equipo\nes el orden de despliegue.", 14, Color(1, 1, 1, 0.55)))

	_refresh_team()
	if not Game.player_team.is_empty():
		_select_member(Game.player_team[0])
	else:
		_select_species(Game.roster[0])


func _build_learnset_box(parent: Control) -> void:
	_learn_box = VBoxContainer.new()
	_learn_box.add_theme_constant_override("separation", 6)
	parent.add_child(_learn_box)
	_learn_box.add_child(HSeparator.new())
	_learn_hint = UiKit.label("", 18, UiKit.ACCENT)
	_learn_box.add_child(_learn_hint)
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 8)
	_learn_box.add_child(filters)
	_learn_search = LineEdit.new()
	_learn_search.placeholder_text = "Buscar ataque…"
	_learn_search.clear_button_enabled = true
	_learn_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_learn_search.text_changed.connect(func(_t: String) -> void: _refresh_learnset())
	filters.add_child(_learn_search)
	_learn_type = OptionButton.new()
	_learn_type.add_item("Todos los tipos")
	for t in TypeChart.TYPES:
		_learn_type.add_item(Combat.TYPE_NAMES[t])
	_learn_type.item_selected.connect(func(_i: int) -> void: _refresh_learnset())
	filters.add_child(_learn_type)
	_learn_list = ItemList.new()
	_learn_list.custom_minimum_size.y = 300
	_learn_list.add_theme_font_size_override("font_size", 15)
	_learn_list.item_clicked.connect(func(index: int, _pos: Vector2, _button: int) -> void: _learn_move(_learn_items[index]))
	_learn_box.add_child(_learn_list)


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
	var title := UiKit.label("#%03d %s%s" % [p.dex_number, p.species_name, "  ◆" if p.size > 1 else ""], 16)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(title)
	box.add_child(UiKit.type_row(p.types, true))
	return b


func _filter_roster() -> void:
	var q := _roster_search.text.strip_edges().to_lower()
	for card in _roster_grid.get_children():
		var p: PokemonData = card.get_meta("species")
		var types := " ".join(Array(p.types).map(func(t: String) -> String: return Combat.TYPE_NAMES[t].to_lower()))
		card.visible = q.is_empty() or q in p.species_name.to_lower() or q in str(p.dex_number) or q in types


func _select_species(p: PokemonData) -> void:
	_member = null
	_show(p)


func _select_member(m: TeamMember) -> void:
	_member = m
	_show(m.data)


func _show(p: PokemonData) -> void:
	_species = p
	_preview.show_pokemon(p)
	UiKit.clear(_detail)
	_detail.add_child(UiKit.label("#%03d %s" % [p.dex_number, p.species_name], 28))
	_detail.add_child(UiKit.type_row(p.types))
	_detail.add_child(_abilities_row(p))

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
		bar.custom_minimum_size = Vector2(160, 14)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color.from_hsv(clampf(stats[i] / STAT_MAX, 0.0, 1.0) * 0.33, 0.7, 0.9)
		fill.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("fill", fill)
		grid.add_child(bar)
		grid.add_child(UiKit.label(str(stats[i]), 15))
	var tiles := clampi(2 + roundi(p.base_speed / 45.0), 2, 6) + p.move_modifier
	_detail.add_child(UiKit.label("Movimiento %d · Salto %d · Tamaño %d" % [tiles, p.jump, p.size], 15, UiKit.ACCENT))

	var profile := TypeChart.defensive_profile(p.types)
	for group in [["Débil a", [4.0, 2.0]], ["Resiste", [0.5, 0.25]], ["Inmune a", [0.0]]]:
		var row := HFlowContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("h_separation", 4)
		for mult: float in group[1]:
			for t: String in profile:
				if is_equal_approx(profile[t], mult):
					var suffix := " ×4" if mult == 4.0 else (" ×¼" if mult == 0.25 else "")
					row.add_child(UiKit.type_chip(t, true, suffix))
		if row.get_child_count() > 0:
			var line := HBoxContainer.new()
			var l := UiKit.label(group[0] + ":", 15, Color(1, 1, 1, 0.75))
			l.custom_minimum_size.x = 80
			line.add_child(l)
			line.add_child(row)
			_detail.add_child(line)

	_refresh_moves()
	_refresh_add_button()


## Habilidad: selector si es un miembro del equipo; lista si es una especie del roster.
func _abilities_row(p: PokemonData) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(UiKit.label("Habilidad:", 15, Color(1, 1, 1, 0.75)))
	if _member:
		var pick := OptionButton.new()
		for i in p.abilities.size():
			var id := p.abilities[i]
			pick.add_item(Abilities.display_name(id) + ("  (oculta)" if i == p.abilities.size() - 1 and p.abilities.size() > 1 else ""))
			pick.set_item_tooltip(i, Abilities.describe(id))
			if id == _member.ability:
				pick.select(i)
		pick.item_selected.connect(func(i: int) -> void:
			_member.ability = p.abilities[i]
			pick.tooltip_text = Abilities.describe(_member.ability)
			Game.save())
		pick.tooltip_text = Abilities.describe(_member.ability)
		row.add_child(pick)
	else:
		for id in p.abilities:
			var l := UiKit.label(Abilities.display_name(id), 15, UiKit.ACCENT if id in Abilities.IMPLEMENTED else Color(1, 1, 1, 0.5))
			l.tooltip_text = Abilities.describe(id)
			l.mouse_filter = Control.MOUSE_FILTER_PASS
			row.add_child(l)
	return row


func _refresh_moves() -> void:
	UiKit.clear(_moves_box)
	var moves: Array[MoveData] = _member.moves if _member else _species.moves
	var caption := "Ataques de tu %s (%d/%d)" % [_species.species_name, moves.size(), TeamMember.MAX_MOVES] \
		if _member else "Ataques por defecto"
	_moves_box.add_child(UiKit.label(caption, 20, UiKit.ACCENT))
	for m in moves:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var head := VBoxContainer.new()
		head.custom_minimum_size.x = 150
		head.add_child(UiKit.label(m.display_name, 17))
		head.add_child(UiKit.type_chip(m.type, true))
		row.add_child(head)
		var desc := UiKit.label(Combat.describe(m), 14, Color(1, 1, 1, 0.8))
		desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc.tooltip_text = m.flavor
		desc.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(desc)
		if _member:
			var remove := UiKit.button("✕", _forget_move.bind(m))
			remove.tooltip_text = "Olvidar este ataque"
			remove.custom_minimum_size = Vector2(44, 44)
			remove.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(remove)
		_moves_box.add_child(row)
		_moves_box.add_child(HSeparator.new())
	_learn_box.visible = _member != null
	if _member:
		_refresh_learnset()


func _refresh_learnset() -> void:
	var q := _learn_search.text.strip_edges().to_lower()
	var type_filter := "" if _learn_type.selected <= 0 else TypeChart.TYPES[_learn_type.selected - 1]
	_learn_list.clear()
	_learn_items.clear()
	for m in _species.learnset:
		if type_filter and m.type != type_filter:
			continue
		if q and q not in m.display_name.to_lower():
			continue
		var known := m in _member.moves
		var power := str(m.fixed_damage) + "*" if m.fixed_damage else (str(m.power) if m.power > 0 else "—")
		var idx := _learn_list.add_item("%s%s   ·  %s · %s · %s" % ["✓ " if known else "", m.display_name,
			Combat.TYPE_NAMES[m.type], CATEGORY_SHORT[m.category], power])
		_learn_list.set_item_custom_fg_color(idx, TypeChart.color(m.type).lightened(0.35) if not known else Color(1, 1, 1, 0.4))
		_learn_list.set_item_tooltip(idx, Combat.describe(m) + ("\n\n" + m.flavor if m.flavor else ""))
		_learn_items.append(m)
	var full := _member.moves.size() >= TeamMember.MAX_MOVES
	_learn_hint.text = "Puede aprender %d ataques%s" % [_species.learnset.size(),
		" — quita uno (✕) para elegir otro" if full else " — clic para enseñárselo"]


func _learn_move(m: MoveData) -> void:
	if m in _member.moves or _member.moves.size() >= TeamMember.MAX_MOVES:
		return
	_member.moves.append(m)
	Game.save()
	_refresh_moves()


func _forget_move(m: MoveData) -> void:
	_member.moves.erase(m)
	Game.save()
	_refresh_moves()


func _add_selected() -> void:
	if _species and Game.add_to_team(_species):
		_refresh_team()
		_select_member(Game.player_team.back())


func _refresh_team() -> void:
	UiKit.clear(_team_box)
	_team_title.text = "Tu equipo (%d/%d)" % [Game.player_team.size(), Game.MAX_TEAM]
	for i in Game.MAX_TEAM:
		if i < Game.player_team.size():
			var m := Game.player_team[i]
			var row := HBoxContainer.new()
			row.add_child(_card(m.data, _select_member.bind(m), 260))
			var remove := UiKit.button("✕", func() -> void:
				Game.remove_from_team(i)
				if _member == m:
					_select_species(m.data)
				_refresh_team())
			remove.tooltip_text = "Quitar del equipo"
			remove.custom_minimum_size = Vector2(52, 62)
			row.add_child(remove)
			_team_box.add_child(row)
		else:
			var empty := UiKit.panel()
			empty.custom_minimum_size = Vector2(320, 62)
			empty.self_modulate = Color(1, 1, 1, 0.35)
			var l := UiKit.label("— vacío —", 15, Color(1, 1, 1, 0.5))
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			empty.add_child(l)
			_team_box.add_child(empty)
	_refresh_add_button()


func _refresh_add_button() -> void:
	if _add_button == null or _species == null:
		return
	var full := Game.player_team.size() >= Game.MAX_TEAM
	_add_button.visible = _member == null
	_add_button.disabled = full
	_add_button.text = "Equipo completo (6/6)" if full else "Agregar %s al equipo" % _species.species_name

extends Control
## Editor de equipo: roster (con buscador) a la izquierda, ficha al centro y equipo (máx. 6)
## a la derecha. Al elegir un miembro del equipo se editan sus 4 ataques.

const STAT_MAX := 160.0
const CATEGORY_SHORT := ["Fís", "Esp", "Est"] # i18n

var _species: PokemonData
## Miembro del equipo que se está editando (null = viendo una especie del roster).
var _member: TeamMember
var _preview: PokemonPreview
var _viewer: AnimationViewer
var _detail: VBoxContainer
var _roster_grid: GridContainer
var _roster_search: LineEdit
var _team_box: VBoxContainer
var _team_title: Label
var _team_tabs: HFlowContainer
var _team_name: LineEdit
var _delete_team: Button
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
	Audio.music("menu")

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 16
	root.offset_top = 16
	root.offset_right = -16
	root.offset_bottom = -16
	root.add_theme_constant_override("separation", 12)
	add_child(root)

	root.add_child(UiKit.screen_header(tr("Editor de equipo"), "← Menú", func() -> void:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")))

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
	roster_col.add_child(UiKit.section(tr("Pokémon disponibles (%d)") % Game.roster.size()))
	_roster_search = LineEdit.new()
	_roster_search.placeholder_text = tr("Buscar por nombre, número o tipo…")
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
	var preview_col := VBoxContainer.new()
	preview_row.add_child(preview_col)
	_preview = PokemonPreview.new()
	_preview.custom_minimum_size = Vector2(240, 240)
	preview_col.add_child(_preview)
	var anim_button := UiKit.button(tr("Ver animaciones"), _open_viewer, 15)
	anim_button.theme_type_variation = UiKit.CARD_BUTTON
	anim_button.tooltip_text = tr("Reproduce sus animaciones y las de cada ataque")
	preview_col.add_child(anim_button)
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 6)
	preview_row.add_child(_detail)
	_add_button = UiKit.primary_button(tr("Agregar al equipo"), _add_selected, 20)
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
	_team_tabs = HFlowContainer.new()
	_team_tabs.add_theme_constant_override("h_separation", 4)
	_team_tabs.add_theme_constant_override("v_separation", 4)
	team_col.add_child(_team_tabs)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	team_col.add_child(name_row)
	_team_name = LineEdit.new()
	_team_name.placeholder_text = tr("Nombre del equipo")
	_team_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_team_name.text_submitted.connect(func(_t: String) -> void: _rename_team())
	_team_name.focus_exited.connect(_rename_team)
	name_row.add_child(_team_name)
	_delete_team = UiKit.danger_button(tr("Borrar"), _confirm_delete_team)
	_delete_team.tooltip_text = tr("Borrar este equipo")
	name_row.add_child(_delete_team)
	team_col.add_child(HSeparator.new())
	_team_title = UiKit.section("")
	team_col.add_child(_team_title)
	_team_box = VBoxContainer.new()
	_team_box.add_theme_constant_override("separation", 8)
	team_col.add_child(_team_box)
	team_col.add_child(UiKit.hint(tr("Clic en un miembro del equipo para\nelegir sus ataques. El orden del equipo\nes el orden de despliegue.")))

	_viewer = AnimationViewer.new()
	add_child(_viewer)

	_refresh_team()
	if not Game.player_team.is_empty():
		_select_member(Game.player_team[0])
	else:
		_select_species(Game.roster[0])


func _open_viewer() -> void:
	if _species:
		_viewer.open(_species, _member.moves if _member else _species.moves, Game.roster)


func _build_learnset_box(parent: Control) -> void:
	_learn_box = VBoxContainer.new()
	_learn_box.add_theme_constant_override("separation", 6)
	parent.add_child(_learn_box)
	_learn_box.add_child(HSeparator.new())
	_learn_hint = UiKit.section("", 18)
	_learn_hint.add_theme_color_override("font_color", UiKit.ACCENT)
	_learn_box.add_child(_learn_hint)
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 8)
	_learn_box.add_child(filters)
	_learn_search = LineEdit.new()
	_learn_search.placeholder_text = tr("Buscar ataque…")
	_learn_search.clear_button_enabled = true
	_learn_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_learn_search.text_changed.connect(func(_t: String) -> void: _refresh_learnset())
	filters.add_child(_learn_search)
	_learn_type = OptionButton.new()
	_learn_type.add_item(tr("Todos los tipos"))
	for t in TypeChart.TYPES:
		_learn_type.add_item(tr(Combat.TYPE_NAMES[t]))
	_learn_type.item_selected.connect(func(_i: int) -> void: _refresh_learnset())
	filters.add_child(_learn_type)
	_learn_list = ItemList.new()
	_learn_list.custom_minimum_size.y = 300
	_learn_list.add_theme_font_size_override("font_size", 15)
	_learn_list.item_clicked.connect(func(index: int, _pos: Vector2, _button: int) -> void: _learn_move(_learn_items[index]))
	_learn_box.add_child(_learn_list)


## Tarjeta clicable con número, nombre, talla y tipos. Se marca (toggle) la que se está viendo.
func _card(p: PokemonData, callback: Callable, width: float) -> Button:
	var b := Button.new()
	b.theme_type_variation = UiKit.CARD_BUTTON
	b.custom_minimum_size = Vector2(width, 64)
	b.toggle_mode = true
	b.pressed.connect(callback)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 12
	box.offset_top = 7
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	b.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(head)
	var dex := UiKit.label("#%03d" % p.dex_number, 14, Color(UiKit.NEON, 0.85))
	dex.add_theme_font_override("font", UiKit.bold_font())
	head.add_child(dex)
	var name_label := UiKit.label(p.species_name, 16)
	name_label.add_theme_font_override("font", UiKit.bold_font())
	head.add_child(name_label)
	head.add_child(UiKit.label(p.size_label(), 14, UiKit.TEXT_DIM))
	for l in head.get_children():
		(l as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		(l as Label).vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(UiKit.type_row(p.types, true))
	b.tooltip_text = p.size_description()
	return b


func _filter_roster() -> void:
	var q := _roster_search.text.strip_edges().to_lower()
	for card in _roster_grid.get_children():
		var p: PokemonData = card.get_meta("species")
		var types := " ".join(Array(p.types).map(func(t: String) -> String: return Combat.TYPE_NAMES[t].to_lower() + " " + tr(Combat.TYPE_NAMES[t]).to_lower()))
		card.visible = q.is_empty() or q in p.species_name.to_lower() or q in str(p.dex_number) or q in types


func _select_species(p: PokemonData) -> void:
	_member = null
	_show(p)


func _select_member(m: TeamMember) -> void:
	_member = m
	_show(m.data)


func _show(p: PokemonData) -> void:
	if p != _species:
		Audio.cry(p, 1.0, -8.0)
	_species = p
	_preview.show_pokemon(p)
	UiKit.clear(_detail)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", UiKit.SPACE_3)
	var dex := UiKit.label("#%03d" % p.dex_number, 22, UiKit.NEON)
	dex.add_theme_font_override("font", UiKit.bold_font())
	dex.size_flags_vertical = Control.SIZE_SHRINK_END
	name_row.add_child(dex)
	name_row.add_child(UiKit.title(p.species_name, 30, UiKit.TEXT))
	_detail.add_child(name_row)
	_mark_selected()
	_detail.add_child(UiKit.type_row(p.types))
	_detail.add_child(_abilities_row(p))
	_detail.add_child(_gender_row(p))
	if _member:
		_detail.add_child(_item_row())

	var stats := UiKit.base_stats(p)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	_detail.add_child(grid)
	for i in stats.size():
		grid.add_child(UiKit.label(tr(UiKit.STAT_NAMES[i]), 15, UiKit.TEXT_DIM))
		var bar := ProgressBar.new()
		bar.max_value = STAT_MAX
		bar.value = stats[i]
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(180, 10)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		# Color por valor en 8 escalones, para compartir los estilos entre barras.
		var step := roundf(clampf(stats[i] / STAT_MAX, 0.0, 1.0) * 8.0) / 8.0
		bar.add_theme_stylebox_override("fill", UiKit.flat_style(Color.from_hsv(step * 0.33, 0.7, 0.95), 2, 0))
		bar.add_theme_stylebox_override("background", UiKit.flat_style(Color(1, 1, 1, 0.08), 2, 0))
		grid.add_child(bar)
		grid.add_child(UiKit.label(str(stats[i]), 15))
	var tiles := clampi(2 + roundi(p.base_speed / 45.0), 2, 6) + p.move_modifier
	var swim := ""
	if "water" in p.types:
		swim = " " + tr("(%d nadando)") % ((tiles - mini(p.move_modifier, 0)) * 2)
	_detail.add_child(UiKit.label(tr("Movimiento %d%s · Salto %d · Talla %s") % [tiles, swim, p.jump, p.size_label()], 15, UiKit.NEON))

	var profile := TypeChart.defensive_profile(p.types)
	for group in [[tr("Débil a"), [4.0, 2.0]], [tr("Resiste"), [0.5, 0.25]], [tr("Inmune a"), [0.0]]]:
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
			var l := UiKit.label(group[0] + ":", 15, UiKit.TEXT_DIM)
			l.custom_minimum_size.x = 80
			line.add_child(l)
			line.add_child(row)
			_detail.add_child(line)

	_refresh_moves()
	_refresh_add_button()


## Género: botones si el miembro puede ser macho o hembra; texto en otro caso.
func _gender_row(p: PokemonData) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(UiKit.label(tr("Género:"), 15, UiKit.TEXT_DIM))
	var options := TeamMember.genders_for(p)
	if options == [0]:
		row.add_child(UiKit.label(tr("sin género"), 15))
		return row
	if p.male_ratio > 0.0 and p.male_ratio < 1.0:
		row.add_child(UiKit.hint("(%d%% ♂ / %d%% ♀)" % [roundi(p.male_ratio * 100), roundi((1.0 - p.male_ratio) * 100)]))
	for g in options:
		var b := UiKit.button(TeamMember.GENDER_SYMBOLS[g], func() -> void:
			if _member:
				_member.gender = g
				Game.save()
				_show(_member.data)
				_refresh_team(), 18)
		b.toggle_mode = true
		b.button_pressed = _member != null and _member.gender == g
		b.disabled = _member == null
		b.add_theme_color_override("font_color", Color(0.5, 0.75, 1.0) if g == 1 else Color(1.0, 0.55, 0.75))
		row.add_child(b)
	return row


## Objeto equipado (bayas y equipables; las piedras solo se usan en la Torre).
func _item_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(UiKit.label(tr("Objeto:"), 15, UiKit.TEXT_DIM))
	var pick := OptionButton.new()
	# Algunos sprites son grandes: se limita el icono en el botón y en la lista.
	pick.add_theme_constant_override("icon_max_width", 24)
	pick.get_popup().add_theme_constant_override("icon_max_width", 24)
	pick.add_item(tr("— ninguno —"))
	var items := Items.holdable()
	for i in items.size():
		var it := items[i]
		if it.icon:
			pick.add_icon_item(it.icon, it.display_name)
		else:
			pick.add_item(it.display_name)
		pick.set_item_tooltip(i + 1, it.description)
		if _member.item == it:
			pick.select(i + 1)
	pick.tooltip_text = _member.item.description if _member.item else ""
	pick.item_selected.connect(func(i: int) -> void:
		_member.item = null if i == 0 else items[i - 1]
		pick.tooltip_text = _member.item.description if _member.item else ""
		Game.save())
	row.add_child(pick)
	return row


## Habilidad: selector si es un miembro del equipo; lista si es una especie del roster.
func _abilities_row(p: PokemonData) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(UiKit.label(tr("Habilidad:"), 15, UiKit.TEXT_DIM))
	if _member:
		var pick := OptionButton.new()
		for i in p.abilities.size():
			var id := p.abilities[i]
			pick.add_item(Abilities.display_name(id) + ("  " + tr("(oculta)") if i == p.abilities.size() - 1 and p.abilities.size() > 1 else ""))
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
			var l := UiKit.label(Abilities.display_name(id), 15, UiKit.ACCENT if id in Abilities.IMPLEMENTED else UiKit.TEXT_DIM)
			l.tooltip_text = Abilities.describe(id)
			l.mouse_filter = Control.MOUSE_FILTER_PASS
			row.add_child(l)
	return row


func _refresh_moves() -> void:
	UiKit.clear(_moves_box)
	var moves: Array[MoveData] = _member.moves if _member else _species.moves
	var caption := tr("Ataques de tu %s (%d/%d)") % [_species.species_name, moves.size(), TeamMember.MAX_MOVES] \
		if _member else tr("Ataques por defecto")
	var caption_label := UiKit.section(caption)
	caption_label.add_theme_color_override("font_color", UiKit.ACCENT)
	_moves_box.add_child(caption_label)
	for m in moves:
		# Cada ataque en su tarjeta, con la franja del color de su tipo.
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UiKit.accent_card_style(TypeChart.color(m.type)))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		card.add_child(row)
		var head := VBoxContainer.new()
		head.custom_minimum_size.x = 150
		head.add_theme_constant_override("separation", 6)
		var move_name := UiKit.label(tr(m.display_name), 17)
		move_name.add_theme_font_override("font", UiKit.bold_font())
		head.add_child(move_name)
		var chips := HBoxContainer.new()
		chips.add_theme_constant_override("separation", 4)
		chips.add_child(UiKit.type_chip(m.type, true))
		chips.add_child(UiKit.category_chip(m.category))
		head.add_child(chips)
		row.add_child(head)
		var desc := UiKit.label(Combat.describe(m), 15, UiKit.TEXT_DIM)
		desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc.tooltip_text = tr(m.flavor)
		desc.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(desc)
		if _member:
			var remove := UiKit.ghost_button("✕", _forget_move.bind(m))
			remove.tooltip_text = tr("Olvidar este ataque")
			remove.custom_minimum_size = Vector2(44, 44)
			remove.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(remove)
		_moves_box.add_child(card)
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
		if q and q not in m.display_name.to_lower() and q not in tr(m.display_name).to_lower():
			continue
		var known := m in _member.moves
		var power := str(m.fixed_damage) + "*" if m.fixed_damage else (str(m.power) if m.power > 0 else "—")
		var idx := _learn_list.add_item("%s%s   ·  %s · %s · %s" % ["✓ " if known else "", tr(m.display_name),
			tr(Combat.TYPE_NAMES[m.type]), tr(CATEGORY_SHORT[m.category]), power])
		_learn_list.set_item_custom_fg_color(idx, TypeChart.color(m.type).lightened(0.35) if not known else Color(1, 1, 1, 0.4))
		_learn_list.set_item_tooltip(idx, Combat.describe(m) + ("\n\n" + tr(m.flavor) if m.flavor else ""))
		_learn_items.append(m)
	var full := _member.moves.size() >= TeamMember.MAX_MOVES
	_learn_hint.text = (tr("Puede aprender %d ataques: quita uno (✕) para elegir otro") if full \
		else tr("Puede aprender %d ataques: clic para enseñárselo")) % _species.learnset.size()


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


## Pestañas de equipos (hasta Game.MAX_TEAMS) y botón para crear uno nuevo.
func _refresh_team_tabs() -> void:
	UiKit.clear(_team_tabs)
	for i in Game.teams.size():
		var b := UiKit.button(Game.teams[i].name, _switch_team.bind(i), 14)
		b.toggle_mode = true
		b.button_pressed = i == Game.current_team
		_team_tabs.add_child(b)
	if Game.teams.size() < Game.MAX_TEAMS:
		var add := UiKit.button(tr("+ Nuevo"), func() -> void:
			_switch_team(Game.add_team()), 14)
		_team_tabs.add_child(add)
	_team_name.text = Game.teams[Game.current_team].name
	_delete_team.disabled = Game.teams.size() <= 1


func _switch_team(index: int) -> void:
	if index < 0:
		return
	Game.select_team(index)
	_refresh_team()
	if not Game.player_team.is_empty():
		_select_member(Game.player_team[0])
	elif _species:
		_select_species(_species)


func _rename_team() -> void:
	var new_name := _team_name.text.strip_edges()
	if new_name and new_name != Game.teams[Game.current_team].name:
		Game.teams[Game.current_team].name = new_name
		Game.save()
		_refresh_team_tabs()


## Borrar pide confirmación con un segundo clic.
func _confirm_delete_team() -> void:
	if _delete_team.text != tr("¿Seguro?"):
		_delete_team.text = tr("¿Seguro?")
		get_tree().create_timer(2.5).timeout.connect(func() -> void:
			if is_instance_valid(_delete_team): _delete_team.text = tr("Borrar"))
		return
	_delete_team.text = tr("Borrar")
	Game.remove_team(Game.current_team)
	_switch_team(Game.current_team)


func _refresh_team() -> void:
	_refresh_team_tabs()
	UiKit.clear(_team_box)
	_team_title.text = tr("Tu equipo (%d/%d)") % [Game.player_team.size(), Game.MAX_TEAM]
	for i in Game.MAX_TEAM:
		if i < Game.player_team.size():
			var m := Game.player_team[i]
			var row := HBoxContainer.new()
			var card := _card(m.data, _select_member.bind(m), 260)
			card.set_meta("member", m)
			if m.gender and TeamMember.display(m.data, m.gender) != m.data.species_name:
				var sym := UiKit.label(TeamMember.GENDER_SYMBOLS[m.gender], 18, Color(0.5, 0.75, 1.0) if m.gender == 1 else Color(1.0, 0.55, 0.75))
				sym.position = Vector2(232, 6)
				sym.mouse_filter = Control.MOUSE_FILTER_IGNORE
				card.add_child(sym)
			row.add_child(card)
			var remove := UiKit.ghost_button("✕", func() -> void:
				Game.remove_from_team(i)
				if _member == m:
					_select_species(m.data)
				_refresh_team())
			remove.tooltip_text = tr("Quitar del equipo")
			remove.custom_minimum_size = Vector2(52, 64)
			row.add_child(remove)
			_team_box.add_child(row)
		else:
			var empty := UiKit.panel(UiKit.CARD)
			empty.custom_minimum_size = Vector2(320, 64)
			empty.self_modulate = Color(1, 1, 1, 0.4)
			var l := UiKit.hint(tr("— vacío —"))
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			empty.add_child(l)
			_team_box.add_child(empty)
	_mark_selected()
	_refresh_add_button()


## Marca la tarjeta de lo que se está viendo: el miembro del equipo o, si no, la especie del roster.
func _mark_selected() -> void:
	for card in _roster_grid.get_children():
		(card as Button).set_pressed_no_signal(_member == null and card.get_meta("species") == _species)
	for row in _team_box.get_children():
		var card := row.get_child(0)
		if card is Button:
			(card as Button).set_pressed_no_signal(_member != null and card.get_meta("member") == _member)


func _refresh_add_button() -> void:
	if _add_button == null or _species == null:
		return
	var full := Game.player_team.size() >= Game.MAX_TEAM
	_add_button.visible = _member == null
	_add_button.disabled = full
	_add_button.text = tr("Equipo completo (6/6)") if full else tr("Agregar %s al equipo") % _species.species_name

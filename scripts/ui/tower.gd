extends Control
## Torre de Batallas: inicio, draft (4 × elegir 1 de 6 básicos), gestión entre pisos y fin.

const STAT_MAX := 160.0

var _run: TowerRun
var _content: Control
var _selected: TeamMember
var _preview: PokemonPreview
var _topology := BoardGrid.Topology.SQUARE
var _difficulty := 1
var _shop_open := false
var _shop_overlay: Control


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.background())
	Audio.music("menu")
	Audio.ambience("")
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
	top.add_child(UiKit.button("← Menú", func() -> void:
		Game.save()
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")))
	top.add_child(UiKit.label("  Torre de Batallas", 30, UiKit.ACCENT))
	_content = MarginContainer.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_content)
	_run = Game.tower
	_topology = Game.topology
	_difficulty = Game.difficulty
	_refresh()


func _refresh() -> void:
	UiKit.clear(_content)
	if _shop_overlay:
		_shop_overlay.queue_free()
		_shop_overlay = null
	_preview = null
	if _run == null:
		_show_start()
	elif _run.finished:
		_show_game_over()
	elif _run.picks_left > 0:
		_show_draft()
	else:
		_show_hub()


# --- Inicio ------------------------------------------------------------------------

func _show_start() -> void:
	var center := CenterContainer.new()
	_content.add_child(center)
	var panel := UiKit.panel()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	box.add_child(UiKit.label("Nueva subida a la Torre", 28, UiKit.ACCENT))
	box.add_child(UiKit.label("Elige 4 Pokémon básicos (de 6 al azar cada vez), empiezan a nivel 5.\nCada piso es un combate contra Pokémon salvajes: captúralos con Poké Balls,\nsube de nivel, evoluciona y llega lo más alto posible.", 16, Color(1, 1, 1, 0.8)))
	box.add_child(UiKit.label("Récord: piso %d" % Game.tower_best, 18, UiKit.ACCENT))
	box.add_child(UiKit.label("Tablero", 16, Color(1, 1, 1, 0.7)))
	var topo_row := HBoxContainer.new()
	box.add_child(topo_row)
	var topo_buttons: Array[Button] = []
	for item in [["▦ Cuadrícula", BoardGrid.Topology.SQUARE], ["⬢ Hexágonos", BoardGrid.Topology.HEX]]:
		var b := UiKit.button(item[0], func() -> void:
			_topology = item[1]
			for x in topo_buttons:
				x.button_pressed = topo_buttons.find(x) == _topology, 18)
		b.toggle_mode = true
		b.button_pressed = item[1] == _topology
		b.custom_minimum_size = Vector2(220, 44)
		topo_row.add_child(b)
		topo_buttons.append(b)
	box.add_child(UiKit.label("Dificultad", 16, Color(1, 1, 1, 0.7)))
	var diff_row := HBoxContainer.new()
	box.add_child(diff_row)
	var diff_buttons: Array[Button] = []
	for i in Game.DIFFICULTY_NAMES.size():
		var b := UiKit.button(Game.DIFFICULTY_NAMES[i], func() -> void:
			_difficulty = i
			for x in diff_buttons:
				x.button_pressed = diff_buttons.find(x) == _difficulty, 18)
		b.toggle_mode = true
		b.button_pressed = i == _difficulty
		b.custom_minimum_size = Vector2(146, 44)
		diff_row.add_child(b)
		diff_buttons.append(b)
	var go := UiKit.button("¡Empezar!", func() -> void:
		_run = TowerRun.new()
		_run.topology = _topology
		_run.difficulty = _difficulty
		_run.roll_offer()
		Game.tower = _run
		Game.save()
		_refresh(), 22)
	go.custom_minimum_size.y = 52
	box.add_child(go)


# --- Draft -----------------------------------------------------------------------------

func _show_draft() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	_content.add_child(col)
	col.add_child(UiKit.label("Elige tu Pokémon (%d de %d)" % [TowerRun.DRAFT_PICKS - _run.picks_left + 1, TowerRun.DRAFT_PICKS], 26))
	if not _run.party.is_empty():
		col.add_child(UiKit.label("Tu equipo: " + ", ".join(_run.party.map(func(m: TeamMember) -> String: return TeamMember.display(m.data, m.gender))), 16, UiKit.ACCENT))
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 16)
	col.add_child(row)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	row.add_child(grid)
	_preview = PokemonPreview.new()
	_preview.custom_minimum_size = Vector2(420, 420)
	row.add_child(_preview)
	for p in _run.offer:
		var b := Button.new()
		b.custom_minimum_size = Vector2(300, 150)
		b.pressed.connect(func() -> void:
			Audio.cry(p)
			_run.pick(p)
			Game.save()
			_refresh())
		b.mouse_entered.connect(func() -> void: _preview.show_pokemon(p))
		var box := VBoxContainer.new()
		box.set_anchors_preset(Control.PRESET_FULL_RECT)
		box.offset_left = 12
		box.offset_top = 8
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_constant_override("separation", 4)
		b.add_child(box)
		for c in [UiKit.label("#%03d %s" % [p.dex_number, p.species_name], 20), UiKit.type_row(p.types),
				UiKit.label("Total de stats: %d · Mov %d" % [UiKit.base_stats(p).reduce(func(a, v): return a + v, 0), clampi(2 + roundi(p.base_speed / 45.0), 2, 6) + p.move_modifier], 14, Color(1, 1, 1, 0.75)),
				UiKit.label("Ataques a nivel 5: " + ", ".join(TeamMember.moves_up_to(p, TowerRun.START_LEVEL).map(func(m: MoveData) -> String: return m.display_name)), 13, Color(1, 1, 1, 0.65)),
				UiKit.label(("Evoluciona a nivel %d" % p.evolve_level) if p.evolve_level > 0 else "No evoluciona", 13, UiKit.ACCENT)]:
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if c is Label:
				c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				c.custom_minimum_size.x = 270
			box.add_child(c)
		grid.add_child(b)
	if not _run.offer.is_empty():
		_preview.show_pokemon(_run.offer[0])


# --- Gestión entre pisos ---------------------------------------------------------------

func _show_hub() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_content.add_child(col)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 24)
	col.add_child(header)
	header.add_child(UiKit.label("Piso %d" % _run.floor_number, 28, UiKit.ACCENT))
	header.add_child(UiKit.label("Poké Balls: %d" % _run.balls, 20))
	var badges := UiKit.label("Medallas: %d" % _run.badges.size(), 20, Color(1.0, 0.85, 0.4))
	badges.tooltip_text = "\n".join(_run.badges) if not _run.badges.is_empty() else "Vence a los líderes de gimnasio (cada 10 pisos)."
	badges.mouse_filter = Control.MOUSE_FILTER_PASS
	header.add_child(badges)
	header.add_child(UiKit.label("%d ₽" % _run.money, 20, UiKit.ACCENT))
	var shop_button := UiKit.button("Tienda", func() -> void:
		_shop_open = true
		_refresh(), 18)
	header.add_child(shop_button)
	header.add_child(UiKit.label("Récord: piso %d" % Game.tower_best, 18, Color(1, 1, 1, 0.7)))
	header.add_child(UiKit.label("Dificultad: %s" % Game.DIFFICULTY_NAMES[_run.difficulty], 18, Color(1, 1, 1, 0.7)))

	var kind := TowerRun.floor_kind(_run.floor_number)
	var next_color := Color(1.0, 0.8, 0.3) if kind == "leader" else (Color(1.0, 0.6, 0.5) if kind == "trainer" else Color(0.7, 0.9, 0.7))
	col.add_child(UiKit.label("Próximo piso: %s" % _run.floor_preview(), 18, next_color))

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 12)
	col.add_child(columns)

	# Equipo y caja
	var lists := UiKit.panel()
	lists.custom_minimum_size.x = 380
	columns.add_child(lists)
	var lists_col := VBoxContainer.new()
	lists_col.add_theme_constant_override("separation", 6)
	lists.add_child(lists_col)
	lists_col.add_child(UiKit.label("Equipo (%d/%d)" % [_run.party.size(), TowerRun.MAX_PARTY], 20))
	for m in _run.party:
		lists_col.add_child(_member_card(m, true))
	lists_col.add_child(HSeparator.new())
	lists_col.add_child(UiKit.label("Caja (%d)" % _run.box.size(), 20))
	var box_scroll := ScrollContainer.new()
	box_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lists_col.add_child(box_scroll)
	var box_col := VBoxContainer.new()
	box_col.add_theme_constant_override("separation", 6)
	box_scroll.add_child(box_col)
	if _run.box.is_empty():
		box_col.add_child(UiKit.label("Captura Pokémon salvajes con Poké Balls\ndurante los combates.", 14, Color(1, 1, 1, 0.5)))
	for m in _run.box:
		box_col.add_child(_member_card(m, false))

	# Ficha del seleccionado
	var detail := UiKit.panel()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(detail)
	if _selected == null or (_selected not in _run.party and _selected not in _run.box):
		_selected = _run.party[0]
	detail.add_child(_member_detail(_selected))

	# Informe del último combate
	var report := UiKit.panel()
	report.custom_minimum_size.x = 360
	columns.add_child(report)
	var report_col := VBoxContainer.new()
	report.add_child(report_col)
	report_col.add_child(UiKit.label("Último combate" if not _run.last_report.is_empty() else "Antes de subir", 20))
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("normal_font_size", 15)
	text.text = "\n".join(_run.last_report) if not _run.last_report.is_empty() else \
		"Tu equipo se cura por completo antes de cada piso.\n\nElige los 4 ataques de cada Pokémon entre los que ha aprendido, y cambia miembros del equipo por los capturados."
	report_col.add_child(text)
	report_col.add_child(HSeparator.new())
	report_col.add_child(UiKit.label("Mochila", 20))
	report_col.add_child(UiKit.label("Clic: equipar a %s (o usar la piedra)." % TeamMember.display(_selected.data, _selected.gender), 13, Color(1, 1, 1, 0.55)))
	var bag_scroll := ScrollContainer.new()
	bag_scroll.custom_minimum_size.y = 220
	bag_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	report_col.add_child(bag_scroll)
	var bag := VBoxContainer.new()
	bag_scroll.add_child(bag)
	if _run.bag.is_empty():
		bag.add_child(UiKit.label("Vacía: a veces ganas un objeto al superar un piso, o cómpralos en la Tienda.", 14, Color(1, 1, 1, 0.5)))
	for id: String in _run.bag:
		var it := Items.find(id)
		if it == null:
			continue
		var b := UiKit.button("%s  ×%d" % [it.display_name, _run.bag[id]], _use_bag_item.bind(it), 15)
		b.icon = it.icon
		b.add_theme_constant_override("icon_max_width", 24)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.tooltip_text = it.description
		bag.add_child(b)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 12)
	col.add_child(actions)
	actions.add_child(UiKit.button("Abandonar la torre", _confirm_abandon, 16))
	var go := UiKit.button("¡Subir al piso %d!" % _run.floor_number, _next_floor, 22)
	go.custom_minimum_size = Vector2(320, 54)
	actions.add_child(go)
	if _shop_open:
		_build_shop()
	elif not _run.news.is_empty():
		_build_news()


## Símbolo y color de cada tipo de novedad.
const NEWS_STYLE := {
	"level": ["↑", Color(0.45, 1.0, 0.5)], "move": ["★", Color(0.5, 0.85, 1.0)],
	"evolve": ["★", Color(1.0, 0.55, 0.9)], "badge": ["★", Color(1.0, 0.82, 0.3)],
	"catch": ["✓", Color(1.0, 0.45, 0.4)], "item": ["", Color(1.0, 0.95, 0.75)],
}


## Anuncio al volver de un piso: niveles, ataques, evoluciones, objetos, medallas y capturas.
func _build_news() -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.65)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	_shop_overlay = overlay
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := UiKit.panel()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.13, 0.18)
	style.border_color = UiKit.ACCENT
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size.x = 560
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var title := UiKit.label("¡Piso %d superado!" % (_run.floor_number - 1), 30, UiKit.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = mini(600, 54 * _run.news.size())
	box.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 6)
	scroll.add_child(rows)
	# Lo más importante primero: dinero, medallas, capturas, objetos, evoluciones, niveles y ataques.
	var ordered: Array[Dictionary] = []
	for kind in ["money", "badge", "catch", "item", "evolve", "level", "move"]:
		ordered.append_array(_run.news.filter(func(n: Dictionary) -> bool: return n.kind == kind))
	var delay := 0.25
	for n: Dictionary in ordered:
		var row: Control
		if n.kind == "money":
			row = UiKit.label(n.text, 18, Color(1, 1, 1, 0.75))
			row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		else:
			row = _news_row(n)
		row.modulate.a = 0.0
		rows.add_child(row)
		var tw := create_tween()
		tw.tween_interval(delay)
		tw.tween_property(row, "modulate:a", 1.0, 0.25)
		if n.kind != "money":
			tw.tween_callback(Audio.sfx.bind("heal" if n.kind == "level" else ("buff" if n.kind in ["evolve", "badge"] else "ui_confirm"), -8.0))
		delay += 0.18
	var ok := UiKit.button("¡Genial!", func() -> void:
		_run.news.clear()
		_refresh(), 20)
	ok.custom_minimum_size.y = 46
	box.add_child(ok)
	ok.grab_focus.call_deferred()


func _news_row(n: Dictionary) -> Control:
	var style: Array = NEWS_STYLE.get(n.kind, ["•", Color.WHITE])
	var card := PanelContainer.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(style[1], 0.12)
	bg.border_color = style[1]
	bg.border_width_left = 4
	bg.set_corner_radius_all(6)
	bg.content_margin_left = 10
	bg.content_margin_right = 10
	bg.content_margin_top = 6
	bg.content_margin_bottom = 6
	card.add_theme_stylebox_override("panel", bg)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	card.add_child(line)
	var it := Items.find(n.get("item", "")) if n.has("item") else null
	if it and it.icon:
		var icon := TextureRect.new()
		icon.texture = it.icon
		icon.custom_minimum_size = Vector2(30, 30)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		line.add_child(icon)
	else:
		var sym := UiKit.label(style[0], 24, style[1])
		sym.custom_minimum_size.x = 30
		sym.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.add_child(sym)
	var text := UiKit.label(n.text, 19, style[1].lerp(Color.WHITE, 0.4))
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(text)
	return card


## Tienda: Poké Balls siempre, más los objetos al azar del piso (cada uno se compra una vez).
func _build_shop() -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	_shop_overlay = overlay
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := UiKit.panel()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.13, 0.18)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	box.add_child(UiKit.label("Tienda  ·  tienes %d ₽" % _run.money, 26, UiKit.ACCENT))
	box.add_child(UiKit.label("Los objetos cambian en cada piso.", 14, Color(1, 1, 1, 0.6)))
	box.add_child(_shop_row(null, "Poké Ball", "Para capturar Pokémon salvajes durante el combate. Tienes %d." % _run.balls, TowerRun.BALL_PRICE, func() -> void:
		if _run.buy_ball():
			Audio.sfx("ui_confirm", -4.0)
			Game.save()
		_refresh()))
	box.add_child(HSeparator.new())
	if _run.shop.is_empty():
		box.add_child(UiKit.label("No queda nada más a la venta en este piso.", 15, Color(1, 1, 1, 0.5)))
	for id in _run.shop:
		var it := Items.find(id)
		if it == null:
			continue
		box.add_child(_shop_row(it, it.display_name, it.description, TowerRun.price(it), func() -> void:
			if _run.buy(it):
				Audio.sfx("ui_confirm", -4.0)
				Game.save()
			_refresh()))
	var close := UiKit.button("Cerrar", func() -> void:
		_shop_open = false
		_refresh(), 18)
	box.add_child(close)


func _shop_row(it: ItemData, title: String, desc: String, cost: int, buy: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var icon := TextureRect.new()
	icon.texture = it.icon if it else null
	icon.custom_minimum_size = Vector2(30, 30)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)
	var text := VBoxContainer.new()
	text.custom_minimum_size.x = 460
	text.add_child(UiKit.label(title, 17))
	var d := UiKit.label(desc, 13, Color(1, 1, 1, 0.6))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size.x = 460
	text.add_child(d)
	row.add_child(text)
	var price := UiKit.label("%d ₽" % cost, 17, UiKit.ACCENT)
	price.custom_minimum_size.x = 80
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(price)
	var b := UiKit.button("Comprar", buy, 15)
	b.disabled = _run.money < cost
	row.add_child(b)
	return row


func _member_card(m: TeamMember, in_party: bool) -> Control:
	var row := HBoxContainer.new()
	var b := Button.new()
	b.custom_minimum_size = Vector2(286, 72)
	b.toggle_mode = true
	b.button_pressed = m == _selected
	b.pressed.connect(func() -> void:
		_selected = m
		Audio.cry(m.data, 1.0, -8.0)
		_refresh())
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 10
	box.offset_top = 4
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(box)
	var title := UiKit.label("%s  Nv. %d" % [TeamMember.display(m.data, m.gender), m.level], 16)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(title)
	var bar := ProgressBar.new()
	bar.max_value = m.exp_to_next()
	bar.value = m.exp
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(250, 8)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(bar)
	var types := UiKit.type_row(m.data.types, true)
	box.add_child(types)
	row.add_child(b)
	var move := UiKit.button("↓" if in_party else "↑", func() -> void:
		if in_party and _run.party.size() > 1:
			_run.party.erase(m)
			_run.box.append(m)
		elif not in_party and _run.party.size() < TowerRun.MAX_PARTY:
			_run.box.erase(m)
			_run.party.append(m)
		Game.save()
		_refresh(), 18)
	move.tooltip_text = "Mandar a la caja" if in_party else "Pasar al equipo"
	move.custom_minimum_size = Vector2(48, 72)
	move.disabled = (in_party and _run.party.size() <= 1) or (not in_party and _run.party.size() >= TowerRun.MAX_PARTY)
	row.add_child(move)
	return row


func _member_detail(m: TeamMember) -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	scroll.add_child(col)
	var top := HBoxContainer.new()
	col.add_child(top)
	_preview = PokemonPreview.new()
	_preview.custom_minimum_size = Vector2(200, 200)
	top.add_child(_preview)
	_preview.show_pokemon(m.data)
	var info := VBoxContainer.new()
	top.add_child(info)
	info.add_child(UiKit.label("%s  Nv. %d" % [TeamMember.display(m.data, m.gender), m.level], 24))
	info.add_child(UiKit.type_row(m.data.types))
	info.add_child(UiKit.label("Experiencia: %d / %d" % [m.exp, m.exp_to_next()], 15, Color(1, 1, 1, 0.75)))
	info.add_child(UiKit.label("Habilidad: %s" % Abilities.display_name(m.ability), 15, Color(1, 1, 1, 0.75)))
	var item_row := HBoxContainer.new()
	item_row.add_child(UiKit.label("Objeto: %s  " % (m.item.display_name if m.item else "—"), 15, Color(1, 1, 1, 0.75)))
	if m.item:
		var icon := TextureRect.new()
		icon.texture = m.item.icon
		icon.custom_minimum_size = Vector2(28, 28)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.tooltip_text = m.item.description
		item_row.add_child(icon)
		item_row.add_child(UiKit.button("Quitar", func() -> void:
			_run.unequip(m)
			Game.save()
			_refresh(), 13))
	info.add_child(item_row)
	if not m.data.stone_evolutions.is_empty():
		var stones := ", ".join(m.data.stone_evolutions.keys().map(func(id: String) -> String: return Items.find(id).display_name if Items.find(id) else id))
		info.add_child(UiKit.label("Evoluciona con: %s" % stones, 15, UiKit.ACCENT))
	if m.data.evolve_level > 0:
		var to := ", ".join(Array(m.data.evolves_to).map(func(id: String) -> String: return Game.find_species(id).species_name if Game.find_species(id) else id))
		info.add_child(UiKit.label("Evoluciona a %s a nivel %d" % [to, m.data.evolve_level], 15, UiKit.ACCENT))
	col.add_child(UiKit.label("Ataques (%d/4) — clic para quitar o añadir" % m.moves.size(), 18, UiKit.ACCENT))
	for mv in m.known:
		var on := mv in m.moves
		var b := UiKit.button("%s %s  [%s]%s" % ["✓" if on else "  ", mv.display_name, Combat.TYPE_NAMES[mv.type],
			("  · Pot %d" % mv.power) if mv.power > 0 else ""], func() -> void:
			if on and m.moves.size() > 1:
				m.moves.erase(mv)
			elif not on and m.moves.size() < TeamMember.MAX_MOVES:
				m.moves.append(mv)
			Game.save()
			_refresh(), 15)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.tooltip_text = Combat.describe(mv)
		b.modulate = Color.WHITE if on else Color(1, 1, 1, 0.6)
		col.add_child(b)
	if m.known.is_empty():
		col.add_child(UiKit.label("(sin ataques aprendidos por nivel)", 14, Color(1, 1, 1, 0.5)))
	return scroll


func _use_bag_item(it: ItemData) -> void:
	if it.category == ItemData.Category.STONE:
		var text := _run.use_stone(_selected, it)
		_run.last_report.append(text if text else "%s no reacciona a la %s." % [TeamMember.display(_selected.data, _selected.gender), it.display_name])
		if text:
			Audio.sfx("buff")
			Audio.cry(_selected.data)
	else:
		_run.equip(_selected, it)
		Audio.sfx("ui_place", -4.0)
	Game.save()
	_refresh()


func _next_floor() -> void:
	_run.prepare_floor()
	_run.last_report.clear()
	Game.mode = "tower"
	Game.map = null
	Game.save()
	get_tree().change_scene_to_file("res://scenes/battle.tscn")


func _confirm_abandon() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = "¿Abandonar esta subida? Se pierde el equipo (el récord se conserva)."
	dialog.ok_button_text = "Abandonar"
	dialog.cancel_button_text = "Seguir"
	dialog.confirmed.connect(func() -> void:
		Game.tower_best = maxi(Game.tower_best, _run.floor_number - 1)
		Game.tower = null
		_run = null
		Game.save()
		_refresh())
	add_child(dialog)
	dialog.popup_centered()


# --- Fin ---------------------------------------------------------------------------------

func _show_game_over() -> void:
	var center := CenterContainer.new()
	_content.add_child(center)
	var panel := UiKit.panel()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	box.add_child(UiKit.label("Fin de la subida", 32, UiKit.ACCENT))
	box.add_child(UiKit.label("Llegaste al piso %d. Récord: piso %d." % [_run.floor_number, Game.tower_best], 20))
	for line in _run.last_report:
		box.add_child(UiKit.label(line, 15, Color(1, 1, 1, 0.75)))
	box.add_child(UiKit.label("Tu equipo final: " + ", ".join(_run.party.map(func(m: TeamMember) -> String: return "%s Nv.%d" % [TeamMember.display(m.data, m.gender), m.level])), 15))
	var again := UiKit.button("Nueva subida", func() -> void:
		Game.tower = null
		_run = null
		Game.save()
		_refresh(), 20)
	box.add_child(again)

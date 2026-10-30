extends Control
## Torre de Batallas: inicio, draft (4 × elegir 1 de 6 básicos), gestión entre pisos y fin.

const STAT_MAX := 160.0
const LOCK_CLOSED := preload("res://assets/ui/lock_closed.svg")
const LOCK_OPEN := preload("res://assets/ui/lock_open.svg")

var _run: TowerRun
var _content: Control
var _selected: TeamMember
var _preview: PokemonPreview
var _topology := BoardGrid.Topology.SQUARE
var _difficulty := 1
## Ventana encima del hub (novedades o evolución).
var _overlay: Control


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
	top.add_child(UiKit.button(tr("← Menú"), func() -> void:
		Game.save()
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")))
	top.add_child(UiKit.label(tr("  Torre de Batallas"), 30, UiKit.ACCENT))
	_content = MarginContainer.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_content)
	_run = Game.tower
	_topology = Game.topology
	_difficulty = Game.difficulty
	_refresh()


func _refresh() -> void:
	UiKit.clear(_content)
	if _overlay:
		_overlay.queue_free()
		_overlay = null
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
	box.add_child(UiKit.label(tr("Nueva subida a la Torre"), 28, UiKit.ACCENT))
	box.add_child(UiKit.label(tr("Elige 4 Pokémon básicos (de 6 al azar cada vez), empiezan a nivel 5.\nCada piso es un combate contra Pokémon salvajes: captúralos con Poké Balls,\nsube de nivel, evoluciona y llega lo más alto posible."), 16, Color(1, 1, 1, 0.8)))
	box.add_child(UiKit.label(tr("Récord: piso %d") % Game.tower_best, 18, UiKit.ACCENT))
	box.add_child(UiKit.label(tr("Tablero"), 16, Color(1, 1, 1, 0.7)))
	var topo_row := HBoxContainer.new()
	box.add_child(topo_row)
	var topo_buttons: Array[Button] = []
	for item in [[tr("▦ Cuadrícula"), BoardGrid.Topology.SQUARE], [tr("⬢ Hexágonos"), BoardGrid.Topology.HEX]]:
		var b := UiKit.button(item[0], func() -> void:
			_topology = item[1]
			for x in topo_buttons:
				x.button_pressed = topo_buttons.find(x) == _topology, 18)
		b.toggle_mode = true
		b.button_pressed = item[1] == _topology
		b.custom_minimum_size = Vector2(220, 44)
		topo_row.add_child(b)
		topo_buttons.append(b)
	box.add_child(UiKit.label(tr("Dificultad"), 16, Color(1, 1, 1, 0.7)))
	var diff_row := HBoxContainer.new()
	box.add_child(diff_row)
	var diff_buttons: Array[Button] = []
	for i in Game.DIFFICULTY_NAMES.size():
		var b := UiKit.button(tr(Game.DIFFICULTY_NAMES[i]), func() -> void:
			_difficulty = i
			for x in diff_buttons:
				x.button_pressed = diff_buttons.find(x) == _difficulty, 18)
		b.toggle_mode = true
		b.button_pressed = i == _difficulty
		b.custom_minimum_size = Vector2(146, 44)
		diff_row.add_child(b)
		diff_buttons.append(b)
	var go := UiKit.button(tr("¡Empezar!"), func() -> void:
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
	col.add_child(UiKit.label(tr("Elige tu Pokémon (%d de %d)") % [TowerRun.DRAFT_PICKS - _run.picks_left + 1, TowerRun.DRAFT_PICKS], 26))
	if not _run.party.is_empty():
		col.add_child(UiKit.label(tr("Tu equipo:") + " " + ", ".join(_run.party.map(func(m: TeamMember) -> String: return TeamMember.display(m.data, m.gender))), 16, UiKit.ACCENT))
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
				UiKit.label(tr("Total de stats: %d · Mov %d") % [UiKit.base_stats(p).reduce(func(a, v): return a + v, 0), clampi(2 + roundi(p.base_speed / 45.0), 2, 6) + p.move_modifier], 14, Color(1, 1, 1, 0.75)),
				UiKit.label(tr("Ataques a nivel 5:") + " " + ", ".join(TeamMember.moves_up_to(p, TowerRun.START_LEVEL).map(func(m: MoveData) -> String: return tr(m.display_name))), 13, Color(1, 1, 1, 0.65)),
				UiKit.label((tr("Evoluciona a nivel %d") % p.evolve_level) if p.evolve_level > 0 else tr("No evoluciona"), 13, UiKit.ACCENT)]:
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
	header.add_child(UiKit.label(tr("Piso %d") % _run.floor_number, 28, UiKit.ACCENT))
	header.add_child(_ball_counts())
	var badges := UiKit.label(tr("Medallas: %d") % _run.badges.size(), 20, Color(1.0, 0.85, 0.4))
	badges.tooltip_text = "\n".join(Array(_run.badges).map(tr)) if not _run.badges.is_empty() else tr("Vence a los líderes de gimnasio (cada 10 pisos).")
	badges.mouse_filter = Control.MOUSE_FILTER_PASS
	header.add_child(badges)
	header.add_child(UiKit.label("%d ₽" % _run.money, 20, UiKit.ACCENT))
	header.add_child(UiKit.label(tr("Récord: piso %d") % Game.tower_best, 18, Color(1, 1, 1, 0.7)))
	header.add_child(UiKit.label(tr("Dificultad: %s") % tr(Game.DIFFICULTY_NAMES[_run.difficulty]), 18, Color(1, 1, 1, 0.7)))

	var kind := TowerRun.floor_kind(_run.floor_number)
	var next_color := Color(1.0, 0.8, 0.3) if kind == "leader" else (Color(1.0, 0.6, 0.5) if kind == "trainer" else Color(0.7, 0.9, 0.7))
	col.add_child(UiKit.label(tr("Próximo piso: %s") % _run.floor_preview(), 18, next_color))

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
	lists_col.add_child(UiKit.label(tr("Equipo (%d/%d)") % [_run.party.size(), TowerRun.MAX_PARTY], 20))
	for m in _run.party:
		lists_col.add_child(_member_card(m, true))
	lists_col.add_child(HSeparator.new())
	lists_col.add_child(UiKit.label(tr("Caja (%d)") % _run.box.size(), 20))
	var box_scroll := ScrollContainer.new()
	box_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lists_col.add_child(box_scroll)
	var box_col := VBoxContainer.new()
	box_col.add_theme_constant_override("separation", 6)
	box_scroll.add_child(box_col)
	if _run.box.is_empty():
		box_col.add_child(UiKit.label(tr("Captura Pokémon salvajes con Poké Balls\ndurante los combates."), 14, Color(1, 1, 1, 0.5)))
	for m in _run.box:
		box_col.add_child(_member_card(m, false))

	columns.add_child(_build_shop())

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
	report_col.add_child(UiKit.label(tr("Último combate") if not _run.last_report.is_empty() else tr("Antes de subir"), 20))
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("normal_font_size", 15)
	text.text = Msg.lines(_run.last_report) if not _run.last_report.is_empty() else \
		tr("Tu equipo se cura por completo antes de cada piso.\n\nElige los 4 ataques de cada Pokémon entre los que ha aprendido, y cambia miembros del equipo por los capturados.")
	report_col.add_child(text)
	report_col.add_child(HSeparator.new())
	report_col.add_child(UiKit.label(tr("Mochila"), 20))
	var bag_hint := UiKit.label(tr("Clic: equipar a %s (o usar la piedra).") % TeamMember.display(_selected.data, _selected.gender), 13, Color(1, 1, 1, 0.55))
	bag_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	report_col.add_child(bag_hint)
	var bag_scroll := ScrollContainer.new()
	bag_scroll.custom_minimum_size.y = 220
	bag_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	report_col.add_child(bag_scroll)
	var bag := VBoxContainer.new()
	bag_scroll.add_child(bag)
	if _run.bag.is_empty():
		var empty := UiKit.label(tr("Vacía: a veces ganas un objeto al superar un piso, o cómpralos en la Tienda."), 14, Color(1, 1, 1, 0.5))
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size.x = 320
		bag.add_child(empty)
	for id: String in _run.bag:
		var it := Items.find(id)
		if it == null:
			continue
		var b := UiKit.button("%s  ×%d" % [tr(it.display_name), _run.bag[id]], _use_bag_item.bind(it), 15)
		b.icon = it.icon
		b.add_theme_constant_override("icon_max_width", 24)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.tooltip_text = it.description
		bag.add_child(b)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 12)
	col.add_child(actions)
	actions.add_child(UiKit.button(tr("Abandonar la torre"), _confirm_abandon, 16))
	var go := UiKit.button(tr("¡Subir al piso %d!") % _run.floor_number, _next_floor, 22)
	go.custom_minimum_size = Vector2(320, 54)
	actions.add_child(go)
	if not _run.news.is_empty():
		_build_news()
	else:
		# Tras las novedades, las evoluciones pendientes, de una en una.
		for m in _run.party + _run.box:
			if m.wants_to_evolve:
				var target := _run.level_evolution(m)
				if target:
					_build_evolution(m, target)
					break
				m.wants_to_evolve = false


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
	_overlay = overlay
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
	var title := UiKit.label(tr("¡Piso %d superado!") % (_run.floor_number - 1), 30, UiKit.ACCENT)
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
	var ok := UiKit.button(tr("¡Genial!"), func() -> void:
		_run.news.clear()
		_refresh(), 20)
	ok.custom_minimum_size.y = 46
	box.add_child(ok)
	ok.grab_focus.call_deferred()


## Tiempo de cada cambio de forma durante la evolución (cada vez más rápido).
const EVOLVE_SWAPS := [0.55, 0.5, 0.45, 0.4, 0.34, 0.28, 0.23, 0.18, 0.14, 0.11, 0.09, 0.08, 0.08]
const EVOLVE_GLOW := Color(4, 4, 4)


## Animación de evolución: el Pokémon brilla y alterna entre su forma y la nueva cada vez más rápido.
## Se puede cancelar mientras dura (con piedra, la piedra no se gasta).
func _build_evolution(m: TeamMember, target: PokemonData, stone: ItemData = null) -> void:
	if _overlay:
		_overlay.queue_free()
	var who := TeamMember.display(m.data, m.gender)
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.75)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	_overlay = overlay
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
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := UiKit.label(tr("¿Eh? ¡%s está evolucionando!") % who, 26, UiKit.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var preview := PokemonPreview.new()
	preview.custom_minimum_size = Vector2(400, 360)
	preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(preview)
	preview.show_pokemon(m.data)
	var details := UiKit.label("", 16, Color(1, 1, 1, 0.8))
	details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(details)
	var button := Button.new()
	button.text = tr("Cancelar")
	button.add_theme_font_size_override("font_size", 20)
	button.custom_minimum_size.y = 46
	box.add_child(button)
	Audio.cry(m.data)

	# "running" mientras dura, luego "done" (evolucionó) o "cancelled".
	var phase := {"value": "running"}
	var tw := create_tween()
	tw.tween_interval(1.2)
	tw.tween_property(preview, "self_modulate", EVOLVE_GLOW, 0.8)
	for i in EVOLVE_SWAPS.size():
		var shown := target if i % 2 == 0 else m.data
		tw.tween_callback(func() -> void:
			preview.show_pokemon(shown)
			Audio.sfx("ui_hover", -6.0, 0.8 + 0.05 * i))
		tw.tween_interval(EVOLVE_SWAPS[i])
	tw.tween_callback(func() -> void:
		phase.value = "done"
		preview.show_pokemon(target)
		var events := _run.evolve(m, target, stone)
		title.text = tr("¡Enhorabuena! ¡%s evolucionó a %s!") % [who, target.species_name]
		details.text = Msg.lines(events.slice(1))
		button.text = tr("¡Genial!")
		Audio.sfx("buff")
		Audio.cry(target))
	tw.tween_property(preview, "self_modulate", Color.WHITE, 0.6)

	button.pressed.connect(func() -> void:
		if phase.value == "running":
			# Cancelado: vuelve a su forma (sin brillo) y no evoluciona.
			phase.value = "cancelled"
			tw.kill()
			preview.show_pokemon(m.data)
			preview.self_modulate = Color.WHITE
			if stone == null:
				_run.cancel_evolution(m)
			title.text = tr("¿Eh? %s dejó de evolucionar.") % who
			details.text = tr("Puedes evolucionarlo luego desde su ficha.") if stone == null else tr("No se ha gastado: %s.") % tr(stone.display_name)
			button.text = tr("Vale")
			Audio.sfx("ui_error", -6.0)
		else:
			Game.save()
			_refresh())
	button.grab_focus.call_deferred()


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
func _build_shop() -> Control:
	var panel := UiKit.panel()
	panel.custom_minimum_size.x = 360
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	var title_row := HBoxContainer.new()
	col.add_child(title_row)
	var title := UiKit.label(tr("Tienda"), 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var lock := UiKit.button(tr("Bloqueada") if _run.shop_locked else tr("Bloquear"), func() -> void:
		_run.shop_locked = not _run.shop_locked
		Audio.sfx("ui_place" if _run.shop_locked else "ui_hover", -4.0)
		Game.save()
		_refresh(), 14)
	lock.icon = LOCK_CLOSED if _run.shop_locked else LOCK_OPEN
	lock.toggle_mode = true
	lock.button_pressed = _run.shop_locked
	lock.tooltip_text = tr("Con el candado puesto, al superar el piso la tienda conserva lo que queda a la venta (el candado se quita solo al llegar).")
	if _run.shop_locked:
		lock.add_theme_color_override("font_color", UiKit.ACCENT)
		lock.add_theme_color_override("font_pressed_color", UiKit.ACCENT)
		lock.add_theme_color_override("icon_pressed_color", UiKit.ACCENT)
	title_row.add_child(lock)
	col.add_child(UiKit.label((tr("Tienes %d ₽ · se guarda para el próximo piso.") if _run.shop_locked else tr("Tienes %d ₽ · los objetos cambian en cada piso.")) % _run.money, 13,
		UiKit.ACCENT if _run.shop_locked else Color(1, 1, 1, 0.6)))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	for kind: String in TowerRun.BALL_KINDS:
		if _run.ball_always_sold(kind):
			box.add_child(_ball_row(kind))
	box.add_child(HSeparator.new())
	if _run.shop.is_empty():
		box.add_child(UiKit.label(tr("No queda nada más a la venta en este piso."), 14, Color(1, 1, 1, 0.5)))
	for id in _run.shop:
		if id.begins_with(TowerRun.SHOP_BALL_PREFIX):
			box.add_child(_ball_row(id.trim_prefix(TowerRun.SHOP_BALL_PREFIX)))
			continue
		var it := Items.find(id)
		if it == null:
			continue
		box.add_child(_shop_row(it.icon, it.display_name, it.description, TowerRun.price(it), func() -> void:
			if _run.buy(it):
				Audio.sfx("ui_confirm", -4.0)
				Game.save()
			_refresh()))
	return panel


func _ball_row(kind: String) -> Control:
	var ball: Dictionary = TowerRun.BALLS[kind]
	return _shop_row(ball.icon, tr(ball.name), tr("%s Tienes %d.") % [tr(ball.desc), _run.ball_count(kind)], ball.price, func() -> void:
		if _run.buy_ball(kind):
			Audio.sfx("ui_confirm", -4.0)
			Game.save()
		_refresh())


## Balls que tienes: icono y cantidad de cada tipo (la Poké Ball siempre, las demás si tienes alguna).
func _ball_counts() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for kind: String in TowerRun.BALL_KINDS:
		if kind != "poke" and _run.ball_count(kind) == 0:
			continue
		var ball: Dictionary = TowerRun.BALLS[kind]
		var icon := TextureRect.new()
		icon.texture = ball.icon
		icon.custom_minimum_size = Vector2(30, 30)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.tooltip_text = ball.name
		row.add_child(icon)
		var count := UiKit.label("%d " % _run.ball_count(kind), 20)
		count.tooltip_text = ball.name
		count.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(count)
	return row


func _shop_row(texture: Texture2D, title: String, desc: String, cost: int, buy: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var icon := TextureRect.new()
	icon.texture = texture
	icon.custom_minimum_size = Vector2(30, 30)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(icon)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_child(UiKit.label(title, 16))
	var d := UiKit.label(desc, 12, Color(1, 1, 1, 0.6))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(d)
	row.add_child(text)
	var buy_col := VBoxContainer.new()
	buy_col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var price := UiKit.label("%d ₽" % cost, 16, UiKit.ACCENT)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	buy_col.add_child(price)
	var b := UiKit.button(tr("Comprar"), buy, 14)
	b.disabled = _run.money < cost
	buy_col.add_child(b)
	row.add_child(buy_col)
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
	var title := UiKit.label(tr("%s  Nv. %d") % [TeamMember.display(m.data, m.gender), m.level], 16)
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
	move.tooltip_text = tr("Mandar a la caja") if in_party else tr("Pasar al equipo")
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
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # el ancho lo pone la ficha, no el texto
	top.add_child(info)
	info.add_child(UiKit.label(tr("%s  Nv. %d") % [TeamMember.display(m.data, m.gender), m.level], 24))
	info.add_child(UiKit.type_row(m.data.types))
	info.add_child(UiKit.label(tr("Experiencia: %d / %d") % [m.exp, m.exp_to_next()], 15, Color(1, 1, 1, 0.75)))
	info.add_child(_wrapped(UiKit.label(tr("Habilidad: %s") % Abilities.display_name(m.ability), 15, Color(1, 1, 1, 0.75))))
	var item_row := HBoxContainer.new()
	item_row.add_child(UiKit.label(tr("Objeto: %s") % (tr(m.item.display_name) if m.item else "—") + "  ", 15, Color(1, 1, 1, 0.75)))
	if m.item:
		var icon := TextureRect.new()
		icon.texture = m.item.icon
		icon.custom_minimum_size = Vector2(28, 28)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.tooltip_text = m.item.description
		item_row.add_child(icon)
		item_row.add_child(UiKit.button(tr("Quitar"), func() -> void:
			_run.unequip(m)
			Game.save()
			_refresh(), 13))
	info.add_child(item_row)
	if not m.data.stone_evolutions.is_empty():
		var stones := ", ".join(m.data.stone_evolutions.keys().map(func(id: String) -> String: return tr(Items.find(id).display_name) if Items.find(id) else id))
		info.add_child(_wrapped(UiKit.label(tr("Evoluciona con: %s") % stones, 15, UiKit.ACCENT)))
	if m.data.evolve_level > 0:
		var to := ", ".join(Array(m.data.evolves_to).map(func(id: String) -> String: return Game.find_species(id).species_name if Game.find_species(id) else id))
		info.add_child(_wrapped(UiKit.label(tr("Evoluciona a %s a nivel %d") % [to, m.data.evolve_level], 15, UiKit.ACCENT)))
		if m.can_evolve_by_level():
			info.add_child(UiKit.button(tr("Evolucionar"), func() -> void:
				m.wants_to_evolve = true
				_refresh(), 15))
	col.add_child(UiKit.label(tr("Ataques (%d/4) — clic para quitar o añadir") % m.moves.size(), 18, UiKit.ACCENT))
	for mv in m.known:
		var on := mv in m.moves
		var b := UiKit.move_button(mv, "%s %s" % ["✓" if on else "  ", tr(mv.display_name)],
			tr("Pot %d") % mv.power if mv.power > 0 else "", func() -> void:
			if on and m.moves.size() > 1:
				m.moves.erase(mv)
			elif not on and m.moves.size() < TeamMember.MAX_MOVES:
				m.moves.append(mv)
			Game.save()
			_refresh(), "", 15)
		b.modulate = Color.WHITE if on else Color(1, 1, 1, 0.6)
		col.add_child(b)
	if m.known.is_empty():
		col.add_child(UiKit.label(tr("(sin ataques aprendidos por nivel)"), 14, Color(1, 1, 1, 0.5)))
	return scroll


## Texto que baja de línea al llegar al borde en vez de ensanchar su panel (p. ej. las tres piedras de Eevee).
func _wrapped(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _use_bag_item(it: ItemData) -> void:
	if it.category == ItemData.Category.STONE:
		var target := TowerRun.stone_evolution(_selected, it)
		if target:
			_build_evolution(_selected, target, it)
			return
		_run.last_report.append(tr("%s no reacciona: %s.") % [TeamMember.display(_selected.data, _selected.gender), tr(it.display_name)])
		Audio.sfx("ui_error", -6.0)
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
	dialog.dialog_text = tr("¿Abandonar esta subida? Se pierde el equipo (el récord se conserva).")
	dialog.ok_button_text = tr("Abandonar")
	dialog.cancel_button_text = tr("Seguir")
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
	box.add_child(UiKit.label(tr("Fin de la subida"), 32, UiKit.ACCENT))
	box.add_child(UiKit.label(tr("Llegaste al piso %d. Récord: piso %d.") % [_run.floor_number, Game.tower_best], 20))
	for line: Variant in _run.last_report:
		box.add_child(UiKit.label(Msg.text(line), 15, Color(1, 1, 1, 0.75)))
	box.add_child(UiKit.label(tr("Tu equipo final:") + " " + ", ".join(_run.party.map(func(m: TeamMember) -> String: return tr("%s Nv.%d") % [TeamMember.display(m.data, m.gender), m.level])), 15))
	var again := UiKit.button(tr("Nueva subida"), func() -> void:
		Game.tower = null
		_run = null
		Game.save()
		_refresh(), 20)
	box.add_child(again)

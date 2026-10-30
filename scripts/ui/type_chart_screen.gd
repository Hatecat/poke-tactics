extends Control
## Tabla de tipos 18×18 (filas = atacante, columnas = defensor) y ficha del tipo elegido.

const CELL := 42

var _info: VBoxContainer
## Columna de la ficha; `_info` apunta a la tarjeta que se está rellenando.
var _info_root: VBoxContainer
var _cells := {} # Vector2i(atacante, defensor) -> Panel
## Cabeceras de cada tipo (fila y columna), para marcar el elegido.
var _headers := {} # tipo -> Array[Button]
var _selected := 0
## Celda bajo el ratón (fila y columna resaltadas), o (-1, -1).
var _hover := Vector2i(-1, -1)


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
	root.add_child(UiKit.screen_header(tr("Tabla de tipos"), tr("← Menú"), func() -> void:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")))

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(columns)

	var chart_panel := UiKit.panel()
	columns.add_child(chart_panel)
	var chart_col := VBoxContainer.new()
	chart_col.add_theme_constant_override("separation", UiKit.SPACE_3)
	chart_panel.add_child(chart_col)
	var help := UiKit.hint(tr("Filas: tipo del ataque · Columnas: tipo del Pokémon que lo recibe · Clic en un tipo para ver su ficha"))
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size.x = 400
	chart_col.add_child(help)
	var grid := GridContainer.new()
	grid.columns = TypeChart.TYPES.size() + 1
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	chart_col.add_child(grid)

	var corner := UiKit.label(tr("ATQ \\ DEF"), 12, Color(UiKit.NEON, 0.8))
	corner.add_theme_font_override("font", UiKit.bold_font())
	corner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	grid.add_child(corner)
	for t in TypeChart.TYPES:
		grid.add_child(_type_header(t))
	for a in TypeChart.TYPES.size():
		grid.add_child(_type_header(TypeChart.TYPES[a]))
		for d in TypeChart.TYPES.size():
			var mult := TypeChart.effectiveness(TypeChart.TYPES[a], [TypeChart.TYPES[d]])
			var cell := Panel.new()
			cell.custom_minimum_size = Vector2(CELL, CELL * 0.8)
			cell.add_theme_stylebox_override("panel", UiKit.flat_style(_mult_color(mult), 4, 0))
			cell.mouse_entered.connect(_set_hover.bind(Vector2i(a, d)))
			cell.mouse_exited.connect(_set_hover.bind(Vector2i(-1, -1)))
			cell.tooltip_text = "%s → %s: ×%s" % [tr(Combat.TYPE_NAMES[TypeChart.TYPES[a]]), tr(Combat.TYPE_NAMES[TypeChart.TYPES[d]]), _mult_text(mult)]
			var l := UiKit.label(_mult_text(mult) if mult != 1.0 else "", 16)
			l.add_theme_font_override("font", UiKit.bold_font())
			l.set_anchors_preset(Control.PRESET_FULL_RECT)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.add_child(l)
			grid.add_child(cell)
			_cells[Vector2i(a, d)] = cell

	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", UiKit.SPACE_2)
	chart_col.add_child(legend)
	for item in [[2.0, tr("Muy eficaz")], [0.5, tr("Poco eficaz")], [0.0, tr("Sin efecto")]]:
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", UiKit.flat_style(_mult_color(item[0]), UiKit.CHIP_H / 2, 3))
		var l := UiKit.label("×%s %s" % [_mult_text(item[0]), tr(item[1])], 15)
		l.add_theme_font_override("font", UiKit.bold_font())
		chip.add_child(l)
		legend.add_child(chip)

	var info_panel := UiKit.panel()
	info_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(info_panel)
	_info = VBoxContainer.new()
	_info_root = _info
	_info.add_theme_constant_override("separation", UiKit.SPACE_3)
	info_panel.add_child(_info)
	UiKit.brackets(info_panel, Color(UiKit.NEON, 0.6), 16.0, 6.0)
	_show_type("fire")


## Cabecera de fila o columna: chip del color del tipo; el tipo elegido lleva borde ACCENT (toggle).
func _type_header(t: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(CELL + 6, CELL * 0.8)
	b.text = tr(UiKit.TYPE_ABBR[t])
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_font_override("font", UiKit.bold_font())
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	var color := TypeChart.color(t)
	b.add_theme_stylebox_override("normal", UiKit.flat_style(color, 4, 0))
	b.add_theme_stylebox_override("hover", UiKit.flat_style(color.lightened(0.2), 4, 0))
	var selected: StyleBoxFlat = UiKit.flat_style(color.lightened(0.1), 4, 0).duplicate()
	selected.border_color = UiKit.ACCENT
	selected.set_border_width_all(2)
	selected.shadow_color = Color(UiKit.ACCENT, 0.4)
	selected.shadow_size = 6
	for state in ["pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(state, selected)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, Color.WHITE)
	if not _headers.has(t):
		_headers[t] = []
	_headers[t].append(b)
	b.add_theme_constant_override("outline_size", 4)
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	b.tooltip_text = tr(Combat.TYPE_NAMES[t])
	b.pressed.connect(_show_type.bind(t))
	return b


func _show_type(t: String) -> void:
	_info = _info_root
	UiKit.clear(_info)
	var chip := UiKit.type_chip(t)
	chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_info.add_child(chip)
	var title := UiKit.title(tr(Combat.TYPE_NAMES[t]), 40, TypeChart.color(t).lightened(0.3))
	title.add_theme_constant_override("outline_size", 8)
	_info.add_child(title)

	_info = _card(tr("Atacando"))
	_group(tr("Muy eficaz contra"), func(o: String) -> bool: return TypeChart.effectiveness(t, [o]) > 1.0)
	_group(tr("Poco eficaz contra"), func(o: String) -> bool: return TypeChart.effectiveness(t, [o]) == 0.5)
	_group(tr("No afecta a"), func(o: String) -> bool: return TypeChart.effectiveness(t, [o]) == 0.0)
	_info = _card(tr("Defendiendo"))
	_group(tr("Débil a"), func(o: String) -> bool: return TypeChart.effectiveness(o, [t]) > 1.0)
	_group(tr("Resiste"), func(o: String) -> bool: return TypeChart.effectiveness(o, [t]) == 0.5)
	_group(tr("Inmune a"), func(o: String) -> bool: return TypeChart.effectiveness(o, [t]) == 0.0)

	_info = _info_root
	var users := Game.roster.filter(func(p: PokemonData) -> bool: return t in p.types)
	if not users.is_empty():
		var roster_label := UiKit.label(tr("En el roster:") + " " + ", ".join(users.map(func(p: PokemonData) -> String: return p.species_name)), 15, UiKit.TEXT_DIM)
		roster_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_info.add_child(roster_label)

	_selected = TypeChart.TYPES.find(t)
	for type: String in _headers:
		for b: Button in _headers[type]:
			b.set_pressed_no_signal(type == t)
	_shade()


## Tarjeta con título (Atacando, Defendiendo) dentro de la ficha; devuelve su columna.
func _card(caption: String) -> VBoxContainer:
	var card := UiKit.panel(UiKit.CARD)
	_info_root.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiKit.SPACE_2)
	card.add_child(col)
	var l := UiKit.section(caption)
	l.add_theme_color_override("font_color", UiKit.ACCENT)
	col.add_child(l)
	return col


func _set_hover(cell: Vector2i) -> void:
	_hover = cell
	_shade()


## Resalta la fila y la columna del tipo elegido y, encima, las de la celda bajo el ratón.
func _shade() -> void:
	for key: Vector2i in _cells:
		var on := key.x == _selected or key.y == _selected
		var hover := key.x == _hover.x or key.y == _hover.y
		(_cells[key] as Control).modulate = Color(1.25, 1.25, 1.25) if key == _hover else \
			(Color.WHITE if on or hover else Color(1, 1, 1, 0.4))


func _group(caption: String, filter: Callable) -> void:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 4)
	for o in TypeChart.TYPES:
		if filter.call(o):
			flow.add_child(UiKit.type_chip(o))
	_info.add_child(UiKit.heading(caption + ":"))
	if flow.get_child_count() == 0:
		flow.add_child(UiKit.hint("—"))
	_info.add_child(flow)


static func _mult_color(mult: float) -> Color:
	if mult == 0.0:
		return Color(0.02, 0.02, 0.05)
	if mult > 1.0:
		return Color(0.16, 0.62, 0.4)
	if mult < 1.0:
		return Color(0.72, 0.2, 0.32)
	return Color(1, 1, 1, 0.05)


static func _mult_text(mult: float) -> String:
	return "0" if mult == 0.0 else ("½" if mult == 0.5 else ("2" if mult == 2.0 else "1"))

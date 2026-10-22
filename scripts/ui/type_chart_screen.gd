extends Control
## Tabla de tipos 18×18 (filas = atacante, columnas = defensor) y ficha del tipo elegido.

const CELL := 38

var _info: VBoxContainer
var _cells := {} # Vector2i(atacante, defensor) -> ColorRect


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
	top.add_child(UiKit.label("  Tabla de tipos", 30, UiKit.ACCENT))

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(columns)

	var chart_panel := UiKit.panel()
	columns.add_child(chart_panel)
	var chart_col := VBoxContainer.new()
	chart_panel.add_child(chart_col)
	chart_col.add_child(UiKit.label("Filas: tipo del ataque · Columnas: tipo del Pokémon que lo recibe · Clic en un tipo para ver su ficha", 14, Color(1, 1, 1, 0.65)))
	var grid := GridContainer.new()
	grid.columns = TypeChart.TYPES.size() + 1
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	chart_col.add_child(grid)

	grid.add_child(UiKit.label("ATQ \\ DEF", 11, Color(1, 1, 1, 0.6)))
	for t in TypeChart.TYPES:
		grid.add_child(_type_header(t))
	for a in TypeChart.TYPES.size():
		grid.add_child(_type_header(TypeChart.TYPES[a]))
		for d in TypeChart.TYPES.size():
			var mult := TypeChart.effectiveness(TypeChart.TYPES[a], [TypeChart.TYPES[d]])
			var cell := ColorRect.new()
			cell.custom_minimum_size = Vector2(CELL, CELL * 0.75)
			cell.color = _mult_color(mult)
			cell.tooltip_text = "%s → %s: ×%s" % [Combat.TYPE_NAMES[TypeChart.TYPES[a]], Combat.TYPE_NAMES[TypeChart.TYPES[d]], _mult_text(mult)]
			var l := UiKit.label(_mult_text(mult) if mult != 1.0 else "", 14)
			l.set_anchors_preset(Control.PRESET_FULL_RECT)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.add_child(l)
			grid.add_child(cell)
			_cells[Vector2i(a, d)] = cell

	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 14)
	chart_col.add_child(legend)
	for item in [[2.0, "Muy eficaz"], [0.5, "Poco eficaz"], [0.0, "Sin efecto"]]:
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(18, 18)
		swatch.color = _mult_color(item[0])
		legend.add_child(swatch)
		legend.add_child(UiKit.label("×%s %s" % [_mult_text(item[0]), item[1]], 14))

	var info_panel := UiKit.panel()
	info_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(info_panel)
	_info = VBoxContainer.new()
	_info.add_theme_constant_override("separation", 10)
	info_panel.add_child(_info)
	_show_type("fire")


func _type_header(t: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(CELL + 6, CELL * 0.75)
	b.text = UiKit.TYPE_ABBR[t]
	b.add_theme_font_size_override("font_size", 12)
	var box := StyleBoxFlat.new()
	box.bg_color = TypeChart.color(t)
	box.set_corner_radius_all(3)
	for state in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(state, box)
	b.add_theme_constant_override("outline_size", 4)
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	b.tooltip_text = Combat.TYPE_NAMES[t]
	b.pressed.connect(_show_type.bind(t))
	return b


func _show_type(t: String) -> void:
	UiKit.clear(_info)
	var chip := UiKit.type_chip(t)
	chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_info.add_child(chip)
	var title := UiKit.label(Combat.TYPE_NAMES[t], 34, TypeChart.color(t).lightened(0.3))
	_info.add_child(title)

	_info.add_child(UiKit.label("Atacando", 20, UiKit.ACCENT))
	_group("Muy eficaz contra", func(o: String) -> bool: return TypeChart.effectiveness(t, [o]) > 1.0)
	_group("Poco eficaz contra", func(o: String) -> bool: return TypeChart.effectiveness(t, [o]) == 0.5)
	_group("No afecta a", func(o: String) -> bool: return TypeChart.effectiveness(t, [o]) == 0.0)
	_info.add_child(HSeparator.new())
	_info.add_child(UiKit.label("Defendiendo", 20, UiKit.ACCENT))
	_group("Débil a", func(o: String) -> bool: return TypeChart.effectiveness(o, [t]) > 1.0)
	_group("Resiste", func(o: String) -> bool: return TypeChart.effectiveness(o, [t]) == 0.5)
	_group("Inmune a", func(o: String) -> bool: return TypeChart.effectiveness(o, [t]) == 0.0)

	var users := Game.roster.filter(func(p: PokemonData) -> bool: return t in p.types)
	if not users.is_empty():
		_info.add_child(HSeparator.new())
		_info.add_child(UiKit.label("En el roster: " + ", ".join(users.map(func(p: PokemonData) -> String: return p.species_name)), 15, Color(1, 1, 1, 0.75)))

	var idx := TypeChart.TYPES.find(t)
	for key: Vector2i in _cells:
		var cell: ColorRect = _cells[key]
		cell.modulate = Color.WHITE if key.x == idx or key.y == idx else Color(1, 1, 1, 0.45)


func _group(caption: String, filter: Callable) -> void:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 4)
	for o in TypeChart.TYPES:
		if filter.call(o):
			flow.add_child(UiKit.type_chip(o))
	_info.add_child(UiKit.label(caption + ":", 15, Color(1, 1, 1, 0.75)))
	if flow.get_child_count() == 0:
		flow.add_child(UiKit.label("—", 15, Color(1, 1, 1, 0.5)))
	_info.add_child(flow)


static func _mult_color(mult: float) -> Color:
	if mult == 0.0:
		return Color(0.1, 0.1, 0.1)
	if mult > 1.0:
		return Color(0.25, 0.6, 0.25)
	if mult < 1.0:
		return Color(0.65, 0.22, 0.2)
	return Color(0.22, 0.25, 0.32)


static func _mult_text(mult: float) -> String:
	return "0" if mult == 0.0 else ("½" if mult == 0.5 else ("2" if mult == 2.0 else "1"))

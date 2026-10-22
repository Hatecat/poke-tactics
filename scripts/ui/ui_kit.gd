class_name UiKit
extends RefCounted
## Piezas de UI compartidas por el menú, el editor, la tabla de tipos y la batalla.

const BG := Color(0.08, 0.1, 0.14, 0.88)
const ACCENT := Color(1.0, 0.8, 0.25)
const TYPE_ABBR := {
	"normal": "NOR", "fire": "FUE", "water": "AGU", "electric": "ELÉ", "grass": "PLA", "ice": "HIE",
	"fighting": "LUC", "poison": "VEN", "ground": "TIE", "flying": "VOL", "psychic": "PSÍ", "bug": "BIC",
	"rock": "ROC", "ghost": "FAN", "dragon": "DRA", "dark": "SIN", "steel": "ACE", "fairy": "HAD",
}
const STAT_NAMES := ["PS", "Ataque", "Defensa", "At. Esp.", "Def. Esp.", "Velocidad"]


static func theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 17
	var normal := _box(Color(0.18, 0.22, 0.3), 6)
	var hover := _box(Color(0.26, 0.32, 0.44), 6)
	var pressed := _box(Color(0.35, 0.3, 0.12), 6)
	pressed.border_color = ACCENT
	pressed.set_border_width_all(2)
	var disabled := _box(Color(0.14, 0.16, 0.2, 0.7), 6)
	for state in ["normal", "focus"]:
		t.set_stylebox(state, "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("hover_pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.35))
	t.set_stylebox("panel", "PanelContainer", _box(BG, 8, 12))
	t.set_stylebox("panel", "TooltipPanel", _box(Color(0.05, 0.06, 0.09, 0.96), 6, 8))
	return t


static func _box(color: Color, radius: int, margin := 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.content_margin_left = margin + 4
	s.content_margin_right = margin + 4
	s.content_margin_top = margin
	s.content_margin_bottom = margin
	return s


static func panel() -> PanelContainer:
	return PanelContainer.new()


static func label(text: String, size := 17, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, callback: Callable, size := 17) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.pressed.connect(callback)
	return b


## Etiqueta coloreada con el nombre (o la abreviatura) de un tipo.
static func type_chip(type: String, short := false, suffix := "") -> PanelContainer:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", _box(TypeChart.color(type), 4, 2))
	var l := label((TYPE_ABBR.get(type, type) if short else Combat.TYPE_NAMES.get(type, type)) + suffix, 14)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.add_child(l)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return chip


static func type_row(types: PackedStringArray, short := false) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for t in types:
		row.add_child(type_chip(t, short))
	return row


static func type_bbcode(type: String) -> String:
	return "[color=#%s]%s[/color]" % [TypeChart.color(type).to_html(false), Combat.TYPE_NAMES.get(type, type)]


static func base_stats(p: PokemonData) -> Array[int]:
	return [p.base_hp, p.base_attack, p.base_defense, p.base_sp_attack, p.base_sp_defense, p.base_speed]


## Fondo con degradado vertical para las pantallas de menú.
static func background() -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(0.16, 0.3, 0.5))
	g.set_color(1, Color(0.05, 0.07, 0.12))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	var rect := TextureRect.new()
	rect.texture = tex
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	return rect


static func clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

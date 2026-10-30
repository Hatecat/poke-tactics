class_name UiKit
extends RefCounted
## Piezas de UI compartidas por el menú, el editor, la tabla de tipos y la batalla.

# --- Tokens -------------------------------------------------------------------
# Toda la interfaz sale de aquí: las pantallas usan estas constantes en vez de colores sueltos.

## Superficies, de la más hundida a la más elevada: fondo de panel, tarjeta/botón y hover.
const SURFACE_0 := Color(0.065, 0.08, 0.12, 0.94)
const SURFACE_1 := Color(0.15, 0.185, 0.26)
const SURFACE_2 := Color(0.21, 0.255, 0.35)
## Superficie de un control seleccionado o activado (dorado oscuro).
const SURFACE_SELECTED := Color(0.27, 0.235, 0.13)
const BORDER := Color(1, 1, 1, 0.09)
const BORDER_STRONG := Color(1, 1, 1, 0.24)
## Borde superior claro de paneles y botones: da la sensación de luz desde arriba.
const RIM := Color(1, 1, 1, 0.13)
const SHADOW := Color(0, 0, 0, 0.35)
const TEXT := Color(0.95, 0.96, 0.98)
const TEXT_DIM := Color(0.71, 0.75, 0.83)
const TEXT_ON_ACCENT := Color(0.12, 0.09, 0.02)
const ACCENT := Color(1.0, 0.8, 0.25)
## Neón (toque cyberpunk, solo en detalles: brillos de foco, corchetes, líneas finas). El acento principal
## sigue siendo el dorado.
const NEON := Color(0.25, 0.93, 1.0)
const NEON_PINK := Color(1.0, 0.3, 0.72)
const SUCCESS := Color(0.36, 0.82, 0.47)
const DANGER := Color(0.9, 0.31, 0.29)
const SCRIM := Color(0, 0, 0, 0.72)
## Compatibilidad: el fondo de panel de antes.
const BG := SURFACE_0

const RADIUS_S := 10
const RADIUS_M := 14
const RADIUS_L := 20
const SPACE_1 := 4
const SPACE_2 := 8
const SPACE_3 := 12
const SPACE_4 := 16
const SPACE_5 := 24
const CONTROL_H := 44
## Alto de todos los chips (tipo, categoría): iguales en cualquier lista.
const CHIP_H := 24
const FONT_BODY := 17
const FONT_SMALL := 15
## Duración de las microanimaciones (hover de tarjetas y aparición de diálogos).
const HOVER_TIME := 0.12
const POP_TIME := 0.14

const TYPE_ABBR := { # i18n
	"normal": "NOR", "fire": "FUE", "water": "AGU", "electric": "ELÉ", "grass": "PLA", "ice": "HIE",
	"fighting": "LUC", "poison": "VEN", "ground": "TIE", "flying": "VOL", "psychic": "PSÍ", "bug": "BIC",
	"rock": "ROC", "ghost": "FAN", "dragon": "DRA", "dark": "SIN", "steel": "ACE", "fairy": "HAD",
}
## Abreviatura y color de cada categoría de ataque (MoveData.Category), como los iconos de los juegos.
const CATEGORY_ABBR := ["Fís.", "Esp.", "Est."] # i18n
const CATEGORY_COLORS := [Color(0.86, 0.33, 0.16), Color(0.25, 0.42, 0.82), Color(0.5, 0.52, 0.58)]
const STAT_NAMES :=["PS", "Ataque", "Defensa", "At. Esp.", "Def. Esp.", "Velocidad"] # i18n

## Variantes de botón (theme_type_variation) además del "Button" normal, que es el secundario.
const PRIMARY := &"PrimaryButton"
const GHOST := &"GhostButton"
const DANGER_BUTTON := &"DangerButton"
## Variantes de panel: tarjeta (un nivel por encima del panel) y tarjeta seleccionada (borde ACCENT de 2 px).
const CARD := &"CardPanel"
const CARD_SELECTED := &"CardSelectedPanel"
## Botón grande e inclinado de los menús de pantalla completa (ver `menu_item`).
const MENU_ITEM := &"MenuItem"
const MENU_ITEM_PRIMARY := &"MenuItemPrimary"
## Tarjeta clicable (roster, equipo...): holograma biselado; seleccionada (toggle) con borde ACCENT.
const CARD_BUTTON := &"CardButton"
## Fondo de las pantallas de menú: azul profundo de arriba abajo.
const BG_TOP := Color(0.1, 0.17, 0.44)
const BG_MID := Color(0.06, 0.07, 0.23)
const BG_BOTTOM := Color(0.03, 0.02, 0.1)
## Bandas diagonales del fondo.
const BAND := Color(0.25, 0.35, 0.95, 0.15)
const BALL_RED := Color(0.9, 0.24, 0.24)
const DIALOG_PANEL := &"DialogPanel"
## Variantes de etiqueta: títulos con más peso y texto atenuado.
const TITLE := &"TitleLabel"
const HEADING := &"HeadingLabel"
const DIM := &"DimLabel"

# Estilos y recursos creados una sola vez y compartidos por todas las pantallas.
static var _theme: Theme
static var _styles := {}
static var _bold: FontVariation
static var _scrim_tex: GradientTexture2D
static var _stripes_tex: ImageTexture
static var _vignette_tex: GradientTexture2D
static var _scan_tex: ImageTexture
static var _sweep_tex: GradientTexture2D
static var _glow_tex: GradientTexture2D


## El tema de toda la interfaz (se crea la primera vez y después se reutiliza).
static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = FONT_BODY
	_theme = t
	_button_styles(t, &"Button", SURFACE_1, SURFACE_2, TEXT)
	t.set_type_variation(PRIMARY, &"Button")
	_button_styles(t, PRIMARY, ACCENT, ACCENT.lightened(0.18), TEXT_ON_ACCENT)
	t.set_type_variation(DANGER_BUTTON, &"Button")
	_button_styles(t, DANGER_BUTTON, DANGER.darkened(0.25), DANGER.darkened(0.08), TEXT)
	t.set_type_variation(GHOST, &"Button")
	var ghost := _box(Color(1, 1, 1, 0.0), RADIUS_S)
	var ghost_hover := _box(Color(1, 1, 1, 0.07), RADIUS_S)
	ghost_hover.border_color = BORDER_STRONG
	ghost_hover.set_border_width_all(1)
	for state in ["normal", "disabled"]:
		t.set_stylebox(state, GHOST, ghost)
	t.set_stylebox("hover", GHOST, ghost_hover)
	t.set_stylebox("pressed", GHOST, _sunk(ghost_hover))
	t.set_stylebox("hover_pressed", GHOST, _sunk(ghost_hover))
	t.set_color("font_color", GHOST, TEXT_DIM)
	t.set_color("font_hover_color", GHOST, TEXT)
	for type in [&"Button", &"OptionButton", &"MenuButton", PRIMARY, GHOST, DANGER_BUTTON]:
		t.set_stylebox("focus", type, _focus_ring())
		t.set_constant("h_separation", type, SPACE_2)
	t.set_color("font_disabled_color", &"Button", Color(TEXT, 0.4))
	t.set_color("font_outline_color", &"Button", Color(0, 0, 0, 0.35))
	# OptionButton y MenuButton heredan de Button pero el tema los busca por su nombre.
	for type in [&"OptionButton", &"MenuButton"]:
		_button_styles(t, type, SURFACE_1, SURFACE_2, TEXT)
		t.set_color("font_disabled_color", type, Color(TEXT, 0.4))

	_menu_item_styles(t, MENU_ITEM, Color(SURFACE_1, 0.88), Color(SURFACE_2, 0.95))
	_menu_item_styles(t, MENU_ITEM_PRIMARY, ACCENT, ACCENT.lightened(0.15))
	var primary_rest: StyleBoxFlat = t.get_stylebox("normal", MENU_ITEM_PRIMARY).duplicate()
	primary_rest.shadow_color = Color(ACCENT, 0.3)
	primary_rest.shadow_size = 10
	primary_rest.shadow_offset = Vector2.ZERO
	t.set_stylebox("normal", MENU_ITEM_PRIMARY, primary_rest)

	var base_panel := _panel_box(SURFACE_0, RADIUS_M, SPACE_3)
	_chamfer(base_panel)
	base_panel.border_color = Color(NEON, 0.2)
	base_panel.set_border_width_all(1)
	t.set_stylebox("panel", "PanelContainer", base_panel)
	_card_button_styles(t)
	t.set_type_variation(CARD, &"PanelContainer")
	t.set_stylebox("panel", CARD, _panel_box(SURFACE_1, RADIUS_M, SPACE_2, false))
	t.set_type_variation(CARD_SELECTED, &"PanelContainer")
	var selected := _panel_box(SURFACE_SELECTED, RADIUS_M, SPACE_2, false)
	selected.border_color = ACCENT
	selected.set_border_width_all(2)
	t.set_stylebox("panel", CARD_SELECTED, selected)
	t.set_type_variation(DIALOG_PANEL, &"PanelContainer")
	var dialog := _panel_box(Color(SURFACE_0, 0.98), RADIUS_L, SPACE_5)
	_chamfer(dialog)
	dialog.border_color = Color(NEON, 0.45)
	dialog.shadow_size = 24
	dialog.shadow_offset = Vector2(0, 8)
	dialog.shadow_color = Color(0, 0, 0, 0.5)
	t.set_stylebox("panel", DIALOG_PANEL, dialog)
	var tip := _box(Color(0.04, 0.05, 0.08, 0.97), RADIUS_S, SPACE_2)
	tip.border_color = BORDER_STRONG
	tip.set_border_width_all(1)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_font_size("font_size", "TooltipLabel", FONT_SMALL)
	t.set_color("font_color", "TooltipLabel", TEXT)

	t.set_color("font_color", "Label", TEXT)
	t.set_type_variation(TITLE, &"Label")
	t.set_font("font", TITLE, bold_font())
	t.set_color("font_color", TITLE, ACCENT)
	t.set_color("font_outline_color", TITLE, Color(0.05, 0.08, 0.2))
	t.set_constant("outline_size", TITLE, 10)
	t.set_color("font_shadow_color", TITLE, Color(0, 0, 0, 0.35))
	t.set_constant("shadow_offset_y", TITLE, 3)
	t.set_type_variation(HEADING, &"Label")
	t.set_font("font", HEADING, bold_font())
	t.set_color("font_color", HEADING, TEXT_DIM)
	t.set_type_variation(DIM, &"Label")
	t.set_color("font_color", DIM, TEXT_DIM)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font("bold_font", "RichTextLabel", bold_font())

	# Campos de texto y selectores.
	var field := _box(Color(0.05, 0.065, 0.1), RADIUS_S, SPACE_2)
	field.border_color = BORDER_STRONG
	field.set_border_width_all(1)
	var field_focus := field.duplicate()
	field_focus.border_color = ACCENT
	field_focus.set_border_width_all(2)
	for type in [&"LineEdit", &"TextEdit"]:
		t.set_stylebox("normal", type, field)
		t.set_stylebox("focus", type, field_focus)
		t.set_stylebox("read_only", type, field)
		t.set_color("caret_color", type, ACCENT)
		t.set_color("selection_color", type, Color(ACCENT, 0.35))
		t.set_color("font_placeholder_color", type, Color(TEXT_DIM, 0.7))

	# Menús desplegables (los de OptionButton).
	var popup := _box(Color(0.06, 0.075, 0.11, 0.98), RADIUS_S, SPACE_1)
	popup.border_color = BORDER_STRONG
	popup.set_border_width_all(1)
	t.set_stylebox("panel", "PopupMenu", popup)
	var popup_hover := _box(SURFACE_2, RADIUS_S - 2, 2)
	t.set_stylebox("hover", "PopupMenu", popup_hover)
	t.set_color("font_hover_color", "PopupMenu", TEXT)
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_constant("v_separation", "PopupMenu", SPACE_2 + 2)
	t.set_font_size("font_size", "PopupMenu", FONT_BODY)

	# Deslizadores y barras.
	var track := _box(Color(1, 1, 1, 0.1), 4, 0)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var track_fill := _box(ACCENT.darkened(0.15), 4, 0)
	track_fill.content_margin_top = 3
	track_fill.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", track_fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", track_fill)
	t.set_icon("grabber", "HSlider", _knob(ACCENT))
	t.set_icon("grabber_highlight", "HSlider", _knob(ACCENT.lightened(0.3)))
	t.set_stylebox("background", "ProgressBar", _box(Color(0.05, 0.065, 0.1), RADIUS_S, 0))
	t.set_stylebox("fill", "ProgressBar", _box(ACCENT.darkened(0.1), RADIUS_S, 0))
	var bar := _box(Color(1, 1, 1, 0.16), 4, 0)
	var bar_hover := _box(Color(1, 1, 1, 0.3), 4, 0)
	var bar_bg := _box(Color(0, 0, 0, 0.18), 4, 0)
	for type in [&"VScrollBar", &"HScrollBar"]:
		bar_bg.content_margin_left = 3
		bar_bg.content_margin_right = 3
		t.set_stylebox("scroll", type, bar_bg)
		t.set_stylebox("grabber", type, bar)
		t.set_stylebox("grabber_highlight", type, bar_hover)
		t.set_stylebox("grabber_pressed", type, bar_hover)
	var line := StyleBoxLine.new()
	line.color = BORDER_STRONG
	line.thickness = 1
	t.set_stylebox("separator", "HSeparator", line)
	t.set_constant("separation", "HSeparator", SPACE_3)
	var vline := StyleBoxLine.new()
	vline.color = BORDER_STRONG
	vline.vertical = true
	t.set_stylebox("separator", "VSeparator", vline)

	# Listas.
	t.set_stylebox("panel", "ItemList", field)
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	t.set_stylebox("hovered", "ItemList", _box(Color(1, 1, 1, 0.06), RADIUS_S, 2))
	var item_sel := _box(SURFACE_SELECTED, RADIUS_S, 2)
	item_sel.border_color = ACCENT
	item_sel.set_border_width_all(1)
	for state in ["selected", "selected_focus"]:
		t.set_stylebox(state, "ItemList", item_sel)
	t.set_color("font_color", "ItemList", TEXT)
	t.set_color("font_selected_color", "ItemList", TEXT)
	t.set_constant("v_separation", "ItemList", SPACE_1 + 2)
	return t


## Estados de un botón: normal, hover (más claro y con borde), pressed (hundido 1 px; en los botones de
## selección, dorado con borde ACCENT de 2 px) y disabled (al 40 %). El foco es un anillo aparte.
static func _button_styles(t: Theme, type: StringName, base: Color, hover_color: Color, font: Color) -> void:
	var normal := _box(base, RADIUS_S)
	normal.border_color = RIM if base.get_luminance() < 0.5 else Color(1, 1, 1, 0.35)
	normal.border_width_top = 1
	normal.shadow_color = Color(0, 0, 0, 0.22)
	normal.shadow_size = 3
	normal.shadow_offset = Vector2(0, 2)
	var hover := normal.duplicate()
	hover.bg_color = hover_color
	hover.border_color = BORDER_STRONG if base.get_luminance() < 0.5 else Color(1, 1, 1, 0.5)
	hover.set_border_width_all(1)
	var pressed := _sunk(_box(SURFACE_SELECTED if type in [&"Button", &"OptionButton", &"MenuButton"] else base.darkened(0.12), RADIUS_S))
	pressed.border_color = ACCENT if type in [&"Button", &"OptionButton", &"MenuButton"] else Color(1, 1, 1, 0.4)
	pressed.set_border_width_all(2)
	var hover_pressed := pressed.duplicate()
	hover_pressed.bg_color = pressed.bg_color.lightened(0.08)
	var disabled := normal.duplicate()
	disabled.bg_color = Color(base, base.a * 0.4)
	disabled.border_color = Color(normal.border_color, normal.border_color.a * 0.4)
	disabled.shadow_size = 0
	t.set_stylebox("normal", type, normal)
	t.set_stylebox("hover", type, hover)
	t.set_stylebox("pressed", type, pressed)
	t.set_stylebox("hover_pressed", type, hover_pressed)
	t.set_stylebox("disabled", type, disabled)
	for c in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(c, type, font)
	if type in [&"Button", &"OptionButton", &"MenuButton"]:
		t.set_color("font_pressed_color", type, ACCENT.lightened(0.25))
		t.set_color("font_hover_pressed_color", type, ACCENT.lightened(0.35))
	t.set_color("font_disabled_color", type, Color(font, 0.4))


## Botón de menú inclinado (como las pestañas de los juegos de Switch): sin borde en reposo; en hover y con
## foco, más claro y con una franja ACCENT a la izquierda.
static func _menu_item_styles(t: Theme, type: StringName, base: Color, hover_color: Color) -> void:
	t.set_type_variation(type, &"Button")
	var normal := _box(base, RADIUS_S, 0)
	normal.skew = Vector2(0.22, 0)
	_chamfer(normal)
	if base.get_luminance() < 0.5:
		# Contorno de neón finito, como un panel de holograma.
		normal.border_color = Color(NEON, 0.22)
		normal.set_border_width_all(1)
	else:
		normal.border_color = Color(1, 1, 1, 0.4)
		normal.border_width_top = 1
	normal.shadow_color = Color(0, 0, 0, 0.3)
	normal.shadow_size = 6
	normal.shadow_offset = Vector2(0, 3)
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = hover_color
	hover.border_color = Color(NEON, 0.9) if base.get_luminance() < 0.5 else Color.WHITE
	hover.border_width_left = 6
	hover.expand_margin_left = 6
	# Brillo de neón alrededor del botón activo.
	hover.shadow_color = Color(NEON, 0.45) if base.get_luminance() < 0.5 else Color(NEON_PINK, 0.4)
	hover.shadow_size = 14
	hover.shadow_offset = Vector2.ZERO
	var pressed := _sunk(hover)
	t.set_stylebox("normal", type, normal)
	t.set_stylebox("hover", type, hover)
	t.set_stylebox("focus", type, hover)
	t.set_stylebox("pressed", type, pressed)
	t.set_stylebox("hover_pressed", type, pressed)
	t.set_stylebox("disabled", type, normal)


static func _card_button_styles(t: Theme) -> void:
	t.set_type_variation(CARD_BUTTON, &"Button")
	var normal := _box(Color(SURFACE_1, 0.85), RADIUS_S, 0)
	_chamfer(normal)
	normal.border_color = Color(NEON, 0.12)
	normal.set_border_width_all(1)
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = Color(SURFACE_2, 0.95)
	hover.border_color = Color(NEON, 0.75)
	hover.shadow_color = Color(NEON, 0.25)
	hover.shadow_size = 8
	var selected: StyleBoxFlat = normal.duplicate()
	selected.bg_color = SURFACE_SELECTED
	selected.border_color = ACCENT
	selected.set_border_width_all(2)
	selected.shadow_color = Color(ACCENT, 0.25)
	selected.shadow_size = 8
	var selected_hover: StyleBoxFlat = selected.duplicate()
	selected_hover.bg_color = SURFACE_SELECTED.lightened(0.08)
	t.set_stylebox("normal", CARD_BUTTON, normal)
	t.set_stylebox("hover", CARD_BUTTON, hover)
	t.set_stylebox("pressed", CARD_BUTTON, selected)
	t.set_stylebox("hover_pressed", CARD_BUTTON, selected_hover)
	t.set_stylebox("disabled", CARD_BUTTON, normal)
	t.set_stylebox("focus", CARD_BUTTON, _focus_ring())


## Esquinas biseladas a 45° en lugar de redondas (corte "tecnológico").
static func _chamfer(s: StyleBoxFlat) -> void:
	s.corner_detail = 1
	s.corner_radius_bottom_left = 0
	s.corner_radius_top_right = 0


## Copia hundida 1 px de un estilo (el contenido baja un píxel al pulsar).
static func _sunk(s: StyleBoxFlat) -> StyleBoxFlat:
	var p: StyleBoxFlat = s.duplicate()
	p.content_margin_top += 1
	p.content_margin_bottom -= 1
	p.shadow_size = 0
	return p


## Anillo de foco (teclado y mando): borde ACCENT de 2 px un poco por fuera del control.
static func _focus_ring() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.draw_center = false
	s.border_color = Color(ACCENT, 0.9)
	s.set_border_width_all(2)
	s.set_corner_radius_all(RADIUS_S + 2)
	s.set_expand_margin_all(3)
	return s


static func _knob(color: Color) -> ImageTexture:
	var img := Image.create(20, 20, false, Image.FORMAT_RGBA8)
	for y in 20:
		for x in 20:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(10, 10))
			var a := clampf(9.0 - d, 0.0, 1.0)
			var rim := clampf(d - 6.5, 0.0, 1.0)
			img.set_pixel(x, y, Color(color.lerp(Color.WHITE, 0.0 if rim < 0.5 else 0.25), a))
	return ImageTexture.create_from_image(img)


static func _box(color: Color, radius: int, margin := 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.content_margin_left = margin + 4
	s.content_margin_right = margin + 4
	s.content_margin_top = margin
	s.content_margin_bottom = margin
	s.anti_aliasing_size = 0.8
	return s


## Panel con borde superior claro y sombra suave: se separa del fondo sin bordes duros.
static func _panel_box(color: Color, radius: int, margin: int, shadow := true) -> StyleBoxFlat:
	var s := _box(color, radius, margin)
	s.border_color = RIM
	s.border_width_top = 1
	if shadow:
		s.shadow_color = SHADOW
		s.shadow_size = 10
		s.shadow_offset = Vector2(0, 4)
	return s


## Estilo de color plano compartido (chips de tipo y categoría): uno por color y margen, no uno por chip.
static func flat_style(color: Color, radius := RADIUS_S, margin := 2) -> StyleBoxFlat:
	var key := "%s|%d|%d" % [color.to_html(), radius, margin]
	if not _styles.has(key):
		_styles[key] = _box(color, radius, margin)
	return _styles[key]


## Tarjeta (no clicable) con una franja a la izquierda del color dado (p. ej. el del tipo de un ataque).
## Se comparte por color.
static func accent_card_style(color: Color) -> StyleBoxFlat:
	var key := "accent|" + color.to_html()
	if not _styles.has(key):
		var st := _box(Color(SURFACE_1, 0.7), RADIUS_S, SPACE_2)
		_chamfer(st)
		st.border_color = color
		st.border_width_left = 5
		st.content_margin_left = SPACE_4
		_styles[key] = st
	return _styles[key]


## Da a un botón los estados de CardButton con una franja del color dado a la izquierda (botones de ataque).
## Los estilos se crean una vez por color.
static func accent_button(b: Button, color: Color) -> void:
	var key := "accent_button|" + color.to_html()
	if not _styles.has(key):
		var t := theme()
		var states := {}
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var st: StyleBoxFlat = t.get_stylebox(state, CARD_BUTTON).duplicate()
			st.border_color = color if state in ["normal", "disabled"] else st.border_color
			st.border_width_left = 6
			st.content_margin_left = SPACE_4
			states[state] = st
		_styles[key] = states
	b.theme_type_variation = CARD_BUTTON
	for state: String in _styles[key]:
		b.add_theme_stylebox_override(state, _styles[key][state])


## Barra de PS: verde, amarilla o roja según lo que queda (estilos compartidos).
static func hp_bar(width := 200.0) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(width, 8)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", flat_style(Color(1, 1, 1, 0.08), 3, 0))
	return bar


static func set_hp(bar: ProgressBar, hp: int, max_hp: int) -> void:
	bar.max_value = max_hp
	bar.value = hp
	var ratio := float(hp) / maxf(1.0, max_hp)
	var color := SUCCESS if ratio > 0.5 else (ACCENT if ratio > 0.2 else DANGER)
	bar.add_theme_stylebox_override("fill", flat_style(color, 3, 0))


## Fuente de los títulos: la de siempre con más peso (sin empaquetar fuentes nuevas).
static func bold_font() -> FontVariation:
	if not _bold:
		_bold = FontVariation.new()
		_bold.base_font = ThemeDB.fallback_font
		_bold.variation_embolden = 0.7
		_bold.spacing_glyph = 1
	return _bold


static func panel(variation := &"") -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = variation
	return p


static func label(text: String, size := 17, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	if color != Color.WHITE:
		l.add_theme_color_override("font_color", color)
	return l


## Título de pantalla o de diálogo: más grueso, dorado, con contorno y sombra.
static func title(text: String, size := 30, color := ACCENT) -> Label:
	var l := label(text, size)
	l.theme_type_variation = TITLE
	if color != ACCENT:
		l.add_theme_color_override("font_color", color)
	return l


## Título grande con aberración cromática (copias cian y magenta desplazadas detrás) y un pequeño
## "glitch" cada pocos segundos: las copias tiemblan un instante y vuelven a su sitio.
static func glitch_title(text: String, size := 72) -> Label:
	var l := title(text, size)
	var ghosts: Array[Label] = []
	# En tamaños pequeños el efecto se reduce para que el texto siga limpio.
	var off := clampf(size / 18.0, 1.5, 4.0)
	var alpha := 0.7 if size >= 56 else 0.45
	if size < 56:
		l.add_theme_constant_override("outline_size", 6)
	for item in [[NEON_PINK, -off], [NEON, off]]:
		var g := label(text, size, Color(item[0], alpha))
		g.add_theme_font_override("font", bold_font())
		g.show_behind_parent = true
		g.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		g.position.x = item[1]
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_child(g)
		ghosts.append(g)
	l.ready.connect(func() -> void:
		var tw := l.create_tween().set_loops()
		tw.tween_interval(4.5)
		for k in 4:
			for i in ghosts.size():
				var sign := -1.0 if i == 0 else 1.0
				tw.parallel().tween_property(ghosts[i], "position", Vector2(sign * randf_range(off + 1.0, off * 2.5), randf_range(-2, 2)), 0.04)
			tw.tween_interval(0.03)
		for i in ghosts.size():
			tw.parallel().tween_property(ghosts[i], "position", Vector2(-off if i == 0 else off, 0), 0.06))
	return l


## Corchetes de esquina en neón (estilo HUD) en el borde de un control (se dibujan sobre su fondo, debajo
## de los hijos). `inset` positivo los mete hacia dentro.
static func brackets(c: Control, color := Color(NEON, 0.8), arm := 14.0, inset := 4.0) -> void:
	c.draw.connect(func() -> void:
		var r := Rect2(Vector2(inset, inset), c.size - Vector2(inset, inset) * 2)
		for corner in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
			var dx := arm if corner.x == r.position.x else -arm
			var dy := arm if corner.y == r.position.y else -arm
			c.draw_polyline(PackedVector2Array([corner + Vector2(0, dy), corner, corner + Vector2(dx, 0)]), color, 2.0))


## Cabecera de las pantallas: botón para volver, barrita, título grande y un código de barras de neón.
static func screen_header(title_text: String, back_text: String, on_back: Callable) -> HBoxContainer:
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", SPACE_4)
	var back := ghost_button(back_text, on_back, 18)
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(back)
	var bar := Panel.new()
	bar.custom_minimum_size = Vector2(6, 34)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_theme_stylebox_override("panel", flat_style(ACCENT, 3, 0))
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(bar)
	var t := glitch_title(title_text, 34)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(t)
	top.add_child(barcode(80, 16))
	return top


## Título de un panel: grueso y claro.
static func section(text: String, size := 20) -> Label:
	var l := label(text, size)
	l.add_theme_font_override("font", bold_font())
	return l


## Rótulo de sección (encima de un grupo de opciones): grueso y atenuado.
static func heading(text: String, size := FONT_SMALL + 1) -> Label:
	var l := label(text, size)
	l.theme_type_variation = HEADING
	return l


## Texto secundario (pistas, descripciones): atenuado, nunca por debajo de 15 px.
static func hint(text: String, size := FONT_SMALL) -> Label:
	var l := label(text, maxi(size, FONT_SMALL))
	l.theme_type_variation = DIM
	return l


static func button(text: String, callback: Callable, size := 17) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size.y = CONTROL_H
	b.pressed.connect(callback)
	return b


## Botón de la acción principal (dorado).
static func primary_button(text: String, callback: Callable, size := 20) -> Button:
	var b := button(text, callback, size)
	b.theme_type_variation = PRIMARY
	return b


## Botón discreto, sin fondo hasta el hover (Cancelar, Cerrar, el aspa de los diálogos).
static func ghost_button(text: String, callback: Callable, size := 17) -> Button:
	var b := button(text, callback, size)
	b.theme_type_variation = GHOST
	return b


## Botón de una acción destructiva o de salida (abandonar, borrar).
static func danger_button(text: String, callback: Callable, size := 17) -> Button:
	var b := button(text, callback, size)
	b.theme_type_variation = DANGER_BUTTON
	return b


## Entrada de un menú de pantalla completa: botón inclinado con el icono en una insignia redonda y el texto
## a la izquierda; al pasar el ratón (o con foco) el contenido se desliza un poco a la derecha.
static func menu_item(icon: String, text: String, callback: Callable, primary := false, size := 24, code := "") -> Button:
	var b := button("", callback, size)
	b.theme_type_variation = MENU_ITEM_PRIMARY if primary else MENU_ITEM
	b.custom_minimum_size.y = 58
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = SPACE_4
	row.offset_right = -SPACE_4
	row.add_theme_constant_override("separation", SPACE_3 + 2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(38, 38)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_stylebox_override("panel", flat_style(Color(0, 0, 0, 0.22) if primary else Color(1, 1, 1, 0.08), 19, 0))
	row.add_child(badge)
	var ic := label(icon, 19, TEXT_ON_ACCENT if primary else ACCENT)
	ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ic.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(ic)
	var l := label(text, size, TEXT_ON_ACCENT if primary else TEXT)
	l.add_theme_font_override("font", bold_font())
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)
	var arrow := label("›", size + 6, TEXT_ON_ACCENT if primary else ACCENT)
	arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	arrow.modulate.a = 0.0
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(arrow)
	# Índice decorativo ("01", "02"...) a la derecha, en neón tenue.
	if code:
		var c := label(code, 14, Color(TEXT_ON_ACCENT, 0.55) if primary else Color(NEON, 0.55))
		c.add_theme_font_override("font", bold_font())
		c.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(c)
	var tw_ref := [null]
	var slide := func(on: bool) -> void:
		if tw_ref[0]:
			(tw_ref[0] as Tween).kill()
		var tw := b.create_tween().set_parallel().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(row, "offset_left", SPACE_4 + (10 if on else 0), HOVER_TIME)
		tw.tween_property(arrow, "modulate:a", 1.0 if on else 0.0, HOVER_TIME)
		tw_ref[0] = tw
	b.mouse_entered.connect(slide.bind(true))
	b.mouse_exited.connect(func() -> void: slide.call(b.has_focus()))
	b.focus_entered.connect(slide.bind(true))
	b.focus_exited.connect(func() -> void: slide.call(b.is_hovered()))
	return b


## Diálogo modal: oscurece la pantalla, centra un panel con cabecera (título y aspa) y aparece con una
## animación corta. Se añade al padre oculto; se abre y cierra con `visible` como los de antes.
## `on_close` se llama al cerrar con el aspa, Escape o clic fuera (si `dismiss_outside`).
static func dialog(parent: Node, title_text: String, on_close := Callable()) -> UiDialog:
	var d := UiDialog.new()
	d.setup(title_text, on_close)
	parent.add_child(d)
	return d


## Textura del velo de los diálogos: más oscuro abajo y en los bordes que en el centro.
static func scrim_texture() -> GradientTexture2D:
	if not _scrim_tex:
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, 0.5))
		g.set_color(1, Color(0, 0, 0, 0.82))
		_scrim_tex = GradientTexture2D.new()
		_scrim_tex.gradient = g
		_scrim_tex.fill = GradientTexture2D.FILL_RADIAL
		_scrim_tex.fill_from = Vector2(0.5, 0.45)
		_scrim_tex.fill_to = Vector2(1.1, 1.1)
		_scrim_tex.width = 256
		_scrim_tex.height = 256
	return _scrim_tex


## Transición de hover (120 ms) para tarjetas que no son botones: aclara un poco al pasar el ratón.
static func hover_lift(c: Control) -> void:
	var tw_ref := [null]
	var to := func(v: Color) -> void:
		if tw_ref[0]:
			(tw_ref[0] as Tween).kill()
		var tw := c.create_tween()
		tw.tween_property(c, "self_modulate", v, HOVER_TIME)
		tw_ref[0] = tw
	c.mouse_entered.connect(to.bind(Color(1.16, 1.16, 1.16)))
	c.mouse_exited.connect(to.bind(Color.WHITE))


## Etiqueta coloreada con el nombre (o la abreviatura) de un tipo.
static func type_chip(type: String, short := false, suffix := "") -> PanelContainer:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", flat_style(TypeChart.color(type), CHIP_H / 2, 2))
	chip.custom_minimum_size.y = CHIP_H
	var l := label(TranslationServer.translate(TYPE_ABBR.get(type, type) if short else Combat.TYPE_NAMES.get(type, type)) + suffix, 14)
	l.add_theme_font_override("font", bold_font())
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
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


## Botón de un ataque: etiqueta del color de su tipo, nombre, icono de su categoría (Físico, Especial o Estado)
## y `extra` a la derecha (PP, potencia...). `type` es el tipo que se muestra si no es el del ataque (Bola Clima).
static func move_button(move: MoveData, name_text: String, extra: String, callback: Callable, type := "", size := 17) -> Button:
	var b := button("", callback, size)
	b.custom_minimum_size.y = maxi(CONTROL_H, size + 22)
	b.tooltip_text = Combat.describe(move)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 10
	row.offset_right = -10
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	var chip := type_chip(type if type else move.type, true)
	chip.custom_minimum_size.x = 44
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(chip)
	var l := label(name_text, size)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)
	row.add_child(category_chip(move.category))
	if extra:
		var e := label(extra, size - 3, TEXT_DIM)
		e.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(e)
	# El botón no es un contenedor: se ensancha a mano para que quepa todo sin cortar el nombre.
	var fit := func() -> void: b.custom_minimum_size.x = row.get_combined_minimum_size().x + 20
	row.minimum_size_changed.connect(fit)
	fit.call()
	# Los botones desactivados (sin PP, ya atacó) atenúan también su contenido.
	b.draw.connect(func() -> void: row.modulate.a = 0.4 if b.disabled else 1.0)
	return b


## Etiqueta de la categoría de un ataque: icono (estallido, ondas o círculo) y abreviatura sobre su color.
static func category_chip(category: MoveData.Category) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", flat_style(CATEGORY_COLORS[category], CHIP_H / 2, 2))
	chip.custom_minimum_size.y = CHIP_H
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(row)
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(14, 14)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.draw.connect(_draw_category_icon.bind(icon, category))
	row.add_child(icon)
	var l := label(TranslationServer.translate(CATEGORY_ABBR[category]), 13)
	l.add_theme_font_override("font", bold_font())
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)
	return chip


## Físico: estallido de ocho puntas. Especial: ondas concéntricas. Estado: anillo con un punto (como los juegos).
static func _draw_category_icon(icon: Control, category: MoveData.Category) -> void:
	var c := icon.size * 0.5
	var r := minf(icon.size.x, icon.size.y) * 0.5
	match category:
		MoveData.Category.PHYSICAL:
			var pts := PackedVector2Array()
			for i in 16:
				pts.append(c + Vector2.from_angle(TAU * i / 16.0 - PI * 0.5) * (r if i % 2 == 0 else r * 0.45))
			icon.draw_colored_polygon(pts, Color.WHITE)
		MoveData.Category.SPECIAL:
			icon.draw_arc(c, r - 1.0, 0.0, TAU, 20, Color.WHITE, 1.6, true)
			icon.draw_arc(c, r * 0.5, 0.0, TAU, 14, Color.WHITE, 1.6, true)
			icon.draw_circle(c, r * 0.16, Color.WHITE)
		_:
			icon.draw_arc(c, r - 1.0, 0.0, TAU, 20, Color.WHITE, 1.8, true)
			icon.draw_circle(c, r * 0.32, Color.WHITE)


static func type_bbcode(type: String) -> String:
	return "[color=#%s]%s[/color]" % [TypeChart.color(type).to_html(false), TranslationServer.translate(Combat.TYPE_NAMES.get(type, type))]


static func base_stats(p: PokemonData) -> Array[int]:
	return [p.base_hp, p.base_attack, p.base_defense, p.base_sp_attack, p.base_sp_defense, p.base_speed]


## Fondo de las pantallas de menú, por capas: degradado azul, bandas diagonales, trama de rayas finas, una
## Poké Ball enorme que gira muy despacio y viñeta. Todo se dibuja una vez (la bola solo rota).
static func background() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([BG_TOP, BG_MID, BG_BOTTOM])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0.3, 0.0)
	tex.fill_to = Vector2(0.6, 1.0)
	root.add_child(_full_rect(tex))
	var bands := Control.new()
	bands.set_anchors_preset(Control.PRESET_FULL_RECT)
	bands.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bands.draw.connect(_draw_bands.bind(bands))
	bands.resized.connect(bands.queue_redraw)
	root.add_child(bands)
	var stripes := _full_rect(_stripes_texture())
	stripes.stretch_mode = TextureRect.STRETCH_TILE
	stripes.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	root.add_child(stripes)
	var floor := Control.new()
	floor.set_anchors_preset(Control.PRESET_FULL_RECT)
	floor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	floor.draw.connect(_draw_grid_floor.bind(floor))
	floor.resized.connect(floor.queue_redraw)
	root.add_child(floor)
	var ball := Control.new()
	ball.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ball.size = Vector2(900, 900)
	ball.position = Vector2(-560, -640)
	ball.pivot_offset = ball.size * 0.5
	ball.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ball.draw.connect(_draw_ball_outline.bind(ball))
	root.add_child(ball)
	ball.ready.connect(func() -> void:
		var tw := ball.create_tween().set_loops()
		tw.tween_property(ball, "rotation", TAU, 120.0).from(0.0))
	# Barrido de escaneo: una franja de luz cian que baja por la pantalla cada pocos segundos.
	var sweep := _full_rect(_sweep_texture())
	sweep.set_anchors_preset(Control.PRESET_TOP_WIDE)
	sweep.custom_minimum_size.y = 160
	sweep.offset_bottom = 160
	root.add_child(sweep)
	sweep.ready.connect(func() -> void:
		var tw := sweep.create_tween().set_loops()
		tw.tween_property(sweep, "position:y", 1400.0, 5.0).from(-200.0)
		tw.tween_interval(3.0))
	# Marco de visor: corchetes en las esquinas de la pantalla y una regla de marcas a la izquierda.
	var hud := Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	brackets(hud, Color(NEON, 0.35), 46.0, 6.0)
	hud.draw.connect(func() -> void:
		for i in 24:
			var y := hud.size.y * 0.3 + i * 14.0
			hud.draw_line(Vector2(6, y), Vector2(6 + (8 if i % 4 == 0 else 4), y), Color(NEON, 0.25), 1.0))
	hud.resized.connect(hud.queue_redraw)
	root.add_child(hud)
	var scan := _full_rect(_scanline_texture())
	scan.stretch_mode = TextureRect.STRETCH_TILE
	scan.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	root.add_child(scan)
	root.add_child(_full_rect(_vignette_texture()))
	return root


## Suelo en rejilla con perspectiva en la parte baja derecha, en neón muy tenue (se funde hacia arriba).
static func _draw_grid_floor(c: Control) -> void:
	var w := c.size.x
	var h := c.size.y
	var horizon := h * 0.66
	var vanish := Vector2(w * 0.72, horizon)
	# Resplandor magenta sobre el horizonte (franjas cada vez más tenues hacia arriba).
	for k in 14:
		var y := horizon - k * 6.0
		c.draw_rect(Rect2(w * 0.36, y - 6.0, w * 0.64, 6.0), Color(NEON_PINK, 0.09 * pow(1.0 - k / 14.0, 2.0)))
	c.draw_line(Vector2(w * 0.36, horizon), Vector2(w, horizon), Color(NEON_PINK, 0.35), 1.5, true)
	for i in range(-12, 13):
		var x := vanish.x + i * w * 0.09
		c.draw_line(vanish.lerp(Vector2(x, h), 0.12), Vector2(x, h), Color(NEON, 0.12), 1.0, true)
	for j in 9:
		var t := pow(float(j + 1) / 9.0, 2.0)
		var y := lerpf(horizon, h, t)
		c.draw_line(Vector2(w * 0.36, y), Vector2(w, y), Color(NEON_PINK.lerp(NEON, t), 0.05 + 0.1 * t), 1.0, true)


static func _full_rect(tex: Texture2D) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = tex
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## Dos bandas diagonales anchas y una línea fina dorada que cruzan la pantalla.
static func _draw_bands(c: Control) -> void:
	var w := c.size.x
	var h := c.size.y
	var band := func(x0: float, width: float, color: Color) -> void:
		var slant := h * 0.45
		c.draw_colored_polygon(PackedVector2Array([Vector2(x0 + slant, 0), Vector2(x0 + slant + width, 0),
			Vector2(x0 + width, h), Vector2(x0, h)]), color)
	band.call(w * 0.42, w * 0.2, BAND)
	band.call(w * 0.66, w * 0.07, Color(BAND, BAND.a * 0.7))
	var slant := h * 0.45
	c.draw_line(Vector2(w * 0.4 + slant, 0), Vector2(w * 0.4, h), Color(NEON, 0.3), 2.0, true)
	c.draw_line(Vector2(w * 0.4 + slant + 10, 0), Vector2(w * 0.4 + 10, h), Color(NEON_PINK, 0.12), 1.0, true)
	c.draw_line(Vector2(w * 0.62 + slant, 0), Vector2(w * 0.62, h), Color(ACCENT, 0.16), 1.0, true)


## Contorno de una Poké Ball: anillo, banda central y botón (sin relleno, muy tenue).
static func _draw_ball_outline(c: Control) -> void:
	var center := c.size * 0.5
	var r := c.size.x * 0.5 - 8
	var col := Color(NEON, 0.05)
	c.draw_arc(center, r, 0.0, TAU, 128, col, 26.0, true)
	c.draw_rect(Rect2(center - Vector2(r, 13), Vector2(r * 2, 26)), col)
	c.draw_arc(center, r * 0.24, 0.0, TAU, 64, col, 26.0, true)
	c.draw_circle(center, r * 0.1, col)


## Trama de rayas diagonales muy finas (se repite en mosaico).
static func _stripes_texture() -> ImageTexture:
	if not _stripes_tex:
		var n := 16
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				img.set_pixel(x, y, Color(1, 1, 1, 0.035 if (x + y) % n < 2 else 0.0))
		_stripes_tex = ImageTexture.create_from_image(img)
	return _stripes_tex


static func _sweep_texture() -> GradientTexture2D:
	if not _sweep_tex:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.85, 0.9, 1.0])
		g.colors = PackedColorArray([Color(NEON, 0.0), Color(NEON, 0.05), Color(NEON, 0.12), Color(NEON, 0.0)])
		_sweep_tex = GradientTexture2D.new()
		_sweep_tex.gradient = g
		_sweep_tex.fill_from = Vector2(0.5, 0.0)
		_sweep_tex.fill_to = Vector2(0.5, 1.0)
	return _sweep_tex


## Código de barras decorativo en neón (junto a subtítulos).
static func barcode(width := 64.0, height := 14.0, color := Color(NEON, 0.8)) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(width, height)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func() -> void:
		var x := 0.0
		var widths := [3, 1, 1, 2, 1, 3, 1, 1, 2, 2, 1, 1, 3, 1, 2]
		var i := 0
		while x < c.size.x:
			var bw: float = widths[i % widths.size()]
			if i % 2 == 0:
				c.draw_rect(Rect2(x, 0, bw, c.size.y), color)
			x += bw + 1.0
			i += 1)
	return c


## Líneas de escaneado horizontales, casi invisibles (una de cada tres filas).
static func _scanline_texture() -> ImageTexture:
	if not _scan_tex:
		var img := Image.create(4, 3, false, Image.FORMAT_RGBA8)
		for x in 4:
			img.set_pixel(x, 0, Color(0, 0, 0, 0.16))
		_scan_tex = ImageTexture.create_from_image(img)
	return _scan_tex


static func _vignette_texture() -> GradientTexture2D:
	if not _vignette_tex:
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, 0.0))
		g.set_color(1, Color(0, 0, 0, 0.55))
		g.set_offset(0, 0.55)
		_vignette_tex = GradientTexture2D.new()
		_vignette_tex.gradient = g
		_vignette_tex.fill = GradientTexture2D.FILL_RADIAL
		_vignette_tex.fill_from = Vector2(0.5, 0.5)
		_vignette_tex.fill_to = Vector2(1.15, 1.15)
	return _vignette_tex


## Halo de luz suave (detrás del Pokémon del escaparate o de un retrato).
static func glow(color := Color(0.45, 0.7, 1.0, 0.35)) -> TextureRect:
	if not _glow_tex:
		var g := Gradient.new()
		g.set_color(0, Color.WHITE)
		g.set_color(1, Color(1, 1, 1, 0.0))
		g.add_point(0.35, Color(1, 1, 1, 0.45))
		_glow_tex = GradientTexture2D.new()
		_glow_tex.gradient = g
		_glow_tex.fill = GradientTexture2D.FILL_RADIAL
		_glow_tex.fill_from = Vector2(0.5, 0.5)
		_glow_tex.fill_to = Vector2(1.0, 0.5)
	var rect := _full_rect(_glow_tex)
	rect.modulate = color
	return rect


static func clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

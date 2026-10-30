class_name DialogueBox
extends Control
## Cuadro de diálogo al estilo de Final Fantasy Tactics: abajo, con el retrato de quien habla a la
## izquierda, su nombre y el texto, que aparece letra a letra. Clic, Enter o Espacio completan el texto y,
## si ya está entero, pasan a la siguiente línea. Mientras está abierto tapa los clics al tablero.
## Los retratos se buscan en assets/portraits/<id>.png; si no hay, se dibuja uno provisional con la inicial.

signal advanced
signal chosen(index: int)

const PORTRAIT_DIR := "res://assets/portraits/"
const CHARS_PER_SECOND := 45.0
const PORTRAIT_SIZE := Vector2(176, 176)
const BOX_HEIGHT := 190.0
const FEELING_COLOR := Color(0.82, 0.7, 1.0)

var _catcher: Control
var _box: PanelContainer
var _box_style: StyleBoxFlat
var _portrait_frame: PanelContainer
var _portrait_style: StyleBoxFlat
var _name_plate: PanelContainer
var _portrait: TextureRect
var _initial: Label
var _name: Label
var _text: RichTextLabel
var _arrow: Label
var _options: HFlowContainer
var _choosing := false
var _typing := false
var _shown := 0.0
var _time := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_catcher = Control.new()
	_catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	_catcher.gui_input.connect(_on_catcher_input)
	add_child(_catcher)

	_box = PanelContainer.new()
	_box.anchor_left = 0.5
	_box.anchor_right = 0.5
	_box.anchor_top = 1.0
	_box.anchor_bottom = 1.0
	_box.offset_left = -640
	_box.offset_right = 640
	_box.offset_top = -BOX_HEIGHT - 24
	_box.offset_bottom = -24
	# Si las opciones no caben en el alto fijo, el cuadro crece hacia arriba (no por debajo de la pantalla).
	_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Estilo propio (no compartido): say() cambia su margen izquierdo según haya retrato o no.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UiKit.SURFACE_0, 0.95)
	style.border_color = Color(UiKit.NEON, 0.45)
	style.set_border_width_all(1)
	style.border_width_top = 2
	style.set_corner_radius_all(UiKit.RADIUS_L)
	style.corner_detail = 1
	style.corner_radius_bottom_left = 0
	style.corner_radius_top_right = 0
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 16
	style.shadow_offset = Vector2(0, 6)
	style.content_margin_left = PORTRAIT_SIZE.x + 48
	style.content_margin_right = 28
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	_box.add_theme_stylebox_override("panel", style)
	_box_style = style
	add_child(_box)
	UiKit.brackets(_box, Color(UiKit.NEON, 0.7), 18.0, 6.0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(col)
	# Nombre en una placa dorada inclinada, como las etiquetas de los menús.
	_name_plate = PanelContainer.new()
	_name_plate.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_name_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var plate := UiKit.flat_style(UiKit.ACCENT, UiKit.RADIUS_S, 2).duplicate() as StyleBoxFlat
	plate.skew = Vector2(0.22, 0)
	plate.content_margin_left = UiKit.SPACE_4
	plate.content_margin_right = UiKit.SPACE_4
	_name_plate.add_theme_stylebox_override("panel", plate)
	col.add_child(_name_plate)
	_name = UiKit.label("", 22, UiKit.TEXT_ON_ACCENT)
	_name.add_theme_font_override("font", UiKit.bold_font())
	_name_plate.add_child(_name)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.custom_minimum_size.y = 86
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.add_theme_font_size_override("normal_font_size", 22)
	_text.add_theme_font_size_override("italics_font_size", 22)
	col.add_child(_text)
	_options = HFlowContainer.new()
	_options.add_theme_constant_override("h_separation", 8)
	_options.visible = false
	col.add_child(_options)
	_arrow = UiKit.label("▼", 18, UiKit.NEON)
	_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(_arrow)

	# El retrato sobresale por arriba del cuadro, como en FFT.
	_portrait_frame = PanelContainer.new()
	_portrait_frame.anchor_left = 0.5
	_portrait_frame.anchor_top = 1.0
	_portrait_frame.anchor_right = 0.5
	_portrait_frame.anchor_bottom = 1.0
	_portrait_frame.offset_left = -640 + 20
	_portrait_frame.offset_right = -640 + 20 + PORTRAIT_SIZE.x
	_portrait_frame.offset_top = -BOX_HEIGHT - 24 - 40
	_portrait_frame.offset_bottom = -BOX_HEIGHT - 24 - 40 + PORTRAIT_SIZE.y
	_portrait_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_style = StyleBoxFlat.new()
	_portrait_style.border_color = UiKit.ACCENT
	_portrait_style.set_border_width_all(3)
	_portrait_style.set_corner_radius_all(UiKit.RADIUS_M)
	_portrait_style.corner_detail = 1
	_portrait_style.corner_radius_bottom_left = 0
	_portrait_style.corner_radius_top_right = 0
	_portrait_style.shadow_color = Color(UiKit.ACCENT, 0.3)
	_portrait_style.shadow_size = 10
	_portrait_style.set_content_margin_all(4)
	_portrait_frame.add_theme_stylebox_override("panel", _portrait_style)
	add_child(_portrait_frame)
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_portrait.custom_minimum_size = PORTRAIT_SIZE - Vector2(8, 8)
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_frame.add_child(_portrait)
	_initial = UiKit.label("", 96)
	_initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_initial.add_theme_constant_override("outline_size", 10)
	_initial.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_portrait_frame.add_child(_initial)
	visible = false


## Muestra una línea y espera a que el jugador la pase. `who` = datos del personaje (nombre, color, id) o
## {} para la narración. `feeling`: lo que Cristina percibe de Gengar (cursiva y color propio).
## Los textos del capítulo llegan en español y se traducen aquí (los ya traducidos quedan igual).
func say(who: Dictionary, text: String, feeling := false) -> void:
	text = tr(text) if text else text
	visible = true
	var narration := who.is_empty()
	_portrait_frame.visible = not narration
	_box_style.content_margin_left = 40 if narration else PORTRAIT_SIZE.x + 48
	_name_plate.visible = not narration
	_name.text = tr(who.get("nombre", "")) if who.get("nombre", "") else ""
	if not narration:
		_set_portrait(who)
	var body := text
	if feeling:
		body = "[i][color=#%s]%s[/color][/i]" % [FEELING_COLOR.to_html(false), text]
	elif narration:
		body = "[i]%s[/i]" % text
	_text.text = body
	_text.visible_characters = 0
	_shown = 0.0
	_typing = true
	await advanced


## Pregunta con opciones (botones dentro del cuadro). Devuelve el índice elegido.
func choose(who: Dictionary, text: String, options: PackedStringArray) -> int:
	UiKit.clear(_options)
	for i in options.size():
		var b := UiKit.button(options[i], chosen.emit.bind(i), 18)
		b.theme_type_variation = UiKit.CARD_BUTTON
		b.custom_minimum_size.x = 160
		b.focus_mode = Control.FOCUS_NONE
		_options.add_child(b)
	_choosing = true
	say(who, text)
	_finish_typing()
	_options.visible = true
	var index: int = await chosen
	_choosing = false
	_options.visible = false
	return index


func close() -> void:
	visible = false


func _set_portrait(who: Dictionary) -> void:
	var path := PORTRAIT_DIR + "%s.png" % who.get("id", "")
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_portrait.texture = tex
	_initial.visible = tex == null
	_initial.text = tr(String(who.get("nombre", "?"))).left(1)
	var color := Color(who.get("color", "#5a6278"))
	_portrait_style.bg_color = color.darkened(0.25) if tex == null else Color(0.05, 0.05, 0.08)


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	if _typing:
		_shown += delta * CHARS_PER_SECOND
		_text.visible_characters = int(_shown)
		if _text.visible_characters >= _text.get_total_character_count():
			_finish_typing()
	_arrow.modulate.a = 0.0 if _typing else 0.55 + 0.45 * sin(_time * 6.0)


func _finish_typing() -> void:
	_typing = false
	_text.visible_characters = -1


func _next() -> void:
	if not visible or _choosing:
		return
	if _typing:
		_finish_typing()
	else:
		advanced.emit()


func _on_catcher_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_next()
		accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo \
			and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		_next()
		get_viewport().set_input_as_handled()

class_name UiDialog
extends Control
## Diálogo modal de UiKit (créalo con `UiKit.dialog`): velo oscuro a pantalla completa y, en el centro, un
## panel con cabecera (título y aspa) y un cuerpo (`body`) donde cada pantalla pone su contenido.
## Se abre y se cierra con `visible`; al aparecer, el panel crece de 0,96 a 1 con un fundido de 140 ms.
## Escape y el aspa lo cierran si `closable`; el clic fuera del panel, solo si además `dismiss_outside`
## (desactívalo cuando haya decisiones a medias).

signal closed

var body: VBoxContainer
var panel: PanelContainer
var header: HBoxContainer
var title_label: Label
var close_button: Button
var closable := true:
	set(v):
		closable = v
		if close_button:
			close_button.visible = v
var dismiss_outside := false
var _on_close := Callable()
var _tween: Tween


func setup(title_text: String, on_close: Callable) -> void:
	_on_close = on_close
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var scrim := TextureRect.new()
	scrim.texture = UiKit.scrim_texture()
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scrim.stretch_mode = TextureRect.STRETCH_SCALE
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	panel = UiKit.panel(UiKit.DIALOG_PANEL)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)
	UiKit.brackets(panel, Color(UiKit.NEON, 0.7), 18.0, 6.0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiKit.SPACE_4)
	panel.add_child(col)
	header = HBoxContainer.new()
	header.add_theme_constant_override("separation", UiKit.SPACE_3)
	col.add_child(header)
	# Barrita dorada delante del título, como las cabeceras de los menús de los juegos.
	var bar := Panel.new()
	bar.custom_minimum_size = Vector2(6, 30)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_theme_stylebox_override("panel", UiKit.flat_style(UiKit.ACCENT, 3, 0))
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(bar)
	title_label = UiKit.title(title_text, 30)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	close_button = UiKit.ghost_button("✕", close, 20)
	close_button.custom_minimum_size = Vector2(UiKit.CONTROL_H, UiKit.CONTROL_H)
	close_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close_button.focus_mode = Control.FOCUS_NONE
	header.add_child(close_button)
	col.add_child(HSeparator.new())
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", UiKit.SPACE_3 + 2)
	col.add_child(body)
	visibility_changed.connect(_on_visibility)


## Cierra (aspa, Escape, clic fuera) y avisa a quien lo abrió.
func close() -> void:
	if not visible:
		return
	visible = false
	if _on_close.is_valid():
		_on_close.call()
	closed.emit()


func _on_visibility() -> void:
	if not visible:
		return
	if _tween:
		_tween.kill()
	modulate.a = 0.0
	panel.scale = Vector2(0.96, 0.96)
	await get_tree().process_frame
	if not is_instance_valid(panel):
		return
	panel.pivot_offset = panel.size * 0.5
	_tween = create_tween().set_parallel().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(self, "modulate:a", 1.0, UiKit.POP_TIME)
	_tween.tween_property(panel, "scale", Vector2.ONE, UiKit.POP_TIME)


func _gui_input(event: InputEvent) -> void:
	# Los clics que llegan aquí son los de fuera del panel (el panel los para).
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if closable and dismiss_outside:
			close()


func _unhandled_input(event: InputEvent) -> void:
	if visible and closable and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

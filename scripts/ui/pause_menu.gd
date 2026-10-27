class_name PauseMenu
extends CanvasLayer
## Menú de pausa (Esc): continuar, volumen y abandonar. Pausa el árbol mientras está abierto.

signal quit_requested

var quit_text := "Abandonar (volver al menú)"
var _root: Control


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = ColorRect.new()
	(_root as ColorRect).color = Color(0, 0, 0, 0.55)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiKit.theme()
	_root.visible = false
	add_child(_root)
	var panel := UiKit.panel()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var title := UiKit.label("Pausa", 32, UiKit.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var resume := UiKit.button("Continuar", close, 20)
	resume.custom_minimum_size = Vector2(380, 48)
	box.add_child(resume)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	box.add_child(grid)
	for item in [["master", "General"], ["music", "Música"], ["sfx", "Efectos"]]:
		grid.add_child(UiKit.label(item[1], 16))
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.value = Game.volumes.get(item[0], 0.8)
		slider.custom_minimum_size = Vector2(260, 26)
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.value_changed.connect(func(v: float) -> void:
			Game.volumes[item[0]] = v
			Audio.apply_volumes())
		grid.add_child(slider)
	grid.add_child(UiKit.label("Velocidad", 16))
	grid.add_child(Game.speed_slider(func(_v: int) -> void: Engine.time_scale = Game.battle_time_scale()))
	grid.add_child(UiKit.label("Gráficos", 16))
	grid.add_child(Game.quality_picker())
	box.add_child(HSeparator.new())
	var quit := UiKit.button(quit_text, func() -> void:
		close()
		quit_requested.emit(), 18)
	box.add_child(quit)


func is_open() -> bool:
	return _root.visible


func open() -> void:
	_root.visible = true
	get_tree().paused = true


func close() -> void:
	if not _root.visible:
		return
	_root.visible = false
	get_tree().paused = false
	Game.save()


func _unhandled_input(event: InputEvent) -> void:
	if _root.visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

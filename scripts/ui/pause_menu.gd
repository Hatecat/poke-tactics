class_name PauseMenu
extends CanvasLayer
## Menú de pausa (Esc): continuar, volumen y abandonar. Pausa el árbol mientras está abierto (salvo con
## `pauses_tree = false`: en VS el rival sigue jugando).

signal quit_requested

var quit_text := tr("Abandonar (volver al menú)")
var pauses_tree := true
var _root: UiDialog


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Diálogo común: el aspa, Escape y el clic fuera del panel cierran (= continuar).
	_root = UiKit.dialog(self, tr("Pausa"), _resumed)
	_root.theme = UiKit.theme()
	_root.dismiss_outside = true
	var box := _root.body
	var resume := UiKit.primary_button(tr("Continuar"), close, 20)
	resume.custom_minimum_size = Vector2(400, 50)
	box.add_child(resume)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", UiKit.SPACE_4)
	grid.add_theme_constant_override("v_separation", UiKit.SPACE_2)
	box.add_child(grid)
	for item in [["master", tr("General")], ["music", tr("Música")], ["sfx", tr("Efectos")]]:
		grid.add_child(UiKit.label(item[1], 16, UiKit.TEXT_DIM))
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
	grid.add_child(UiKit.label(tr("Velocidad"), 16, UiKit.TEXT_DIM))
	grid.add_child(Game.speed_slider(func(_v: int) -> void: Engine.time_scale = Game.battle_time_scale()))
	grid.add_child(UiKit.label(tr("Gráficos"), 16, UiKit.TEXT_DIM))
	grid.add_child(Game.quality_picker())
	box.add_child(HSeparator.new())
	var quit := UiKit.danger_button(quit_text, func() -> void:
		close()
		quit_requested.emit(), 18)
	box.add_child(quit)


func is_open() -> bool:
	return _root.visible


func open() -> void:
	_root.visible = true
	get_tree().paused = pauses_tree


func close() -> void:
	_root.close()


## Al cerrarse el diálogo (por cualquier vía): reanuda y guarda las opciones.
func _resumed() -> void:
	get_tree().paused = false
	Game.save()

class_name AnimationViewer
extends ColorRect
## Visor de animaciones (editor de equipo): el modelo en grande con las acciones base y cada ataque.
## Cada ataque dice qué clip usaría en combate: el suyo propio (anim_map o variante), el genérico
## (fight_b / fight_d) o la animación procedural si el modelo no trae ninguno.

const ACTIONS := [["idle", "Reposo"], ["walk", "Caminar"], ["fight_b", "Ataque físico"],
	["fight_d", "Ataque especial"], ["hit", "Recibe daño"], ["ko", "Debilitado"]]
const OWN_CLIP := Color(1.0, 0.8, 0.25)
const BASE_CLIP := Color(0.85, 0.9, 1.0)
const NO_CLIP := Color(1, 1, 1, 0.45)

var _species: PokemonData
var _moves: Array[MoveData] = []
var _preview: PokemonPreview
var _title: Label
var _status: Label
var _clip_count: Label
var _actions_row: HFlowContainer
var _own_box: VBoxContainer
var _search: LineEdit
var _list: ItemList
var _list_moves: Array[MoveData] = []


func _ready() -> void:
	color = Color(0, 0, 0, 0.75)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var panel := UiKit.panel()
	# Opaco: el panel normal deja ver el editor de detrás.
	var box := (theme_get_panel() as StyleBoxFlat).duplicate() as StyleBoxFlat
	box.bg_color.a = 1.0
	panel.add_theme_stylebox_override("panel", box)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 60
	panel.offset_top = 40
	panel.offset_right = -60
	panel.offset_bottom = -40
	add_child(panel)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	panel.add_child(columns)

	# Modelo
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	columns.add_child(left)
	_title = UiKit.label("", 26, UiKit.ACCENT)
	left.add_child(_title)
	_preview = PokemonPreview.new()
	_preview.interactive = true
	_preview.custom_minimum_size = Vector2(520, 520)
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(_preview)
	var view_row := HBoxContainer.new()
	view_row.add_theme_constant_override("separation", 6)
	left.add_child(view_row)
	view_row.add_child(UiKit.button("Frente", _preview.turn_to.bind(0.0), 15))
	view_row.add_child(UiKit.button("Perfil", _preview.turn_to.bind(90.0), 15))
	view_row.add_child(UiKit.button("Espalda", _preview.turn_to.bind(180.0), 15))
	var spin := UiKit.button("Girar", func() -> void: _preview.spin = not _preview.spin, 15)
	view_row.add_child(spin)
	left.add_child(UiKit.label("Arrastra el modelo para girarlo.", 13, Color(1, 1, 1, 0.5)))
	_status = UiKit.label("", 15)
	left.add_child(_status)

	# Acciones y ataques
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	columns.add_child(right)
	var top := HBoxContainer.new()
	right.add_child(top)
	_clip_count = UiKit.label("", 15, Color(1, 1, 1, 0.7))
	_clip_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_clip_count)
	top.add_child(UiKit.button("Cerrar", close, 16))
	right.add_child(UiKit.label("Acciones", 20, UiKit.ACCENT))
	_actions_row = HFlowContainer.new()
	_actions_row.add_theme_constant_override("h_separation", 6)
	_actions_row.add_theme_constant_override("v_separation", 6)
	right.add_child(_actions_row)
	right.add_child(HSeparator.new())
	right.add_child(UiKit.label("Sus ataques", 20, UiKit.ACCENT))
	_own_box = VBoxContainer.new()
	_own_box.add_theme_constant_override("separation", 4)
	right.add_child(_own_box)
	right.add_child(HSeparator.new())
	right.add_child(UiKit.label("Todos los que puede aprender", 20, UiKit.ACCENT))
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 14)
	right.add_child(legend)
	legend.add_child(UiKit.label("■ clip propio", 13, OWN_CLIP))
	legend.add_child(UiKit.label("■ clip genérico", 13, BASE_CLIP))
	legend.add_child(UiKit.label("■ procedural", 13, NO_CLIP))
	_search = LineEdit.new()
	_search.placeholder_text = "Buscar ataque o clip…"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t: String) -> void: _refresh_list())
	right.add_child(_search)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.add_theme_font_size_override("font_size", 15)
	_list.item_clicked.connect(func(index: int, _pos: Vector2, _button: int) -> void: _play_move(_list_moves[index]))
	right.add_child(_list)


func theme_get_panel() -> StyleBox:
	return UiKit.theme().get_stylebox("panel", "PanelContainer")


func open(species: PokemonData, moves: Array[MoveData]) -> void:
	_species = species
	_moves = moves
	visible = true
	_title.text = "#%03d %s — animaciones" % [species.dex_number, species.species_name]
	_preview.spin = false
	_preview.show_pokemon(species)
	_preview.turn_to(30.0)
	# El modelo se carga al mostrarse; los clips se consultan un fotograma después.
	await get_tree().process_frame
	_refresh()


func close() -> void:
	visible = false
	_preview.show_pokemon(null)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	var clips := _preview.clips()
	_clip_count.text = "El modelo trae %d clips" % clips.size() if clips.size() > 0 \
		else "El modelo no trae animaciones: todo es procedural"
	UiKit.clear(_actions_row)
	for a in ACTIONS:
		var b := UiKit.button(a[1], _play.bind(a[1], a[0]), 15)
		var clip := _clip(a[0])
		b.tooltip_text = clip if clip else "procedural"
		b.add_theme_color_override("font_color", BASE_CLIP if clip else NO_CLIP)
		_actions_row.add_child(b)
	UiKit.clear(_own_box)
	for m in _moves:
		var b := UiKit.button("%s  ·  %s" % [m.display_name, _clip_text(m)], _play_move.bind(m), 15)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_color_override("font_color", _clip_color(m))
		_own_box.add_child(b)
	_refresh_list()


func _refresh_list() -> void:
	var q := _search.text.strip_edges().to_lower()
	_list.clear()
	_list_moves.clear()
	for m in _species.learnset:
		var clip_text := _clip_text(m)
		if q and q not in m.display_name.to_lower() and q not in clip_text.to_lower():
			continue
		var idx := _list.add_item("%s   ·  %s · %s" % [m.display_name, Combat.TYPE_NAMES[m.type], clip_text])
		_list.set_item_custom_fg_color(idx, _clip_color(m))
		_list.set_item_tooltip(idx, Combat.describe(m))
		_list_moves.append(m)


func _clip(key: String, variant := "", move_id := "") -> String:
	var unit := _preview.unit()
	return unit.clip_for(key, variant, move_id) if unit else ""


## Nombre corto del clip que usaría el ataque, sin el prefijo de los rips ("skeleton|fight_b").
func _clip_text(m: MoveData) -> String:
	var clip := _clip(m.animation, m.anim_variant, m.id)
	return clip.get_slice("|", clip.get_slice_count("|") - 1) if clip else "procedural (%s)" % m.animation


func _clip_color(m: MoveData) -> Color:
	var clip := _clip(m.animation, m.anim_variant, m.id)
	if not clip:
		return NO_CLIP
	return BASE_CLIP if clip == _clip(m.animation) else OWN_CLIP


func _play_move(m: MoveData) -> void:
	_play(m.display_name, m.animation, m.anim_variant, m.id)


func _play(label: String, key: String, variant := "", move_id := "") -> void:
	var clip := _preview.play_action(key, variant, move_id)
	var shown := clip.get_slice("|", clip.get_slice_count("|") - 1) if clip else "procedural"
	_status.text = "%s → %s%s" % [label, shown, "  (variante: %s)" % variant if variant else ""]

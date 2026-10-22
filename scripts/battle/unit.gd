class_name Unit
extends Node3D
## Un Pokémon en el tablero: stats calculados, estado, CT y su modelo animado.

signal fainted(unit: Unit)

const LEVEL := 50
const TEAM_COLORS: Array[Color] = [Color(0.25, 0.55, 1.0), Color(1.0, 0.3, 0.25)]
const LOOPING_ANIMS: PackedStringArray = ["idle", "walk", "run"]
## Radio del anillo de equipo según el tamaño del Pokémon.
const RING_SCALE := [1.0, 1.0, 2.1, 2.9]

var data: PokemonData
var team := 0
## Celda ancla; `footprint` son todas las celdas que ocupa (ver BoardGrid.footprint).
var cell := Vector2i.ZERO
var footprint: Array[Vector2i] = []
var ct := 0.0
var max_hp := 1
var hp := 1
var stats := {}
var status := MoveData.Status.NONE
var status_turns := 0

var _model: Node3D
var _anim: AnimationPlayer
var _label: Label3D
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _marker: MeshInstance3D
var _active := false
var _time := 0.0
# Animación procedural para modelos sin clips: "", "idle" o "walk".
var _proc_mode := ""
var _model_base_pos := Vector3.ZERO
var _model_base_scale := Vector3.ONE


func setup(p_data: PokemonData, p_team: int) -> void:
	data = p_data
	team = p_team
	max_hp = int((2 * data.base_hp + 31) * LEVEL / 100.0) + LEVEL + 10
	hp = max_hp
	stats = {
		"attack": _stat(data.base_attack),
		"defense": _stat(data.base_defense),
		"sp_attack": _stat(data.base_sp_attack),
		"sp_defense": _stat(data.base_sp_defense),
		"speed": _stat(data.base_speed),
	}
	name = "%s_%d" % [data.species_name, team]
	_build_visuals()


func _stat(base: int) -> int:
	return int((2 * base + 31) * LEVEL / 100.0) + 5


func is_alive() -> bool:
	return hp > 0


func effective_speed() -> float:
	var s: float = stats.speed
	if status == MoveData.Status.PARALYSIS:
		s *= 0.5
	return s


## Casillas por turno: 2 + velocidad base / 45 (redondeado), entre 2 y 6.
## Shuckle 2 · Bulbasaur/Scizor 3 · Pikachu 4 · Jolteon 5 · Ninjask 6.
func move_range() -> int:
	var tiles := clampi(2 + roundi(data.base_speed / 45.0), 2, 6) + data.move_modifier
	if status == MoveData.Status.PARALYSIS:
		tiles -= 1
	return maxi(tiles, 1)


func display_name() -> String:
	return "%s%s" % [data.species_name, "" if team == 0 else " (rival)"]


func status_text() -> String:
	match status:
		MoveData.Status.POISON: return "ENV"
		MoveData.Status.SLEEP: return "DOR"
		MoveData.Status.PARALYSIS: return "PAR"
		MoveData.Status.BURN: return "QUE"
	return ""


## Solo el modelo, sin anillo, nombre ni colisión (para vistas previas).
func hide_overlays() -> void:
	_ring.visible = false
	_label.visible = false
	for body in find_children("*", "StaticBody3D", false, false):
		body.queue_free()


## Marca (o desmarca) al Pokémon como el que tiene el turno.
func set_active(on: bool) -> void:
	_active = on
	_marker.visible = on
	_ring_mat.emission_energy_multiplier = 0.6
	_ring.scale = Vector3(RING_SCALE[data.size], 0.15, RING_SCALE[data.size])


func _process(delta: float) -> void:
	_time += delta
	if _active:
		_marker.position.y = data.model_height + 0.75 + sin(_time * 4.0) * 0.1
		_marker.rotation.y += delta * 2.0
		var pulse := 0.5 + 0.5 * sin(_time * 5.0)
		_ring_mat.emission_energy_multiplier = 0.6 + pulse * 2.0
		var r: float = RING_SCALE[data.size] * (1.0 + pulse * 0.12)
		_ring.scale = Vector3(r, 0.15, r)
	match _proc_mode:
		"idle":
			_model.scale = _model_base_scale * Vector3(1.0, 1.0 + 0.025 * sin(_time * 2.5), 1.0)
		"walk":
			_model.position.y = _model_base_pos.y + absf(sin(_time * 14.0)) * 0.06 * data.model_height


func take_damage(amount: int) -> void:
	hp = clampi(hp - amount, 0, max_hp)
	refresh_label()
	if hp == 0:
		play("ko")
		fainted.emit(self)


func heal(amount: int) -> void:
	hp = clampi(hp + amount, 0, max_hp)
	refresh_label()


func face_towards(world_target: Vector3) -> void:
	var d := world_target - global_position
	if Vector2(d.x, d.z).length() > 0.01:
		_model.rotation.y = atan2(d.x, d.z)


## Reproduce la primera animación cuyo nombre contenga `key`. Si el modelo no la
## tiene (la mayoría del repo no trae animaciones), usa una versión procedural.
## Devuelve la duración.
func play(key: String) -> float:
	_reset_procedural()
	if _anim:
		for anim_name in _anim.get_animation_list():
			if key in anim_name:
				var anim := _anim.get_animation(anim_name)
				anim.loop_mode = Animation.LOOP_LINEAR if key in LOOPING_ANIMS else Animation.LOOP_NONE
				_anim.play(anim_name, 0.15)
				return anim.length
	return _play_procedural(key)


func _play_procedural(key: String) -> float:
	if key == "idle":
		_proc_mode = "idle"
	elif key == "walk" or key == "run":
		_proc_mode = "walk"
	elif key == "ko":
		var tw := create_tween().set_parallel()
		tw.tween_property(_model, "rotation:z", PI * 0.5, 0.5).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw.tween_property(_model, "position:y", _model_base_pos.y - data.model_height * 0.15, 0.5)
		return 0.6
	elif key.begins_with("fight"):
		# Embestida hacia delante y vuelta.
		var fwd := Vector3(sin(_model.rotation.y), 0.0, cos(_model.rotation.y)) * 0.3 * data.size
		var tw := create_tween()
		tw.tween_property(_model, "position", _model_base_pos + fwd + Vector3.UP * 0.1, 0.15).set_ease(Tween.EASE_OUT)
		tw.tween_property(_model, "position", _model_base_pos, 0.25).set_ease(Tween.EASE_IN_OUT)
		return 0.8
	return 0.0


func _reset_procedural() -> void:
	_proc_mode = ""
	if _model and hp > 0:
		_model.position = _model_base_pos
		_model.scale = _model_base_scale
		_model.rotation.z = 0.0


func refresh_label() -> void:
	var st := status_text()
	_label.text = "%s\n%d/%d%s" % [data.species_name, hp, max_hp, "  " + st if st else ""]


func _build_visuals() -> void:
	_model = data.model.instantiate()
	add_child(_model)
	var players := _model.find_children("*", "AnimationPlayer", true, false)
	_anim = players[0] if not players.is_empty() else null
	# Aplicar la pose de idle antes de medir: en estos modelos las animaciones
	# compensan una escala enorme del nodo raíz, así que la malla en reposo no sirve.
	play("idle")
	if _anim:
		_anim.advance(0.0)
	_normalize_model()
	_model_base_pos = _model.position
	_model_base_scale = _model.scale
	play("idle")

	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.3
	torus.outer_radius = 0.38
	_ring.mesh = torus
	_ring.position.y = 0.02
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.albedo_color = TEAM_COLORS[team]
	_ring_mat.emission_enabled = true
	_ring_mat.emission = TEAM_COLORS[team]
	_ring.material_override = _ring_mat
	add_child(_ring)

	# Flecha que flota sobre el Pokémon activo.
	_marker = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.22
	cone.bottom_radius = 0.0
	cone.height = 0.42
	cone.radial_segments = 4
	_marker.mesh = cone
	var marker_mat := StandardMaterial3D.new()
	marker_mat.albedo_color = Color(1.0, 0.85, 0.2)
	marker_mat.emission_enabled = true
	marker_mat.emission = Color(1.0, 0.75, 0.1)
	marker_mat.emission_energy_multiplier = 1.5
	_marker.material_override = marker_mat
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_marker)
	set_active(false)

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0012
	_label.font_size = 22
	_label.outline_size = 8
	_label.modulate = TEAM_COLORS[team].lightened(0.5)
	_label.position.y = data.model_height + 0.35
	add_child(_label)
	refresh_label()

	# Colisión para poder hacer clic sobre el Pokémon.
	var body := StaticBody3D.new()
	body.set_meta("unit", self)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6 * data.size, data.model_height, 0.6 * data.size)
	shape.shape = box
	shape.position.y = data.model_height * 0.5
	body.add_child(shape)
	add_child(body)


func _normalize_model() -> void:
	var aabb := AABB()
	var first := true
	for m: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		var a := _skinned_aabb(m)
		aabb = a if first else aabb.merge(a)
		first = false
	if first or aabb.size.y <= 0.0:
		return
	var s := data.model_height / aabb.size.y
	_model.scale = Vector3.ONE * s
	_model.position.y = -aabb.position.y * s


## AABB de la malla deformada por la pose actual del esqueleto, relativa a `_model`.
## Muestrea como mucho ~2000 vértices; basta para medir el tamaño.
func _skinned_aabb(m: MeshInstance3D) -> AABB:
	var skel := m.get_node_or_null(m.skeleton) as Skeleton3D
	if m.skin == null or skel == null:
		return _relative_transform(m) * m.get_aabb()
	var binds: Array[Transform3D] = []
	for b in m.skin.get_bind_count():
		var bone := m.skin.get_bind_bone(b)
		if bone < 0:
			bone = skel.find_bone(m.skin.get_bind_name(b))
		binds.append(skel.get_bone_global_pose(bone) * m.skin.get_bind_pose(b))
	var to_model := _relative_transform(skel)
	var aabb := AABB()
	var first := true
	for surface in m.mesh.get_surface_count():
		var arrays := m.mesh.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if verts.is_empty() or bones.is_empty():
			continue
		var per := bones.size() / verts.size()
		for i in range(0, verts.size(), maxi(1, verts.size() / 2000)):
			var p := Vector3.ZERO
			for k in per:
				var w := weights[i * per + k]
				if w > 0.0:
					p += (binds[bones[i * per + k]] * verts[i]) * w
			p = to_model * p
			if first:
				aabb = AABB(p, Vector3.ZERO)
				first = false
			else:
				aabb = aabb.expand(p)
	return aabb


func _relative_transform(node: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != _model and n is Node3D:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t

class_name Unit
extends Node3D
## Un Pokémon en el tablero: stats calculados, estado, CT y su modelo animado.

signal fainted(unit: Unit)

const LEVEL := 50
const TEAM_COLORS: Array[Color] = [Color(0.25, 0.55, 1.0), Color(1.0, 0.3, 0.25)]
const LOOPING_ANIMS: PackedStringArray = ["idle", "walk", "run"]
## Radio del anillo de equipo según el tamaño del Pokémon.
const RING_SCALE := [1.0, 1.0, 2.1, 2.9]
## Las mejoras de stats duran estos turnos propios (aplicar otra reinicia la cuenta).
const STAGE_TURNS := 3
const MAX_STAGE := 6
const STRUGGLE_PATH := "res://data/moves/struggle.tres"
const STAT_SHORT := {"attack": "Atq", "defense": "Def", "sp_attack": "AtE", "sp_defense": "DfE", "speed": "Vel",
	"accuracy": "Pre", "evasion": "Eva", "crit": "Crít"}
const STAT_LABELS := {"attack": "Ataque", "defense": "Defensa", "sp_attack": "At. Esp.", "sp_defense": "Def. Esp.",
	"speed": "Velocidad", "accuracy": "Precisión", "evasion": "Evasión", "crit": "Índice crítico"}
## El índice de crítico va de 0 a 3 (no se puede bajar).
const MAX_CRIT_STAGE := 3

var data: PokemonData
## Especie original (Transformación cambia `data` y `moves` durante el combate).
var base_data: PokemonData
var base_moves: Array[MoveData] = []
## Nivel (el jugador siempre 50; el rival según la dificultad).
var level := LEVEL
## Ataques de este Pokémon concreto (los elegidos en el editor de equipo).
var moves: Array[MoveData] = []
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
## Niveles de mejora de stats (-6..+6), como en los juegos.
var stages := {}
## Turnos propios que le quedan a cada mejora antes de disiparse.
var stage_turns := {}
## Usos restantes de cada ataque en este combate.
var pp := {}
var ability := ""
## Objeto equipado, el último que consumió (para Reciclaje) y el ataque al que le ata un objeto Elección.
var item: ItemData
var consumed_item: ItemData
var choice_lock: MoveData
## Liviano: velocidad ×2 tras perder el objeto.
var unburdened := false
## 0 = sin género, 1 = macho, 2 = hembra.
var gender := 0
## Hacia dónde mira (dirección en el plano XZ); decide el flanqueo.
var facing := Vector2(0, 1)
## Estados volátiles activos: nombre -> datos (turnos restantes, quién lo causó...).
## confusion, leechseed, yawn, taunt, nightmare, curse, perish, protect, endure, substitute,
## ingrain, aquaring, destinybond, charge, magnetrise, flashfire.
var volatiles := {}
## Usos seguidos de Protección/Aguante (cada uno reduce la probabilidad de éxito).
var protect_streak := 0
## Rivales a los que ya intimidó (Intimidación actúa una vez por rival).
var intimidated := {}

var _model: Node3D
var _anim: AnimationPlayer
var _label: Label3D
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _marker: MeshInstance3D
## Flechita sobre el anillo que indica hacia dónde mira.
var _facing_arrow: Node3D
var _active := false
var _time := 0.0
# Animación procedural para modelos sin clips: "", "idle" o "walk".
var _proc_mode := ""
var _model_base_pos := Vector3.ZERO
var _model_base_scale := Vector3.ONE


func setup(member: TeamMember, p_team: int, p_level := LEVEL) -> void:
	level = p_level
	data = member.data
	base_data = data
	moves = member.moves.duplicate()
	base_moves = moves.duplicate()
	ability = member.ability
	item = member.item
	gender = member.gender
	for mv in moves:
		pp[mv] = mv.pp
	team = p_team
	max_hp = int((2 * data.base_hp + 31) * level / 100.0) + level + 10
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
	return int((2 * base + 31) * level / 100.0) + 5


func is_alive() -> bool:
	return hp > 0


## Stat con sus mejoras aplicadas: ×(2+n)/2 si sube, ×2/(2+n) si baja.
## Un crítico ignora las bajadas del atacante (`ignore = 1`) y las subidas del defensor (`ignore = -1`).
func stat(stat_name: String, ignore := 0) -> float:
	var n: int = stages.get(stat_name, 0)
	if ignore == 2 or (ignore == 1 and n < 0) or (ignore == -1 and n > 0):
		n = 0
	var mult := (2.0 + n) / 2.0 if n >= 0 else 2.0 / (2.0 - n)
	return stats[stat_name] * mult


## Aplica cambios de stats y devuelve un texto para el registro ("" si no cambió nada).
func apply_stages(changes: Dictionary) -> String:
	var parts := PackedStringArray()
	for key: String in changes:
		var before: int = stages.get(key, 0)
		var lo := 0 if key == "crit" else -MAX_STAGE
		var hi := MAX_CRIT_STAGE if key == "crit" else MAX_STAGE
		var after := clampi(before + int(changes[key]), lo, hi)
		stages[key] = after
		stage_turns[key] = STAGE_TURNS
		if after == before:
			parts.append("%s no puede %s más" % [STAT_LABELS.get(key, key), "subir" if changes[key] > 0 else "bajar"])
		else:
			var amount := absi(after - before)
			var verb := "subió" if after > before else "bajó"
			parts.append("%s %s%s" % [STAT_LABELS.get(key, key), verb, " mucho" if amount >= 2 else ""])
	refresh_label()
	return ", ".join(parts)


## Al empezar su turno: las mejoras pierden un turno y las agotadas se disipan.
## Devuelve los nombres de los stats que volvieron a la normalidad.
func tick_stages() -> PackedStringArray:
	var expired := PackedStringArray()
	for key: String in stage_turns.keys():
		stage_turns[key] -= 1
		if stage_turns[key] <= 0:
			stage_turns.erase(key)
			if stages.get(key, 0) != 0:
				expired.append(STAT_LABELS.get(key, key))
			stages.erase(key)
	refresh_label()
	return expired


## Ataques que aún puede usar. Sin PP en ninguno, solo le queda Forcejeo.
func usable_moves() -> Array[MoveData]:
	var list: Array[MoveData] = []
	for mv in moves:
		# Con Mofa o Chaleco Asalto solo puede usar ataques que hacen daño; un objeto Elección le ata a uno.
		var no_status := volatiles.has("taunt") or (item != null and item.effect == "assault_vest")
		if pp.get(mv, 0) > 0 and not (no_status and mv.category == MoveData.Category.STATUS) \
				and (choice_lock == null or choice_lock == mv):
			list.append(mv)
	if list.is_empty():
		list.append(load(STRUGGLE_PATH))
	return list


## Pierde el objeto (consumido o quitado). `consumed` = se lo comió o lo usó (Reciclaje lo recupera).
func lose_item(consumed := true) -> void:
	if item == null:
		return
	if consumed:
		consumed_item = item
	item = null
	choice_lock = null
	unburdened = true


func spend_pp(mv: MoveData) -> void:
	if pp.has(mv):
		pp[mv] = maxi(pp[mv] - 1, 0)


## Texto corto de las mejoras activas, p. ej. "Atq+2 Vel-1".
func stages_text() -> String:
	var parts := PackedStringArray()
	for key: String in stages:
		if stages[key] != 0:
			parts.append("%s%s%d" % [STAT_SHORT.get(key, key), "+" if stages[key] > 0 else "", stages[key]])
	return " ".join(parts)


func effective_speed() -> float:
	var s := stat("speed") * Abilities.speed_mult(self, Combat.weather) * Items.speed_mult(self)
	if unburdened and ability == "unburden":
		s *= 2.0
	if status == MoveData.Status.PARALYSIS and ability != "quickfeet":
		s *= 0.5
	if Combat.field and Combat.field.tailwind[team] > 0:
		s *= 2.0
	return s


## Casillas por turno: 2 + velocidad base / 45 (redondeado), entre 2 y 6.
## Shuckle 2 · Bulbasaur/Scizor 3 · Pikachu 4 · Jolteon 5 · Ninjask 6.
## `in_water`: los de tipo Agua no sufren la penalización por peso mientras nadan.
func move_range(in_water := false) -> int:
	var tiles := clampi(2 + roundi(data.base_speed / 45.0), 2, 6) + data.move_modifier
	if in_water and data.move_modifier < 0:
		tiles -= data.move_modifier
	# Granizo: a los voladores les cuesta avanzar (salvo Hielo o habilidades que lo ignoran).
	if not Abilities.weather_immune(self, Combat.weather):
		tiles -= Weather.move_penalty(Combat.weather, data.types)
	if status == MoveData.Status.PARALYSIS:
		tiles -= 1
	return maxi(tiles, 1)


## Casillas por turno nadando (solo tipo Agua): el doble y sin penalización por peso.
func swim_range() -> int:
	return move_range(true) * 2 if "water" in data.types else 0


## ¿Puede desplazarse? Arraigo, estar atrapado o sujetar a otro lo impiden (sí puede atacar).
func can_move() -> bool:
	return not (volatiles.has("ingrain") or volatiles.has("wrapped") or volatiles.has("vortex") or volatiles.has("holding"))


func display_name() -> String:
	return "%s%s" % [TeamMember.display(base_data, gender), "" if team == 0 else " (rival)"]


## ¿Son de sexos opuestos? (los sin género no cuentan).
func opposite_gender(other: Unit) -> bool:
	return gender != 0 and other.gender != 0 and gender != other.gender


## ¿Puede atacar este turno? (Atracción puede impedirlo).
func can_attack() -> bool:
	return not (volatiles.has("attract") and volatiles.attract.get("blocked", false))


func status_text() -> String:
	match status:
		MoveData.Status.POISON: return "ENV"
		MoveData.Status.SLEEP: return "DOR"
		MoveData.Status.PARALYSIS: return "PAR"
		MoveData.Status.BURN: return "QUE"
		MoveData.Status.FREEZE: return "CON"
	return ""


const VOLATILE_SHORT := {
	"confusion": "Confuso", "leechseed": "Drenadoras", "yawn": "Somnoliento", "taunt": "Mofa",
	"nightmare": "Pesadilla", "curse": "Maldito", "perish": "Canto Mortal", "protect": "Protegido",
	"endure": "Aguante", "substitute": "Sustituto", "ingrain": "Arraigado", "aquaring": "Acua Aro",
	"destinybond": "Mismo Destino", "charge": "Carga", "magnetrise": "Levitón", "flashfire": "Absorbe Fuego",
	"attract": "Enamorado", "wrapped": "Atrapado", "vortex": "Remolino", "holding": "Sujetando",
}


func volatiles_text() -> String:
	var parts := PackedStringArray()
	for key: String in volatiles:
		var label: String = VOLATILE_SHORT.get(key, key)
		if key == "perish":
			label += " %d" % volatiles[key].turns
		parts.append(label)
	return ", ".join(parts)


## Solo el modelo, sin anillo, nombre ni colisión (para vistas previas).
func hide_overlays() -> void:
	_ring.visible = false
	_facing_arrow.visible = false
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
		var ko_time := play("ko")
		# Fuera del tablero: sin anillo, nombre ni colisión (no tapa los clics) y el modelo se desvanece.
		hide_overlays()
		_fade_out(clampf(ko_time, 0.6, 1.4))
		fainted.emit(self)
	elif amount > 0:
		var duration := play("hit")
		if is_inside_tree():
			get_tree().create_timer(maxf(duration, 0.3)).timeout.connect(_back_to_idle)


func _fade_out(delay: float) -> void:
	if not is_inside_tree():
		_model.visible = false
		return
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_property(_model, "scale", _model.scale * 0.05, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void: _model.visible = false)


func _back_to_idle() -> void:
	if is_alive() and _proc_mode != "walk":
		play("idle")


func heal(amount: int) -> void:
	hp = clampi(hp + amount, 0, max_hp)
	refresh_label()


func face_towards(world_target: Vector3) -> void:
	var d := world_target - global_position
	if Vector2(d.x, d.z).length() > 0.01:
		_model.rotation.y = atan2(d.x, d.z)
		facing = Vector2(d.x, d.z).normalized()
		if _facing_arrow:
			_facing_arrow.rotation.y = _model.rotation.y


## Reproduce la animación de la acción `key` (idle, walk, fight_b, fight_d, hit, ko).
## Busca el clip indicado en data.anim_map o, si no hay, uno que contenga `key`.
## Si el modelo no lo tiene (la mayoría del repo no trae animaciones), usa una
## versión procedural. Devuelve la duración.
func play(key: String) -> float:
	_reset_procedural()
	var clip_key: String = data.anim_map.get(key, key)
	if _anim:
		for anim_name in _anim.get_animation_list():
			if clip_key in anim_name:
				var anim := _anim.get_animation(anim_name)
				anim.loop_mode = Animation.LOOP_LINEAR if key in LOOPING_ANIMS else Animation.LOOP_NONE
				_anim.play(anim_name, 0.15)
				return anim.length
		# Sin clip para esta acción: congelar el anterior (si no, p. ej. el de caminar
		# seguiría en bucle) y usar la versión procedural.
		_anim.pause()
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
	elif key == "hit":
		# Retrocede un poco, como encajando el golpe.
		var back := -Vector3(sin(_model.rotation.y), 0.0, cos(_model.rotation.y)) * 0.12 * data.size
		var tw := create_tween()
		tw.tween_property(_model, "position", _model_base_pos + back, 0.08).set_ease(Tween.EASE_OUT)
		tw.tween_property(_model, "position", _model_base_pos, 0.2)
		return 0.3
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
	var boosts := stages_text()
	var vols := volatiles_text()
	_label.text = "%s\n%d/%d%s%s%s" % [TeamMember.display(base_data, gender), hp, max_hp, "  " + st if st else "",
		"\n" + boosts if boosts else "", "\n" + vols if vols else ""]


func is_transformed() -> bool:
	return data != base_data


## Transformación: copia el aspecto, tipos, stats (salvo PS), cambios de stats, habilidad y ataques
## de `t`. Conserva su tamaño en el tablero (el modelo se escala a su huella).
func transform_into(t: Unit) -> void:
	var copy: PokemonData = t.data.duplicate()
	copy.size = data.size
	copy.model_height = t.data.model_height / t.data.size * data.size
	var rot := _model.rotation.y
	_model.queue_free()
	data = copy
	stats = t.stats.duplicate()
	stages = t.stages.duplicate()
	stage_turns = t.stage_turns.duplicate()
	ability = t.ability
	moves = t.moves.duplicate()
	pp.clear()
	for mv in moves:
		pp[mv] = ceili(mv.pp / 2.0)
	choice_lock = null
	_load_model()
	_model.rotation.y = rot
	_label.position.y = data.model_height + 0.35
	refresh_label()


func _build_visuals() -> void:
	_load_model()

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

	_facing_arrow = Node3D.new()
	add_child(_facing_arrow)
	var arrow := MeshInstance3D.new()
	var tri := CylinderMesh.new()
	tri.top_radius = 0.0
	tri.bottom_radius = 0.11
	tri.height = 0.2
	tri.radial_segments = 3
	arrow.mesh = tri
	arrow.rotation.x = PI * 0.5
	arrow.position = Vector3(0, 0.04, 0.42 * RING_SCALE[data.size])
	arrow.scale = Vector3(1, 1, 0.35)
	arrow.material_override = _ring_mat
	arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_facing_arrow.add_child(arrow)

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


func _load_model() -> void:
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

class_name StoryFigure
extends Node3D
## Figura provisional de una persona en las escenas de historia (hasta que haya modelos): piernas, torso
## con la ropa, brazos, cabeza y pelo, con los colores del personaje. Se balancea al andar.

const HEIGHT := 1.15

var walking := false
var _body: Node3D
var _time := 0.0
var _base_y := 0.0


## `look`: {"ropa", "piel", "pelo", "pantalon"} (colores) y "alto" (escala, 1 = adulto).
func setup(look: Dictionary) -> void:
	var cloth := Color(look.get("ropa", "#4a6fa5"))
	var skin := Color(look.get("piel", "#f0c8a0"))
	var hair := Color(look.get("pelo", "#3a2a1a"))
	var legs := Color(look.get("pantalon", cloth.darkened(0.45).to_html()))
	var s := float(look.get("alto", 1.0))
	_body = Node3D.new()
	_body.scale = Vector3.ONE * s
	add_child(_body)
	for x in [-0.07, 0.07]:
		_part(_cylinder(0.055, 0.42), legs, Vector3(x, 0.21, 0))
	_part(_capsule(0.17, 0.5), cloth, Vector3(0, 0.62, 0))
	for x in [-0.21, 0.21]:
		var arm := _part(_capsule(0.05, 0.4), cloth.darkened(0.1), Vector3(x, 0.62, 0))
		arm.rotation.z = -0.12 * signf(x)
	_part(_sphere(0.15), skin, Vector3(0, 1.0, 0))
	var hair_mesh := _part(_sphere(0.165), hair, Vector3(0, 1.04, -0.025))
	hair_mesh.scale = Vector3(1.0, 0.85, 1.05)
	# Ojos: que se vea hacia dónde mira.
	for x in [-0.05, 0.05]:
		_part(_sphere(0.022), Color(0.08, 0.08, 0.1), Vector3(x, 1.01, 0.135))
	if look.get("melena", false):
		var long := _part(_capsule(0.14, 0.42), hair, Vector3(0, 0.84, -0.09))
		long.scale = Vector3(1.1, 1.0, 0.6)


func _process(delta: float) -> void:
	if _body == null:
		return
	_time += delta
	if walking:
		_body.position.y = absf(sin(_time * 12.0)) * 0.05
		_body.rotation.z = sin(_time * 12.0) * 0.05
	else:
		_body.position.y = 0.0
		_body.rotation.z = 0.0
		_body.scale.y = _body.scale.x * (1.0 + 0.012 * sin(_time * 2.2))


func face_towards(world_target: Vector3) -> void:
	var d := world_target - global_position
	d.y = 0.0
	if d.length() > 0.01:
		rotation.y = atan2(d.x, d.z)


func _part(mesh: Mesh, color: Color, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	mi.material_override = mat
	mi.position = pos
	_body.add_child(mi)
	return mi


func _capsule(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	return m


func _cylinder(r: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r * 0.85
	m.height = h
	return m


func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	return m

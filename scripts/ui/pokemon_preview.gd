class_name PokemonPreview
extends SubViewportContainer
## Vista 3D giratoria de un Pokémon, con su propio mundo (no interfiere con la batalla).

var _viewport: SubViewport
var _pivot: Node3D
var _camera: Camera3D
var _unit: Unit


func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	add_child(_viewport)

	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.9, 1.0)
	env.ambient_light_energy = 0.7
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 30, 0)
	sun.light_energy = 1.2
	_viewport.add_child(sun)

	_pivot = Node3D.new()
	_viewport.add_child(_pivot)

	var pedestal := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.05
	cyl.height = 0.08
	pedestal.mesh = cyl
	pedestal.position.y = -0.04
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.3, 0.4)
	pedestal.material_override = mat
	_pivot.add_child(pedestal)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.rotation_degrees.x = -12.0
	_viewport.add_child(_camera)


func show_pokemon(data: PokemonData) -> void:
	if _unit:
		_unit.queue_free()
		_unit = null
	if data == null:
		return
	_unit = Unit.new()
	_pivot.add_child(_unit)
	_unit.setup(TeamMember.create(data), 0)
	_unit.hide_overlays()
	_unit.face_towards(Vector3(0, 0, 10))
	var h := data.model_height
	var w := 1.0 + (data.size - 1) * 0.9
	_pivot.scale = Vector3.ONE * (1.0 / maxf(h, w * 0.8))
	# La cámara mira 12° hacia abajo: se sube para que el centro de la vista quede a media altura.
	_camera.size = 1.6
	_camera.position = Vector3(0, 0.55 + 6.0 * tan(deg_to_rad(12.0)), 6)


func _process(delta: float) -> void:
	_pivot.rotation.y += delta * 0.6

class_name WeatherFx
extends Node3D
## Efecto visual del clima: partículas que siguen a la cámara y ajustes de luz y niebla.

var follow: Node3D
var _particles: CPUParticles3D
var _env: Environment
var _sun: DirectionalLight3D
var _base := {}


## `scene_root` es donde CameraRig.build_environment creó WorldEnvironment y Sun.
func apply(kind: Weather.Kind, scene_root: Node) -> void:
	var world_env := scene_root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	var sun := scene_root.get_node_or_null("Sun") as DirectionalLight3D
	if world_env == null or sun == null:
		return
	if world_env.environment != _env:
		_env = world_env.environment
		_sun = sun
		_base = {
			"energy": sun.light_energy, "color": sun.light_color, "fog": _env.fog_enabled,
			"fog_color": _env.fog_light_color, "fog_density": _env.fog_density,
		}
	_sun.light_energy = _base.energy
	_sun.light_color = _base.color
	_env.fog_enabled = _base.fog
	_env.fog_light_color = _base.fog_color
	_env.fog_density = _base.fog_density
	if _particles:
		_particles.queue_free()
		_particles = null

	match kind:
		Weather.Kind.SUN:
			_sun.light_energy = _base.energy * 1.4
			_sun.light_color = Color(1.0, 0.9, 0.72)
		Weather.Kind.RAIN:
			_sun.light_energy = _base.energy * 0.55
			_fog(Color(0.45, 0.5, 0.58), 0.012)
			_particles = _make(Color(0.7, 0.8, 1.0, 0.55), Vector2(0.025, 0.55), 1600, 1.1, Vector3.DOWN, 16.0, 2.0)
		Weather.Kind.SAND:
			_sun.light_energy = _base.energy * 0.75
			_sun.light_color = Color(1.0, 0.85, 0.65)
			_fog(Color(0.75, 0.6, 0.4), 0.012)
			_particles = _make(Color(0.85, 0.7, 0.45, 0.7), Vector2(0.09, 0.09), 1400, 2.2, Vector3(1, -0.15, 0.3).normalized(), 9.0, 20.0)
		Weather.Kind.HAIL:
			_sun.light_energy = _base.energy * 0.8
			_fog(Color(0.8, 0.85, 0.92), 0.007)
			_particles = _make(Color(0.95, 0.97, 1.0, 0.9), Vector2(0.08, 0.08), 900, 1.6, Vector3(0.15, -1, 0).normalized(), 9.0, 6.0)
	if _particles:
		add_child(_particles)
		_particles.emitting = true


func _fog(color: Color, density: float) -> void:
	_env.fog_enabled = true
	_env.fog_light_color = color
	_env.fog_density = density


func _make(color: Color, size: Vector2, amount: int, lifetime: float, dir: Vector3, speed: float, spread: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.preprocess = lifetime
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(18, 0.5, 18)
	p.position = Vector3(0, 12, 0) - dir * 2.0
	p.direction = dir
	p.spread = spread
	p.initial_velocity_min = speed * 0.85
	p.initial_velocity_max = speed
	p.gravity = Vector3.ZERO
	var quad := QuadMesh.new()
	quad.size = size
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	# La lluvia se orienta vertical; el resto mira siempre a la cámara.
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y if size.y > size.x * 3.0 else BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = mat
	p.mesh = quad
	return p


func _process(_delta: float) -> void:
	if follow:
		global_position = Vector3(follow.global_position.x, 0.0, follow.global_position.z)

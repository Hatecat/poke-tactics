class_name WeatherFx
extends Node3D
## Efecto visual del clima: partículas que siguen a la cámara y ajustes de luz y niebla.

var follow: Node3D
var _particles: CPUParticles3D
## Capas extra de partículas (la tormenta de arena tiene varias).
var _layers: Array[CPUParticles3D] = []
## Dirección del viento de la tormenta de arena (la misma con la que se mecen las plantas).
const SAND_DIR := Vector3(1, -0.08, 0.3)
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
			"fog_color": _env.fog_light_color, "fog_density": _env.fog_density, "fog_sky": _env.fog_sky_affect,
		}
	_sun.light_energy = _base.energy
	_sun.light_color = _base.color
	_env.fog_enabled = _base.fog
	_env.fog_light_color = _base.fog_color
	_env.fog_density = _base.fog_density
	_env.fog_sky_affect = _base.fog_sky
	if _particles:
		_particles.queue_free()
		_particles = null
	for layer in _layers:
		layer.queue_free()
	_layers.clear()

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
			_sandstorm()
		Weather.Kind.HAIL:
			_sun.light_energy = _base.energy * 0.8
			_hailstorm()
	if _particles:
		add_child(_particles)
		_particles.emitting = true


## Tormenta de arena en capas: bruma densa, nubes de polvo grandes y lentas que la hacen ondular, ráfagas
## de arena alargadas y rápidas en la dirección del viento, y granos finos.
func _sandstorm() -> void:
	_fog(Color(0.8, 0.62, 0.4), 0.014)
	var dir := SAND_DIR.normalized()
	# Nubes de polvo: grandes, muy transparentes, cruzan despacio y se superponen.
	var clouds := _layer(_soft_texture(false), Color(0.84, 0.64, 0.4, 0.3), Vector2(4.5, 3.0), 60, 5.0, dir, 4.0, 6.0)
	clouds.emission_box_extents = Vector3(16, 1.5, 16)
	clouds.position = Vector3(0, 1.8, 0) - dir * 10.0
	clouds.scale_amount_min = 0.6
	clouds.scale_amount_max = 1.5
	clouds.angle_max = 360.0
	clouds.angular_velocity_min = -10.0
	clouds.angular_velocity_max = 10.0
	# Ráfagas: trazos largos alineados con su velocidad.
	var streaks := _layer(_soft_texture(true), Color(0.98, 0.86, 0.62, 0.75), Vector2(0.05, 0.9), 1000, 1.6, dir, 12.0, 17.0)
	streaks.particle_flag_align_y = true
	(streaks.mesh.material as StandardMaterial3D).billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	(streaks.mesh.material as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	streaks.emission_box_extents = Vector3(16, 2.5, 16)
	streaks.position = Vector3(0, 2.5, 0) - dir * 12.0
	# Granos finos, más dispersos.
	var grains := _layer(_soft_texture(false), Color(0.9, 0.75, 0.5, 0.85), Vector2(0.07, 0.07), 1400, 2.0, dir, 8.0, 12.0)
	grains.emission_box_extents = Vector3(16, 3.0, 16)
	grains.position = Vector3(0, 3.0, 0) - dir * 10.0
	grains.spread = 12.0


## Granizo: bolitas de hielo con volumen y brillo (azuladas, para que se vean sobre la nieve) que caen
## rápido dejando una estela, y ventisca: jirones de nieve que barren el tablero a ras de suelo.
func _hailstorm() -> void:
	_fog(Color(0.78, 0.84, 0.92), 0.01)
	var dir := Vector3(0.25, -1, 0.08).normalized()
	var stones := _make(Color.WHITE, Vector2.ONE, 700, 1.0, dir, 15.0, 3.0)
	stones.initial_velocity_min = 12.0
	var ball := SphereMesh.new()
	ball.radius = 0.055
	ball.height = 0.11
	ball.radial_segments = 8
	ball.rings = 4
	ball.material = WeatherFx.ice_material()
	stones.mesh = ball
	stones.position = Vector3(0, 14, 0) - dir * 2.0
	stones.scale_amount_min = 0.7
	stones.scale_amount_max = 1.4
	add_child(stones)
	stones.emitting = true
	_layers.append(stones)
	var trails := _layer(_soft_texture(true), Color(0.75, 0.88, 1.0, 0.45), Vector2(0.04, 0.6), 500, 1.0, dir, 12.0, 15.0)
	trails.particle_flag_align_y = true
	(trails.mesh.material as StandardMaterial3D).billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	(trails.mesh.material as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	trails.position = Vector3(0, 14, 0) - dir * 2.0
	var blizzard := _layer(_soft_texture(true), Color(1, 1, 1, 0.35), Vector2(0.25, 2.2), 160, 2.2, Vector3(1, -0.05, 0.3).normalized(), 6.0, 9.0)
	blizzard.particle_flag_align_y = true
	(blizzard.mesh.material as StandardMaterial3D).billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	(blizzard.mesh.material as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	blizzard.emission_box_extents = Vector3(16, 0.6, 16)
	blizzard.position = Vector3(0, 0.9, 0) - Vector3(1, 0, 0.3) * 10.0


## Hielo de las bolitas de granizo: blanco azulado, brillante y con borde más azul (no se pierde en la nieve).
static func ice_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.72, 0.85, 1.0)
	m.roughness = 0.12
	m.metallic_specular = 1.0
	m.rim_enabled = true
	m.rim = 1.0
	m.rim_tint = 0.0
	m.emission_enabled = true
	m.emission = Color(0.2, 0.35, 0.6)
	m.emission_energy_multiplier = 0.4
	m.disable_fog = true
	return m


func _layer(tex: Texture2D, color: Color, size: Vector2, amount: int, lifetime: float, dir: Vector3,
		speed_min: float, speed_max: float) -> CPUParticles3D:
	var p := _make(color, size, amount, lifetime, dir, speed_max, 3.0)
	p.initial_velocity_min = speed_min
	var mat := p.mesh.material as StandardMaterial3D
	mat.albedo_texture = tex
	mat.disable_fog = true  # la bruma no las apaga: se distinguen sobre ella
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(p)
	p.emitting = true
	_layers.append(p)
	return p


## Textura suave procedural: mancha redonda difuminada o trazo (más denso en el centro, se apaga en las puntas).
static func _soft_texture(streak: bool) -> Texture2D:
	var w := 16 if streak else 64
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var d := Vector2((x + 0.5) / w * 2.0 - 1.0, (y + 0.5) / h * 2.0 - 1.0)
			var a := clampf(1.0 - d.length(), 0.0, 1.0) if not streak else \
				clampf(1.0 - absf(d.x), 0.0, 1.0) * clampf(1.0 - absf(d.y), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)


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

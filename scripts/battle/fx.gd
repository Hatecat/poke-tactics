class_name Fx
extends RefCounted
## Efectos visuales de los ataques: partículas por tipo, proyectiles, rayos y auras.
## Todo se crea con CPUParticles3D y primitivas, y se libera solo al terminar.

## Por tipo: color principal, color secundario, gravedad (negativa = sube), velocidad,
## tamaño, duración, brillo aditivo y cantidad base de partículas.
const PROFILES := {
	"normal": [Color(1, 1, 1), Color(0.75, 0.72, 0.65), 2.0, 2.5, 0.12, 0.5, false, 24],
	"fire": [Color(1.0, 0.6, 0.15), Color(0.9, 0.15, 0.05), -2.0, 1.8, 0.22, 0.7, true, 40],
	"water": [Color(0.45, 0.7, 1.0), Color(0.85, 0.95, 1.0), 7.0, 3.2, 0.11, 0.7, false, 40],
	"electric": [Color(1.0, 0.95, 0.35), Color(1, 1, 1), 0.0, 5.5, 0.08, 0.3, true, 36],
	"grass": [Color(0.4, 0.85, 0.3), Color(0.2, 0.55, 0.15), 1.0, 1.8, 0.15, 1.0, false, 28],
	"ice": [Color(0.7, 0.95, 1.0), Color(1, 1, 1), 3.5, 3.0, 0.1, 0.7, true, 34],
	"fighting": [Color(1.0, 0.55, 0.3), Color(1, 1, 1), 2.0, 4.0, 0.12, 0.35, true, 26],
	"poison": [Color(0.7, 0.3, 0.85), Color(0.45, 0.1, 0.55), -1.2, 1.0, 0.17, 1.0, false, 26],
	"ground": [Color(0.65, 0.5, 0.3), Color(0.45, 0.35, 0.2), 7.0, 3.5, 0.15, 0.8, false, 34],
	"flying": [Color(0.9, 0.92, 1.0), Color(0.7, 0.65, 0.95), 0.0, 2.8, 0.12, 0.6, true, 26],
	"psychic": [Color(1.0, 0.45, 0.75), Color(0.75, 0.4, 1.0), 0.0, 1.6, 0.16, 0.8, true, 30],
	"bug": [Color(0.7, 0.85, 0.2), Color(0.45, 0.6, 0.1), 1.0, 2.6, 0.09, 0.6, false, 30],
	"rock": [Color(0.6, 0.55, 0.45), Color(0.4, 0.37, 0.32), 9.0, 3.2, 0.18, 0.8, false, 24],
	"ghost": [Color(0.45, 0.3, 0.6), Color(0.15, 0.08, 0.25), -0.8, 0.9, 0.24, 1.1, false, 24],
	"dragon": [Color(0.5, 0.35, 1.0), Color(0.3, 0.75, 1.0), 0.0, 3.0, 0.14, 0.6, true, 34],
	"dark": [Color(0.3, 0.2, 0.35), Color(0.08, 0.05, 0.1), 0.0, 2.0, 0.2, 0.7, false, 28],
	"steel": [Color(0.85, 0.88, 0.95), Color(1, 1, 1), 4.0, 4.5, 0.07, 0.4, true, 34],
	"fairy": [Color(1.0, 0.65, 0.85), Color(1, 1, 1), -0.5, 1.5, 0.11, 0.9, true, 30],
}
const HEAL_COLOR := Color(0.4, 1.0, 0.5)
const BUFF_COLOR := Color(1.0, 0.55, 0.25)
const DEBUFF_COLOR := Color(0.35, 0.55, 1.0)

static var _dot: Texture2D
static var _materials := {}


static func _profile(type: String) -> Array:
	return PROFILES.get(type, PROFILES["normal"])


## Explosión de partículas del tipo `type` en `pos`. `strength` escala cantidad y tamaño.
static func burst(parent: Node3D, pos: Vector3, type: String, strength := 1.0) -> void:
	var p := _profile(type)
	var parts := _particles(p[0], p[1], p[6], p[4] * (0.7 + 0.3 * strength))
	parts.amount = maxi(6, int(p[7] * strength))
	parts.lifetime = p[5]
	parts.direction = Vector3.UP
	parts.spread = 180.0
	parts.initial_velocity_min = p[3] * 0.5
	parts.initial_velocity_max = p[3]
	parts.gravity = Vector3(0, -p[2], 0)
	parts.damping_min = 1.0
	parts.damping_max = 3.0
	if type == "flying":
		parts.tangential_accel_min = 4.0
		parts.tangential_accel_max = 8.0
	elif type == "psychic" or type == "dragon":
		parts.radial_accel_min = 1.0
		parts.radial_accel_max = 2.5
	_spawn(parent, parts, pos)
	if type == "electric":
		_flash(parent, pos, p[0])


## Bola brillante que recorre `points` dejando estela. Devuelve el Tween para esperarlo.
static func projectile(parent: Node3D, points: Array[Vector3], type: String) -> Tween:
	var p := _profile(type)
	var ball := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.13
	sphere.height = 0.26
	ball.mesh = sphere
	ball.material_override = _glow_material(p[0])
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(ball)
	ball.global_position = points[0]

	var trail := _particles(p[0], p[1], p[6], p[4] * 0.7)
	trail.one_shot = false
	trail.explosiveness = 0.0
	trail.amount = 40
	trail.lifetime = 0.35
	trail.spread = 25.0
	trail.initial_velocity_max = 0.4
	trail.gravity = Vector3(0, -p[2] * 0.3, 0)
	trail.local_coords = false
	ball.add_child(trail)
	trail.emitting = true

	var tw := parent.create_tween()
	for i in range(1, points.size()):
		var dist := points[i].distance_to(points[i - 1])
		tw.tween_property(ball, "global_position", points[i], maxf(dist * 0.07, 0.03))
	tw.tween_callback(func() -> void:
		trail.emitting = false
		ball.material_override = null
		ball.mesh = null
		parent.get_tree().create_timer(0.5).timeout.connect(ball.queue_free))
	return tw


## Haz recto entre `from` y `to` que aparece y se desvanece.
static func beam(parent: Node3D, from: Vector3, to: Vector3, type: String) -> void:
	var p := _profile(type)
	var length := from.distance_to(to)
	if length < 0.05:
		return
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.global_position = (from + to) * 0.5
	holder.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.95 else Vector3.RIGHT)
	var core := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.09
	cyl.bottom_radius = 0.09
	cyl.height = length
	core.mesh = cyl
	core.rotation.x = PI * 0.5
	core.material_override = _glow_material(p[0])
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(core)
	holder.scale = Vector3(0.1, 0.1, 1.0)
	var tw := parent.create_tween()
	tw.tween_property(holder, "scale", Vector3(1.4, 1.4, 1.0), 0.08)
	tw.tween_property(holder, "scale", Vector3(0.9, 0.9, 1.0), 0.25)
	tw.tween_property(holder, "scale", Vector3(0.0, 0.0, 1.0), 0.15)
	tw.tween_callback(holder.queue_free)
	# Chispas a lo largo del haz.
	var steps := maxi(2, int(length / 0.6))
	for i in steps:
		burst(parent, from.lerp(to, float(i + 1) / steps), type, 0.25)


## Aura que sube (o baja) alrededor de un Pokémon: estados, cambios de stats, curación.
static func aura(parent: Node3D, pos: Vector3, color: Color, height: float, rising := true) -> void:
	var parts := _particles(color, color.lightened(0.5), true, 0.1)
	parts.amount = 26
	parts.lifetime = 0.9
	parts.explosiveness = 0.3
	parts.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	parts.emission_ring_axis = Vector3.UP
	parts.emission_ring_radius = 0.45
	parts.emission_ring_inner_radius = 0.35
	parts.emission_ring_height = 0.05
	parts.direction = Vector3.UP if rising else Vector3.DOWN
	parts.spread = 8.0
	parts.initial_velocity_min = 0.8
	parts.initial_velocity_max = 1.4
	parts.gravity = Vector3.ZERO
	_spawn(parent, parts, pos + (Vector3.ZERO if rising else Vector3.UP * height))


static func _flash(parent: Node3D, pos: Vector3, color: Color) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 4.0
	light.omni_range = 3.0
	parent.add_child(light)
	light.global_position = pos + Vector3.UP * 0.4
	var tw := parent.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.25)
	tw.tween_callback(light.queue_free)


static func _particles(color: Color, color2: Color, additive: bool, size: float) -> CPUParticles3D:
	var parts := CPUParticles3D.new()
	parts.one_shot = true
	parts.explosiveness = 0.9
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	quad.material = _particle_material(additive)
	parts.mesh = quad
	var ramp := Gradient.new()
	ramp.set_color(0, color)
	ramp.set_color(1, Color(color2, 0.0))
	parts.color_ramp = ramp
	parts.scale_amount_min = 0.6
	parts.scale_amount_max = 1.3
	return parts


static func _spawn(parent: Node3D, parts: CPUParticles3D, pos: Vector3) -> void:
	if not parent.is_inside_tree():
		parts.free()
		return
	parent.add_child(parts)
	parts.global_position = pos
	parts.emitting = true
	parent.get_tree().create_timer(parts.lifetime + 0.6).timeout.connect(parts.queue_free)


static func _particle_material(additive: bool) -> StandardMaterial3D:
	var key := "add" if additive else "mix"
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = _soft_dot()
		m.no_depth_test = false
		_materials[key] = m
	return _materials[key]


static func _glow_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 3.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


## Textura de punto suave (degradado radial) compartida por todas las partículas.
static func _soft_dot() -> Texture2D:
	if _dot == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.4, Color(1, 1, 1, 0.8))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 64
		tex.height = 64
		_dot = tex
	return _dot

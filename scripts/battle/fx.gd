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
static var _star_tex: Texture2D
static var _bolt_tex: Texture2D
static var _bubble_tex: Texture2D
static var _bird_tex: Texture2D
static var _flame_tex: Texture2D
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


## Poké Ball del color de su tipo. La mitad de arriba es una tapa con bisagra atrás (Fx.ball_open) y el botón,
## delante (+Z), se puede iluminar (Fx.ball_button).
static func pokeball(parent: Node3D, color := Color(0.85, 0.12, 0.12)) -> Node3D:
	var root := Node3D.new()
	parent.add_child(root)
	var r := 0.17
	var half := SphereMesh.new()
	half.radius = r
	half.height = r
	half.is_hemisphere = true
	# Tapa: gira sobre la bisagra (detrás, a la altura de la junta).
	var lid := Node3D.new()
	lid.position = Vector3(0, 0, -r)
	root.add_child(lid)
	var top := MeshInstance3D.new()
	top.mesh = half
	top.position = Vector3(0, 0, r)
	top.material_override = _solid(color)
	lid.add_child(top)
	var white := MeshInstance3D.new()
	white.mesh = half
	white.rotation.x = PI
	white.material_override = _solid(Color(0.96, 0.96, 0.96))
	root.add_child(white)
	var band := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = r * 1.01
	cyl.bottom_radius = r * 1.01
	cyl.height = 0.03
	band.mesh = cyl
	band.material_override = _solid(Color(0.08, 0.08, 0.08))
	root.add_child(band)
	var button := MeshInstance3D.new()
	var dot := CylinderMesh.new()
	dot.top_radius = 0.05
	dot.bottom_radius = 0.05
	dot.height = 0.03
	button.mesh = dot
	button.rotation.x = PI * 0.5
	button.position = Vector3(0, 0, r * 0.97)
	var button_mat := _solid(Color(0.95, 0.95, 0.95))
	button_mat.emission = Color(1.0, 0.15, 0.1)
	button.material_override = button_mat
	root.add_child(button)
	root.set_meta("lid", lid)
	root.set_meta("button", button_mat)
	return root


## Abre (o cierra) la tapa de una Poké Ball de Fx.pokeball. Devuelve el Tween para esperarlo.
static func ball_open(ball: Node3D, open: bool, time := 0.12) -> Tween:
	var lid: Node3D = ball.get_meta("lid")
	var tw := ball.create_tween()
	tw.tween_property(lid, "rotation:x", -1.9 if open else 0.0, time).set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_OUT if open else Tween.EASE_IN)
	return tw


## Enciende (con ese color) o apaga el botón de una Poké Ball de Fx.pokeball.
static func ball_button(ball: Node3D, on: bool, color := Color(1.0, 0.15, 0.1)) -> void:
	var m: StandardMaterial3D = ball.get_meta("button")
	m.emission_enabled = on
	m.emission = color
	m.emission_energy_multiplier = 3.0


## Destello de luz en `pos` (sale de la Poké Ball, impactos eléctricos...).
static func flash(parent: Node3D, pos: Vector3, color: Color, energy := 4.0) -> void:
	_flash(parent, pos, color, energy)


## Estrellitas que saltan en abanico desde `pos` y caen apagándose (captura lograda).
static func stars(parent: Node3D, pos: Vector3, size := 0.14) -> void:
	for i in 3:
		var s := Sprite3D.new()
		s.texture = _star()
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.shaded = false
		s.no_depth_test = true
		s.pixel_size = size / 64.0
		s.modulate = Color(1.0, 0.92, 0.3)
		parent.add_child(s)
		s.global_position = pos
		var dir := Vector3((i - 1) * 0.5, 1.0, 0.0)
		var end := pos + dir * size * 4.0
		var tw := s.create_tween().set_parallel()
		tw.tween_property(s, "global_position", end, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(s, "rotation:z", TAU, 0.7)
		tw.tween_property(s, "modulate:a", 0.0, 0.3).set_delay(0.45)
		tw.chain().tween_callback(s.queue_free)


## Nube de humo (al escaparse de la Poké Ball).
static func smoke(parent: Node3D, pos: Vector3) -> void:
	var parts := _particles(Color(0.85, 0.85, 0.85, 0.9), Color(0.6, 0.6, 0.6), false, 0.35)
	parts.amount = 30
	parts.lifetime = 0.9
	parts.spread = 180.0
	parts.initial_velocity_min = 0.6
	parts.initial_velocity_max = 1.4
	parts.gravity = Vector3(0, 0.8, 0)
	parts.damping_min = 1.5
	parts.damping_max = 2.5
	parts.scale_amount_min = 0.8
	parts.scale_amount_max = 1.8
	_spawn(parent, parts, pos + Vector3.UP * 0.2)


## Gas tóxico que sale sin parar de un Pokémon (Koffing, Weezing). Las partículas se sueltan en el mundo,
## así que al moverse dejan un rastro. Devuelve el emisor para apagarlo (emitting = false).
static func toxic_gas(parent: Node3D, height: float, color: Color, color2: Color) -> CPUParticles3D:
	var parts := _particles(color, color2, false, 0.3 * height)
	parts.one_shot = false
	parts.explosiveness = 0.0
	parts.amount = 26
	parts.lifetime = 2.4
	# Empieza ya con la nube formada: las partículas que aún no han salido se pintaban como un punto oscuro.
	parts.preprocess = parts.lifetime
	parts.local_coords = false
	# Sale de un anillo alrededor de la parte alta del cuerpo, no de dentro: así no tapa la cara.
	parts.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	parts.emission_ring_axis = Vector3.UP
	parts.emission_ring_radius = 0.5 * height
	parts.emission_ring_inner_radius = 0.4 * height
	parts.emission_ring_height = 0.2 * height
	parts.direction = Vector3.UP
	parts.spread = 60.0
	parts.initial_velocity_min = 0.1
	parts.initial_velocity_max = 0.3
	parts.gravity = Vector3(0, 0.12, 0)
	parts.damping_min = 0.2
	parts.damping_max = 0.5
	parts.scale_amount_min = 0.7
	parts.scale_amount_max = 1.6
	# Crecen al alejarse, como una nube que se deshace.
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.4))
	grow.add_point(Vector2(1, 1.4))
	parts.scale_amount_curve = grow
	parent.add_child(parts)
	parts.position = Vector3.UP * height * 0.7
	parts.emitting = true
	return parts


## Llamas que brotan sin parar del cuerpo de un Pokémon quemado (como en los juegos de DS): lenguas de fuego con
## forma (núcleo amarillo, cuerpo naranja, borde rojo) que nacen alrededor del cuerpo, suben, crecen y se apagan.
## Van con él (coordenadas locales). Devuelve el emisor para apagarlo (queue_free).
static func burning(parent: Node3D, height: float, width: float) -> CPUParticles3D:
	var h := clampf(height, 0.6, 2.5)
	var parts := CPUParticles3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.75, 1.0) * 0.32 * h
	quad.material = _flame_material()
	parts.mesh = quad
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	ramp.add_point(0.92, Color(1, 1, 1))  # opacas hasta el final: se apagan encogiéndose, no destiñéndose
	parts.color_ramp = ramp
	parts.randomness = 0.6
	parts.amount = 12
	parts.lifetime = 0.9
	parts.preprocess = parts.lifetime
	parts.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	parts.emission_ring_axis = Vector3.UP
	parts.emission_ring_radius = 0.48 * width
	parts.emission_ring_inner_radius = 0.3 * width
	parts.emission_ring_height = 0.6 * height
	parts.direction = Vector3.UP
	parts.spread = 10.0
	parts.initial_velocity_min = 0.25
	parts.initial_velocity_max = 0.5
	parts.gravity = Vector3(0, 0.3, 0)
	parts.scale_amount_min = 0.6
	parts.scale_amount_max = 1.3
	# Cada llama nace pequeña, crece y se apaga encogiéndose, como una lengua de fuego.
	var flame := Curve.new()
	flame.add_point(Vector2(0, 0.3))
	flame.add_point(Vector2(0.35, 1.0))
	flame.add_point(Vector2(1, 0.2))
	parts.scale_amount_curve = flame
	parent.add_child(parts)
	parts.position = Vector3.UP * height * 0.5
	parts.emitting = true
	return parts


## Material de las llamas del quemado: mirando a cámara, con los colores en la textura.
static func _flame_material() -> StandardMaterial3D:
	if not _materials.has("flame"):
		var m := _particle_material(false).duplicate() as StandardMaterial3D
		m.albedo_texture = _flame()
		_materials["flame"] = m
	return _materials["flame"]


## Lengua de fuego: base redonda y punta afilada algo torcida; borde rojo, cuerpo naranja y núcleo amarillo
## (la misma silueta, más pequeña, anclada en la base). Se dibuja una vez y se comparte.
static func _flame() -> Texture2D:
	if _flame_tex == null:
		var layers := [[1.0, Color(0.85, 0.12, 0.04)], [0.84, Color(1.0, 0.45, 0.08)], [0.64, Color(1.0, 0.72, 0.15)],
			[0.4, Color(1.0, 0.95, 0.6)]]
		var img := Image.create(48, 64, false, Image.FORMAT_RGBA8)
		for y in 64:
			for x in 48:
				var acc := Color(0, 0, 0, 0)
				for sy in 2:  # 2x2 muestras por píxel para suavizar el borde
					for sx in 2:
						var p := Vector2(x + 0.25 + 0.5 * sx, y + 0.25 + 0.5 * sy)
						var c := Color(0, 0, 0, 0)
						for l: Array in layers:
							if _in_flame(p, l[0]):
								c = l[1]
						acc += Color(c.r * c.a, c.g * c.a, c.b * c.a, c.a)
				var a := maxf(acc.a, 0.001)
				img.set_pixel(x, y, Color(acc.r / a, acc.g / a, acc.b / a, acc.a / 4.0))
		_flame_tex = ImageTexture.create_from_image(img)
	return _flame_tex


## ¿Está `p` (píxeles de la textura de 48x64) dentro de la llama escalada `k` desde su base?
static func _in_flame(p: Vector2, k: float) -> bool:
	var base := Vector2(24, 61)
	var q := base + (p - base) / k
	var r := 15.0
	var cy := 44.0
	if q.distance_to(Vector2(24, cy)) <= r:
		return true
	if q.y < 3.0 or q.y > cy:
		return false
	var t := (q.y - 3.0) / (cy - 3.0)  # 0 en la punta, 1 donde empieza la base redonda
	var cx := 24.0 + 5.0 * (1.0 - t) * (1.0 - t)  # la punta se tuerce un poco
	return absf(q.x - cx) <= r * pow(t, 0.9)


## Bloque de hielo que encierra a un Pokémon congelado (como en los juegos): un cristal facetado y translúcido,
## algo irregular, del tamaño del Pokémon. Devuelve el nodo para quitarlo (queue_free).
static func ice_block(parent: Node3D, height: float, radius: float) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7  # siempre la misma forma
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 6
	var top := height * 1.15
	var low: Array[Vector3] = []
	var mid: Array[Vector3] = []
	for i in sides:
		var a := TAU * i / sides + rng.randf_range(-0.12, 0.12)
		var d := Vector3(cos(a), 0, sin(a))
		low.append(d * radius * rng.randf_range(0.85, 0.95))
		mid.append(d * radius * rng.randf_range(1.0, 1.12) + Vector3.UP * top * rng.randf_range(0.72, 0.82))
	var apex := Vector3(radius * 0.12, top, -radius * 0.08)
	var floor_c := Vector3.ZERO
	for i in sides:
		var j := (i + 1) % sides
		_tri(st, floor_c, low[j], low[i])
		_tri(st, low[i], low[j], mid[j])
		_tri(st, low[i], mid[j], mid[i])
		_tri(st, mid[i], mid[j], apex)
	st.generate_normals()  # sin índices: una normal por cara, facetado
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.78, 0.82, 1.0, 0.32)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.05
	mat.metallic_specular = 1.0
	mat.rim_enabled = true
	mat.rim = 0.6
	mat.emission_enabled = true
	mat.emission = Color(0.55, 0.6, 1.0)
	mat.emission_energy_multiplier = 0.15
	var block := MeshInstance3D.new()
	block.mesh = st.commit()
	block.material_override = mat
	block.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(block)
	return block


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


## Zetas que suben de la cabeza de un Pokémon dormido, una tras otra y en zigzag (como en los juegos).
## Devuelve el nodo para quitarlo (queue_free).
static func sleeping(parent: Node3D, height: float) -> Node3D:
	var root := Node3D.new()
	parent.add_child(root)
	root.position = Vector3.UP * height * 0.95
	var h := clampf(height, 0.8, 2.5)
	var timer := Timer.new()
	timer.wait_time = 0.9
	timer.autostart = true
	root.add_child(timer)
	var count := [0]
	timer.timeout.connect(func() -> void:
		var side := 1.0 if count[0] % 2 else -1.0
		count[0] += 1
		var z := Label3D.new()
		z.text = "Z"
		z.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		z.font_size = 64
		z.outline_size = 16
		z.pixel_size = 0.3 * h / 64.0
		z.modulate = Color(1.0, 0.42, 0.55)
		z.outline_modulate = Color(1, 1, 1)
		# Salen de un lado de la cabeza para no subir por encima del nombre.
		z.position = Vector3(0.18 * h + 0.04 * h * side, 0, 0)
		z.scale = Vector3.ONE * 0.6
		root.add_child(z)
		var tw := z.create_tween().set_parallel()
		# Suben en diagonal y lejos, para que cada Z se lea separada de la anterior.
		tw.tween_property(z, "position", Vector3(0.55 * h - 0.06 * h * side, 0.85 * h, 0), 1.8)
		tw.tween_property(z, "scale", Vector3.ONE * 1.2, 1.8)
		tw.tween_property(z, "modulate:a", 0.0, 0.5).set_delay(1.3)
		tw.chain().tween_callback(z.queue_free))
	return root


## Estrellas y pajaritos que dan vueltas sobre la cabeza de un Pokémon confuso (como en el anime y los juegos).
## El que lo crea lo hace girar (rotation.y). Devuelve el nodo para quitarlo (queue_free).
static func dizzy(parent: Node3D, height: float, width: float) -> Node3D:
	var root := Node3D.new()
	parent.add_child(root)
	root.position = Vector3.UP * (height + 0.1)
	var r := clampf(0.4 * width, 0.3, 0.9)
	var n := 6
	for i in n:
		var s := Sprite3D.new()
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.shaded = false
		if i % 2 == 0:
			s.texture = _star()
			s.pixel_size = maxf(0.6 * r, 0.2) / 64.0
			s.modulate = Color(1.0, 0.92, 0.3) if i % 4 == 0 else Color(1.0, 0.6, 0.15)
		else:
			s.texture = _bird()
			s.pixel_size = maxf(0.8 * r, 0.27) / 64.0
		var a := TAU * i / n
		s.position = Vector3(cos(a) * r, 0.04 * r * sin(3 * a), sin(a) * r)
		root.add_child(s)
	return root


## Pajarito amarillo-anaranjado de perfil (como los que rodean a los confusos en el anime), con contorno marrón.
## Se dibuja una vez y se comparte.
static func _bird() -> Texture2D:
	if _bird_tex == null:
		var yellow := Color(1.0, 0.8, 0.22)
		var orange := Color(1.0, 0.55, 0.1)
		# Formas de detrás adelante: [centro, radios, color]. La última que contiene el punto manda.
		var shapes := [
			[Vector2(28, 40), Vector2(19, 16), yellow],  # cuerpo
			[Vector2(10, 36), Vector2(7, 4), orange],  # cola
			[Vector2(41, 24), Vector2(13, 13), yellow],  # cabeza
			[Vector2(37, 10), Vector2(4, 5), orange],  # copete
			[Vector2(44, 9), Vector2(3, 4), orange],
			[Vector2(56, 26), Vector2(6, 3), orange],  # pico
			[Vector2(25, 41), Vector2(10, 7), Color(0.95, 0.62, 0.15)],  # ala
			[Vector2(45, 21), Vector2(2.5, 2.5), Color(0.1, 0.05, 0.0)],  # ojo
		]
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		for y in 64:
			for x in 64:
				var p := Vector2(x + 0.5, y + 0.5)
				for sh: Array in shapes:
					var q: Vector2 = (p - sh[0]) / sh[1]
					if q.length() <= 1.0:
						img.set_pixel(x, y, sh[2])
		# Contorno: los píxeles vacíos junto a uno pintado.
		var outline := img.duplicate() as Image
		for y in 64:
			for x in 64:
				if img.get_pixel(x, y).a > 0.0:
					continue
				for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nx := x + o.x
					var ny := y + o.y
					if nx >= 0 and ny >= 0 and nx < 64 and ny < 64 and img.get_pixel(nx, ny).a > 0.0:
						outline.set_pixel(x, y, Color(0.45, 0.22, 0.05))
						break
		_bird_tex = ImageTexture.create_from_image(outline)
	return _bird_tex


## Burbujas moradas que suben del cuerpo de un Pokémon envenenado, se hinchan y revientan (como en los juegos).
## Devuelve el emisor para apagarlo (queue_free).
static func poisoned(parent: Node3D, height: float, width: float) -> CPUParticles3D:
	var h := clampf(height, 0.7, 2.5)
	var parts := CPUParticles3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.22 * h
	quad.material = _bubble_material()
	parts.mesh = quad
	# Opacas casi toda la vida; al reventar se desvanecen de golpe.
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	ramp.add_point(0.85, Color(1, 1, 1))
	parts.color_ramp = ramp
	parts.randomness = 0.5
	parts.amount = 24
	parts.lifetime = 1.4
	parts.preprocess = parts.lifetime
	parts.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	parts.emission_ring_axis = Vector3.UP
	parts.emission_ring_radius = 0.45 * width
	parts.emission_ring_inner_radius = 0.2 * width
	parts.emission_ring_height = 0.5 * height
	parts.direction = Vector3.UP
	parts.spread = 25.0
	parts.initial_velocity_min = 0.2
	parts.initial_velocity_max = 0.45
	parts.gravity = Vector3(0, 0.15, 0)
	parts.scale_amount_min = 0.5
	parts.scale_amount_max = 1.4
	# Nacen pequeñas, se hinchan al subir y al final revientan (un último estirón antes de desaparecer).
	var bubble := Curve.new()
	bubble.add_point(Vector2(0, 0.3))
	bubble.add_point(Vector2(0.8, 1.0))
	bubble.add_point(Vector2(1, 1.6))
	parts.scale_amount_curve = bubble
	parent.add_child(parts)
	parts.position = Vector3.UP * height * 0.6
	parts.emitting = true
	return parts


## Material de las burbujas del envenenado: mirando a cámara, con los colores en la textura.
static func _bubble_material() -> StandardMaterial3D:
	if not _materials.has("bubble"):
		var m := _particle_material(false).duplicate() as StandardMaterial3D
		m.albedo_texture = _bubble()
		_materials["bubble"] = m
	return _materials["bubble"]


## Burbuja: relleno morado (más claro arriba), borde morado oscuro y un brillo blanco. Se dibuja una vez.
static func _bubble() -> Texture2D:
	if _bubble_tex == null:
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		for y in 64:
			for x in 64:
				var acc := Color(0, 0, 0, 0)
				for sy in 2:  # 2x2 muestras por píxel para suavizar los bordes
					for sx in 2:
						var p := (Vector2(x + 0.25 + 0.5 * sx, y + 0.25 + 0.5 * sy) - Vector2(32, 32)) / 30.0
						var d := p.length()
						var c := Color(0, 0, 0, 0)
						if d < 0.8:
							c = Color(0.82, 0.5, 1.0).lerp(Color(0.6, 0.22, 0.85), clampf(0.5 + 0.6 * p.y, 0.0, 1.0))
						elif d < 1.0:
							c = Color(0.36, 0.06, 0.5)
						if p.distance_to(Vector2(-0.32, -0.34)) < 0.2:
							c = Color(1, 1, 1)
						acc += Color(c.r * c.a, c.g * c.a, c.b * c.a, c.a)
				img.set_pixel(x, y, Color(acc.r / maxf(acc.a, 0.001), acc.g / maxf(acc.a, 0.001),
						acc.b / maxf(acc.a, 0.001), acc.a / 4.0))
		_bubble_tex = ImageTexture.create_from_image(img)
	return _bubble_tex


## Rayos que le saltan del cuerpo a un Pokémon paralizado cada poco (en ráfagas, a ratos): en cada ráfaga,
## `flash` (la capa de tinte del modelo) parpadea tres veces y con cada parpadeo chisporrotean unos rayos en
## zigzag alrededor del cuerpo, girados al azar. Devuelve el emisor para apagarlo (queue_free).
static func paralyzed(parent: Node3D, height: float, width: float, flash: StandardMaterial3D) -> CPUParticles3D:
	var h := clampf(height, 0.7, 2.5)
	var parts := CPUParticles3D.new()
	parts.one_shot = true
	parts.explosiveness = 1.0
	parts.emitting = false  # cada parpadeo lanza los suyos
	var quad := QuadMesh.new()
	quad.size = Vector2(0.42, 0.84) * h
	quad.material = _bolt_material()
	parts.mesh = quad
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	ramp.add_point(0.75, Color(1, 1, 1))
	parts.color_ramp = ramp
	parts.amount = 7
	parts.lifetime = 0.12
	parts.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE_SURFACE
	# Nacen alrededor del cuerpo, no encima: así asoman por fuera de la silueta.
	parts.emission_sphere_radius = 0.85 * maxf(width, height * 0.7)
	parts.spread = 180.0
	parts.initial_velocity_min = 0.2
	parts.initial_velocity_max = 0.5
	parts.gravity = Vector3.ZERO
	parts.angle_min = 0.0
	parts.angle_max = 360.0
	parts.scale_amount_min = 0.7
	parts.scale_amount_max = 1.3
	parent.add_child(parts)
	parts.position = Vector3.UP * height * 0.55
	var timer := Timer.new()
	timer.autostart = true
	timer.wait_time = 0.6
	parts.add_child(timer)
	timer.timeout.connect(func() -> void:
		var tw := parts.create_tween()
		for i in 3:
			tw.tween_callback(func() -> void:
				flash.albedo_color.a = 0.55
				parts.restart())
			tw.tween_interval(0.12)
			tw.tween_callback(func() -> void: flash.albedo_color.a = 0.0)
			tw.tween_interval(0.08)
		timer.start(randf_range(0.9, 1.8)))
	return parts


## Material de los rayos del paralizado: mirando a cámara, con el giro de cada partícula y por encima del
## modelo (como en los juegos, el rayo se pinta sobre el Pokémon). Los colores van en la textura.
static func _bolt_material() -> StandardMaterial3D:
	if not _materials.has("bolt"):
		var m := _particle_material(false).duplicate() as StandardMaterial3D
		m.albedo_texture = _bolt()
		m.no_depth_test = true
		_materials["bolt"] = m
	return _materials["bolt"]


## Rayo en zigzag: núcleo blanco, cuerpo amarillo, borde naranja oscuro (para que destaque sobre fondos claros
## y sobre el propio destello amarillo) y un halo suave. Se dibuja una vez y se comparte.
static func _bolt() -> Texture2D:
	if _bolt_tex == null:
		var pts := PackedVector2Array([Vector2(31, 3), Vector2(13, 40), Vector2(32, 45), Vector2(12, 93)])
		var img := Image.create(48, 96, false, Image.FORMAT_RGBA8)
		for y in 96:
			for x in 48:
				var p := Vector2(x + 0.5, y + 0.5)
				var d := INF
				for i in pts.size() - 1:
					d = minf(d, p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])))
				var c := Color(1.0, 0.9, 0.3, clampf(1.0 - (d - 5.0) / 5.0, 0.0, 1.0) * 0.4)
				if d < 1.5:
					c = Color(1.0, 1.0, 0.85)
				elif d < 3.5:
					c = Color(1.0, 0.85, 0.05)
				elif d < 5.0:
					c = Color(0.7, 0.3, 0.0)
				img.set_pixel(x, y, c)
		_bolt_tex = ImageTexture.create_from_image(img)
	return _bolt_tex


## Estrella de cinco puntas (para los confusos), dibujada una vez y compartida.
static func _star() -> Texture2D:
	if _star_tex == null:
		var poly := PackedVector2Array()
		for i in 10:
			var a := -PI / 2 + PI * i / 5
			poly.append(Vector2(cos(a), sin(a)) * (1.0 if i % 2 == 0 else 0.45))
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		for y in 64:
			for x in 64:
				var hits := 0  # 2x2 muestras por píxel para suavizar el borde
				for sy in 2:
					for sx in 2:
						var p := (Vector2(x + 0.25 + 0.5 * sx, y + 0.25 + 0.5 * sy) - Vector2(32, 33)) / 30.0
						hits += int(Geometry2D.is_point_in_polygon(p, poly))
				img.set_pixel(x, y, Color(1, 1, 1, hits / 4.0))
		_star_tex = ImageTexture.create_from_image(img)
	return _star_tex


static func _solid(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.35
	return m


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


static func _flash(parent: Node3D, pos: Vector3, color: Color, energy := 4.0) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
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

class_name CameraRig
extends Node3D
## Cámara isométrica ortográfica: rotar (Q/E), zoom (rueda), desplazar (WASD/flechas
## o arrastrando con el botón central) y lanzar rayos para saber qué hay bajo el ratón.

const MIN_ZOOM := 5.0
const MAX_ZOOM := 30.0
const PAN_SPEED := 12.0
const START_YAW := 45.0
## Giro del sol con la vista inicial; al rotar el mapa el sol gira lo mismo (ver `_follow_sun`). Va 70° a
## la izquierda de la cámara: si estuviera detrás de ella, cada sombra quedaría tapada por su objeto.
const SUN_YAW := -25.0

var camera: Camera3D
var rotation_step := 90.0
var _yaw := START_YAW
var _dragging := false


func _init() -> void:
	var pitch := Node3D.new()
	pitch.rotation_degrees.x = -35.0
	add_child(pitch)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 12.0
	camera.position = Vector3(0, 0, 25)
	camera.far = 120.0
	pitch.add_child(camera)
	rotation_degrees.y = _yaw


## Centra la vista en `target`. `follow` (0-1) indica cuánto se acerca: con zoom lejano
## conviene moverse poco para no perder de vista el tablero.
func focus(target: Vector3, follow := -1.0) -> void:
	if follow < 0.0:
		follow = remap(clampf(camera.size, 6.0, 26.0), 6.0, 26.0, 1.0, 0.2)
	var tw := create_tween()
	tw.tween_property(self, "position", Vector3(target.x, 0.0, target.z) * follow, 0.4).set_trans(Tween.TRANS_SINE)


func rotate_view(dir: int) -> void:
	_yaw += dir * rotation_step
	var tw := create_tween()
	tw.set_speed_scale(1.0 / maxf(Engine.time_scale, 0.01))
	tw.tween_property(self, "rotation_degrees:y", _yaw, 0.3).set_trans(Tween.TRANS_SINE)


func zoom(delta: float) -> void:
	camera.size = clampf(camera.size + delta, MIN_ZOOM, MAX_ZOOM)


## Devuelve el resultado de intersect_ray bajo la posición de pantalla (o {}).
func pick(screen_pos: Vector2) -> Dictionary:
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 300.0
	return get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))


## Procesa rueda, botón central y Q/E. Devuelve true si consumió el evento.
func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				zoom(-0.8)
				return true
			MOUSE_BUTTON_WHEEL_DOWN:
				zoom(0.8)
				return true
			MOUSE_BUTTON_MIDDLE:
				_dragging = event.pressed
				return true
	elif event is InputEventMouseMotion and _dragging:
		var scale := camera.size / camera.get_viewport().get_visible_rect().size.y
		var right := global_transform.basis.x
		var fwd := Vector3(global_transform.basis.z.x, 0.0, global_transform.basis.z.z).normalized()
		position -= (right * event.relative.x + fwd * event.relative.y) * scale * 1.2
		return true
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Q:
				rotate_view(-1)
				return true
			KEY_E:
				rotate_view(1)
				return true
	return false


func _process(delta: float) -> void:
	_follow_sun()
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1
	if dir == Vector2.ZERO:
		return
	var right := global_transform.basis.x
	var fwd := Vector3(global_transform.basis.z.x, 0.0, global_transform.basis.z.z).normalized()
	# El desplazamiento manual no se frena con la velocidad de combate.
	var real_delta := delta / maxf(Engine.time_scale, 0.01)
	position += (right * dir.x + fwd * dir.y).normalized() * PAN_SPEED * real_delta * camera.size / 12.0


## El sol (de build_environment, hermano de la cámara) gira con la vista: al rotar el mapa la luz y las
## sombras caen siempre desde el mismo lado de la pantalla, también durante el giro.
func _follow_sun() -> void:
	var sun := get_parent().get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		sun.rotation_degrees.y = SUN_YAW + rotation_degrees.y - START_YAW


## Configura el entorno (cielo y luz) del bioma bajo `parent`.
static func build_environment(parent: Node, biome: Biome.Kind) -> void:
	var sky_info: Array = Biome.SKIES[biome]
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = sky_info[0]
	sky_mat.sky_horizon_color = sky_info[1]
	sky_mat.ground_horizon_color = sky_info[1].darkened(0.2)
	sky_mat.ground_bottom_color = sky_info[1].darkened(0.6)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	var cave := biome in [Biome.Kind.CAVE, Biome.Kind.UNDERWATER]
	# Al aire libre el sol directo es varias veces más fuerte que la luz del cielo: así la sombra se ve.
	env.ambient_light_energy = sky_info[3] * (1.0 if cave else 0.5)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# Luz realista: sombra de contacto en rincones y al pie de cada objeto (SSAO) y luz que rebota entre
	# superficies y tiñe lo de al lado (SSIL).
	env.ssao_enabled = true
	env.ssao_radius = 0.7
	env.ssao_intensity = 2.5 if cave else 1.6
	env.ssao_power = 1.8 if cave else 1.4
	env.ssil_enabled = true
	env.ssil_radius = 2.0
	env.ssil_intensity = 0.8
	if biome == Biome.Kind.UNDERWATER:
		env.fog_enabled = true  # agua azul que apaga lo lejano
		env.fog_light_color = Color(0.05, 0.2, 0.3)
		env.fog_density = 0.02
	elif cave:
		env.fog_enabled = true
		env.fog_light_color = Color(0.08, 0.07, 0.09)
		env.fog_density = 0.015
	elif biome == Biome.Kind.CEMETERY:
		env.fog_enabled = true  # neblina nocturna
		env.fog_light_color = Color(0.32, 0.32, 0.42)
		env.fog_density = 0.01
	elif biome == Biome.Kind.SWAMP:
		env.fog_enabled = true  # bruma verdosa del pantano
		env.fog_light_color = Color(0.5, 0.58, 0.48)
		env.fog_density = 0.007
	elif biome == Biome.Kind.VOLCANO:
		env.fog_enabled = true  # calima de humo y ceniza
		env.fog_light_color = Color(0.55, 0.32, 0.24)
		env.fog_density = 0.006
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	parent.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-48, SUN_YAW, 0)
	sun.shadow_enabled = true
	sun.light_energy = sky_info[2] if cave else minf(sky_info[2] * 1.4, 1.5)  # tope: la arena y la nieve no se queman
	# Sombras reales: el sol es un disco, no un punto, así que el borde de la sombra se difumina según la
	# distancia entre el objeto y el suelo (nítida al pie, suave lejos). Su largo y su forma salen de la
	# geometría de cada objeto: una piedra da una sombra corta y nítida; un árbol, una larga y difusa.
	# En la cueva la luz llega rebotada y el disco es más grande.
	sun.light_angular_distance = 1.5 if cave else 0.8
	sun.shadow_opacity = 1.0
	sun.directional_shadow_max_distance = 60.0  # solo el tablero: más resolución donde importa
	sun.directional_shadow_blend_splits = true
	sun.set_meta("angular", sun.light_angular_distance)
	parent.add_child(sun)
	apply_quality(parent)


## Ajusta el entorno y el sol de `parent` a la calidad gráfica (Game.graphics_quality). En Alta queda todo.
static func apply_quality(parent: Node) -> void:
	var q: int = Game.graphics_quality
	var world_env := parent.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env and world_env.environment:
		world_env.environment.ssil_enabled = q == Game.Quality.HIGH
		world_env.environment.ssao_enabled = q != Game.Quality.LOW
	var sun := parent.get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		var low := q == Game.Quality.LOW
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if low \
				else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		sun.light_angular_distance = 0.0 if low else sun.get_meta("angular", sun.light_angular_distance)

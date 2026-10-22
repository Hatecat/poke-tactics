class_name CameraRig
extends Node3D
## Cámara isométrica ortográfica: rotar (Q/E), zoom (rueda), desplazar (WASD/flechas
## o arrastrando con el botón central) y lanzar rayos para saber qué hay bajo el ratón.

const MIN_ZOOM := 5.0
const MAX_ZOOM := 30.0
const PAN_SPEED := 12.0

var camera: Camera3D
var rotation_step := 90.0
var _yaw := 45.0
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
	create_tween().tween_property(self, "rotation_degrees:y", _yaw, 0.3).set_trans(Tween.TRANS_SINE)


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
	position += (right * dir.x + fwd * dir.y).normalized() * PAN_SPEED * delta * camera.size / 12.0


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
	env.ambient_light_energy = sky_info[3]
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	if biome == Biome.Kind.CAVE:
		env.fog_enabled = true
		env.fog_light_color = Color(0.08, 0.07, 0.09)
		env.fog_density = 0.015
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	parent.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.shadow_enabled = true
	sun.light_energy = sky_info[2]
	parent.add_child(sun)

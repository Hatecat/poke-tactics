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
const PITCH := -35.0
## Pantalla completa: cuánto más lejos del encuadre justo del tablero deja alejarse la rueda.
const FIT_SLACK := 1.1
## Margen del encuadre justo, para que los nombres de los Pokémon de las esquinas no toquen el borde.
const FIT_MARGIN := 1.06

var camera: Camera3D
var rotation_step := 90.0
var _yaw := START_YAW
var _dragging := false
## Pantalla completa (`frame`): caja del tablero que se encuadra; tamaño vacío = cámara libre de siempre.
var _board := AABB()
## Alto de la vista con el tablero justo encuadrado (se recalcula al girar o cambiar el tamaño de la ventana).
var _fit_size := 0.0
## Pantalla completa: ancho (en píxeles de la vista) que tapa la interfaz a la izquierda. El tablero se
## encuadra en el resto, desplazando la imagen con `h_offset` (los rayos de `pick` lo tienen en cuenta).
var safe_left := 0.0
## Radio del campo de adorno alrededor del centro del tablero: la vista no se aleja tanto que lo rebase.
var _reach := 0.0

func _init() -> void:
	var pitch := Node3D.new()
	pitch.rotation_degrees.x = PITCH
	add_child(pitch)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 12.0
	camera.position = Vector3(0, 0, 25)
	camera.far = 120.0
	pitch.add_child(camera)
	rotation_degrees.y = _yaw


func _ready() -> void:
	get_viewport().size_changed.connect(_refit)


## Mapa a pantalla completa: la vista arranca con todo `board` encuadrado y no deja alejarse ni desplazarse
## tanto que se salga del campo que lo rodea (`reach`, BoardView.scenery_reach). Rueda, giro y
## desplazamiento siguen igual.
func frame(board: AABB, reach: float) -> void:
	_board = board
	_reach = reach
	_fit_size = _fitting_size()
	camera.size = minf(_fit_size, _max_zoom())
	position = Vector3(board.get_center().x, 0.0, board.get_center().z)


func _view_size() -> Vector2:
	return camera.get_viewport().get_visible_rect().size if camera.is_inside_tree() else Vector2(16, 9)


## Píxeles reservados a la izquierda: en una ventana estrecha, apartarse del panel encogería demasiado el
## tablero, así que se encuadra a lo ancho entero.
func _reserved() -> float:
	var view := _view_size()
	return safe_left if (view.x - safe_left) / maxf(view.y, 1.0) >= 1.2 else 0.0


## Alto de la vista ortográfica con el que cabe todo el tablero con el giro de destino: se proyectan las
## esquinas de su caja en el plano de la cámara y manda el lado (ancho o alto) que antes llena la pantalla.
func _fitting_size() -> float:
	var basis := Basis(Vector3.UP, deg_to_rad(_yaw)) * Basis(Vector3.RIGHT, deg_to_rad(PITCH))
	var inv := basis.inverse()
	var lo := Vector2(INF, INF)
	var hi := -lo
	for i in 8:
		var v := inv * (_board.get_endpoint(i) - _board.get_center())
		lo = lo.min(Vector2(v.x, v.y))
		hi = hi.max(Vector2(v.x, v.y))
	var view := _view_size()
	var aspect := (view.x - _reserved()) / maxf(view.y, 1.0)
	return maxf(hi.y - lo.y, (hi.x - lo.x) / aspect) * FIT_MARGIN


## Al cambiar el tamaño de la ventana o girar, el encuadre se recalcula y el zoom guarda su proporción.
func _refit() -> void:
	if _fit_size <= 0.0:
		return
	var fit := _fitting_size()
	var ratio := camera.size / _fit_size
	_fit_size = fit
	camera.size = clampf(fit * ratio, MIN_ZOOM, _max_zoom())


## Pantalla completa: el encuadre justo y un poco más, sin que las esquinas de la vista (con el centro en el
## del tablero) pasen del campo de alrededor. Cada esquina se aleja del centro, en el suelo, en proporción al
## alto de la vista: medio ancho (más el desplazamiento de `h_offset`) y medio alto entre el seno de la
## inclinación.
func _max_zoom() -> float:
	if _fit_size <= 0.0:
		return MAX_ZOOM
	var view := _view_size()
	var half_w := view.x / maxf(view.y, 1.0) * 0.5 + _reserved() * 0.5 / maxf(view.y, 1.0)
	var half_d := 0.5 / sin(deg_to_rad(-PITCH))
	return minf(_fit_size * FIT_SLACK, _reach / Vector2(half_w, half_d).length())


## Pantalla completa: con todo el tablero a la vista el centro queda quieto; al acercarse puede ir hasta
## los bordes, sin asomar más allá del campo de alrededor.
func _clamped(p: Vector3) -> Vector3:
	if _fit_size <= 0.0:
		return p
	var room := clampf(1.0 - camera.size / _fit_size, 0.0, 1.0)
	var c := _board.get_center()
	var half := _board.size * 0.5 * room
	return Vector3(clampf(p.x, c.x - half.x, c.x + half.x), p.y, clampf(p.z, c.z - half.z, c.z + half.z))


## Centra la vista en `target`. `follow` (0-1) indica cuánto se acerca: con zoom lejano
## conviene moverse poco para no perder de vista el tablero.
func focus(target: Vector3, follow := -1.0) -> void:
	if follow < 0.0:
		follow = remap(clampf(camera.size, 6.0, 26.0), 6.0, 26.0, 1.0, 0.2)
	var tw := create_tween()
	tw.tween_property(self, "position", _clamped(Vector3(target.x, 0.0, target.z) * follow), 0.4).set_trans(Tween.TRANS_SINE)


func rotate_view(dir: int) -> void:
	_yaw += dir * rotation_step
	_refit()
	var tw := create_tween()
	tw.set_speed_scale(1.0 / maxf(Engine.time_scale, 0.01))
	tw.tween_property(self, "rotation_degrees:y", _yaw, 0.3).set_trans(Tween.TRANS_SINE)


func zoom(delta: float) -> void:
	camera.size = clampf(camera.size + delta, MIN_ZOOM, _max_zoom())


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
	position = _clamped(position)
	if _fit_size > 0.0:
		camera.h_offset = -_reserved() * 0.5 * camera.size / maxf(_view_size().y, 1.0)
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
	biome = Biome.look(biome)
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
	elif biome == Biome.Kind.LIBRARY:
		env.fog_enabled = true  # aire con polvo, cálido, que apaga las salas del fondo
		env.fog_light_color = Color(0.32, 0.22, 0.13)
		env.fog_density = 0.012
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	parent.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-48, SUN_YAW, 0)
	sun.shadow_enabled = true
	sun.light_energy = sky_info[2] if cave else minf(sky_info[2] * 1.4, 1.5)  # tope: la arena y la nieve no se queman
	if biome == Biome.Kind.LIBRARY:
		sun.light_color = Color(1.0, 0.84, 0.62)  # luz de tarde que entra por los ventanales
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

class_name PokemonPreview
extends SubViewportContainer
## Vista 3D giratoria de un Pokémon, con su propio mundo (no interfiere con la batalla).

## Gira solo; al arrastrar con el ratón (si `interactive`) deja de hacerlo.
var spin := true
## Permite girar el modelo arrastrando.
var interactive := false:
	set(v):
		interactive = v
		mouse_filter = Control.MOUSE_FILTER_STOP if v else Control.MOUSE_FILTER_IGNORE

## Animaciones con Poké Ball: de dónde llega la bola (arriba a la derecha, fuera de cuadro) y dónde cae al
## capturar (delante del Pokémon, algo a la derecha). Posiciones del mundo de la vista previa.
const BALL_FROM := Vector3(1.1, 1.5, 1.5)
const BALL_GROUND := Vector3(0.35, 0.0, 0.55)

var _viewport: SubViewport
var _pivot: Node3D
var _camera: Camera3D
var _unit: Unit
## Cada acción reproducida invalida la vuelta a idle de la anterior.
var _action_serial := 0
## Hay una animación con Poké Ball en curso (los botones no la repiten encima).
var _ball_busy := false


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
	mat.albedo_color = Color(0.14, 0.19, 0.32)
	mat.metallic = 0.3
	mat.roughness = 0.45
	pedestal.material_override = mat
	_pivot.add_child(pedestal)
	# Aro de neón que brilla en el borde del pedestal (el NEON de la interfaz).
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.0
	torus.outer_radius = 1.025
	torus.rings = 48
	ring.mesh = torus
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = UiKit.NEON
	ring.material_override = ring_mat
	ring.scale.y = 0.3
	_pivot.add_child(ring)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.rotation_degrees.x = -12.0
	_viewport.add_child(_camera)


func show_pokemon(data: PokemonData) -> void:
	# Si el panel aún no está en pantalla, se carga en cuanto entre.
	if not is_inside_tree():
		ready.connect(show_pokemon.bind(data), CONNECT_ONE_SHOT)
		return
	_action_serial += 1
	if _unit:
		_unit.queue_free()
		_unit = null
	# Si había una animación con Poké Ball a medias, la bola se va con el Pokémon anterior.
	for ball in _pivot.get_children():
		if ball.has_meta("lid"):
			ball.queue_free()
	_ball_busy = false
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
	_fit_width.call_deferred(_action_serial)


## Los anchos y largos (los brazos de Geodude, la cola de Arbok, Grimer al derretirse) se salían por los lados:
## con la pose del idle ya puesta, se aleja hasta que quepa el círculo que barre al girar (y algo más, para el
## debilitado).
func _fit_width(serial: int) -> void:
	await get_tree().process_frame
	if serial != _action_serial or _unit == null or _unit._model == null:
		return
	var radius := 0.0
	for m: MeshInstance3D in _unit._model.find_children("*", "MeshInstance3D", true, false):
		var a := Unit._skinned_aabb(_unit, m)
		for x in [a.position.x, a.end.x]:
			for z in [a.position.z, a.end.z]:
				radius = maxf(radius, Vector2(x, z).length())
	var aspect := size.x / maxf(size.y, 1.0)
	var room := _camera.size * aspect * 0.5 * 0.92  # medio ancho de la vista, con margen
	if radius * _pivot.scale.x > room:
		_pivot.scale = Vector3.ONE * (room / radius)


## Reproduce una acción (idle, walk, fight_b, hit, ko...) y, si no es un bucle, vuelve a idle al
## terminar. Devuelve el clip usado ("" = animación procedural).
func play_action(key: String, variant := "", move_id := "") -> String:
	if _unit == null:
		return ""
	_action_serial += 1
	var serial := _action_serial
	var clip := _unit.clip_for(key, variant, move_id)
	var duration := _unit.play(key, variant, move_id)
	if key not in Unit.LOOPING_ANIMS and is_inside_tree():
		get_tree().create_timer(duration + 0.6).timeout.connect(func() -> void:
			if serial == _action_serial and is_instance_valid(_unit):
				_unit.play("idle"))
	return clip


## Captura como en los juegos: la Poké Ball llega en arco, el Pokémon entra en ella, la bola cae, se sacude tres
## veces y hace clic. Luego vuelve a salir para seguir viéndolo.
func play_capture() -> void:
	if _unit == null or _ball_busy:
		return
	_ball_busy = true
	var u := _unit
	var was_spinning := spin
	spin = false
	_action_serial += 1
	u.play("idle")
	var ball := BallFx.new_ball(_pivot, Color(0.85, 0.12, 0.12), _ball_size())
	await BallFx.throw_arc(_pivot, ball, BALL_FROM, BallFx.top(u), 0.5, 0.5)
	if is_instance_valid(u):
		await BallFx.absorb(_pivot, ball, u, BALL_GROUND)
	for i in 3:
		if not is_instance_valid(u):
			break
		await get_tree().create_timer(0.25).timeout
		await BallFx.wobble(ball, i, 0.7)
	if is_instance_valid(u):
		await BallFx.caught(_pivot, ball)
		await get_tree().create_timer(0.9).timeout
	if is_instance_valid(u):
		await BallFx.escape(_pivot, ball, u, Color.WHITE)
	else:
		ball.queue_free()
	spin = was_spinning
	_ball_busy = false


## Salida como al empezar el combate: la Poké Ball llega en arco, se abre en el aire y el Pokémon sale de ella.
func play_send_out() -> void:
	if _unit == null or _ball_busy:
		return
	_ball_busy = true
	var was_spinning := spin
	spin = false
	_action_serial += 1
	_unit.play("idle")
	await BallFx.send_out(_pivot, _unit, Color(0.85, 0.12, 0.12), BALL_FROM, _ball_size())
	spin = was_spinning
	_ball_busy = false


## Escala de la bola dentro de `_pivot` (que encoge o agranda al Pokémon): siempre del mismo tamaño en pantalla.
func _ball_size() -> float:
	return 0.7 / _pivot.scale.x


func unit() -> Unit:
	return _unit


## Deja de girar y muestra el modelo con ese ángulo (0 = de frente).
func turn_to(degrees: float) -> void:
	spin = false
	_pivot.rotation.y = deg_to_rad(degrees)


## Nombres de los clips que trae el modelo (vacío si solo usa animación procedural).
func clips() -> PackedStringArray:
	if _unit == null:
		return PackedStringArray()
	var players := _unit.find_children("*", "AnimationPlayer", true, false)
	return (players[0] as AnimationPlayer).get_animation_list() if not players.is_empty() else PackedStringArray()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		spin = false
		_pivot.rotation.y += event.relative.x * 0.01


func _process(delta: float) -> void:
	if spin:
		_pivot.rotation.y += delta * 0.6

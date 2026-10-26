class_name BallFx
extends RefCounted
## Animaciones con Poké Ball, como en los juegos: sacar a un Pokémon de su bola (al empezar el combate) y
## capturarlo (la bola se abre, el Pokémon entra como energía roja, cae, se sacude y hace clic o se escapa).
## Lo usan el combate y la vista previa del editor de equipos. `parent` es donde se crea la bola (el tablero o
## el mundo de la vista previa); las distancias se miden en tamaños de bola (_k), así que sirven a cualquier escala.


## La bola de `from` a `to` en arco de altura `arc`, girando hacia delante.
static func throw_arc(parent: Node3D, ball: Node3D, from: Vector3, to: Vector3, arc: float, time: float) -> void:
	await throw_path(parent, ball, [from, to], arc, time)


## La bola por los puntos de `points` (en línea, como un ataque) con un arco de altura `arc` por encima.
static func throw_path(parent: Node3D, ball: Node3D, points: Array[Vector3], arc: float, time: float) -> void:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i].distance_to(points[i - 1])
	ball.global_position = points[0]
	var tw := parent.create_tween()
	tw.tween_method(func(t: float) -> void:
		if not is_instance_valid(ball):
			return
		ball.global_position = _along(points, total * t) + Vector3.UP * arc * 4.0 * t * (1.0 - t)
		ball.rotation.x = t * TAU * 1.5, 0.0, 1.0, time)
	await tw.finished
	if is_instance_valid(ball):
		ball.rotation.x = 0.0


## Saca a `u` de su Poké Ball: la bola llega en arco desde `from`, se abre en el aire con un destello y el
## Pokémon se materializa desde ella; luego la bola se cierra y desaparece.
static func send_out(parent: Node3D, u: Unit, color: Color, from: Vector3, size := 1.0) -> void:
	u.visible = false
	var label := u.show_label(false)  # la bola se abre donde van sus letras: vuelven al terminar
	var ball := new_ball(parent, color, size)
	var k := _k(ball)
	var open_at := above(u, k)
	await throw_arc(parent, ball, from, open_at, 0.9 * k, 0.55)
	if not is_instance_valid(u):
		ball.queue_free()
		return
	_face_camera(ball)
	Fx.ball_open(ball, true)
	Fx.flash(parent, ball.global_position, Color(1, 1, 1), 3.0)
	Fx.burst(parent, ball.global_position, "steel", 0.5 * k)
	_audio().sfx("launch_special", -8.0, 1.3)
	await u.materialize(ball.global_position, 0.45)
	if is_instance_valid(u):
		u.show_label(label)
		_audio().cry(u.data, 1.0, -8.0)
	var tw := ball.create_tween()
	tw.tween_interval(0.1)
	tw.tween_callback(func() -> void: Fx.ball_open(ball, false))
	tw.tween_property(ball, "scale", Vector3.ONE * 0.01, 0.25).set_delay(0.15)
	tw.tween_callback(ball.queue_free)


## Captura, primera parte: la bola (que acaba de llegar a `u`) rebota hacia arriba, se abre, el Pokémon entra
## como energía roja, se cierra y cae al suelo (`ground`, posición global) dando botes.
static func absorb(parent: Node3D, ball: Node3D, u: Unit, ground: Vector3) -> void:
	var k := _k(ball)
	var hover := above(u, k)
	hide_label(u)
	var up := parent.create_tween()
	up.tween_property(ball, "global_position", hover, 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	await up.finished
	_face_camera(ball)
	await Fx.ball_open(ball, true).finished
	Fx.flash(parent, ball.global_position, Color(1.0, 0.4, 0.4), 2.0)
	_audio().sfx("launch_beam", -10.0, 1.4)
	await u.dematerialize(ball.global_position, 0.4)
	await Fx.ball_open(ball, false, 0.1).finished
	await parent.get_tree().create_timer(0.15, false).timeout
	# Cae y bota dos veces, cada vez menos.
	var rest := ground + Vector3.UP * 0.17 * k
	var fall := parent.create_tween()
	fall.tween_property(ball, "global_position", rest, 0.3).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	for h: float in [0.25, 0.1]:
		fall.tween_callback(func() -> void: _audio().sfx("hit_wood", -12.0, 1.6))
		fall.tween_property(ball, "global_position", rest + Vector3.UP * h * k, 0.14) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		fall.tween_property(ball, "global_position", rest, 0.14).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	await fall.finished
	_audio().sfx("hit_wood", -14.0, 1.8)


## Una sacudida de la bola en el suelo (la `i`-ésima), con el botón parpadeando en rojo. Dura `time`.
static func wobble(ball: Node3D, i: int, time: float) -> void:
	_audio().sfx("ui_hover", -2.0, 0.7)
	Fx.ball_button(ball, true)
	var side := 1.0 if i % 2 == 0 else -1.0
	var tw := ball.create_tween()
	tw.tween_property(ball, "rotation:z", 0.5 * side, time * 0.25).set_trans(Tween.TRANS_SINE)
	tw.tween_property(ball, "rotation:z", -0.32 * side, time * 0.25).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void: Fx.ball_button(ball, false))
	tw.tween_property(ball, "rotation:z", 0.0, time * 0.2).set_trans(Tween.TRANS_SINE)
	await tw.finished


## Captura lograda: clic, el botón se ilumina un momento y saltan estrellitas; la bola se queda quieta.
static func caught(parent: Node3D, ball: Node3D) -> void:
	var k := _k(ball)
	_audio().sfx("ui_click", 0.0, 0.8)
	Fx.ball_button(ball, true, Color(1.0, 0.95, 0.6))
	Fx.stars(parent, ball.global_position + Vector3.UP * 0.1 * k, 0.14 * k)
	await parent.get_tree().create_timer(0.35, false).timeout
	if is_instance_valid(ball):
		Fx.ball_button(ball, false)


## Se escapa: la bola se abre de golpe con un destello, el Pokémon sale de ella y la bola desaparece.
static func escape(parent: Node3D, ball: Node3D, u: Unit, color := Color(1.0, 0.3, 0.32)) -> void:
	Fx.ball_open(ball, true, 0.08)
	Fx.flash(parent, ball.global_position, color.lightened(0.3), 3.0)
	Fx.burst(parent, ball.global_position, "steel", 0.5 * _k(ball))
	var tw := ball.create_tween()
	tw.tween_interval(0.15)
	tw.tween_property(ball, "scale", Vector3.ONE * 0.01, 0.2)
	tw.tween_callback(ball.queue_free)
	await u.materialize(ball.global_position, 0.35, color)
	if is_instance_valid(u):
		u.show_label(u.get_meta("ball_label", true))
		u.remove_meta("ball_label")


## Oculta las letras de encima de `u` mientras una bola va a por él, recordando si se veían (si se escapa,
## `escape` las devuelve). Si ya estaban ocultas por una bola, no hace nada.
static func hide_label(u: Unit) -> void:
	if not u.has_meta("ball_label"):
		u.set_meta("ball_label", u.show_label(false))


## Una Poké Ball nueva del color dado, a escala `size`.
static func new_ball(parent: Node3D, color: Color, size := 1.0) -> Node3D:
	var ball := Fx.pokeball(parent, color)
	ball.scale = Vector3.ONE * size
	return ball


## El autoload Audio, buscado al usarlo: esta clase puede cargarse antes que los autoloads (p. ej. desde un
## script de pruebas) y entonces el nombre global aún no existe.
static func _audio() -> Node:
	return Engine.get_main_loop().root.get_node("Audio")


## Tamaño de la bola en el mundo (1 = la del tablero): escala de las distancias de cada animación.
static func _k(ball: Node3D) -> float:
	return ball.global_basis.get_scale().x


## Lo alto del Pokémon (posición global), contando la escala de lo que lo contiene (la vista previa).
static func top(u: Unit) -> Vector3:
	return u.global_transform * (Vector3.UP * u.data.model_height)


## Donde la bola se queda en el aire para abrirse: por encima de la cabeza, sin tocar el modelo (la bola de
## tamaño `k` queda entera por encima, con un margen).
static func above(u: Unit, k: float) -> Vector3:
	return top(u) + Vector3.UP * 0.4 * k


## Gira la bola para que su botón mire a la cámara (la tapa se abre hacia atrás).
static func _face_camera(ball: Node3D) -> void:
	var cam := ball.get_viewport().get_camera_3d()
	if cam == null:
		return
	var d := cam.global_position - ball.global_position
	ball.global_rotation = Vector3(0, atan2(d.x, d.z), 0)


## Punto a distancia `dist` a lo largo de la línea quebrada `points`.
static func _along(points: Array[Vector3], dist: float) -> Vector3:
	for i in range(1, points.size()):
		var seg := points[i].distance_to(points[i - 1])
		if dist <= seg or i == points.size() - 1:
			return points[i - 1].lerp(points[i], clampf(dist / maxf(seg, 0.001), 0.0, 1.0))
		dist -= seg
	return points[-1]

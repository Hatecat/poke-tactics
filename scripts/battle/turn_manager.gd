class_name TurnManager
extends RefCounted
## Turnos estilo FFT: cada unidad acumula CT según su velocidad y actúa al llegar a 100.
##
## Para que la velocidad no rompa el juego, la tasa de carga usa la velocidad
## elevada a SPEED_EXPONENT (< 1). Con 0.4, a nivel 50:
##   Shuckle (stat ~25) -> 36     Bulbasaur (65)  -> 53
##   Scizor  (85)       -> 59     Ninjask  (~180) -> 80
## El Pokémon más rápido del juego actúa ~2.2 veces por cada turno del más lento,
## en lugar de las ~8 veces que daría una relación lineal.

const CT_MAX := 100.0
const SPEED_EXPONENT := 0.4
const SPEED_SCALE := 10.0
## CT que cuesta terminar el turno según lo que se hizo (como en FFT).
const COST_FULL := 100.0
const COST_PARTIAL := 90.0
const COST_WAIT := 80.0


static func charge_rate(speed: float) -> float:
	return SPEED_SCALE * pow(maxf(speed, 1.0), SPEED_EXPONENT)


## Avanza el reloj hasta que alguna unidad llegue a CT_MAX y la devuelve.
func advance(units: Array[Unit]) -> Unit:
	var alive := units.filter(func(u: Unit) -> bool: return u.is_alive())
	if alive.is_empty():
		return null
	var ready := _first_ready(alive)
	if ready:
		return ready
	var dt := INF
	for u: Unit in alive:
		dt = minf(dt, (CT_MAX - u.ct) / charge_rate(u.effective_speed()))
	for u: Unit in alive:
		u.ct += charge_rate(u.effective_speed()) * dt
	return _first_ready(alive)


static func cost(moved: bool, acted: bool) -> float:
	if moved and acted:
		return COST_FULL
	if moved or acted:
		return COST_PARTIAL
	return COST_WAIT


## `extra` es el CT adicional de ataques que recargan o cargan (Hiperrayo, Rayo Solar...).
func end_turn(unit: Unit, moved: bool, acted: bool, extra := 0.0) -> void:
	unit.ct = minf(unit.ct - cost(moved, acted) - extra, CT_MAX - 1.0)


## Simula los próximos `count` turnos asumiendo que todos gastan un turno completo.
func predict(units: Array[Unit], count: int) -> Array[Unit]:
	var sim := {}
	for u in units:
		if u.is_alive():
			sim[u] = u.ct
	var order: Array[Unit] = []
	if sim.is_empty():
		return order
	while order.size() < count:
		var best: Unit = null
		var best_t := INF
		for u: Unit in sim:
			var t := maxf(CT_MAX - sim[u], 0.0) / charge_rate(u.effective_speed())
			if t < best_t or (is_equal_approx(t, best_t) and u.effective_speed() > best.effective_speed()):
				best_t = t
				best = u
		for u: Unit in sim:
			sim[u] += charge_rate(u.effective_speed()) * best_t
		sim[best] -= COST_FULL
		order.append(best)
	return order


func _first_ready(alive: Array) -> Unit:
	var best: Unit = null
	for u: Unit in alive:
		if u.ct >= CT_MAX - 0.001:
			if best == null or u.ct > best.ct or (is_equal_approx(u.ct, best.ct) and u.effective_speed() > best.effective_speed()):
				best = u
	return best

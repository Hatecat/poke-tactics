class_name BoardGrid
extends RefCounted
## Lógica pura de la rejilla: vecinos, distancias, líneas y posición en el mundo.
## Soporta rejilla cuadrada y hexagonal ("pointy-top", filas impares desplazadas).
## Las celdas siempre se guardan como Vector2i(columna, fila) para que el resto
## del juego no tenga que saber qué topología está usando.

enum Topology { SQUARE, HEX }

const HEIGHT_STEP := 0.35
const SQUARE_DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
# Direcciones en coordenadas axiales (q, r).
const HEX_DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1),
]
const HEX_ROW_SPACING := 0.8660254 # sqrt(3) / 2

var topology: Topology
var width: int
var height: int
var heights: Dictionary = {} # Vector2i -> int
var tiles: Dictionary = {} # Vector2i -> Biome.Tile
var props: Dictionary = {} # Vector2i -> Biome.Prop (obstáculos)
var biome := Biome.Kind.MEADOW


func _init(p_topology: Topology, p_width: int, p_height: int) -> void:
	topology = p_topology
	width = p_width
	height = p_height
	for c in all_cells():
		heights[c] = 0
		tiles[c] = Biome.Tile.GRASS
		props[c] = Biome.Prop.NONE


func all_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in height:
		for x in width:
			cells.append(Vector2i(x, y))
	return cells


func is_inside(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height


func get_height(c: Vector2i) -> int:
	return heights.get(c, 0)


## Hay un obstáculo: no se puede atravesar ni estar encima.
func is_blocked(c: Vector2i) -> bool:
	return props.get(c, Biome.Prop.NONE) != Biome.Prop.NONE


func direction_count() -> int:
	return 4 if topology == Topology.SQUARE else 6


## Celda vecina en la dirección indicada (puede quedar fuera del tablero).
func step(c: Vector2i, dir: int) -> Vector2i:
	if topology == Topology.SQUARE:
		return c + SQUARE_DIRS[dir]
	return _axial_to_offset(_offset_to_axial(c) + HEX_DIRS[dir])


func neighbors(c: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for d in direction_count():
		var n := step(c, d)
		if is_inside(n):
			result.append(n)
	return result


func distance(a: Vector2i, b: Vector2i) -> int:
	if topology == Topology.SQUARE:
		return absi(a.x - b.x) + absi(a.y - b.y)
	var d := _offset_to_axial(a) - _offset_to_axial(b)
	return (absi(d.x) + absi(d.y) + absi(d.x + d.y)) / 2


func cells_in_range(origin: Vector2i, range_min: int, range_max: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in range(maxi(origin.y - range_max, 0), mini(origin.y + range_max + 1, height)):
		for x in range(maxi(origin.x - range_max - 1, 0), mini(origin.x + range_max + 2, width)):
			var c := Vector2i(x, y)
			var d := distance(origin, c)
			if d >= range_min and d <= range_max:
				result.append(c)
	return result


## Celdas en línea recta desde `origin` (sin incluirla).
func line(origin: Vector2i, dir: int, length: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var c := origin
	for i in length:
		c = step(c, dir)
		if not is_inside(c):
			break
		result.append(c)
	return result


## Celdas que ocupa un Pokémon de tamaño `size` anclado en `anchor` (pueden quedar fuera).
## Cuadrada: bloque size×size. Hex: 1 = una celda, 2 = triángulo de 3, 3 = flor de 7.
func footprint(anchor: Vector2i, size: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [anchor]
	if size <= 1:
		return cells
	if topology == Topology.SQUARE:
		cells.clear()
		for y in size:
			for x in size:
				cells.append(anchor + Vector2i(x, y))
		return cells
	if size == 2:
		cells.append(step(anchor, 0))
		cells.append(step(anchor, 1))
		return cells
	for d in 6:
		cells.append(step(anchor, d))
	return cells


## Punto del mundo donde se coloca un Pokémon que ocupa `cells`: centro en planta,
## a la altura de la celda más alta.
func footprint_center(cells: Array[Vector2i]) -> Vector3:
	var sum := Vector3.ZERO
	var top := 0.0
	for c in cells:
		var w := to_world(c)
		sum += w
		top = maxf(top, w.y)
	sum /= cells.size()
	return Vector3(sum.x, top, sum.z)


func footprint_height(cells: Array[Vector2i]) -> int:
	var h := 0
	for c in cells:
		h = maxi(h, get_height(c))
	return h


## Distancia mínima entre una celda y cualquiera de un conjunto.
func distance_to_set(cells: Array[Vector2i], c: Vector2i) -> int:
	var best := 1 << 30
	for o in cells:
		best = mini(best, distance(o, c))
	return best


## Dirección cuyo ángulo en el mundo se parece más al vector from -> to.
func direction_towards(from: Vector2i, to: Vector2i) -> int:
	var target := to_world(to) - to_world(from)
	var best := 0
	var best_dot := -INF
	for d in direction_count():
		var v := to_world(step(from, d)) - to_world(from)
		var dot := Vector2(v.x, v.z).normalized().dot(Vector2(target.x, target.z).normalized())
		if dot > best_dot:
			best_dot = dot
			best = d
	return best


## Centro de la cara superior de la celda, con el tablero centrado en el origen.
func to_world(c: Vector2i) -> Vector3:
	var y := get_height(c) * HEIGHT_STEP
	if topology == Topology.SQUARE:
		return Vector3(c.x - (width - 1) * 0.5, y, c.y - (height - 1) * 0.5)
	var x := c.x + (0.5 if c.y & 1 else 0.0)
	return Vector3(x - width * 0.5 + 0.25, y, (c.y - (height - 1) * 0.5) * HEX_ROW_SPACING)


## Casilla que contiene el punto del mundo `p` (ignora la altura).
func world_to_cell(p: Vector3) -> Vector2i:
	var origin := to_world(Vector2i.ZERO)
	var x := p.x - origin.x
	var z := p.z - origin.z
	if topology == Topology.SQUARE:
		return Vector2i(roundi(x), roundi(z))
	# Axial fraccionario (hexágono "pointy-top" de 1 de ancho) y redondeo cúbico.
	var r := z / HEX_ROW_SPACING
	var q := x - r * 0.5
	var s := -q - r
	var rq := roundf(q)
	var rr := roundf(r)
	var rs := roundf(s)
	var dq := absf(rq - q)
	var dr := absf(rr - r)
	var ds := absf(rs - s)
	if dq > dr and dq > ds:
		rq = -rr - rs
	elif dr > ds:
		rr = -rq - rs
	return _axial_to_offset(Vector2i(int(rq), int(rr)))


## Celdas que atraviesa el segmento entre los centros de `a` y `b`, en orden y sin `a`.
func ray(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var from := to_world(a)
	var to := to_world(b)
	var steps := maxi(1, ceili(Vector2(to.x - from.x, to.z - from.z).length() / 0.2))
	for i in range(1, steps + 1):
		var c := world_to_cell(from.lerp(to, float(i) / steps))
		if c != a and (cells.is_empty() or cells.back() != c) and is_inside(c):
			cells.append(c)
	if cells.is_empty() or cells.back() != b:
		cells.append(b)
	return cells


## Una casilla corta la línea de visión si tiene un obstáculo o es una pared de terreno
## (al menos 2 niveles más alta que los dos extremos).
func blocks_sight(c: Vector2i, from: Vector2i, to: Vector2i) -> bool:
	return is_blocked(c) or get_height(c) >= maxi(get_height(from), get_height(to)) + 2


func _offset_to_axial(c: Vector2i) -> Vector2i:
	return Vector2i(c.x - (c.y - (c.y & 1)) / 2, c.y)


func _axial_to_offset(a: Vector2i) -> Vector2i:
	return Vector2i(a.x + (a.y - (a.y & 1)) / 2, a.y)

class_name Biome
extends RefCounted
## Tipos de campo: aspecto (suelo, obstáculos, cielo) y generador procedural.
## Por ahora son solo visuales; los efectos (p. ej. potenciar Agua en el lago) vendrán después.

enum Kind { MEADOW, FOREST, MOUNTAIN, DESERT, LAKE, SNOW, CAVE, GYM }
enum Tile { GRASS, DIRT, SAND, ROCK, WATER, SNOW, ICE, FLOOR, FLOOR_LINE, CAVE }
## Obstáculos: bloquean el paso y no se puede estar encima.
enum Prop { NONE, TREE, PINE, BOULDER, CACTUS, PILLAR, CRYSTAL, STALAGMITE, PALM }

const NAMES := {
	Kind.MEADOW: "Pradera", Kind.FOREST: "Bosque", Kind.MOUNTAIN: "Montaña", Kind.DESERT: "Desierto",
	Kind.LAKE: "Lago", Kind.SNOW: "Nieve", Kind.CAVE: "Cueva", Kind.GYM: "Gimnasio",
}
const ICONS := {
	Kind.MEADOW: "🌼", Kind.FOREST: "🌲", Kind.MOUNTAIN: "⛰", Kind.DESERT: "🌵",
	Kind.LAKE: "🌊", Kind.SNOW: "❄", Kind.CAVE: "🪨", Kind.GYM: "★",
}
const TILE_NAMES := {
	Tile.GRASS: "Hierba", Tile.DIRT: "Tierra", Tile.SAND: "Arena", Tile.ROCK: "Roca", Tile.WATER: "Agua",
	Tile.SNOW: "Nieve", Tile.ICE: "Hielo", Tile.FLOOR: "Suelo", Tile.FLOOR_LINE: "Línea", Tile.CAVE: "Cueva",
}
const PROP_NAMES := {
	Prop.NONE: "Nada", Prop.TREE: "Árbol", Prop.PINE: "Pino", Prop.BOULDER: "Roca",
	Prop.CACTUS: "Cactus", Prop.PILLAR: "Columna", Prop.CRYSTAL: "Cristal",
	Prop.STALAGMITE: "Estalagmita", Prop.PALM: "Palmera",
}
const TILE_COLORS := {
	Tile.GRASS: Color(0.4, 0.66, 0.34), Tile.DIRT: Color(0.58, 0.45, 0.3), Tile.SAND: Color(0.88, 0.78, 0.52),
	Tile.ROCK: Color(0.56, 0.54, 0.5), Tile.WATER: Color(0.26, 0.52, 0.86), Tile.SNOW: Color(0.93, 0.95, 0.98),
	Tile.ICE: Color(0.68, 0.85, 0.95), Tile.FLOOR: Color(0.78, 0.75, 0.68), Tile.FLOOR_LINE: Color(0.85, 0.32, 0.26),
	Tile.CAVE: Color(0.36, 0.33, 0.31),
}
## Color de los laterales de las casillas.
const SIDE_COLORS := {
	Kind.MEADOW: Color(0.42, 0.32, 0.22), Kind.FOREST: Color(0.36, 0.27, 0.18), Kind.MOUNTAIN: Color(0.4, 0.38, 0.36),
	Kind.DESERT: Color(0.7, 0.58, 0.38), Kind.LAKE: Color(0.42, 0.34, 0.24), Kind.SNOW: Color(0.6, 0.64, 0.72),
	Kind.CAVE: Color(0.22, 0.2, 0.19), Kind.GYM: Color(0.45, 0.45, 0.5),
}
## Cielo (arriba, horizonte), energía del sol y luz ambiente.
const SKIES := {
	Kind.MEADOW: [Color(0.35, 0.55, 0.85), Color(0.75, 0.85, 0.95), 1.1, 0.8],
	Kind.FOREST: [Color(0.3, 0.5, 0.7), Color(0.6, 0.75, 0.7), 0.9, 0.7],
	Kind.MOUNTAIN: [Color(0.3, 0.45, 0.75), Color(0.8, 0.85, 0.9), 1.2, 0.8],
	Kind.DESERT: [Color(0.4, 0.6, 0.9), Color(0.95, 0.85, 0.65), 1.4, 0.9],
	Kind.LAKE: [Color(0.35, 0.6, 0.9), Color(0.75, 0.88, 0.98), 1.1, 0.85],
	Kind.SNOW: [Color(0.55, 0.65, 0.8), Color(0.88, 0.9, 0.95), 0.9, 1.0],
	Kind.CAVE: [Color(0.04, 0.04, 0.06), Color(0.12, 0.1, 0.1), 0.7, 0.3],
	Kind.GYM: [Color(0.25, 0.25, 0.32), Color(0.5, 0.48, 0.5), 1.0, 0.9],
}


static func default_tile(kind: Kind) -> Tile:
	match kind:
		Kind.DESERT: return Tile.SAND
		Kind.SNOW: return Tile.SNOW
		Kind.CAVE: return Tile.CAVE
		Kind.GYM: return Tile.FLOOR
		Kind.MOUNTAIN: return Tile.ROCK
	return Tile.GRASS


## Rellena alturas, suelos y obstáculos de `grid` según el bioma. `keep_clear` son
## celdas que deben quedar libres (zonas de despliegue). Garantiza que se pueda
## llegar de `from_cells` a `to_cells` con salto 1.
## Primero la geografía (relieve con ruido fractal suavizado, ríos, lagos, dunas...),
## luego el suelo según altura y pendiente, y por último los obstáculos donde tendrían sentido.
static func generate(grid: BoardGrid, kind: Kind, rng: RandomNumberGenerator,
		keep_clear: Array[Vector2i], from_cells: Array[Vector2i], to_cells: Array[Vector2i]) -> void:
	grid.biome = kind
	for c in grid.all_cells():
		grid.heights[c] = 0
		grid.tiles[c] = default_tile(kind)
		grid.props[c] = Prop.NONE
	var clear := {}
	for c in keep_clear:
		clear[c] = true
	match kind:
		Kind.MEADOW: _meadow(grid, rng, clear)
		Kind.FOREST: _forest(grid, rng, clear)
		Kind.MOUNTAIN: _mountain(grid, rng, clear)
		Kind.DESERT: _desert(grid, rng, clear)
		Kind.LAKE: _lake(grid, rng, clear)
		Kind.SNOW: _snow(grid, rng, clear)
		Kind.CAVE: _cave(grid, rng, clear)
		Kind.GYM: _gym_layout(grid, keep_clear)
	for c in keep_clear:
		grid.props[c] = Prop.NONE
	_ensure_path(grid, from_cells, to_cells, rng)


## Pradera: lomas suaves, un sendero de tierra entre los dos bandos, una charca en la hondonada
## y árboles en bosquecillos.
static func _meadow(grid: BoardGrid, rng: RandomNumberGenerator, clear: Dictionary) -> void:
	var hf := _field(grid, rng, 0.06, 3, 18.0)
	var grove := _field(grid, rng, 0.16, 2)
	for c in grid.all_cells():
		grid.heights[c] = _levels(pow(hf[c], 1.3), 3.0, 2)
	_smooth(grid, 2)
	_lowest_pond(grid, hf, 0.07, clear, Tile.WATER)
	for c in _trail(grid, rng):
		if grid.tiles[c] == Tile.GRASS:
			grid.tiles[c] = Tile.DIRT
	for c in grid.all_cells():
		if clear.has(c) or grid.tiles[c] != Tile.GRASS:
			continue
		var r := rng.randf()
		if grove[c] > 0.72 and r < 0.45 or r < 0.01:
			grid.props[c] = Prop.TREE
		elif _slope(grid, c) > 0 and r < 0.04:
			grid.props[c] = Prop.BOULDER


## Bosque: arboleda densa con claros, un arroyo que lo cruza y un sendero. Pinos en lo alto,
## frondosos en lo bajo; bajo la espesura el suelo es tierra (hojarasca).
static func _forest(grid: BoardGrid, rng: RandomNumberGenerator, clear: Dictionary) -> void:
	var hf := _field(grid, rng, 0.07, 3, 14.0)
	var dense := _field(grid, rng, 0.11, 3)
	for c in grid.all_cells():
		grid.heights[c] = _levels(hf[c], 2.6, 2)
	_smooth(grid, 2)
	var stream := _river(grid, rng, true)
	for c in stream:
		grid.tiles[c] = Tile.WATER
		grid.heights[c] = 0
	_bank(grid, stream)
	var trail := _trail(grid, rng)
	for c in trail:
		if grid.tiles[c] != Tile.WATER:
			grid.tiles[c] = Tile.DIRT
	for c in grid.all_cells():
		if grid.tiles[c] == Tile.WATER or trail.has(c):
			continue
		if dense[c] > 0.62 and rng.randf() < 0.6:
			grid.tiles[c] = Tile.DIRT
		if clear.has(c):
			continue
		var r := rng.randf()
		if dense[c] > 0.42 and r < remap(dense[c], 0.42, 1.0, 0.3, 0.75):
			grid.props[c] = Prop.PINE if grid.heights[c] >= 2 or r < 0.12 else Prop.TREE
		elif r < 0.015:
			grid.props[c] = Prop.BOULDER


## Montaña: un macizo de crestas entre los dos bandos con valles verdes a sus pies. Suelo según altura
## y pendiente (hierba, tierra, roca y cumbres nevadas); pedregal al pie de los cortados y pinos en los valles.
static func _mountain(grid: BoardGrid, rng: RandomNumberGenerator, clear: Dictionary) -> void:
	var ridge := _field(grid, rng, 0.055, 4, 10.0, true)
	var base := _field(grid, rng, 0.035, 2)
	var mix := _field(grid, rng, 0.2, 2)
	var pines := _field(grid, rng, 0.14, 2)
	for c in grid.all_cells():
		# Más alto hacia el centro del tablero (el paso entre los dos bandos).
		var mid := 1.0 - absf(float(c.y) / maxf(grid.height - 1, 1) - 0.5) * 2.0
		var v: float = (0.6 * ridge[c] + 0.4 * base[c]) * lerpf(0.45, 1.1, mid)
		grid.heights[c] = _levels(pow(v, 1.15), 6.0, 5)
	_smooth(grid, 2)
	for c in grid.all_cells():
		var h: int = grid.heights[c]
		var steep := _slope(grid, c) >= 2
		if h >= 4:
			grid.tiles[c] = Tile.ROCK if steep and mix[c] > 0.5 else Tile.SNOW
		elif h == 3 or steep:
			grid.tiles[c] = Tile.ROCK
		elif h == 2:
			grid.tiles[c] = Tile.DIRT if mix[c] > 0.55 else (Tile.ROCK if mix[c] < 0.3 else Tile.GRASS)
		else:
			grid.tiles[c] = Tile.DIRT if mix[c] > 0.75 else Tile.GRASS
	for c in grid.all_cells():
		if clear.has(c):
			continue
		var r := rng.randf()
		if _rise(grid, c) >= 2 and r < 0.2:
			grid.props[c] = Prop.BOULDER
		elif grid.heights[c] <= 1 and pines[c] > 0.62 and r < 0.4:
			grid.props[c] = Prop.PINE
		elif grid.tiles[c] == Tile.ROCK and r < 0.03:
			grid.props[c] = Prop.BOULDER


## Desierto: campos de dunas alineadas por el viento, mesetas de roca con su ladera de derrubios y un
## oasis con agua y palmeras. Cactus en la arena llana.
static func _desert(grid: BoardGrid, rng: RandomNumberGenerator, clear: Dictionary) -> void:
	var warp := _field(grid, rng, 0.05, 2)
	var amp := _field(grid, rng, 0.04, 2)
	var mesa := _field(grid, rng, 0.08, 3, 8.0)
	var thicket := _field(grid, rng, 0.14, 2)  # zonas donde los cactus crecen juntos
	var angle := rng.randf() * TAU
	var dir := Vector2(cos(angle), sin(angle))
	for c in grid.all_cells():
		var w := grid.to_world(c)
		var s := sin(Vector2(w.x, w.z).dot(dir) * 0.75 + warp[c] * 6.0) * 0.5 + 0.5
		grid.heights[c] = _levels(pow(s, 1.6) * lerpf(0.4, 1.0, amp[c]), 2.6, 2)
		if mesa[c] > 0.8:
			grid.heights[c] = 3
			grid.tiles[c] = Tile.ROCK
		elif mesa[c] > 0.7:
			grid.heights[c] = maxi(grid.heights[c], 2)
			grid.tiles[c] = Tile.ROCK
	_smooth(grid, 1)
	_oasis(grid, rng, clear)
	for c in grid.all_cells():
		if clear.has(c) or grid.props[c] != Prop.NONE:
			continue
		var r := rng.randf()
		if grid.tiles[c] == Tile.SAND and _slope(grid, c) <= 1 and r < 0.05 + 0.18 * smoothstep(0.55, 0.85, thicket[c]):
			grid.props[c] = Prop.CACTUS
		elif grid.tiles[c] == Tile.ROCK and _rise(grid, c) == 0 and _slope(grid, c) > 0 and r < 0.12:
			grid.props[c] = Prop.BOULDER


## Lago: una cuenca en el centro con orillas de arena; la tierra sube poco a poco al alejarse del agua.
static func _lake(grid: BoardGrid, rng: RandomNumberGenerator, clear: Dictionary) -> void:
	var hf := _field(grid, rng, 0.06, 3, 16.0)
	var grove := _field(grid, rng, 0.15, 2)
	var center := Vector2(grid.width - 1, grid.height - 1) * 0.5
	var v := {}
	var values: Array[float] = []
	for c in grid.all_cells():
		var d := (Vector2(c) - center) / Vector2(grid.width * 0.5, grid.height * 0.38)
		v[c] = hf[c] * 0.5 + clampf(d.length(), 0.0, 1.2) * 0.5
		if not clear.has(c):
			values.append(v[c])
	values.sort()
	var level: float = values[int(values.size() * 0.32)]
	var water := {}
	for c in grid.all_cells():
		if v[c] < level and not clear.has(c):
			water[c] = true
	var dist := _distance(grid, water)
	for c in grid.all_cells():
		if water.has(c):
			grid.tiles[c] = Tile.WATER
			continue
		var dd: int = dist.get(c, 99)
		grid.tiles[c] = Tile.SAND if dd <= 1 else Tile.GRASS
		grid.heights[c] = clampi(int((dd - 1) / 3.0 + hf[c] * 1.4), 0, 2)
	_smooth(grid, 1)
	for c in grid.all_cells():
		if clear.has(c):
			continue
		var r := rng.randf()
		var dd: int = dist.get(c, 99)
		if grid.tiles[c] == Tile.GRASS and dd >= 2 and (grove[c] > 0.66 and r < 0.45 or r < 0.02):
			grid.props[c] = Prop.TREE
		elif grid.tiles[c] == Tile.SAND and r < 0.05:
			grid.props[c] = Prop.BOULDER


## Nieve: ventisqueros suaves, un estanque helado en la hondonada, roca desnuda en las lomas
## barridas por el viento y pinares nevados.
static func _snow(grid: BoardGrid, rng: RandomNumberGenerator, clear: Dictionary) -> void:
	var hf := _field(grid, rng, 0.06, 3, 14.0)
	var bare := _field(grid, rng, 0.18, 2)
	var pines := _field(grid, rng, 0.13, 2)
	for c in grid.all_cells():
		grid.heights[c] = _levels(pow(hf[c], 1.2), 3.0, 2)
	_smooth(grid, 2)
	_lowest_pond(grid, hf, 0.15, clear, Tile.ICE)
	for c in grid.all_cells():
		if grid.tiles[c] == Tile.ICE:
			continue
		if grid.heights[c] >= 2 and bare[c] > 0.7 or _slope(grid, c) >= 2:
			grid.tiles[c] = Tile.ROCK
		if clear.has(c):
			continue
		var r := rng.randf()
		if pines[c] > 0.62 and r < 0.45 or r < 0.01:
			grid.props[c] = Prop.PINE
		elif grid.tiles[c] == Tile.ROCK and r < 0.12:
			grid.props[c] = Prop.BOULDER


## Cueva: suelo irregular cruzado por crestas de roca, charcas subterráneas en lo más hondo,
## estalagmitas y grupos de cristales junto a las paredes y por las vetas de cristal.
static func _cave(grid: BoardGrid, rng: RandomNumberGenerator, clear: Dictionary) -> void:
	var hf := _field(grid, rng, 0.08, 3, 10.0)
	var ridge := _field(grid, rng, 0.07, 3, 12.0, true)
	var gems := _field(grid, rng, 0.15, 2)
	for c in grid.all_cells():
		grid.heights[c] = _levels(hf[c], 2.6, 2)
		if ridge[c] > 0.86 and not clear.has(c):
			grid.heights[c] += 2
			grid.tiles[c] = Tile.ROCK
		elif ridge[c] > 0.78:
			grid.tiles[c] = Tile.ROCK
	_smooth(grid, 1)
	_lowest_pond(grid, hf, 0.08, clear, Tile.WATER)
	for c in grid.all_cells():
		if clear.has(c) or grid.tiles[c] == Tile.WATER:
			continue
		var r := rng.randf()
		if _rise(grid, c) >= 2 and gems[c] > 0.45 and r < 0.5:
			grid.props[c] = Prop.CRYSTAL
		elif gems[c] > 0.68 and r < 0.12:  # alguna drusa suelta en medio de la vena de cristal
			grid.props[c] = Prop.CRYSTAL
		elif r < 0.05:
			grid.props[c] = Prop.STALAGMITE
		elif r < 0.07:
			grid.props[c] = Prop.BOULDER


## Gimnasio: suelo plano, líneas de la arena y columnas simétricas.
static func _gym_layout(grid: BoardGrid, keep_clear: Array[Vector2i]) -> void:
	var mid := grid.height / 2
	for c in grid.all_cells():
		var border := c.x == 1 or c.x == grid.width - 2 or c.y == 1 or c.y == grid.height - 2
		if border or c.y == mid or c.y == mid - 1 and grid.height % 2 == 0:
			grid.tiles[c] = Tile.FLOOR_LINE
	var pillars := [Vector2i(3, mid - 3), Vector2i(grid.width / 2 - 1, mid - 5), Vector2i(grid.width - 5, mid - 2)]
	for p: Vector2i in pillars:
		for c in [p, Vector2i(grid.width - 1 - p.x, grid.height - 1 - p.y)]:
			if grid.is_inside(c) and c not in keep_clear:
				grid.props[c] = Prop.PILLAR


static func _noise(rng: RandomNumberGenerator, freq: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = rng.randi()
	n.frequency = freq
	return n


static func _levels(value: float, scale: float, max_level: int) -> int:
	return clampi(floori(value * scale + 0.5), 0, max_level)


## Campo de ruido fractal (fBm) normalizado a 0-1 en todo el tablero, para que cada mapa use todo el
## rango de alturas. `warp` deforma el dominio (formas más orgánicas); `ridged` da crestas afiladas.
static func _field(grid: BoardGrid, rng: RandomNumberGenerator, freq: float, octaves := 3,
		warp := 0.0, ridged := false) -> Dictionary:
	var n := _noise(rng, freq)
	n.fractal_type = FastNoiseLite.FRACTAL_RIDGED if ridged else FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	if warp > 0.0:
		n.domain_warp_enabled = true
		n.domain_warp_amplitude = warp
		n.domain_warp_frequency = freq
	var out := {}
	var lo := INF
	var hi := -INF
	for c in grid.all_cells():
		var w := grid.to_world(c)
		var v := n.get_noise_2d(w.x, w.z)
		out[c] = v
		lo = minf(lo, v)
		hi = maxf(hi, v)
	for c in out:
		out[c] = (out[c] - lo) / maxf(hi - lo, 0.001)
	return out


## Quita picos y hoyos de una sola casilla (no los hay en un terreno real).
static func _smooth(grid: BoardGrid, passes: int) -> void:
	for i in passes:
		for c in grid.all_cells():
			var lo := 99
			var hi := -99
			for n in grid.neighbors(c):
				lo = mini(lo, grid.heights[n])
				hi = maxi(hi, grid.heights[n])
			grid.heights[c] = clampi(grid.heights[c], lo, hi)


## Mayor desnivel con los vecinos.
static func _slope(grid: BoardGrid, c: Vector2i) -> int:
	var s := 0
	for n in grid.neighbors(c):
		s = maxi(s, absi(grid.heights[n] - grid.heights[c]))
	return s


## Cuánto más alto está el vecino más alto (casillas al pie de un cortado).
static func _rise(grid: BoardGrid, c: Vector2i) -> int:
	var s := 0
	for n in grid.neighbors(c):
		s = maxi(s, grid.heights[n] - grid.heights[c])
	return s


## Distancia (en pasos) de cada celda al conjunto `from`.
static func _distance(grid: BoardGrid, from: Dictionary) -> Dictionary:
	var dist := {}
	var frontier: Array[Vector2i] = []
	for c: Vector2i in from:
		dist[c] = 0
		frontier.append(c)
	var i := 0
	while i < frontier.size():
		var c := frontier[i]
		i += 1
		for n in grid.neighbors(c):
			if not dist.has(n):
				dist[n] = dist[c] + 1
				frontier.append(n)
	return dist


## Sendero que serpentea de la zona del jugador (abajo) a la del rival (arriba).
static func _trail(grid: BoardGrid, rng: RandomNumberGenerator) -> Dictionary:
	var cells := {}
	var x := float(rng.randi_range(grid.width / 4, grid.width * 3 / 4))
	var drift := _noise(rng, 0.15)
	for y in range(grid.height - 1, -1, -1):
		var nx := clampf(x + drift.get_noise_1d(y) * 1.6, 1.0, grid.width - 2.0)
		for xx in range(mini(roundi(x), roundi(nx)), maxi(roundi(x), roundi(nx)) + 1):
			cells[Vector2i(xx, y)] = true
		x = nx
	return cells


## Río o arroyo que cruza el tablero de lado a lado (`across`: de izquierda a derecha) por el centro,
## serpenteando; 1-2 casillas de ancho.
static func _river(grid: BoardGrid, rng: RandomNumberGenerator, across: bool) -> Dictionary:
	var cells := {}
	var length := grid.width if across else grid.height
	var span := grid.height if across else grid.width
	var bend := _noise(rng, 0.09)
	var width := _noise(rng, 0.2)
	for i in length:
		var mid := span * 0.5 + bend.get_noise_1d(i) * span * 0.22
		var half := 0.5 + (0.6 if width.get_noise_1d(i) > 0.1 else 0.0)
		for j in range(floori(mid - half), ceili(mid + half)):
			var c := Vector2i(i, j) if across else Vector2i(j, i)
			if grid.is_inside(c):
				cells[c] = true
	return cells


## Las orillas de un cauce quedan como mucho un nivel por encima del agua.
static func _bank(grid: BoardGrid, water: Dictionary) -> void:
	for c: Vector2i in water:
		for n in grid.neighbors(c):
			if not water.has(n):
				grid.heights[n] = mini(grid.heights[n], 1)


## Charca (o estanque helado) en las hondonadas: celdas de altura 0 con el relieve por debajo de `below`.
static func _lowest_pond(grid: BoardGrid, hf: Dictionary, below: float, clear: Dictionary, tile: Tile) -> void:
	for c in grid.all_cells():
		if hf[c] < below and grid.heights[c] == 0 and not clear.has(c):
			grid.tiles[c] = tile


## Oasis del desierto: un hoyo con agua en una hondonada lejos de los bandos, rodeado de hierba y palmeras.
static func _oasis(grid: BoardGrid, rng: RandomNumberGenerator, clear: Dictionary) -> void:
	var options: Array[Vector2i] = []
	for c in grid.all_cells():
		if grid.heights[c] == 0 and grid.tiles[c] == Tile.SAND and c.y > grid.height * 0.3 and c.y < grid.height * 0.7:
			options.append(c)
	if options.is_empty():
		return
	var center := options[rng.randi_range(0, options.size() - 1)]
	var radius := rng.randf_range(1.2, 1.9)
	for c in grid.all_cells():
		var d := Vector2(c - center).length()
		if clear.has(c) or d > radius + 1.6:
			continue
		grid.heights[c] = 0
		grid.props[c] = Prop.NONE
		if d <= radius:
			grid.tiles[c] = Tile.WATER
		else:
			grid.tiles[c] = Tile.GRASS
			if rng.randf() < 0.35:
				grid.props[c] = Prop.PALM


## Si no hay camino entre las zonas (obstáculos o desniveles), suaviza alturas y
## quita obstáculos hasta que lo haya.
static func _ensure_path(grid: BoardGrid, from_cells: Array[Vector2i], to_cells: Array[Vector2i], rng: RandomNumberGenerator) -> void:
	if from_cells.is_empty() or to_cells.is_empty():
		return
	for attempt in 60:
		if _connected(grid, from_cells, to_cells):
			return
		if attempt % 2 == 0:
			for c in grid.all_cells():
				var lowest := 99
				for n in grid.neighbors(c):
					lowest = mini(lowest, grid.get_height(n))
				grid.heights[c] = mini(grid.get_height(c), lowest + 1)
		var blocked := grid.all_cells().filter(func(c: Vector2i) -> bool: return grid.is_blocked(c))
		for i in mini(blocked.size(), 6):
			grid.props[blocked[rng.randi_range(0, blocked.size() - 1)]] = Prop.NONE


static func _connected(grid: BoardGrid, from_cells: Array[Vector2i], to_cells: Array[Vector2i]) -> bool:
	var targets := {}
	for c in to_cells:
		targets[c] = true
	var seen := {}
	var frontier: Array[Vector2i] = []
	for c in from_cells:
		if not grid.is_blocked(c):
			seen[c] = true
			frontier.append(c)
	while not frontier.is_empty():
		var c: Vector2i = frontier.pop_back()
		if targets.has(c):
			return true
		for n in grid.neighbors(c):
			if seen.has(n) or grid.is_blocked(n):
				continue
			var dh := grid.get_height(n) - grid.get_height(c)
			if dh > 1 or dh < -2:
				continue
			seen[n] = true
			frontier.append(n)
	return false

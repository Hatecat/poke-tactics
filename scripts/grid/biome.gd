class_name Biome
extends RefCounted
## Tipos de campo: aspecto (suelo, obstáculos, cielo) y generador procedural.
## Por ahora son solo visuales; los efectos (p. ej. potenciar Agua en el lago) vendrán después.

enum Kind { MEADOW, FOREST, MOUNTAIN, DESERT, LAKE, SNOW, CAVE, GYM }
enum Tile { GRASS, DIRT, SAND, ROCK, WATER, SNOW, ICE, FLOOR, FLOOR_LINE, CAVE }
## Obstáculos: bloquean el paso y no se puede estar encima.
enum Prop { NONE, TREE, PINE, BOULDER, CACTUS, PILLAR, CRYSTAL }

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
	Kind.CAVE: [Color(0.04, 0.04, 0.06), Color(0.12, 0.1, 0.1), 0.35, 0.45],
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
static func generate(grid: BoardGrid, kind: Kind, rng: RandomNumberGenerator,
		keep_clear: Array[Vector2i], from_cells: Array[Vector2i], to_cells: Array[Vector2i]) -> void:
	grid.biome = kind
	var hn := _noise(rng, 0.07)
	var detail := _noise(rng, 0.18)
	var cluster := _noise(rng, 0.12)
	for c in grid.all_cells():
		var w := grid.to_world(c)
		var h := hn.get_noise_2d(w.x, w.z)
		var d := detail.get_noise_2d(w.x, w.z)
		var k := cluster.get_noise_2d(w.x, w.z)
		var r := rng.randf()
		var height := 0
		var tile := default_tile(kind)
		var prop := Prop.NONE
		match kind:
			Kind.MEADOW:
				height = _levels(h + 0.2, 3.0, 2)
				if d > 0.4:
					tile = Tile.DIRT
				prop = Prop.TREE if r < 0.03 else (Prop.BOULDER if r < 0.045 else Prop.NONE)
			Kind.FOREST:
				height = _levels(h, 2.5, 1)
				tile = Tile.DIRT if d > 0.25 else Tile.GRASS
				if k > 0.1 and r < 0.45:
					prop = Prop.TREE if r < 0.3 else Prop.PINE
			Kind.MOUNTAIN:
				height = _levels(h + 0.35, 6.0, 4)
				tile = Tile.GRASS if height <= 1 else (Tile.SNOW if height >= 4 else Tile.ROCK)
				prop = Prop.BOULDER if r < 0.05 else (Prop.PINE if r < 0.08 and height <= 1 else Prop.NONE)
			Kind.DESERT:
				height = _levels(h + 0.15, 3.0, 2)
				if d > 0.45:
					tile = Tile.ROCK
					height += 1
				prop = Prop.CACTUS if r < 0.03 else (Prop.BOULDER if r < 0.04 else Prop.NONE)
			Kind.LAKE:
				if h < -0.12:
					tile = Tile.WATER
				elif h < -0.02:
					tile = Tile.SAND
				else:
					height = _levels(h, 3.0, 2)
					prop = Prop.TREE if r < 0.04 else Prop.NONE
			Kind.SNOW:
				height = _levels(h + 0.1, 3.0, 2)
				if d > 0.4 and height == 0:
					tile = Tile.ICE
				prop = Prop.PINE if r < 0.06 else (Prop.BOULDER if r < 0.075 else Prop.NONE)
			Kind.CAVE:
				height = _levels(h + 0.3, 4.0, 3)
				if d > 0.35:
					tile = Tile.ROCK
				prop = Prop.CRYSTAL if r < 0.03 else (Prop.BOULDER if r < 0.08 else Prop.NONE)
			Kind.GYM:
				pass
		grid.heights[c] = height
		grid.tiles[c] = tile
		grid.props[c] = prop if c not in keep_clear else Prop.NONE
	if kind == Kind.GYM:
		_gym_layout(grid, keep_clear)
	_ensure_path(grid, from_cells, to_cells, rng)


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

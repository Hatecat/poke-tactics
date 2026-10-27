class_name Biome
extends RefCounted
## Tipos de campo: aspecto (suelo, obstáculos, cielo) y generador procedural.
## Por ahora son solo visuales; los efectos (p. ej. potenciar Agua en el lago) vendrán después.

enum Kind { MEADOW, FOREST, MOUNTAIN, DESERT, LAKE, SNOW, CAVE, GYM, SWAMP, CITY, LAB, VOLCANO, BEACH, CEMETERY, STUDIO, LIBRARY, AIRPORT, UNDERWATER }
enum Tile { GRASS, DIRT, SAND, ROCK, WATER, SNOW, ICE, FLOOR, FLOOR_LINE, CAVE, BRIDGE, MUD, ROAD, LAVA, WOOD }
## Obstáculos: bloquean el paso y no se puede estar encima.
enum Prop { NONE, TREE, PINE, BOULDER, CACTUS, PILLAR, CRYSTAL, STALAGMITE, PALM, DEAD_TREE, BUILDING, LAMP, PARASOL, MACHINE, TANK, VENT, GRAVE, SHELF,
	SPOTLIGHT, CAMERA, PLANE, PLANE_PART, CORAL }

const NAMES := {
	Kind.MEADOW: "Pradera", Kind.FOREST: "Bosque", Kind.MOUNTAIN: "Montaña", Kind.DESERT: "Desierto",
	Kind.LAKE: "Lago", Kind.SNOW: "Nieve", Kind.CAVE: "Cueva", Kind.GYM: "Gimnasio", Kind.SWAMP: "Pantano",
	Kind.CITY: "Ciudad", Kind.LAB: "Laboratorio", Kind.VOLCANO: "Volcán", Kind.BEACH: "Playa",
	Kind.CEMETERY: "Cementerio", Kind.STUDIO: "Estudio", Kind.LIBRARY: "Librería", Kind.AIRPORT: "Aeropuerto",
	Kind.UNDERWATER: "Cueva submarina",
}
const ICONS := {
	Kind.MEADOW: "🌼", Kind.FOREST: "🌲", Kind.MOUNTAIN: "⛰", Kind.DESERT: "🌵",
	Kind.LAKE: "🌊", Kind.SNOW: "❄", Kind.CAVE: "🪨", Kind.GYM: "★", Kind.SWAMP: "🐸", Kind.CITY: "🏙",
	Kind.LAB: "⚗", Kind.VOLCANO: "🌋", Kind.BEACH: "🏖", Kind.CEMETERY: "🪦", Kind.STUDIO: "🎬", Kind.LIBRARY: "📚",
	Kind.AIRPORT: "✈", Kind.UNDERWATER: "🐚",
}
const TILE_NAMES := {
	Tile.GRASS: "Hierba", Tile.DIRT: "Tierra", Tile.SAND: "Arena", Tile.ROCK: "Roca", Tile.WATER: "Agua",
	Tile.SNOW: "Nieve", Tile.ICE: "Hielo", Tile.FLOOR: "Suelo", Tile.FLOOR_LINE: "Línea", Tile.CAVE: "Cueva",
	Tile.BRIDGE: "Puente", Tile.MUD: "Lodo", Tile.ROAD: "Calzada", Tile.LAVA: "Lava", Tile.WOOD: "Madera",
}
const PROP_NAMES := {
	Prop.NONE: "Nada", Prop.TREE: "Árbol", Prop.PINE: "Pino", Prop.BOULDER: "Roca",
	Prop.CACTUS: "Cactus", Prop.PILLAR: "Columna", Prop.CRYSTAL: "Cristal",
	Prop.STALAGMITE: "Estalagmita", Prop.PALM: "Palmera", Prop.DEAD_TREE: "Árbol seco", Prop.BUILDING: "Edificio",
	Prop.LAMP: "Farola", Prop.PARASOL: "Sombrilla", Prop.MACHINE: "Máquina", Prop.TANK: "Incubadora",
	Prop.VENT: "Fumarola", Prop.GRAVE: "Lápida", Prop.SHELF: "Estantería", Prop.SPOTLIGHT: "Foco",
	Prop.CAMERA: "Cámara", Prop.PLANE: "Avión", Prop.PLANE_PART: "Avión", Prop.CORAL: "Coral",
}
const TILE_COLORS := {
	Tile.GRASS: Color(0.4, 0.66, 0.34), Tile.DIRT: Color(0.58, 0.45, 0.3), Tile.SAND: Color(0.88, 0.78, 0.52),
	Tile.ROCK: Color(0.56, 0.54, 0.5), Tile.WATER: Color(0.26, 0.52, 0.86), Tile.SNOW: Color(0.93, 0.95, 0.98),
	Tile.ICE: Color(0.68, 0.85, 0.95), Tile.FLOOR: Color(0.78, 0.75, 0.68), Tile.FLOOR_LINE: Color(0.85, 0.32, 0.26),
	Tile.CAVE: Color(0.36, 0.33, 0.31), Tile.BRIDGE: Color(0.55, 0.4, 0.26), Tile.MUD: Color(0.36, 0.29, 0.2),
	Tile.ROAD: Color(0.3, 0.3, 0.32), Tile.LAVA: Color(0.95, 0.4, 0.1),
	Tile.WOOD: Color(0.6, 0.42, 0.26),
}
## Color de los laterales de las casillas.
const SIDE_COLORS := {
	Kind.MEADOW: Color(0.42, 0.32, 0.22), Kind.FOREST: Color(0.36, 0.27, 0.18), Kind.MOUNTAIN: Color(0.4, 0.38, 0.36),
	Kind.DESERT: Color(0.7, 0.58, 0.38), Kind.LAKE: Color(0.42, 0.34, 0.24), Kind.SNOW: Color(0.6, 0.64, 0.72),
	Kind.CAVE: Color(0.22, 0.2, 0.19), Kind.GYM: Color(0.45, 0.45, 0.5), Kind.SWAMP: Color(0.3, 0.25, 0.17),
	Kind.CITY: Color(0.5, 0.5, 0.52), Kind.LAB: Color(0.55, 0.58, 0.62), Kind.VOLCANO: Color(0.2, 0.17, 0.16),
	Kind.BEACH: Color(0.8, 0.7, 0.5), Kind.CEMETERY: Color(0.32, 0.27, 0.22), Kind.STUDIO: Color(0.16, 0.16, 0.18),
	Kind.LIBRARY: Color(0.42, 0.28, 0.18), Kind.AIRPORT: Color(0.45, 0.45, 0.47), Kind.UNDERWATER: Color(0.2, 0.26, 0.32),
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
	Kind.SWAMP: [Color(0.34, 0.44, 0.42), Color(0.62, 0.68, 0.56), 0.85, 0.75],
	Kind.CITY: [Color(0.4, 0.55, 0.8), Color(0.88, 0.84, 0.78), 1.1, 0.85],
	Kind.LAB: [Color(0.1, 0.12, 0.16), Color(0.32, 0.36, 0.42), 0.9, 0.95],
	Kind.VOLCANO: [Color(0.25, 0.12, 0.1), Color(0.78, 0.42, 0.26), 1.0, 0.7],
	Kind.BEACH: [Color(0.3, 0.6, 0.95), Color(0.8, 0.92, 1.0), 1.3, 0.9],
	Kind.CEMETERY: [Color(0.12, 0.13, 0.24), Color(0.42, 0.4, 0.52), 0.65, 0.75],
	Kind.STUDIO: [Color(0.04, 0.04, 0.06), Color(0.14, 0.13, 0.16), 0.8, 0.6],
	Kind.LIBRARY: [Color(0.22, 0.15, 0.1), Color(0.55, 0.42, 0.3), 0.85, 0.9],
	Kind.AIRPORT: [Color(0.35, 0.58, 0.9), Color(0.82, 0.9, 0.98), 1.2, 0.85],
	Kind.UNDERWATER: [Color(0.02, 0.08, 0.16), Color(0.08, 0.28, 0.4), 0.6, 0.5],
}
## Tipos con estilo propio de gimnasio ("" = neutral).
const GYM_TYPES: PackedStringArray = ["", "normal", "fire", "water", "electric", "grass", "ice", "fighting", "poison",
	"ground", "flying", "psychic", "bug", "rock", "ghost", "dragon", "dark", "steel", "fairy"]
## Estilo de cada gimnasio: colores del suelo, las líneas, los laterales y las columnas, el obstáculo que hace
## de columna y un rasgo del terreno a los lados de la arena (piscina, lava, jardín, hielo, arena, roca).
## `water` cambia el color del agua (charcas venenosas).
const GYM_STYLES := {
	"": {"floor": Color(0.78, 0.75, 0.68), "line": Color(0.85, 0.32, 0.26), "side": Color(0.45, 0.45, 0.5),
		"pillar": Color(0.82, 0.8, 0.76), "prop": Prop.PILLAR, "feature": ""},
	"normal": {"floor": Color(0.86, 0.82, 0.72), "line": Color(0.6, 0.55, 0.45), "side": Color(0.55, 0.52, 0.46),
		"pillar": Color(0.92, 0.9, 0.84), "prop": Prop.PILLAR, "feature": ""},
	"fire": {"floor": Color(0.55, 0.3, 0.24), "line": Color(0.98, 0.7, 0.2), "side": Color(0.35, 0.18, 0.14),
		"pillar": Color(0.42, 0.22, 0.17), "prop": Prop.PILLAR, "feature": "lava"},
	"water": {"floor": Color(0.66, 0.8, 0.9), "line": Color(0.2, 0.45, 0.85), "side": Color(0.3, 0.42, 0.55),
		"pillar": Color(0.86, 0.93, 0.97), "prop": Prop.PILLAR, "feature": "pool"},
	"electric": {"floor": Color(0.32, 0.32, 0.36), "line": Color(0.98, 0.85, 0.2), "side": Color(0.22, 0.22, 0.25),
		"pillar": Color(0.95, 0.8, 0.2), "prop": Prop.PILLAR, "feature": ""},
	"grass": {"floor": Color(0.62, 0.52, 0.36), "line": Color(0.95, 0.85, 0.4), "side": Color(0.36, 0.28, 0.2),
		"pillar": Color(0.5, 0.4, 0.3), "prop": Prop.TREE, "feature": "garden"},
	"ice": {"floor": Color(0.84, 0.91, 0.97), "line": Color(0.4, 0.7, 0.95), "side": Color(0.6, 0.7, 0.8),
		"pillar": Color(0.76, 0.88, 0.98), "prop": Prop.CRYSTAL, "feature": "ice"},
	"fighting": {"floor": Color(0.68, 0.52, 0.34), "line": Color(0.8, 0.2, 0.18), "side": Color(0.4, 0.28, 0.18),
		"pillar": Color(0.5, 0.34, 0.22), "prop": Prop.PILLAR, "feature": ""},
	"poison": {"floor": Color(0.42, 0.32, 0.5), "line": Color(0.72, 0.42, 0.88), "side": Color(0.28, 0.2, 0.32),
		"pillar": Color(0.5, 0.38, 0.58), "prop": Prop.PILLAR, "feature": "pool",
		"water": [Color(0.32, 0.12, 0.4), Color(0.6, 0.35, 0.72)]},
	"ground": {"floor": Color(0.7, 0.55, 0.38), "line": Color(0.55, 0.32, 0.18), "side": Color(0.6, 0.45, 0.3),
		"pillar": Color(0.6, 0.48, 0.36), "prop": Prop.BOULDER, "feature": "sand"},
	"flying": {"floor": Color(0.86, 0.92, 0.98), "line": Color(0.45, 0.65, 0.95), "side": Color(0.65, 0.75, 0.88),
		"pillar": Color(0.96, 0.97, 1.0), "prop": Prop.PILLAR, "feature": ""},
	"psychic": {"floor": Color(0.88, 0.72, 0.82), "line": Color(0.85, 0.3, 0.6), "side": Color(0.55, 0.4, 0.5),
		"pillar": Color(0.8, 0.6, 0.75), "prop": Prop.CRYSTAL, "feature": ""},
	"bug": {"floor": Color(0.6, 0.62, 0.38), "line": Color(0.75, 0.85, 0.25), "side": Color(0.34, 0.3, 0.18),
		"pillar": Color(0.45, 0.4, 0.25), "prop": Prop.TREE, "feature": "garden"},
	"rock": {"floor": Color(0.6, 0.56, 0.5), "line": Color(0.78, 0.62, 0.35), "side": Color(0.4, 0.36, 0.32),
		"pillar": Color(0.55, 0.5, 0.45), "prop": Prop.BOULDER, "feature": "rock"},
	"ghost": {"floor": Color(0.27, 0.22, 0.34), "line": Color(0.58, 0.38, 0.88), "side": Color(0.16, 0.13, 0.2),
		"pillar": Color(0.35, 0.3, 0.42), "prop": Prop.DEAD_TREE, "feature": ""},
	"dragon": {"floor": Color(0.24, 0.26, 0.44), "line": Color(0.88, 0.72, 0.3), "side": Color(0.15, 0.16, 0.28),
		"pillar": Color(0.32, 0.34, 0.58), "prop": Prop.PILLAR, "feature": ""},
	"dark": {"floor": Color(0.2, 0.19, 0.22), "line": Color(0.78, 0.18, 0.2), "side": Color(0.12, 0.11, 0.13),
		"pillar": Color(0.27, 0.25, 0.3), "prop": Prop.PILLAR, "feature": ""},
	"steel": {"floor": Color(0.64, 0.67, 0.72), "line": Color(0.3, 0.35, 0.42), "side": Color(0.45, 0.48, 0.52),
		"pillar": Color(0.78, 0.8, 0.84), "prop": Prop.PILLAR, "feature": ""},
	"fairy": {"floor": Color(0.96, 0.85, 0.9), "line": Color(0.95, 0.5, 0.72), "side": Color(0.75, 0.6, 0.68),
		"pillar": Color(0.98, 0.9, 0.95), "prop": Prop.CRYSTAL, "feature": ""},
}


## Estilo del gimnasio de un tipo (el neutral si no tiene).
static func gym_style(type: String) -> Dictionary:
	return GYM_STYLES.get(type, GYM_STYLES[""])


static func default_tile(kind: Kind) -> Tile:
	match kind:
		Kind.DESERT: return Tile.SAND
		Kind.SNOW: return Tile.SNOW
		Kind.CAVE: return Tile.CAVE
		Kind.GYM: return Tile.FLOOR
		Kind.MOUNTAIN: return Tile.ROCK
		Kind.CITY, Kind.LAB: return Tile.FLOOR
		Kind.VOLCANO: return Tile.ROCK
		Kind.BEACH: return Tile.SAND
		Kind.STUDIO: return Tile.FLOOR
		Kind.LIBRARY: return Tile.WOOD
		Kind.UNDERWATER: return Tile.CAVE
	return Tile.GRASS


## Rellena alturas, suelos y obstáculos de `grid` según el bioma. `keep_clear` son
## celdas que deben quedar libres (zonas de despliegue). Garantiza que se pueda
## llegar de `from_cells` a `to_cells` con salto 1, también sin pisar el agua y con la talla más grande (3).
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
		Kind.SWAMP: _swamp(grid, rng, clear)
		Kind.CITY: _city(grid, rng, clear)
		Kind.LAB: _lab(grid, rng, clear)
		Kind.VOLCANO: _volcano(grid, rng, clear)
		Kind.BEACH: _beach(grid, rng, clear)
		Kind.CEMETERY: _cemetery(grid, rng, clear)
		Kind.STUDIO: _studio(grid, rng, clear)
		Kind.LIBRARY: _library(grid, rng, clear)
		Kind.AIRPORT: _airport(grid, rng, clear)
		Kind.UNDERWATER: _underwater(grid, rng, clear)
	for c in keep_clear:
		if grid.is_blocked(c):
			_clear_prop(grid, c)
	_ensure_path(grid, from_cells, to_cells, rng)
	_ensure_dry_path(grid, from_cells, to_cells, kind)
	if kind != Kind.GYM:
		_ensure_wide_path(grid, from_cells, to_cells, kind)


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
	var to_ford := _distance(grid, _fords(grid, rng, stream, trail))
	var to_water := _distance(grid, stream)
	for c in grid.all_cells():
		if grid.tiles[c] == Tile.WATER or trail.has(c):
			continue
		if dense[c] > 0.62 and rng.randf() < 0.6:
			grid.tiles[c] = Tile.DIRT
		# Accesos a los vados despejados y orillas con menos árboles, para poder cruzar
		if clear.has(c) or to_ford.get(c, 99) <= 2 or to_water.get(c, 99) == 1 and rng.randf() < 0.65:
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


## Pantano: terreno bajo y casi llano con pozas de agua estancada entre lodazales; sauces de copa oscura,
## árboles secos y alguna roca. Los juncos y nenúfares los pone la vista en el agua.
static func _swamp(grid: BoardGrid, rng: RandomNumberGenerator, clear: Dictionary) -> void:
	var hf := _field(grid, rng, 0.08, 3, 10.0)
	var wet := _field(grid, rng, 0.13, 3, 6.0)
	for c in grid.all_cells():
		grid.heights[c] = _levels(hf[c], 1.6, 1)
	_smooth(grid, 1)
	for c in grid.all_cells():
		if clear.has(c):
			continue
		if wet[c] > 0.64:
			grid.tiles[c] = Tile.WATER
			grid.heights[c] = 0
		elif wet[c] > 0.5 or wet[c] > 0.4 and rng.randf() < 0.4:
			grid.tiles[c] = Tile.MUD
	for c in grid.all_cells():
		if clear.has(c) or grid.tiles[c] == Tile.WATER:
			continue
		var r := rng.randf()
		if r < 0.07:
			grid.props[c] = Prop.TREE
		elif r < 0.11:
			grid.props[c] = Prop.DEAD_TREE
		elif r < 0.125:
			grid.props[c] = Prop.BOULDER


## Ciudad: calles de asfalto de dos carriles en cuadrícula con aceras, manzanas de edificios de distinta
## altura, un parque con árboles y una fuente, y farolas junto a la calzada.
static func _city(grid: BoardGrid, rng: RandomNumberGenerator, clear: Dictionary) -> void:
	var cols: Array[int] = [rng.randi_range(2, 4), rng.randi_range(grid.width - 6, grid.width - 4)]
	if rng.randf() < 0.5:
		cols.append(grid.width / 2 - 1)
	var rows: Array[int] = [grid.height / 2 - 1 + rng.randi_range(-1, 0)]
	for c in grid.all_cells():
		if cols.any(func(x: int) -> bool: return c.x == x or c.x == x + 1) \
				or rows.any(func(y: int) -> bool: return c.y == y or c.y == y + 1):
			grid.tiles[c] = Tile.ROAD
	# Parque en una manzana al azar, lejos de las zonas de despliegue
	var park := Vector2i(rng.randi_range(4, grid.width - 5), rows[0] + (4 if rng.randf() < 0.5 else -3))
	var dense := _field(grid, rng, 0.25, 2)
	for c in grid.all_cells():
		if grid.tiles[c] == Tile.ROAD or clear.has(c):
			continue
		var by_road := grid.neighbors(c).any(func(n: Vector2i) -> bool: return grid.tiles[n] == Tile.ROAD)
		if Vector2(c - park).length() < 2.6:
			grid.tiles[c] = Tile.WATER if c == park else Tile.GRASS
			if c != park and not by_road and rng.randf() < 0.3:
				grid.props[c] = Prop.TREE
		elif by_road:
			if rng.randf() < 0.1:
				grid.props[c] = Prop.LAMP  # la acera queda libre salvo alguna farola
		elif dense[c] > 0.35 and rng.randf() < 0.8:
			grid.props[c] = Prop.BUILDING


## Laboratorio: suelo de paneles con líneas guía, una plataforma central elevada, bancos de máquinas y
## incubadoras en filas simétricas (los dos bandos tienen el mismo terreno).
static func _lab(grid: BoardGrid, rng: RandomNumberGenerator, clear: Dictionary) -> void:
	var center := Vector2(grid.width - 1, grid.height - 1) * 0.5
	for c in grid.all_cells():
		var d := Vector2(c).distance_to(center)
		if d < 2.3:
			grid.heights[c] = 1
		elif d < 3.2 or c.x == 1 or c.x == grid.width - 2:
			grid.tiles[c] = Tile.FLOOR_LINE
	var put := func(c: Vector2i, prop: Prop) -> void:
		for m in [c, Vector2i(grid.width - 1 - c.x, grid.height - 1 - c.y)]:
			if grid.is_inside(m) and not clear.has(m) and grid.heights[m] == 0 and grid.tiles[m] != Tile.FLOOR_LINE:
				grid.props[m] = prop
	# Bancos de máquinas: tramos de 2-4 con huecos para pasar
	for y in [grid.height / 2 - 4, grid.height / 2 - 6]:
		var x := rng.randi_range(2, 4)
		while x < grid.width - 3:
			var run := rng.randi_range(2, 4)
			for i in run:
				put.call(Vector2i(x + i, y), Prop.MACHINE)
			x += run + rng.randi_range(2, 3)
	# Incubadoras junto a la plataforma y en las esquinas de la sala
	for c: Vector2i in [Vector2i(grid.width / 2 - 4, grid.height / 2 - 2), Vector2i(2, grid.height / 2 - 2),
			Vector2i(grid.width - 3, grid.height / 2 - 1)]:
		put.call(c, Prop.TANK)
		if rng.randf() < 0.5:
			put.call(c + Vector2i(0, -1), Prop.TANK)


## Volcán: crestas de basalto, un río de lava que cruza por el centro con dos pasos de roca, pozas de lava
## en las hondonadas, ceniza, fumarolas y troncos calcinados.
static func _volcano(grid: BoardGrid, rng: RandomNumberGenerator, clear: Dictionary) -> void:
	var hf := _field(grid, rng, 0.08, 4, 12.0, true)
	var ash := _field(grid, rng, 0.15, 2)
	for c in grid.all_cells():
		grid.heights[c] = _levels(hf[c], 3.2, 3)
	_smooth(grid, 2)
	var flow := _river(grid, rng, true)
	for c in flow:
		grid.tiles[c] = Tile.LAVA
		grid.heights[c] = 0
	_bank(grid, flow)
	_lowest_pond(grid, hf, 0.05, clear, Tile.LAVA)
	var to_pass := _distance(grid, _fords(grid, rng, flow, {}, [Tile.ROCK]))
	for c in grid.all_cells():
		if grid.tiles[c] == Tile.LAVA:
			continue
		if ash[c] > 0.62:
			grid.tiles[c] = Tile.DIRT  # ceniza
		if clear.has(c) or to_pass.get(c, 99) <= 2:
			continue
		var r := rng.randf()
		if r < 0.05:
			grid.props[c] = Prop.BOULDER
		elif r < 0.075:
			grid.props[c] = Prop.VENT
		elif r < 0.09:
			grid.props[c] = Prop.DEAD_TREE


## Playa: el mar ocupa un costado (los dos bandos tienen la misma costa), con orilla irregular, arena que
## pasa a dunas con hierba tierra adentro, un muelle de madera, sombrillas, palmeras y rocas.
static func _beach(grid: BoardGrid, rng: RandomNumberGenerator, clear: Dictionary) -> void:
	var left := rng.randf() < 0.5
	var coast := _noise(rng, 0.12)
	var hf := _field(grid, rng, 0.09, 3, 8.0)
	var shore := {}
	for c in grid.all_cells():
		var x := c.x if left else grid.width - 1 - c.x  # distancia al borde del mar
		var line := 4.5 + coast.get_noise_1d(c.y) * 2.0
		shore[c] = x - line
		if shore[c] < 0.0 and not clear.has(c):
			grid.tiles[c] = Tile.WATER
		elif shore[c] > 6.0:
			grid.heights[c] = _levels(hf[c], 1.8, 1)
			if hf[c] > 0.55:
				grid.tiles[c] = Tile.GRASS
	# Muelle: una fila de tablones desde la orilla hasta mar adentro
	var pier_y := rng.randi_range(grid.height * 2 / 5, grid.height * 3 / 5)
	for c in grid.all_cells():
		if c.y == pier_y and grid.tiles[c] == Tile.WATER:
			grid.tiles[c] = Tile.BRIDGE
	for c in grid.all_cells():
		if clear.has(c) or grid.tiles[c] in [Tile.WATER, Tile.BRIDGE]:
			continue
		var r := rng.randf()
		if shore[c] < 4.0:
			if r < 0.06:
				grid.props[c] = Prop.PARASOL
			elif r < 0.08:
				grid.props[c] = Prop.BOULDER
		elif r < 0.1:
			grid.props[c] = Prop.PALM


## Cementerio: lomas suaves de hierba oscura, un camino de tierra entre los bandos y otro que lo cruza,
## hileras de lápidas, árboles secos y faroles junto al camino.
static func _cemetery(grid: BoardGrid, rng: RandomNumberGenerator, clear: Dictionary) -> void:
	var hf := _field(grid, rng, 0.07, 3, 10.0)
	for c in grid.all_cells():
		grid.heights[c] = _levels(hf[c], 1.8, 1)
	_smooth(grid, 2)
	var path := _trail(grid, rng)
	var cross := grid.height / 2 + rng.randi_range(-1, 1)
	for c in grid.all_cells():
		if c.y == cross:
			path[c] = true
	for c in path:
		grid.tiles[c] = Tile.DIRT
	for c in grid.all_cells():
		if clear.has(c) or path.has(c):
			continue
		var by_path := grid.neighbors(c).any(func(n: Vector2i) -> bool: return path.has(n))
		var r := rng.randf()
		if c.x % 2 == 1 and c.y % 3 != 0 and r < 0.55:
			grid.props[c] = Prop.GRAVE  # hileras con pasillos entre ellas
		elif by_path and r < 0.6 and r > 0.55:
			grid.props[c] = Prop.LAMP
		elif r > 0.96:
			grid.props[c] = Prop.DEAD_TREE


## Librería: suelo de parqué con alfombras en los pasillos centrales y estanterías en filas paralelas, con
## huecos para pasar, iguales en las dos mitades.
static func _library(grid: BoardGrid, rng: RandomNumberGenerator, clear: Dictionary) -> void:
	var mx := grid.width / 2
	var my := grid.height / 2
	for c in grid.all_cells():
		if absi(c.x - mx) <= 1 and c.x != mx + 1 or absi(c.y - my) <= 0:
			grid.tiles[c] = Tile.FLOOR_LINE  # alfombra
	var put := func(c: Vector2i) -> void:
		for m in [c, Vector2i(grid.width - 1 - c.x, grid.height - 1 - c.y)]:
			if grid.is_inside(m) and not clear.has(m) and grid.tiles[m] == Tile.WOOD:
				grid.props[m] = Prop.SHELF
	for y in range(my - 6, my, 2):
		var x := rng.randi_range(1, 2)
		while x < grid.width - 1:
			var run := rng.randi_range(3, 5)
			for i in run:
				put.call(Vector2i(x + i, y))
			x += run + rng.randi_range(1, 2)


## Estudio: plató a oscuras con un escenario elevado de madera en el centro rodeado de cinta de marcas,
## focos en las esquinas del escenario y cámaras que lo enfocan desde los dos lados.
static func _studio(grid: BoardGrid, rng: RandomNumberGenerator, clear: Dictionary) -> void:
	var mx := grid.width / 2
	var my := grid.height / 2
	var half := Vector2i(rng.randi_range(3, 4), 2)
	for c in grid.all_cells():
		var d := (c - Vector2i(mx, my)).abs()
		if d.x < half.x and d.y < half.y:
			grid.tiles[c] = Tile.WOOD
			grid.heights[c] = 1
		elif d.x <= half.x and d.y <= half.y:
			grid.tiles[c] = Tile.FLOOR_LINE
	var put := func(c: Vector2i, prop: Prop) -> void:
		for m in [c, Vector2i(grid.width - 1 - c.x, grid.height - 1 - c.y)]:
			if grid.is_inside(m) and not clear.has(m) and grid.heights[m] == 0:
				grid.props[m] = prop
	put.call(Vector2i(mx - half.x - 1, my - half.y - 1), Prop.SPOTLIGHT)
	put.call(Vector2i(mx + half.x + 1, my - half.y - 1), Prop.SPOTLIGHT)
	for x in [mx - 4, mx + 1, mx + 5]:
		if rng.randf() < 0.8:
			put.call(Vector2i(x, my - half.y - 3), Prop.CAMERA)
	for y in [my - 1, my + 1]:
		put.call(Vector2i(2, y), Prop.SPOTLIGHT)


## Aeropuerto: pista de dos carriles que cruza el tablero, una calle de rodaje, hierba entre ellas, una
## plataforma de hormigón con aviones aparcados (3×3) y la terminal al fondo.
static func _airport(grid: BoardGrid, rng: RandomNumberGenerator, clear: Dictionary) -> void:
	var my := grid.height / 2 - 1
	var taxi := rng.randi_range(3, 5) if rng.randf() < 0.5 else rng.randi_range(grid.width - 7, grid.width - 5)
	for c in grid.all_cells():
		if c.y == my or c.y == my + 1 or c.x == taxi or c.x == taxi + 1:
			grid.tiles[c] = Tile.ROAD
	# Plataforma a un lado de la pista, lejos de la calle de rodaje, con 1 o 2 aviones
	var apron_x := grid.width - 8 if taxi < grid.width / 2 else 1
	var apron_y := my - 6 if rng.randf() < 0.5 else my + 3
	for c in grid.all_cells():
		if c.x >= apron_x and c.x < apron_x + 7 and c.y >= apron_y and c.y < apron_y + 4:
			grid.tiles[c] = Tile.FLOOR
	for i in rng.randi_range(1, 2):
		var a := Vector2i(apron_x + i * 4, apron_y)
		var cells := grid.footprint(a, 3)
		if cells.all(func(c: Vector2i) -> bool: return grid.is_inside(c) and not clear.has(c) and not grid.is_blocked(c)):
			for c in cells:
				grid.props[c] = Prop.PLANE_PART
			grid.props[a] = Prop.PLANE
	# Terminal: un bloque de edificios en el otro lado de la pista
	var term_y := my + 4 if apron_y < my else my - 4
	for x in range(grid.width / 2 - 3, grid.width / 2 + 3):
		var c := Vector2i(x, term_y)
		if grid.is_inside(c) and not clear.has(c) and grid.tiles[c] != Tile.ROAD:
			grid.tiles[c] = Tile.FLOOR
			grid.props[c] = Prop.BUILDING
	for c in grid.all_cells():
		if clear.has(c) or grid.props[c] != Prop.NONE or grid.tiles[c] != Tile.GRASS:
			continue
		if grid.neighbors(c).any(func(n: Vector2i) -> bool: return grid.tiles[n] == Tile.ROAD) and rng.randf() < 0.06:
			grid.props[c] = Prop.LAMP


## Cueva submarina: caverna inundada con mucha agua entre islotes de roca y arena, corales, estalagmitas y
## cristales que alumbran el azul.
static func _underwater(grid: BoardGrid, rng: RandomNumberGenerator, clear: Dictionary) -> void:
	var hf := _field(grid, rng, 0.08, 3, 10.0)
	var wet := _field(grid, rng, 0.1, 3, 8.0)
	var gems := _field(grid, rng, 0.15, 2)
	for c in grid.all_cells():
		grid.heights[c] = _levels(hf[c], 2.2, 2)
	_smooth(grid, 1)
	for c in grid.all_cells():
		if clear.has(c):
			continue
		if wet[c] > 0.55:
			grid.tiles[c] = Tile.WATER
			grid.heights[c] = 0
		elif wet[c] > 0.45:
			grid.tiles[c] = Tile.SAND
			grid.heights[c] = mini(grid.heights[c], 1)
	for c in grid.all_cells():
		if clear.has(c) or grid.tiles[c] == Tile.WATER:
			continue
		var r := rng.randf()
		if grid.tiles[c] == Tile.SAND and r < 0.2 or r < 0.05:
			grid.props[c] = Prop.CORAL
		elif gems[c] > 0.7 and r < 0.15:
			grid.props[c] = Prop.CRYSTAL
		elif r < 0.09:
			grid.props[c] = Prop.STALAGMITE


## Gimnasio: suelo plano, líneas de la arena, tarimas del líder y del retador y columnas simétricas, con
## el estilo del tipo del gimnasio (`grid.gym_type`): suelo de hierba, arena o roca, piscinas o lava a los lados de la arena, placas de
## hielo, y árboles, rocas o cristales en lugar de columnas.
static func _gym_layout(grid: BoardGrid, keep_clear: Array[Vector2i]) -> void:
	var style := gym_style(grid.gym_type)
	var feature: String = style.feature
	var floor_tile: Tile = {"garden": Tile.GRASS, "sand": Tile.SAND, "rock": Tile.ROCK}.get(feature, Tile.FLOOR)
	var mid := grid.height / 2
	for c in grid.all_cells():
		grid.tiles[c] = floor_tile
		var border := c.x == 1 or c.x == grid.width - 2 or c.y == 1 or c.y == grid.height - 2
		if border or c.y == mid or c.y == mid - 1 and grid.height % 2 == 0:
			grid.tiles[c] = Tile.FLOOR_LINE
	# Piscinas, lava o placas de hielo a ambos lados de la arena, dejando libre el centro
	var pool: int = {"pool": Tile.WATER, "lava": Tile.LAVA, "ice": Tile.ICE}.get(feature, -1)
	if pool >= 0:
		for c in grid.all_cells():
			var side := c.x >= 3 and c.x <= 5 or c.x >= grid.width - 6 and c.x <= grid.width - 4
			if side and absi(c.y - mid) <= 3 and c not in keep_clear:
				grid.tiles[c] = pool
	# Tarimas escalonadas del líder y del retador en el fondo de cada campo: dos escalones en el centro
	# y uno a los lados.
	var cx := grid.width / 2
	for x in range(cx - 3, cx + 3):
		var inner := x >= cx - 2 and x < cx + 2
		for c in [Vector2i(x, 0), Vector2i(x, grid.height - 1)]:
			grid.heights[c] = 2 if inner else 1
			grid.tiles[c] = floor_tile
		if inner:
			for c in [Vector2i(x, 1), Vector2i(x, grid.height - 2)]:
				grid.heights[c] = 1
				grid.tiles[c] = floor_tile
	var pillars := [Vector2i(3, mid - 5), Vector2i(grid.width / 2 - 1, mid - 5), Vector2i(grid.width - 5, mid - 6)]
	for p: Vector2i in pillars:
		for c in [p, Vector2i(grid.width - 1 - p.x, grid.height - 1 - p.y)]:
			if grid.is_inside(c) and c not in keep_clear:
				grid.props[c] = style.prop


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


## Cruces de 3 casillas de ancho (lo que ocupa Onix) en un río que cruza de izquierda a derecha:
## uno donde lo cruza el sendero y otro lejos de él; cada uno de los suelos de `options` (por defecto, vado
## de tierra o puente de madera).
## Sin ellos los Pokémon que no pueden entrar al agua (roca, acero, tierra) se quedan en su orilla y
## la partida no puede terminar.
static func _fords(grid: BoardGrid, rng: RandomNumberGenerator, stream: Dictionary, trail: Dictionary,
		options: Array[Tile] = [Tile.BRIDGE, Tile.DIRT]) -> Dictionary:
	var first := rng.randi_range(1, grid.width - 2)
	for c: Vector2i in trail:
		if stream.has(c):
			first = clampi(c.x, 1, grid.width - 2)
			break
	var far: Array[int] = []
	for x in range(1, grid.width - 1):
		if absi(x - first) >= grid.width / 3:
			far.append(x)
	var columns: Array[int] = [first]
	if not far.is_empty():
		columns.append(far[rng.randi_range(0, far.size() - 1)])
	var ford := {}
	for x in columns:
		var tile := options[rng.randi_range(0, options.size() - 1)]
		for c: Vector2i in stream:
			if absi(c.x - x) <= 1:
				ford[c] = true
				grid.tiles[c] = tile
	return ford


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
			_clear_prop(grid, blocked[rng.randi_range(0, blocked.size() - 1)])


## Garantiza un paso para los Pokémon más grandes (3 casillas) que no pueden entrar al agua: busca el
## trayecto que menos hay que tocar y en él quita obstáculos, cambia el agua por vado y rebaja las
## cuestas para que la huella quepa (desnivel 1) y pueda avanzar.
static func _ensure_wide_path(grid: BoardGrid, from_cells: Array[Vector2i], to_cells: Array[Vector2i], kind: Kind) -> void:
	if from_cells.is_empty() or to_cells.is_empty():
		return
	var ford := default_tile(kind)
	if ford == Tile.GRASS:
		ford = Tile.DIRT
	for attempt in 4:
		var path := _wide_route(grid, from_cells, to_cells)
		if path.is_empty():
			return
		var touched := false
		for a: Vector2i in path:
			var cells := grid.footprint(a, 3)
			var lo := 99
			for c in cells:
				lo = mini(lo, grid.get_height(c))
			for c in cells:
				if grid.is_blocked(c):
					_clear_prop(grid, c)
					touched = true
				if grid.tiles[c] == Tile.WATER:
					grid.tiles[c] = ford
					touched = true
				elif grid.tiles[c] == Tile.LAVA:
					grid.tiles[c] = Tile.ROCK
					touched = true
				if grid.heights[c] > lo + 1:
					grid.heights[c] = lo + 1
					touched = true
		if not touched:
			return


## Trayecto más barato de anclas de huella 3 entre los bandos (vacío si ya se puede pasar sin tocar nada).
## Coste: 1 por paso, más lo que habría que cambiar (obstáculos, agua, cuestas dentro de la huella o
## escalones de más de 1 con la anterior).
static func _wide_route(grid: BoardGrid, from_cells: Array[Vector2i], to_cells: Array[Vector2i]) -> Array[Vector2i]:
	var targets := {}
	for c in to_cells:
		targets[c] = true
	var penalty := func(a: Vector2i) -> int:
		var cells := grid.footprint(a, 3)
		var p := 0
		var lo := 99
		var hi := -99
		for c in cells:
			if not grid.is_inside(c):
				return -1
			if grid.is_blocked(c):
				p += 6
			if _liquid(grid.tiles[c]):
				p += 6
			lo = mini(lo, grid.get_height(c))
			hi = maxi(hi, grid.get_height(c))
		return p + (8 if hi - lo > 1 else 0)
	var cost := {}
	var changes := {}  # penalización acumulada: 0 si el trayecto ya es transitable tal cual
	var prev := {}
	var frontier: Array[Vector2i] = []
	for a in from_cells:
		var p: int = penalty.call(a)
		if p >= 0:
			cost[a] = p
			changes[a] = p
			frontier.append(a)
	while not frontier.is_empty():
		frontier.sort_custom(func(x: Vector2i, y: Vector2i) -> bool: return cost[x] < cost[y])
		var a: Vector2i = frontier.pop_front()
		if grid.footprint(a, 3).any(func(c: Vector2i) -> bool: return targets.has(c)):
			if changes[a] == 0:
				return []
			var path: Array[Vector2i] = [a]
			while prev.has(path[-1]):
				path.append(prev[path[-1]])
			return path
		for n in grid.neighbors(a):
			var p: int = penalty.call(n)
			if p < 0:
				continue
			var dh := grid.footprint_height(grid.footprint(n, 3)) - grid.footprint_height(grid.footprint(a, 3))
			var extra := p + (8 if dh > 1 or dh < -2 else 0)
			var total: int = cost[a] + 1 + extra
			if total < cost.get(n, 1 << 30):
				if not cost.has(n):
					frontier.append(n)
				cost[n] = total
				changes[n] = changes[a] + extra
				prev[n] = a
	return []


## Si un Pokémon que no puede entrar al agua (ni a la lava) no tiene forma de llegar al otro bando, abre un
## vado por el cruce más corto (el que pisa menos), con el suelo propio del bioma (roca sobre la lava) y sin
## obstáculos.
static func _ensure_dry_path(grid: BoardGrid, from_cells: Array[Vector2i], to_cells: Array[Vector2i], kind: Kind) -> void:
	if from_cells.is_empty() or to_cells.is_empty() or _connected(grid, from_cells, to_cells, true):
		return
	var cost := {}
	var prev := {}
	var frontier: Array[Vector2i] = []
	for c in from_cells:
		cost[c] = 0
		frontier.append(c)
	var targets := {}
	for c in to_cells:
		targets[c] = true
	var goal := Vector2i(-1, -1)
	while not frontier.is_empty():
		frontier.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return cost[a] < cost[b])
		var c: Vector2i = frontier.pop_front()
		if targets.has(c):
			goal = c
			break
		for n in grid.neighbors(c):
			var dh := grid.get_height(n) - grid.get_height(c)
			if dh > 1 or dh < -2:
				continue
			var step := 20 if _liquid(grid.tiles[n]) else 5 if grid.is_blocked(n) else 1
			if cost[c] + step < cost.get(n, INF):
				if not cost.has(n):
					frontier.append(n)
				cost[n] = cost[c] + step
				prev[n] = c
	var ford := default_tile(kind)
	if ford == Tile.GRASS:
		ford = Tile.DIRT
	var c := goal
	while prev.has(c):
		if grid.tiles[c] == Tile.WATER:
			grid.tiles[c] = ford
		elif grid.tiles[c] == Tile.LAVA:
			grid.tiles[c] = Tile.ROCK  # lava enfriada
		if grid.is_blocked(c):
			_clear_prop(grid, c)
		c = prev[c]


## Quita el obstáculo de `c`; si es parte de un avión (3×3), quita el avión entero.
static func _clear_prop(grid: BoardGrid, c: Vector2i) -> void:
	if grid.props[c] in [Prop.PLANE, Prop.PLANE_PART]:
		for a in grid.all_cells():
			if grid.props[a] == Prop.PLANE and c in grid.footprint(a, 3):
				for p in grid.footprint(a, 3):
					if grid.is_inside(p):
						grid.props[p] = Prop.NONE
	grid.props[c] = Prop.NONE


## Agua o lava: lo que no pisan los Pokémon de Roca, Acero o Tierra (agua) o los que no son de Fuego (lava).
static func _liquid(tile: int) -> bool:
	return tile == Tile.WATER or tile == Tile.LAVA


## ¿Hay camino de `from_cells` a `to_cells` con salto 1? Con `dry`, sin pisar agua ni lava.
static func _connected(grid: BoardGrid, from_cells: Array[Vector2i], to_cells: Array[Vector2i], dry := false) -> bool:
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
			if seen.has(n) or grid.is_blocked(n) or dry and _liquid(grid.tiles[n]):
				continue
			var dh := grid.get_height(n) - grid.get_height(c)
			if dh > 1 or dh < -2:
				continue
			seen[n] = true
			frontier.append(n)
	return false

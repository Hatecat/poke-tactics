class_name MapData
extends Resource
## Escenario guardable: tablero, zonas de despliegue y rivales colocados.
## Lo crea el editor de escenarios y lo usará el modo historia.

@export var map_name := "Nuevo escenario"
@export var topology := BoardGrid.Topology.SQUARE
@export var biome := Biome.Kind.MEADOW
@export var width := 20
@export var height := 20
@export var heights := PackedInt32Array()
@export var tiles := PackedByteArray()
@export var props := PackedByteArray()
@export var player_zone: Array[Vector2i] = []
@export var enemy_zone: Array[Vector2i] = []
## Rivales fijos: [{"species": "onix", "moves": ["rockthrow", ...], "cell": Vector2i(3, 2)}].
## Si está vacío, el rival se genera al azar dentro de enemy_zone.
@export var enemies: Array[Dictionary] = []


func to_grid() -> BoardGrid:
	var grid := BoardGrid.new(topology, width, height)
	grid.biome = biome
	for c in grid.all_cells():
		var i := c.y * width + c.x
		if i < heights.size():
			grid.heights[c] = heights[i]
			grid.tiles[c] = tiles[i]
			grid.props[c] = props[i]
	return grid


func store_grid(grid: BoardGrid) -> void:
	topology = grid.topology
	biome = grid.biome
	width = grid.width
	height = grid.height
	heights.resize(width * height)
	tiles.resize(width * height)
	props.resize(width * height)
	for c in grid.all_cells():
		var i := c.y * width + c.x
		heights[i] = grid.get_height(c)
		tiles[i] = grid.tiles.get(c, 0)
		props[i] = grid.props.get(c, 0)


## Zonas por defecto: las `rows` filas inferiores para el jugador y las superiores para el rival.
static func default_zone(w: int, h: int, team: int, rows := 4) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in h:
		for x in w:
			if (team == 0 and y >= h - rows) or (team == 1 and y < rows):
				cells.append(Vector2i(x, y))
	return cells

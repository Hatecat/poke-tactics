class_name BoardView
extends Node3D
## Dibuja las casillas de una BoardGrid (suelo, laterales, detalles y obstáculos) y gestiona los resaltados.
## La vegetación y el agua se mueven con el viento (TerrainFx); `set_wind` cambia su fuerza según el clima.

const TILE_GAP := 0.04
const BASE_THICKNESS := 0.25
const TOP_THICKNESS := 0.06
## Resaltado del movimiento sobre suelos azules (agua, hielo...), donde el azul no se ve.
const HIGHLIGHT_ON_BLUE := Color(0.22, 0.88, 0.36)

var grid: BoardGrid
## Bioma del que se toma el aspecto (Test se ve como la Pradera: `Biome.look`).
var _look := Biome.Kind.MEADOW
## En combate, las piezas repetidas de las casillas (caras de arriba, laterales y detalles del suelo) se
## agrupan en MultiMesh: se ven igual y se dibujan en muchas menos llamadas. El editor lo deja apagado
## para poder rehacer casillas sueltas (`refresh_cell`).
var batching := false
## Lado (en casillas) de cada zona del tablero en que se agrupan: cada cascada de sombra y la cámara solo
## dibujan las zonas que ven.
const CHUNK := 5
## Combate a pantalla completa: campo de adorno alrededor del tablero para que el mapa llene la pantalla sin
## vacío en los bordes. Solo es decorado: sin colisión ni resaltado y fuera de la
## lógica del tablero (`grid` no lo guarda).
var scenery := false
var _building_scenery := false
var _city_variants := {}  # edificios del campo de adorno ya hechos: clave -> [altura, [[malla, material]...]]
## Relieve del campo de adorno (biomas naturales): una malla de terreno sin colisión sustituye al suelo llano
## de fuera, con dunas, lomas, laderas o paredes de roca según el bioma. `_relief_at` da la altura de cada
## casilla de fuera, para asentar en ella sus árboles y rocas.
var _relief_on := false
var _relief_at := {}
var _relief_tiles := {}
var _relief_flat := {}
var _relief_noise: FastNoiseLite
var _relief_ridge: FastNoiseLite
## Biomas con relieve fuera del tablero: todos menos los interiores y urbanos (Gimnasio, Ciudad, Laboratorio,
## Estudio, Librería y Aeropuerto siguen llanos). El Test toma el aspecto de la Pradera.
const RELIEF_KINDS := [Biome.Kind.MEADOW, Biome.Kind.FOREST, Biome.Kind.MOUNTAIN, Biome.Kind.DESERT,
	Biome.Kind.LAKE, Biome.Kind.SNOW, Biome.Kind.CAVE, Biome.Kind.SWAMP, Biome.Kind.VOLCANO, Biome.Kind.BEACH,
	Biome.Kind.CEMETERY, Biome.Kind.UNDERWATER]
## Resolución de la malla de relieve (vértices por casilla y lado).
const RELIEF_RES := 2
## Pendiente máxima del relieve vista desde el tablero (alto / distancia al borde): con la cámara a 35°,
## por debajo de ~0,7 una loma nunca tapa las casillas, se gire como se gire la vista.
const RELIEF_SLOPE := 0.55
## Mallas de las caras de arriba y los laterales agrupados (las mismas en todas las zonas).
var _batch_meshes: Array[Mesh] = []
## Alcance del campo de adorno, en veces la media diagonal del tablero: cubre el encuadre de `CameraRig`
## (que deja sitio al panel de la izquierda) en pantallas de 4:3 a 21:9.
const SCENERY_REACH := 2.3
## Radio del campo de adorno alrededor del centro del tablero (0 sin campo): hasta dónde puede ver la cámara.
var scenery_reach := 0.0
## Zonas del campo de adorno, más grandes que las del tablero: sus árboles tienen muchos tonos de hoja y con
## zonas pequeñas saldrían muchos grupos de pocas piezas.
const SCENERY_CHUNK := 16
## Cuánto se oscurecen los colores del campo de adorno justo fuera del borde (0-1) y a lo lejos, donde casi se
## pierde en la sombra, como el bosque que rodea la zona de combate en la referencia del usuario. Árboles y
## rocas, con una sola sombra (cada tono más sería un grupo más que dibujar).
const SCENERY_SHADE := 0.5
const SCENERY_SHADE_FAR := 0.8
const SCENERY_PROP_SHADE := 0.7
## Campo de adorno de cada bioma: densidad de obstáculos (0-1, en las arboledas más lejanas) y los que lleva,
## con su peso: el paisaje que rodearía ese campo de batalla (bosque alrededor del claro, manzanas de casas
## junto a las calles, maquinaria en el laboratorio, sombrillas y palmeras en la playa...). Sin los que llevan
## luces (focos, cristales): cientos de ellos costarían demasiado.
const SCENERY_PROPS := {
	Biome.Kind.MEADOW: [0.3, [Biome.Prop.TREE, 8], [Biome.Prop.BOULDER, 1]],
	Biome.Kind.FOREST: [0.55, [Biome.Prop.PINE, 5], [Biome.Prop.TREE, 4], [Biome.Prop.BOULDER, 1]],
	Biome.Kind.MOUNTAIN: [0.35, [Biome.Prop.BOULDER, 5], [Biome.Prop.PINE, 4]],
	Biome.Kind.DESERT: [0.2, [Biome.Prop.CACTUS, 5], [Biome.Prop.BOULDER, 4], [Biome.Prop.PALM, 1]],
	Biome.Kind.LAKE: [0.3, [Biome.Prop.TREE, 6], [Biome.Prop.PINE, 2], [Biome.Prop.BOULDER, 2]],
	Biome.Kind.SNOW: [0.35, [Biome.Prop.PINE, 7], [Biome.Prop.BOULDER, 3]],
	Biome.Kind.CAVE: [0.35, [Biome.Prop.STALAGMITE, 7], [Biome.Prop.BOULDER, 3]],
	Biome.Kind.SWAMP: [0.35, [Biome.Prop.DEAD_TREE, 5], [Biome.Prop.TREE, 4], [Biome.Prop.BOULDER, 1]],
	Biome.Kind.CITY: [0.4, [Biome.Prop.BUILDING, 6], [Biome.Prop.TREE, 3], [Biome.Prop.LAMP, 1]],
	Biome.Kind.VOLCANO: [0.25, [Biome.Prop.BOULDER, 8], [Biome.Prop.DEAD_TREE, 2]],
	Biome.Kind.BEACH: [0.2, [Biome.Prop.PALM, 6], [Biome.Prop.PARASOL, 2], [Biome.Prop.BOULDER, 2]],
	Biome.Kind.CEMETERY: [0.35, [Biome.Prop.GRAVE, 6], [Biome.Prop.DEAD_TREE, 3], [Biome.Prop.PINE, 1]],
	Biome.Kind.AIRPORT: [0.15, [Biome.Prop.TREE, 6], [Biome.Prop.BOULDER, 2], [Biome.Prop.LAMP, 2]],
	Biome.Kind.UNDERWATER: [0.3, [Biome.Prop.CORAL, 6], [Biome.Prop.BOULDER, 2], [Biome.Prop.STALAGMITE, 2]],
}
## Estanterías: medio fondo, baldas y su separación; hileras de libros distintas (`_book_row`) y su medio
## ancho; colores de las tapas (piel, tela y papel de biblioteca antigua).
const SHELF_DEPTH := 0.29
const SHELF_LEVELS := 4
const SHELF_STEP := 0.335
const BOOK_ROWS := 16
const BOOK_ROW_HALF := 0.45
const BOOK_COLORS := [Color(0.45, 0.1, 0.1), Color(0.34, 0.08, 0.08), Color(0.12, 0.3, 0.18), Color(0.1, 0.16, 0.35),
	Color(0.62, 0.44, 0.16), Color(0.6, 0.47, 0.32), Color(0.34, 0.2, 0.11), Color(0.09, 0.08, 0.09),
	Color(0.82, 0.77, 0.64), Color(0.12, 0.33, 0.36), Color(0.3, 0.13, 0.28), Color(0.52, 0.3, 0.14)]
## Edificios distintos en el campo de adorno de la Ciudad (`_scenery_building`).
const CITY_VARIANTS := 40
## Biomas cuyo campo de adorno funde sus obstáculos por zonas (`_merge_baked`): cientos de muebles o casas.
const SCENERY_MERGED := [Biome.Kind.LIBRARY, Biome.Kind.CITY]
## Biblioteca: cada cuántas casillas cortan las hileras de estanterías del campo de adorno.
const LIBRARY_BAY := 7
## Muebles que se unen con los iguales de al lado (al cambiar uno en el editor se rehacen los vecinos).
const JOINED_PROPS := [Biome.Prop.SHELF, Biome.Prop.DESK]
## Suelos que, si salen por el borde a ras de suelo, siguen fuera del tablero (ríos, caminos, lava...).
const SCENERY_TRAILS := [Biome.Tile.WATER, Biome.Tile.DIRT, Biome.Tile.SAND, Biome.Tile.LAVA, Biome.Tile.ROAD,
	Biome.Tile.MUD, Biome.Tile.ICE]
## Cuántas casillas a lo sumo se apartan de su línea los ríos y senderos del campo de adorno.
const SCENERY_BEND := 6.0
## Gimnasio: casillas alrededor del tablero que ocupa el estadio (GymDressing): ahí no va campo de adorno.
const SCENERY_GYM_GAP := 7
## Casillas del campo de adorno junto al tablero que llevan hierba y flores.
const SCENERY_GRASS := 3
var _cells := {} # Vector2i -> Node3D con todo lo de esa casilla
var _overlays := {} # Vector2i -> MeshInstance3D
var _mats := {} # Color -> StandardMaterial3D
var _overlay_mats := {} # Color -> StandardMaterial3D
var _marks_root: Node3D
var _traps_root: Node3D
var _live_mats := {} # clave -> ShaderMaterial con viento (vegetación, agua)
var _side_mats := {}
var _tint_noise := FastNoiseLite.new()
var _grass_noise := FastNoiseLite.new()  # zonas de hierba alta / corta
var _crystal_lights: Array[OmniLight3D] = []  # laten al ritmo del brillo de sus cristales
var _wind := 1.0
var _wet := 0.0
var _wet_tween: Tween
var _puddles: Array[MeshInstance3D] = []
var _hail := 0.0
var _hail_tween: Tween
var _hail_piles: Array[MeshInstance3D] = []
var _hail_bounce: CPUParticles3D
## Agua: algo más baja que la tierra, para que se vean las orillas.
const WATER_DROP := 0.1
const CRYSTAL_LIGHT := 1.1
## Detalles del suelo con altura suficiente para dar sombra (el césped corto y los guijarros no).
const SHADOW_DECOR: PackedStringArray = ["tallgrass", "fern", "reeds", "shrub", "mushrooms", "glowshroom", "stones",
	"flowers"]  # energía media de la luz de cada drusa de cristal
## Color del lateral justo bajo cada suelo (la roca madre de debajo depende del bioma).
const SIDE_TOP := {
	Biome.Tile.SAND: Color(0.76, 0.62, 0.4), Biome.Tile.ROCK: Color(0.5, 0.48, 0.45),
	Biome.Tile.SNOW: Color(0.78, 0.82, 0.9), Biome.Tile.ICE: Color(0.6, 0.74, 0.86),
	Biome.Tile.CAVE: Color(0.3, 0.27, 0.25), Biome.Tile.WATER: Color(0.12, 0.3, 0.5),
	Biome.Tile.LAVA: Color(0.25, 0.12, 0.08),
}
const BEDROCK := {
	Biome.Kind.MEADOW: Color(0.38, 0.33, 0.28), Biome.Kind.FOREST: Color(0.32, 0.27, 0.22),
	Biome.Kind.MOUNTAIN: Color(0.36, 0.35, 0.34), Biome.Kind.DESERT: Color(0.62, 0.42, 0.28),
	Biome.Kind.LAKE: Color(0.38, 0.33, 0.28), Biome.Kind.SNOW: Color(0.42, 0.43, 0.47),
	Biome.Kind.CAVE: Color(0.16, 0.15, 0.15), Biome.Kind.GYM: Color(0.4, 0.4, 0.45),
	Biome.Kind.SWAMP: Color(0.27, 0.23, 0.17), Biome.Kind.CITY: Color(0.42, 0.41, 0.42),
	Biome.Kind.LAB: Color(0.36, 0.38, 0.42), Biome.Kind.VOLCANO: Color(0.14, 0.11, 0.1),
	Biome.Kind.BEACH: Color(0.62, 0.5, 0.36), Biome.Kind.CEMETERY: Color(0.24, 0.21, 0.19),
	Biome.Kind.STUDIO: Color(0.1, 0.1, 0.11), Biome.Kind.LIBRARY: Color(0.3, 0.2, 0.13),
	Biome.Kind.AIRPORT: Color(0.36, 0.33, 0.3), Biome.Kind.UNDERWATER: Color(0.12, 0.16, 0.2),
}


func build(p_grid: BoardGrid) -> void:
	grid = p_grid
	_look = Biome.look(grid.biome)
	for child in get_children():
		child.queue_free()
	_cells.clear()
	_overlays.clear()
	_puddles.clear()
	_hail_piles.clear()
	_crystal_lights.clear()
	_hail_bounce = null
	_caustic_mesh = null  # su forma depende de la topología
	_batch_meshes.clear()
	_tint_noise.seed = 7
	_tint_noise.frequency = 0.18
	_grass_noise.seed = grid.width * 131 + grid.height * 17 + _look
	_grass_noise.frequency = 0.22
	for c in grid.all_cells():
		_build_cell(c)
	if batching:
		_batch(_cells.values())
	if scenery:
		_build_scenery()
	if _look == Biome.Kind.GYM:
		var dressing := GymDressing.new()
		add_child(dressing)
		dressing.setup(grid)
	var w0 := grid.to_world(Vector2i.ZERO)
	var w1 := grid.to_world(Vector2i(grid.width - 1, grid.height - 1))
	var amb := TerrainFx.ambient(_look, Vector3((w0.x + w1.x) * 0.5, 0.0, (w0.z + w1.z) * 0.5),
		Vector2(absf(w1.x - w0.x) + 1.0, absf(w1.z - w0.z) + 1.0))
	if amb:
		add_child(amb)
		amb.emitting = true
	_marks_root = Node3D.new()
	add_child(_marks_root)
	_traps_root = Node3D.new()
	add_child(_traps_root)


## Capa persistente de casillas teñidas (zonas, terreno): {id: [celdas, color]}.
func set_marks(marks: Dictionary) -> void:
	for child in _marks_root.get_children():
		child.queue_free()
	for id: String in marks:
		var cells: Array = marks[id][0]
		var color: Color = marks[id][1]
		for c: Vector2i in cells:
			var top := grid.to_world(c)
			var m := MeshInstance3D.new()
			m.mesh = _tile_mesh(0.01, 0.02)
			m.position = Vector3(top.x, top.y + 0.006, top.z)
			m.material_override = _overlay_material(color)
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_marks_root.add_child(m)


## Trampas en el suelo: {celda: {"spikes", "toxic", "rocks"}}.
func set_traps(traps: Dictionary) -> void:
	for child in _traps_root.get_children():
		child.queue_free()
	for c: Vector2i in traps:
		var t: Dictionary = traps[c]
		var node := Node3D.new()
		node.position = grid.to_world(c)
		_traps_root.add_child(node)
		var spots := [Vector3(-0.2, 0, -0.15), Vector3(0.2, 0, -0.1), Vector3(0, 0, 0.2)]
		for i in t.spikes:
			_part(node, _cyl(0.0, 0.07, 0.22, 6), spots[i] + Vector3.UP * 0.11, Color(0.75, 0.75, 0.78))
		for i in t.toxic:
			_part(node, _cyl(0.0, 0.07, 0.22, 6), spots[2 - i] * 0.6 + Vector3.UP * 0.11, Color(0.65, 0.3, 0.8))
		if t.rocks:
			for i in 2:
				var rock := _part(node, _unit_box(), Vector3(-0.15 + i * 0.3, 0.55 + i * 0.1, 0), Color(0.55, 0.48, 0.4))
				rock.scale = Vector3.ONE * 0.16
				rock.rotation = Vector3(0.5, 0.8 * i, 0.3)


## La hierba y las plantas se apartan alrededor de cada Pokémon (grupo "units"), para que no lo tapen, y
## la luz de los cristales late.
func _process(_delta: float) -> void:
	var pushers := PackedVector4Array()
	pushers.resize(12)
	var i := 0
	for u: Node3D in get_tree().get_nodes_in_group("units"):
		if i >= 12:
			break
		if not u.visible or not u.is_inside_tree():
			continue
		var size: int = u.data.size if u.get("data") else 1
		var p := u.global_position
		pushers[i] = Vector4(p.x, p.y, p.z, 0.3 + 0.32 * size)
		i += 1
	for key: String in _live_mats:
		if key.begins_with("decor_"):
			_live_mats[key].set_shader_parameter("pushers", pushers)
	var t := Time.get_ticks_msec() / 1000.0
	for light in _crystal_lights:
		if not is_instance_valid(light) or not light.is_inside_tree():
			continue
		var p := light.global_position
		light.light_energy = CRYSTAL_LIGHT * (1.0 + 0.35 * sin(t * 2.2 + p.x * 1.3 + p.z))


## Junta las piezas marcadas con "batch" de todas las casillas en una MultiMesh por zona, malla, material y
## sombra, con la posición de cada una y lo que cada shader necesita por pieza: el color de la losa
## (caras de arriba), la altura de la cara de arriba (laterales, que van en una caja de alto 1 escalada)
## y la base y altura con viento (detalles del suelo). Los originales se borran.
func _batch(roots: Array) -> void:
	var groups := {}
	_collect(roots, groups, CHUNK)
	_emit(groups)


## Saca de `roots` las piezas marcadas con "batch" y las apunta en `groups` (clave: malla, material, sombra y
## zona de `chunk` casillas -> [[Transform3D, Color custom, Color color]]).
func _collect(roots: Array, groups: Dictionary, chunk: int) -> void:
	if _batch_meshes.is_empty():
		_batch_meshes = [_tile_mesh(TOP_THICKNESS, 0.0), _tile_mesh(1.0, 0.0)]
	var top_mesh := _batch_meshes[0]
	var side_mesh := _batch_meshes[1]
	for root: Node3D in roots:
		for mi in root.get_children():
			if not (mi is MeshInstance3D and mi.has_meta("batch")):
				continue
			var mesh: Mesh = mi.mesh
			var mat: Material = mi.material_override
			var custom := Color(0, 0, 0, 0)
			var color := Color.WHITE
			var xf: Transform3D = root.transform * mi.transform
			match mi.get_meta("batch"):
				"top":
					mesh = top_mesh
					color = mi.get_meta("color")
					mat = _instanced_top_material(mat, mi.has_meta("matte"))
				"side":
					mesh = side_mesh
					custom.r = mi.get_meta("top_y")
					xf = Transform3D(xf.basis.scaled(Vector3(1, mi.get_meta("thickness"), 1)), xf.origin)
					mat = _instanced_material(mat, "side")
				"decor":
					var sb: Vector2 = mi.get_meta("sway_base")
					custom = Color(sb.x, sb.y, 0, 0)
					if mat is ShaderMaterial:
						mat = _instanced_material(mat, "decor")
			var cell: Vector2i = root.get_meta("cell")
			# División hacia abajo: el campo de adorno tiene celdas negativas. Las hileras de libros van todas
			# juntas (una MultiMesh por variante): por zonas serían cientos de llamadas para unas pocas cajas.
			var zone := Vector2i.ZERO if mi.get_meta("batch") == "books" else \
				Vector2i(floori(cell.x / float(chunk)), floori(cell.y / float(chunk)))
			var key := [mesh, mat, mi.cast_shadow, zone]
			if not groups.has(key):
				groups[key] = []
			groups[key].append([xf, custom, color])
			root.remove_child(mi)
			mi.free()


## Una MultiMesh por cada grupo de `_collect`.
func _emit(groups: Dictionary) -> void:
	for key: Array in groups:
		var items: Array = groups[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = key[0]
		mm.instance_count = items.size()
		for i in items.size():
			mm.set_instance_transform(i, items[i][0])
			mm.set_instance_custom_data(i, items[i][1])
			mm.set_instance_color(i, items[i][2])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = key[1]
		mmi.cast_shadow = key[2]
		add_child(mmi)


## Material de las caras de arriba agrupadas: el color sale de cada instancia. Los suelos lisos usan un
## StandardMaterial con color de vértice (se moja como los demás) y la piedra y la tarima su shader en modo instancia.
## `matte`: sin brillo (el campo de adorno: el reflejo del cielo aclaraba su sombra hasta un gris azulado).
func _instanced_top_material(mat: Material, matte := false) -> Material:
	if mat is ShaderMaterial:  # piedra o tarima: una sola copia de cada shader para todos los colores
		var key := "top_inst_%d" % (mat as ShaderMaterial).shader.get_instance_id()
		if not _live_mats.has(key):
			var dup := mat.duplicate() as ShaderMaterial
			dup.set_shader_parameter("instanced", true)
			_live_mats[key] = dup
		return _live_mats[key]
	var glossy: bool = (mat as StandardMaterial3D).roughness < 0.5
	var key := "top_glossy" if glossy else "top_matte" if matte else "top"
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		if matte:
			m.metallic_specular = 0.0
			m.roughness = 1.0
		if glossy:
			m.roughness = 0.15
			m.metallic_specular = 0.9
		_mats[key] = m
	return _mats[key]


## Copia de un material con shader en modo instancia, registrada donde corresponde para que siga
## recibiendo viento, lluvia y los Pokémon que apartan la hierba.
func _instanced_material(mat: ShaderMaterial, kind: String) -> ShaderMaterial:
	if mat.has_meta("instanced"):
		return mat.get_meta("instanced")
	var dup := mat.duplicate() as ShaderMaterial
	dup.set_shader_parameter("instanced", true)
	mat.set_meta("instanced", dup)
	if kind == "side":
		_side_mats["%d_inst" % _side_mats.size()] = dup
	else:
		for key: String in _live_mats.keys():
			if _live_mats[key] == mat:
				_live_mats[key + "_inst"] = dup
	return dup


## Reconstruye una casilla (el editor la llama al cambiar altura, suelo u obstáculo).
func refresh_cell(c: Vector2i) -> void:
	for n: Vector2i in [c] + Array(grid.neighbors(c)):
		if n != c and grid.props.get(n, Biome.Prop.NONE) not in JOINED_PROPS:
			continue
		if _cells.has(n):
			_cells[n].queue_free()
		_build_cell(n)


## Fuerza del viento (1 = brisa normal): mece más o menos árboles, hierba y agua.
func set_wind(strength: float) -> void:
	_wind = strength
	_set_dune_dust(strength >= 2.0)
	for m: ShaderMaterial in _live_mats.values():
		m.set_shader_parameter("wind", strength)


var _dune_dust: CPUParticles3D


## Con viento muy fuerte, las crestas de arena (casillas de arena con un desnivel a sotavento) sueltan
## polvo que el viento arrastra a ras de suelo.
func _set_dune_dust(on: bool) -> void:
	if _dune_dust:
		_dune_dust.queue_free()
		_dune_dust = null
	if not on:
		return
	var points := PackedVector3Array()
	for c in grid.all_cells():
		if grid.tiles.get(c, 0) != Biome.Tile.SAND:
			continue
		var crest := false
		for n in grid.neighbors(c):
			crest = crest or grid.get_height(n) < grid.get_height(c)
		if crest or hash(c) % 5 == 0:
			points.append(grid.to_world(c) + Vector3.UP * 0.05)
	if points.is_empty():
		return
	var p := CPUParticles3D.new()
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
	p.emission_points = points
	p.amount = mini(points.size() * 3, 400)
	p.lifetime = 1.6
	p.preprocess = 1.6
	p.direction = Vector3(1, 0.35, 0.3)
	p.spread = 15.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0, -0.6, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.6
	p.color_ramp = TerrainFx._fade_ramp()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.35, 0.2)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_texture = WeatherFx._soft_texture(false)
	quad.material = mat
	p.mesh = quad
	p.color = Color(0.92, 0.78, 0.52, 0.5)
	add_child(p)
	p.emitting = true
	_dune_dust = p


## Lluvia: el suelo, los laterales y la vegetación se van oscureciendo y brillan (mojados), aparecen charcos
## y las gotas hacen ondas en el agua. Al parar, se seca poco a poco. `time` = segundos de la transición.
func set_rain(on: bool, time := 1.5) -> void:
	if _wet_tween:
		_wet_tween.kill()
	_wet_tween = create_tween()
	_wet_tween.tween_method(_apply_wet, _wet, 1.0 if on else 0.0, time)


## Granizo: las bolitas rebotan al chocar contra el suelo, se van acumulando en las casillas y salpican el
## agua (las mismas ondas que la lluvia). Al parar, lo acumulado se derrite poco a poco.
func set_hail(on: bool, time := 2.5) -> void:
	if _hail_tween:
		_hail_tween.kill()
	_hail_tween = create_tween()
	_hail_tween.tween_method(_apply_hail, _hail, 1.0 if on else 0.0, time)
	if _hail_bounce:
		_hail_bounce.emitting = on
	elif on:
		_hail_bounce = _bounce_particles()
		if _hail_bounce:
			add_child(_hail_bounce)
			_hail_bounce.emitting = true


func _apply_hail(h: float) -> void:
	_hail = h
	for key: String in _live_mats:
		if key.begins_with("water") or key == "puddle":
			_live_mats[key].set_shader_parameter("rain", maxf(_wet, h))
	for p in _hail_piles:
		if is_instance_valid(p):
			p.visible = h > 0.02
			p.scale = Vector3.ONE * h


## Rebotes: trocitos de hielo que saltan desde lo alto de las casillas de tierra.
func _bounce_particles() -> CPUParticles3D:
	var points := PackedVector3Array()
	for c in grid.all_cells():
		if grid.tiles.get(c, 0) == Biome.Tile.WATER or grid.is_blocked(c):
			continue
		var top := grid.to_world(c)
		for i in 2:
			var h := hash(c * 3 + Vector2i(i, 7))
			points.append(top + Vector3(float(h % 80) / 100.0 - 0.4, 0.03, float(h / 80 % 80) / 100.0 - 0.4))
	if points.is_empty():
		return null
	var p := CPUParticles3D.new()
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
	p.emission_points = points
	p.amount = 260
	p.lifetime = 0.45
	p.direction = Vector3.UP
	p.spread = 35.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.2
	p.gravity = Vector3(0, -9.0, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var ball := SphereMesh.new()
	ball.radius = 0.035
	ball.height = 0.07
	ball.radial_segments = 6
	ball.rings = 3
	ball.material = WeatherFx.ice_material()
	p.mesh = ball
	return p


func _apply_wet(w: float) -> void:
	_wet = w
	for m: StandardMaterial3D in _mats.values():
		if not m.has_meta("dry"):
			m.set_meta("dry", [m.albedo_color, m.roughness])
		var dry: Array = m.get_meta("dry")
		var col: Color = dry[0]
		m.albedo_color = col.darkened(0.3 * w)
		m.roughness = lerpf(dry[1], minf(dry[1], 0.72), w)
	for key: String in _live_mats:
		_live_mats[key].set_shader_parameter("rain" if key.begins_with("water") or key == "puddle" else "wet",
			maxf(w, _hail) if key.begins_with("water") or key == "puddle" else w)
	for m: ShaderMaterial in _side_mats.values():
		m.set_shader_parameter("wet", w)
	for p in _puddles:
		if is_instance_valid(p):
			p.visible = w > 0.02
			p.scale = Vector3(w, 1.0, w)


func clear_highlights() -> void:
	for overlay: MeshInstance3D in _overlays.values():
		overlay.visible = false


## `selected`: la casilla que señala el jugador (destino, objetivo), con su propio estilo.
func highlight(cells: Array[Vector2i], color: Color, selected := false) -> void:
	for c in cells:
		var overlay: MeshInstance3D = _overlays.get(c)
		if overlay:
			overlay.material_override = _highlight_material(_contrast(c, color), selected)
			overlay.visible = true


## Los resaltados azules no se distinguen sobre suelos azules: el del movimiento pasa a verde sobre el agua
## y los suelos azules (hielo, líneas del laboratorio, gimnasio de Agua...); el del despliegue, a un tono
## claro (agua) u oscuro (hielo y nieve). El resto se hace más opaco sobre el agua y los suelos claros, que
## si no lo tiñen, y el verde también sobre la hierba, que es del mismo tono.
func _contrast(c: Vector2i, color: Color) -> Color:
	var tile: int = grid.tiles.get(c, Biome.Tile.GRASS)
	if color.b > color.r + 0.3 and color.b >= color.g:
		if color.a >= 0.4 and (tile == Biome.Tile.WATER or _bluish(_base_color(tile))):
			return Color(HIGHLIGHT_ON_BLUE, maxf(color.a, 0.78))
		match tile:
			Biome.Tile.WATER:
				return Color(0.85, 1.0, 1.0, maxf(color.a, 0.6))
			Biome.Tile.ICE, Biome.Tile.SNOW:
				return Color(0.1, 0.3, 0.95, maxf(color.a, 0.6))
		return color
	if color.a < 0.4:  # alcance de las Poké Balls: un velo, no una opción
		return color
	match tile:
		Biome.Tile.WATER:
			return Color(color, maxf(color.a, 0.82))
		Biome.Tile.SAND, Biome.Tile.SNOW, Biome.Tile.ICE:
			return Color(color, maxf(color.a, 0.74))
		Biome.Tile.GRASS when color.g > color.r + 0.3 and color.g > color.b + 0.3:
			return Color(color, maxf(color.a, 0.75))
	return color


## Suelo de color azul (o cian): ahí un resaltado azul no se ve.
static func _bluish(color: Color) -> bool:
	return color.h > 0.45 and color.h < 0.72 and color.s > 0.25


## Campo de adorno: un llano del suelo del bioma alrededor del tablero, con el agua, los caminos y la lava que
## salen por el borde a ras de suelo, y sus obstáculos (árboles, cactus, estanterías...) más tupidos cuanto
## más lejos, como el bosque que rodea un claro. Se monta con las
## mismas piezas que las casillas (se mece con el viento y se moja con la lluvia), pero más oscuro y sin el
## ajedrezado, para que se vea dónde acaba el tablero: lo que está alto en el borde queda como un escalón.
func _build_scenery() -> void:
	var w0 := grid.to_world(Vector2i.ZERO)
	var w1 := grid.to_world(Vector2i(grid.width - 1, grid.height - 1))
	var center := (w0 + w1) * 0.5
	var reach := Vector2(w1.x - w0.x + 1.0, w1.z - w0.z + 1.0).length() * 0.5 * SCENERY_REACH
	scenery_reach = reach - 1.0  # el borde del círculo es de casillas enteras
	var margin := ceili(reach)
	var noise := FastNoiseLite.new()
	noise.seed = grid.width * 7 + grid.height * 3
	noise.frequency = 0.15
	var extra := {}  # zona -> [celdas]
	var coast := _beach_coast(margin) if _look == Biome.Kind.BEACH else {}
	var bends := FastNoiseLite.new()  # curvas de los ríos y senderos al salir del tablero
	bends.seed = grid.width * 5 + grid.height * 13
	bends.frequency = 0.045  # curvas largas: con casillas, un giro brusco se ve a escalones
	for y in range(-margin, grid.height + margin):
		for x in range(-margin, grid.width + margin):
			var c := Vector2i(x, y)
			if grid.is_inside(c):
				continue
			var w := grid.to_world(c)
			if Vector2(w.x - center.x, w.z - center.z).length() > reach:
				continue
			var far := _outside(c)
			if _look == Biome.Kind.GYM and far <= SCENERY_GYM_GAP:
				continue
			var ground := Biome.default_tile(_look)
			var tile := ground
			if not coast.is_empty():
				# Playa: el mar abierto sigue la orilla del tablero en vez de un río recto
				var d: int = x if coast.left else grid.width - 1 - x
				tile = Biome.Tile.WATER if d < coast.line[y] else ground
			else:
				var trail := _scenery_trail(c, bends)
				if trail >= 0:
					tile = trail
			var prop := Biome.Prop.NONE
			var h := hash(c)
			var props: Array = SCENERY_PROPS.get(_look, [])
			var layout := [] if _look == Biome.Kind.LIBRARY else _scenery_layout(c, far, tile, ground)
			if tile == ground and far >= 2 and _look == Biome.Kind.LIBRARY:
				prop = _library_scenery(x, y, h)  # en hileras, como la librería del tablero
			elif not layout.is_empty():
				tile = layout[0]
				prop = layout[1]
			elif tile == ground and far >= 2 and not props.is_empty():
				var dense := clampf((far - 1) / 6.0, 0.0, 1.0) * (1.0 if noise.get_noise_2d(x, y) > -0.1 else 0.25)
				if float(h % 1000) / 1000.0 < dense * props[0]:
					prop = _pick_weighted(props, (h >> 10) % 1000 / 1000.0)
			grid.heights[c] = 0
			grid.tiles[c] = tile
			grid.props[c] = prop
			_relief_tiles[c] = tile
			var zone := Vector2i(floori(x / float(CHUNK)), floori(y / float(CHUNK)))
			if not extra.has(zone):
				extra[zone] = []
			extra[zone].append(c)
	_relief_on = _look in RELIEF_KINDS
	if _relief_on:
		_prepare_relief(reach)
	# Zona a zona, recogiendo las piezas de cada una al terminarla: con todo suelto a la vez se agotan los
	# parámetros por instancia de los shaders.
	_building_scenery = true
	var groups := {}
	for zone: Vector2i in extra:
		var roots := []
		for c: Vector2i in extra[zone]:
			_build_cell(c, true)
			roots.append(_cells[c])
		_collect(roots, groups, SCENERY_CHUNK)  # también en el editor: el campo de adorno no se edita
		if _look in SCENERY_MERGED:
			_merge_baked(roots)
	_emit(groups)
	if _relief_on:
		_build_relief(center, reach)
	_building_scenery = false
	_relief_on = false
	_relief_at.clear()
	_relief_tiles.clear()
	_relief_flat.clear()
	# Fuera de la lógica: el tablero vuelve a ser solo sus casillas.
	for zone: Vector2i in extra:
		for c: Vector2i in extra[zone]:
			grid.heights.erase(c)
			grid.tiles.erase(c)
			grid.props.erase(c)


## Relieve: distancia (en casillas) de cada casilla de fuera al agua, la lava o un sendero, que aplanan el
## terreno a su alrededor (orillas y caminos llanos), y altura de cada casilla para sus adornos.
func _prepare_relief(reach: float) -> void:
	_relief_noise = FastNoiseLite.new()
	_relief_noise.seed = grid.width * 31 + grid.height * 17 + _look
	_relief_noise.frequency = 0.05
	_relief_noise.fractal_octaves = 3
	_relief_ridge = FastNoiseLite.new()
	_relief_ridge.seed = _relief_noise.seed + 7
	_relief_ridge.frequency = 0.035
	_relief_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_relief_ridge.fractal_octaves = 3
	var ground := Biome.default_tile(_look)
	var queue: Array[Vector2i] = []
	for c: Vector2i in _relief_tiles:
		if _relief_tiles[c] != ground:
			_relief_flat[c] = 0
			queue.append(c)
	var i := 0
	while i < queue.size():  # distancia por anchura: cada casilla, la del vecino más cercano + 1
		var c := queue[i]
		i += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if _relief_tiles.has(n) and not _relief_flat.has(n):
				_relief_flat[n] = _relief_flat[c] + 1
				if _relief_flat[n] < 6:
					queue.append(n)
	for c: Vector2i in _relief_tiles:
		var w := grid.to_world(c)
		_relief_at[c] = 0.0 if _relief_tiles[c] in [Biome.Tile.WATER, Biome.Tile.LAVA, Biome.Tile.BRIDGE] \
				else maxf(_relief_height(Vector2(w.x, w.z)), 0.0)


## Altura del relieve en el punto `p` del mundo: la forma del bioma, que crece al alejarse del tablero (junto
## al borde es llano, a ras de las casillas), se aplana cerca del agua y los senderos, y se hunde en los cauces.
func _relief_height(p: Vector2) -> float:
	var d := _board_distance(p)
	var shape := 0.0
	var n := _relief_noise.get_noise_2d(p.x, p.y) * 0.5 + 0.5
	var r := _relief_ridge.get_noise_2d(p.x, p.y) * 0.5 + 0.5
	match _look:
		Biome.Kind.DESERT:
			# Dunas: crestas alargadas a lo ancho del viento, con valles entre ellas
			var u := Vector2(p.x * 0.87 + p.y * 0.5, -p.x * 0.5 + p.y * 0.87)
			var crest := 1.0 - absf(_relief_ridge.get_noise_2d(u.x * 0.7, u.y * 2.2))
			shape = (crest * crest * 0.75 + n * 0.35) * 3.4
		Biome.Kind.MOUNTAIN:
			shape = (r * 0.75 + n * 0.3) * (2.5 + d * 0.3)
		Biome.Kind.SNOW:
			shape = (n * 0.7 + r * 0.45) * 3.2
		Biome.Kind.VOLCANO:
			shape = (r * r * 0.9 + n * 0.25) * 3.6
		Biome.Kind.CAVE:
			# Paredes de roca que cierran la cueva, con salientes
			shape = smoothstep(2.5, 9.0, d) * 7.0 + (r * 0.9 + n * 0.5) * 2.2
		Biome.Kind.SWAMP:
			shape = (n * n * 0.9 + r * 0.35) * 1.8  # montículos bajos entre charcas
		Biome.Kind.BEACH:
			var u := Vector2(p.x * 0.6 + p.y * 0.8, -p.x * 0.8 + p.y * 0.6)
			shape = (1.0 - absf(_relief_ridge.get_noise_2d(u.x * 0.8, u.y * 2.0))) * 2.3 + n * 0.7
		Biome.Kind.FOREST:
			shape = (n * 0.85 + r * 0.4) * 3.6
		Biome.Kind.UNDERWATER:
			# Fondo marino: ondas de arena cerca y, más lejos, arrecifes de roca que cierran la cueva
			var ripple := sin(p.x * 1.3 + p.y * 0.6 + n * 4.0) * 0.12
			shape = ripple + n * 1.4 + smoothstep(3.0, 10.0, d) * (r * 4.0 + 2.0)
		_:  # praderas, lago, cementerio: lomas suaves
			shape = (n * 0.85 + r * 0.3) * 3.2
	var h := shape * smoothstep(0.5, 5.0, d)
	var flat := _flat_at(p)
	var radius := 4.0 if _look == Biome.Kind.BEACH else 2.5
	h *= smoothstep(0.5, radius, flat)
	h -= 0.45 * (1.0 - smoothstep(0.0, 0.9, flat)) if _wet_near(p) else 0.0
	return minf(h, RELIEF_SLOPE * maxf(d - 0.5, 0.0)) - 0.02  # algo bajo las casillas del borde: sin parpadeo


## Distancia (mundo) al rectángulo del tablero.
func _board_distance(p: Vector2) -> float:
	var w0 := grid.to_world(Vector2i.ZERO)
	var w1 := grid.to_world(Vector2i(grid.width - 1, grid.height - 1))
	var lo := Vector2(minf(w0.x, w1.x) - 0.5, minf(w0.z, w1.z) - 0.5)
	var hi := Vector2(maxf(w0.x, w1.x) + 0.5, maxf(w0.z, w1.z) + 0.5)
	return Vector2(maxf(maxf(lo.x - p.x, p.x - hi.x), 0.0), maxf(maxf(lo.y - p.y, p.y - hi.y), 0.0)).length()


## Distancia suavizada (en casillas) al agua o senderos más cercanos: media de las casillas de alrededor.
func _flat_at(p: Vector2) -> float:
	var total := 0.0
	for o in [Vector2(-0.35, -0.35), Vector2(0.35, -0.35), Vector2(-0.35, 0.35), Vector2(0.35, 0.35)]:
		var c := grid.world_to_cell(Vector3(p.x + o.x, 0.0, p.y + o.y))
		total += float(_relief_flat.get(c, 6))
	return total * 0.25


## Si lo más cercano que aplana es agua o lava (el terreno se hunde bajo su superficie) y no un sendero.
func _wet_near(p: Vector2) -> bool:
	var c := grid.world_to_cell(Vector3(p.x, 0.0, p.y))
	for d in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if _relief_tiles.get(c + d, -1) in [Biome.Tile.WATER, Biome.Tile.LAVA, Biome.Tile.BRIDGE]:
			return true
	return false


## Malla del relieve: rejilla de vértices sobre todo el campo de adorno (sin los cuadros que caen dentro del
## tablero), con el color de suelo de cada casilla de fuera y su sombra, y matices por pendiente y altura
## (roca en las laderas, crestas de duna más claras, nieve en las cumbres).
func _build_relief(center: Vector3, reach: float) -> void:
	var step := 1.0 / RELIEF_RES
	var n := ceili((reach + 1.0) / step)
	var size := n * 2 + 1
	var heights := PackedFloat32Array()
	heights.resize(size * size)
	var origin := Vector2(center.x, center.z) - Vector2(n, n) * step
	for j in size:
		for i in size:
			heights[j * size + i] = _relief_height(origin + Vector2(i, j) * step)
	var ground := Biome.default_tile(_look)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var index := PackedInt32Array()
	var ids := PackedInt32Array()
	ids.resize(size * size)
	ids.fill(-1)
	var rock := _base_color(Biome.Tile.ROCK)
	for j in size:
		for i in size:
			var p := origin + Vector2(i, j) * step
			if Vector2(p.x - center.x, p.y - center.z).length() > reach + 1.0:
				continue
			var h := heights[j * size + i]
			var hx := heights[j * size + clampi(i + 1, 0, size - 1)] - heights[j * size + clampi(i - 1, 0, size - 1)]
			var hz := heights[clampi(j + 1, 0, size - 1) * size + i] - heights[clampi(j - 1, 0, size - 1) * size + i]
			var normal := Vector3(-hx, 2.0 * step, -hz).normalized()
			var c := grid.world_to_cell(Vector3(p.x, 0.0, p.y))
			var tile: int = _relief_tiles.get(c, ground)
			if tile in [Biome.Tile.WATER, Biome.Tile.LAVA, Biome.Tile.BRIDGE]:
				tile = Biome.Tile.SAND if _look in [Biome.Kind.BEACH, Biome.Kind.DESERT] else Biome.Tile.DIRT
			var col := _relief_color(c, tile, h, 1.0 - normal.y, rock)
			ids[j * size + i] = verts.size()
			verts.append(Vector3(p.x, h, p.y))
			normals.append(normal)
			colors.append(col)
	for j in size - 1:
		for i in size - 1:
			var a := ids[j * size + i]
			var b := ids[j * size + i + 1]
			var c2 := ids[(j + 1) * size + i]
			var d := ids[(j + 1) * size + i + 1]
			if a < 0 or b < 0 or c2 < 0 or d < 0:
				continue
			var mid := origin + Vector2(i + 0.5, j + 0.5) * step
			if grid.is_inside(grid.world_to_cell(Vector3(mid.x, 0.0, mid.y))) and _board_distance(mid) <= 0.0:
				continue  # bajo el tablero
			index.append_array([a, b, c2, b, d, c2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = index
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "Relieve"
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.95
	m.metallic_specular = 0.2 if _look != Biome.Kind.SNOW else 0.4
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)


## Color del relieve en un vértice: el del suelo de su casilla (con la sombra del campo de adorno), con roca
## en las laderas empinadas de montaña, nieve y volcán, crestas de duna más claras y valles más oscuros.
func _relief_color(c: Vector2i, tile: int, h: float, steep: float, rock: Color) -> Color:
	var col := _scenery_color(c, tile)
	var dim := _scenery_dim(c)
	match _look:
		Biome.Kind.DESERT, Biome.Kind.BEACH:
			col = col.lightened(clampf(h * 0.05, 0.0, 0.12)).darkened(clampf(steep * 0.6, 0.0, 0.2))
		Biome.Kind.MOUNTAIN, Biome.Kind.VOLCANO, Biome.Kind.CAVE, Biome.Kind.UNDERWATER:
			col = col.lerp(rock.darkened(dim), smoothstep(0.15, 0.45, steep) * 0.6)
			if _look in [Biome.Kind.CAVE, Biome.Kind.UNDERWATER]:  # en la penumbra, paredes algo más claras para leerlas
				col = col.lightened(clampf(h * 0.03, 0.0, 0.18))
			if _look == Biome.Kind.MOUNTAIN and h > 4.5:  # cumbres nevadas
				col = col.lerp(Color(0.92, 0.94, 0.98).darkened(dim * 0.8), smoothstep(4.5, 6.0, h) * (1.0 - smoothstep(0.3, 0.6, steep)))
		Biome.Kind.SNOW:
			# El blanco apenas toma sombra: laderas algo azuladas y más oscuras para que se lean las lomas
			col = col.lerp(Color(0.62, 0.7, 0.85).darkened(dim), clampf(steep * 1.6, 0.0, 0.45))
			col = col.lerp(rock.darkened(dim), smoothstep(0.35, 0.6, steep) * 0.7)
		_:
			col = col.darkened(clampf(steep * 0.5, 0.0, 0.22)).lightened(clampf(h * 0.025, 0.0, 0.08))
	return col


## Interiores (Laboratorio, Librería, Estudio): el campo de adorno sigue un plano ordenado en vez de piezas
## al azar, que ahí parecían trastos tirados. Devuelve [suelo, obstáculo], o vacío para el reparto al azar.
func _scenery_layout(c: Vector2i, far: int, tile: int, ground: int) -> Array:
	if _look not in [Biome.Kind.LAB, Biome.Kind.LIBRARY, Biome.Kind.STUDIO]:
		return []
	if tile != ground or far < 2:
		return [tile, Biome.Prop.NONE]
	match _look:
		Biome.Kind.LIBRARY:
			# Pasillos de estanterías en tramos de cinco, con dos filas de paso entre hileras y cruces
			if posmod(c.y, 3) == 0 and posmod(c.x, 7) < 5:
				return [tile, Biome.Prop.SHELF]
		Biome.Kind.LAB:
			# Salas separadas por líneas de luz en el suelo; en cada una, dos bancos de máquinas espalda con
			# espalda y un par de incubadoras
			var l := Vector2i(posmod(c.x, 10), posmod(c.y, 8))
			if l.x == 0 or l.y == 0:
				return [Biome.Tile.FLOOR_LINE, Biome.Prop.NONE]
			if l.y in [3, 4] and l.x in [2, 3, 4, 6, 7, 8]:
				return [tile, Biome.Prop.MACHINE]
			if l.y == 6 and l.x in [2, 8]:
				return [tile, Biome.Prop.TANK]
		Biome.Kind.STUDIO:
			# Otros platós alrededor: escenarios de madera rodeados de cinta, cámaras o focos en sus trípodes
			var block := Vector2i(floori(c.x / 9.0), floori(c.y / 9.0))
			var l := Vector2i(posmod(c.x, 9), posmod(c.y, 9))
			var edge := mini(mini(l.x, l.y), mini(8 - l.x, 8 - l.y))
			match hash(block) % 3:
				0:
					if edge >= 2:
						return [Biome.Tile.WOOD, Biome.Prop.NONE]
					if edge == 1 and (l.x + l.y) % 2 == 0:  # cinta a trozos, como las marcas de un plató
						return [Biome.Tile.FLOOR_LINE, Biome.Prop.NONE]
				1:
					if l in [Vector2i(2, 2), Vector2i(6, 2), Vector2i(4, 6)]:
						return [tile, Biome.Prop.CAMERA]
				2:
					if l in [Vector2i(1, 1), Vector2i(1, 7), Vector2i(7, 1), Vector2i(7, 7)]:
						return [tile, Biome.Prop.SPOTLIGHT]
	return [tile, Biome.Prop.NONE]


## Río o sendero que sale del tablero y pasa por `c` (-1 si no hay). Al salir siguen la casilla del borde y
## luego serpentean (desplazamiento lateral con ruido, nulo junto al borde); también pueden doblar hacia las
## esquinas. Las carreteras siguen rectas. Se mira también el desplazamiento de la fila anterior para que un
## cambio de carril no deje el cauce unido solo por una esquina.
func _scenery_trail(c: Vector2i, bends: FastNoiseLite) -> int:
	var out_x := maxi(maxi(-c.x, c.x - (grid.width - 1)), 0)
	var out_y := maxi(maxi(-c.y, c.y - (grid.height - 1)), 0)
	var across := out_x >= out_y  # sale por la izquierda/derecha (si no, por arriba/abajo)
	var t := out_x if across else out_y
	var lateral := c.y if across else c.x
	var length := grid.height if across else grid.width
	var side := (0 if c.x < 0 else 1) if across else (2 if c.y < 0 else 3)
	var edge_of := func(i: int) -> Vector2i:
		return Vector2i(0 if side == 0 else grid.width - 1, i) if across else Vector2i(i, 0 if side == 2 else grid.height - 1)
	if out_x == 0 or out_y == 0:
		var e: Vector2i = edge_of.call(lateral)
		var straight: int = grid.tiles[e]
		if (straight == Biome.Tile.ROAD or straight == Biome.Tile.FLOOR_LINE and _look == Biome.Kind.LIBRARY) \
				and grid.heights[e] == 0:
			return straight  # carreteras y la alfombra de la Librería, rectas
	for k in [t, t - 1]:
		if k < 1:
			continue
		var shift := roundi(bends.get_noise_1d(k + side * 97.0) * SCENERY_BEND * smoothstep(0.0, 5.0, k))
		var from: int = lateral - shift
		if from < 0 or from >= length:
			continue
		var e: Vector2i = edge_of.call(from)
		var tile: int = grid.tiles[e]
		if tile in SCENERY_TRAILS and tile != Biome.Tile.ROAD and grid.heights[e] == 0:
			return tile
	return -1


## Playa: lado del mar (`left`) y, por fila (también las de fuera del tablero), cuántas casillas de agua hay
## desde ese borde (`line`). Dentro, la orilla del tablero; fuera, se suaviza hacia la media con olas suaves.
## Vacío si el tablero no toca el mar (p. ej. un mapa vacío del editor).
func _beach_coast(margin: int) -> Dictionary:
	var sea := [0, 0]
	for y in grid.height:
		for i in 2:
			if grid.tiles[Vector2i(0 if i == 0 else grid.width - 1, y)] in [Biome.Tile.WATER, Biome.Tile.BRIDGE]:
				sea[i] += 1
	if sea[0] == 0 and sea[1] == 0:
		return {}
	var left: bool = sea[0] >= sea[1]
	var rows := {}
	var total := 0.0
	for y in grid.height:
		var d := 0
		while d < grid.width:
			var c := Vector2i(d if left else grid.width - 1 - d, y)
			if grid.tiles[c] not in [Biome.Tile.WATER, Biome.Tile.BRIDGE]:
				break
			d += 1
		rows[y] = float(d)
		total += d
	var mean := total / grid.height
	var waves := FastNoiseLite.new()
	waves.seed = grid.width * 11 + grid.height
	waves.frequency = 0.08
	var line := {}
	for y in range(-margin, grid.height + margin):
		var row := clampi(y, 0, grid.height - 1)
		var out := float(absi(y - row))
		line[y] = lerpf(rows[row], mean, smoothstep(0.0, 6.0, out)) + waves.get_noise_1d(y) * 2.5 * smoothstep(0.0, 4.0, out)
	return {"left": left, "line": line}


## Sombra del campo de adorno en `c` (0-1, lo que se oscurecen sus colores): ya fuerte junto al borde y casi
## negra a lo lejos, para que solo destaque la zona de combate. Con manchas suaves (ruido) para que el
## degradado no se vea a escalones, anillo a anillo.
func _scenery_dim(c: Vector2i) -> float:
	var w := grid.to_world(c)
	var spots := _tint_noise.get_noise_2d(w.x * 0.35, w.z * 0.35) * 0.1
	return clampf(lerpf(SCENERY_SHADE, SCENERY_SHADE_FAR, smoothstep(1.0, 16.0, _outside(c))) + spots, 0.0, 0.9)


## Color del suelo del campo de adorno: el del suelo sin las manchas escalonadas ni el ajedrezado de las
## casillas (fuera se verían como un mosaico), con su sombra.
func _scenery_color(c: Vector2i, tile_kind: int) -> Color:
	var color := _base_color(tile_kind)
	if tile_kind == Biome.Tile.GRASS and _look in [Biome.Kind.MEADOW, Biome.Kind.LAKE]:
		var w := grid.to_world(c)
		color = color.lerp(Color(0.32, 0.55, 0.16), 0.5 + _tint_noise.get_noise_2d(w.x * 0.5, w.z * 0.5) * 0.5)
	return color.darkened(_scenery_dim(c))


## Biblioteca: fuera del tablero siguen las salas de estanterías, en hileras corridas (las filas pares, como
## las del tablero) cortadas por pasillos cada pocas casillas, con columnas donde se cruzan.
func _library_scenery(x: int, y: int, h: int) -> int:
	if posmod(y, 2) != 0:
		return Biome.Prop.NONE
	if posmod(x, LIBRARY_BAY) == 0:
		return Biome.Prop.PILLAR if posmod(y, 4) == 0 else Biome.Prop.NONE
	return Biome.Prop.NONE if h % 23 == 0 else Biome.Prop.SHELF


## Funde en una malla por acabado los obstáculos ya fundidos (`_bake`) de una zona del campo de adorno: cada
## uno era una llamada de dibujo, y otra por cada cascada de sombra.
func _merge_baked(roots: Array) -> void:
	var holder := Node3D.new()
	add_child(holder)
	var meshes := []
	for root: Node3D in roots:
		for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			var m := mi.material_override as StandardMaterial3D
			if m == null or not m.vertex_color_use_as_albedo or mi.has_meta("batch") or mi.get_child_count() > 0:
				continue
			var xf := _relative_transform(mi, self)
			mi.get_parent().remove_child(mi)
			mi.transform = xf
			holder.add_child(mi)
			meshes.append(mi.mesh)
	_bake(holder)
	for mesh in meshes:  # mallas de un solo uso: no hace falta guardar sus datos
		_mesh_arrays.erase(mesh)


## Obstáculo de una lista de `SCENERY_PROPS` ([densidad, [obstáculo, peso]...]) según `r` (0-1).
func _pick_weighted(props: Array, r: float) -> int:
	var total := 0.0
	for i in range(1, props.size()):
		total += props[i][1]
	r *= total
	for i in range(1, props.size()):
		r -= props[i][1]
		if r < 0.0:
			return props[i][0]
	return props[-1][0]


## Caja que ocupa el tablero en el mundo (casillas y relieve), para encuadrarlo a pantalla completa.
func board_box() -> AABB:
	var box := AABB(grid.to_world(Vector2i.ZERO), Vector3.ZERO)
	for c in grid.all_cells():
		var w := grid.to_world(c)
		box = box.expand(w + Vector3(-0.5, -BASE_THICKNESS, -0.5)).expand(w + Vector3(0.5, 0.0, 0.5))
	return box


## Casillas que separan `c` del tablero (0 = dentro).
func _outside(c: Vector2i) -> int:
	return maxi(absi(c.x - clampi(c.x, 0, grid.width - 1)), absi(c.y - clampi(c.y, 0, grid.height - 1)))


## Campo de adorno: las piezas con viento de un obstáculo (las hojas y troncos de los árboles) pasan a ser
## detalles sueltos de la casilla, para que `_batch` las agrupe como la hierba. Son cientos de árboles: uno
## a uno se dibujaban en miles de llamadas. Solo las tres primeras piezas (tronco y copas grandes, casi
## toda la silueta) hacen sombra: así no flotan y las cascadas de sombra no dibujan cada hoja.
func _loose_parts(root: Node3D, prop: Node3D, base_y: float) -> void:
	var height: float = prop.get_meta("sway_height", 1.0)
	var i := 0
	for mi: MeshInstance3D in prop.find_children("*", "MeshInstance3D", true, false):
		if not mi.material_override is ShaderMaterial or mi.get_child_count() > 0:
			continue
		if i not in [0, 2, 3]:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		i += 1
		var xf := _relative_transform(mi, root)
		mi.get_parent().remove_child(mi)
		mi.transform = xf
		mi.set_meta("batch", "decor")
		mi.set_meta("sway_base", Vector2(base_y, height))
		root.add_child(mi)


## `decor`: casilla del campo de adorno (sin colisión ni resaltado).
func _build_cell(c: Vector2i, decor := false) -> void:
	var root := Node3D.new()
	root.set_meta("cell", c)
	add_child(root)
	_cells[c] = root
	var top := grid.to_world(c)
	if _building_scenery:
		top.y += _relief_at.get(c, 0.0)  # sobre el relieve (el suelo lo pone la malla de `_build_relief`)
	var thickness := BASE_THICKNESS + top.y
	var tile_kind: int = grid.tiles.get(c, Biome.Tile.GRASS)

	var water := tile_kind in [Biome.Tile.WATER, Biome.Tile.BRIDGE, Biome.Tile.LAVA]  # el puente va sobre el agua
	if water:
		var surface := MeshInstance3D.new()
		surface.mesh = _water_mesh()
		surface.position = Vector3(top.x, top.y - WATER_DROP, top.z)
		# En el volcán los puentes cruzan la lava
		var lava := tile_kind == Biome.Tile.LAVA or tile_kind == Biome.Tile.BRIDGE and _look == Biome.Kind.VOLCANO
		if lava:
			if _building_scenery:  # fuera, la lava se enfría y apaga con la distancia
				var cool := snappedf(_scenery_dim(c), 0.1)
				surface.material_override = _live("lava_%.1f" % cool, func() -> ShaderMaterial:
					var m := TerrainFx.lava_material()
					m.set_shader_parameter("hot", Color(1.0, 0.45, 0.08).lerp(Color(0.55, 0.12, 0.04), cool))
					m.set_shader_parameter("crust", Color(0.16, 0.08, 0.06).darkened(cool * 0.5))
					return m)
			else:
				surface.material_override = _live("lava", func() -> ShaderMaterial: return TerrainFx.lava_material())
			if (c.x * 3 + c.y) % 4 == 0 and not _building_scenery:  # la lava ilumina lo que tiene cerca (una luz cada pocas casillas)
				var light := OmniLight3D.new()
				light.light_color = Color(1.0, 0.45, 0.15)
				light.light_energy = 0.9
				light.omni_range = 2.2
				light.position = Vector3(top.x, top.y + 0.3, top.z)
				root.add_child(light)
		else:
			var tint: Array = Biome.gym_style(grid.gym_type).get("water", [Color(0.1, 0.3, 0.62), Color(0.28, 0.6, 0.86)]) \
					if _look == Biome.Kind.GYM else [Color(0.1, 0.3, 0.62), Color(0.28, 0.6, 0.86)]
			if _building_scenery:  # el agua de fuera se apaga como el suelo, por escalones para agrupar
				if _look == Biome.Kind.SWAMP:  # y en el pantano se enturbia, verdosa, lejos del tablero
					var murk := snappedf(smoothstep(1.0, 5.0, _outside(c)), 0.25) * 0.8
					tint = [tint[0].lerp(Color(0.13, 0.2, 0.1), murk), tint[1].lerp(Color(0.32, 0.38, 0.2), murk)]
				var dim := snappedf(_scenery_dim(c), 0.1)
				tint = [tint[0].darkened(dim), tint[1].darkened(dim)]
			var gloss := 1.0 - snappedf(_scenery_dim(c), 0.1) if _building_scenery else 1.0
			surface.material_override = _live("water_%s_%.1f" % [tint[0].to_html(), gloss], func() -> ShaderMaterial:
				var m := TerrainFx.water_material(tint[0], tint[1])
				m.set_shader_parameter("gloss", gloss)
				return m)
		surface.set_instance_shader_parameter("shore", _shore(c))
		surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(surface)
		if tile_kind == Biome.Tile.BRIDGE:
			_bridge(root, c, top)
	elif not (decor and _relief_on):
		var top_mesh := MeshInstance3D.new()
		top_mesh.mesh = _tile_mesh(TOP_THICKNESS, 0.0)
		top_mesh.position = Vector3(top.x, top.y - TOP_THICKNESS * 0.5, top.z)
		var col := _tile_color(c, tile_kind)
		if tile_kind in [Biome.Tile.CAVE, Biome.Tile.ROCK]:
			top_mesh.material_override = _live("stone_%s" % col.to_html(), func() -> ShaderMaterial:
				return TerrainFx.stone_material(col))
		elif tile_kind == Biome.Tile.WOOD:
			top_mesh.material_override = _live("wood_%s" % col.to_html(), func() -> ShaderMaterial:
				return TerrainFx.wood_material(col))
		else:
			top_mesh.material_override = _material(col, tile_kind in [Biome.Tile.ICE, Biome.Tile.MUD])  # el lodo brilla mojado
		if decor:
			top_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # llano: no hace sombra a nada
			# Sin laterales debajo, las juntas entre losas dejarían ver el fondo: justo hasta tocarse, sin solaparse
			top_mesh.scale = Vector3.ONE * (1.0 / (1.0 - TILE_GAP))
			top_mesh.scale.y = 1.0
			top_mesh.set_meta("matte", true)
		top_mesh.set_meta("batch", "top")
		top_mesh.set_meta("color", col)
		root.add_child(top_mesh)

	var side_top := top.y - (WATER_DROP + 0.1 if water else TOP_THICKNESS)  # bajo el seno de las olas
	var side := MeshInstance3D.new()
	side.mesh = _tile_mesh(side_top + BASE_THICKNESS, 0.0)
	side.position = Vector3(top.x, (side_top - BASE_THICKNESS) * 0.5, top.z)
	side.material_override = _side_material(tile_kind)
	side.set_instance_shader_parameter("top_y", top.y)
	side.set_meta("batch", "side")
	side.set_meta("top_y", top.y)
	side.set_meta("thickness", side_top + BASE_THICKNESS)
	if decor and not water:
		side.free()  # el campo de adorno es llano: sus laterales no se ven (el agua sí necesita su lecho)
	else:
		root.add_child(side)

	# El campo de adorno lleva hierba solo junto al tablero; más lejos, césped liso (la hierba de todo el
	# campo costaba más que el tablero entero)
	if not decor or _outside(c) <= SCENERY_GRASS:
		_decorate(root, c, tile_kind, top)
	if _look == Biome.Kind.UNDERWATER and not water and not (decor and _relief_on and _relief_at.get(c, 0.0) > 0.05):
		_caustics(root, top)  # sobre el relieve inclinado quedarían flotando
	if tile_kind == Biome.Tile.ROAD:
		_road_marks(root, c, top)
	_maybe_puddle(root, c, tile_kind, top)
	_hail_pile(root, c, tile_kind, top)

	var prop: int = grid.props.get(c, Biome.Prop.NONE)
	if prop != Biome.Prop.NONE:
		var p := _prop_node(prop, c)
		p.position = top - (Vector3.UP * WATER_DROP if water else Vector3.ZERO)
		root.add_child(p)
		_root_sway(p, top.y)
		_bake(p)
		# Piezas que se agrupan aparte (hileras de libros): pasan a la casilla, donde las busca `_collect`
		for mi: MeshInstance3D in p.find_children("*", "MeshInstance3D", true, false):
			if mi.has_meta("batch"):
				var xf := _relative_transform(mi, root)
				mi.get_parent().remove_child(mi)
				mi.transform = xf
				root.add_child(mi)
		if decor:
			_loose_parts(root, p, top.y)
	if decor:
		return

	var body := StaticBody3D.new()
	body.set_meta("cell", c)
	var shape := CollisionShape3D.new()
	shape.shape = _tile_mesh(thickness, 0.0).create_convex_shape()
	body.position = Vector3(top.x, top.y - thickness * 0.5, top.z)
	body.add_child(shape)
	root.add_child(body)

	var overlay := MeshInstance3D.new()
	overlay.mesh = _tile_mesh(0.02, 0.08)
	overlay.position = Vector3(top.x, top.y + 0.012, top.z)
	overlay.visible = false
	overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(overlay)
	_overlays[c] = overlay


## Obstáculo hecho con primitivas. Tamaño y giro varían de forma estable según la celda; los detalles
## dependen del bioma (nieve sobre pinos y rocas, musgo en el bosque, rocas rojizas en el desierto...).
## Lo que tiene hojas se mece con el viento.
func _prop_node(prop: int, c: Vector2i) -> Node3D:
	var node := Node3D.new()
	var h := hash(c)
	var jitter := 0.85 + float(h % 30) / 100.0
	node.rotation.y = float(h % 360) * PI / 180.0
	node.scale = Vector3.ONE * jitter
	var snowy: bool = _look == Biome.Kind.SNOW or grid.tiles.get(c, 0) == Biome.Tile.SNOW
	var snow := Color(0.95, 0.97, 1.0)
	var height := 1.0
	match prop:
		Biome.Prop.TREE:
			var leaf := Color(0.22, 0.48, 0.2) if _look == Biome.Kind.FOREST else Color(0.28, 0.56, 0.24)
			if _look == Biome.Kind.SWAMP:
				leaf = Color(0.3, 0.38, 0.16)  # sauce de pantano, verde oliva
			# En el campo de adorno, dos tonos en vez de siete: cada tono es un grupo más que dibujar.
			leaf = leaf.lerp(Color(0.45, 0.55, 0.18), float(h % 2 * 4 if _building_scenery else h % 7) / 20.0)
			var bark := 3 if snowy else 4  # con musgo salvo en la nieve
			_leaf(node, _cyl(0.05, 0.1, 0.62, 7), Vector3(0, 0.31, 0), Color(0.4, 0.27, 0.16), 0.3, 0.0, bark)
			_leaf(node, _cyl(0.02, 0.04, 0.3, 5), Vector3(0.1, 0.55, 0), Color(0.4, 0.27, 0.16), 0.4, 0.0, bark).rotation.z = -0.8
			var blobs := [[0.34, Vector3(0, 0.84, 0)], [0.24, Vector3(0.22, 0.72, 0.1)], [0.22, Vector3(-0.2, 0.75, -0.08)],
				[0.2, Vector3(0.04, 1.06, 0.04)], [0.18, Vector3(-0.05, 0.7, 0.24)]]
			for i in blobs.size():
				var r: float = blobs[i][0]
				_leaf(node, _sphere(r, r * 1.7), blobs[i][1], leaf.lightened(0.06 * (i % 3)).darkened(0.05 * (i % 2)), 1.0, 1.0, 1)
			height = 1.2
		Biome.Prop.PINE:
			var needle := Color(0.14, 0.36, 0.24)
			_leaf(node, _cyl(0.04, 0.08, 0.4, 6), Vector3(0, 0.2, 0), Color(0.38, 0.25, 0.15), 0.25, 0.0, 3)
			var tiers := [[0.42, 0.45, 0.42], [0.34, 0.4, 0.66], [0.26, 0.34, 0.88], [0.16, 0.3, 1.08]]
			for i in tiers.size():
				var t: Array = tiers[i]
				_leaf(node, _cyl(0.0, t[0], t[1], 9), Vector3(0, t[2], 0), needle.lightened(0.05 * i), 0.7, 0.35, 2)
				if snowy:
					_leaf(node, _cyl(0.0, t[0] * 0.75, t[1] * 0.45, 9), Vector3(0, t[2] + t[1] * 0.3, 0), snow, 0.7, 0.35)
			height = 1.25
		Biome.Prop.BOULDER:
			var stone := Color(0.5, 0.48, 0.46)
			match _look:
				Biome.Kind.DESERT: stone = Color(0.66, 0.47, 0.34)
				Biome.Kind.CAVE: stone = Color(0.42, 0.41, 0.4)  # gris frío, sin tono café
				Biome.Kind.SNOW: stone = Color(0.48, 0.5, 0.54)
				Biome.Kind.VOLCANO: stone = Color(0.22, 0.2, 0.2)
				Biome.Kind.GYM: stone = Biome.gym_style(grid.gym_type).pillar
			# Cuatro composiciones (peñasco con canto, roca alta, lajas apiladas, montón de cantos) y tamaño
			# variable; cada pieza con su forma (TerrainFx.rock_mesh) y su tono.
			var size := 0.8 + float((h >> 3) % 5) * 0.1
			var v := (h >> 5) % 2 * 4  # una de las dos formas de cada estilo
			var layouts := [
				[[0, Vector3(0, 0.16, 0), Vector3(0.78, 0.6, 0.68)], [1, Vector3(0.3, 0.06, 0.18), Vector3(0.28, 0.24, 0.26)]],
				[[3, Vector3(0, 0.3, 0), Vector3(0.6, 0.62, 0.55)], [1, Vector3(-0.24, 0.07, 0.16), Vector3(0.3, 0.26, 0.28)],
					[0, Vector3(0.22, 0.05, -0.18), Vector3(0.2, 0.18, 0.2)]],
				[[2, Vector3(0, 0.08, 0), Vector3(0.85, 0.5, 0.75)], [2, Vector3(0.05, 0.22, 0.02), Vector3(0.55, 0.42, 0.5)],
					[1, Vector3(-0.3, 0.06, 0.2), Vector3(0.22, 0.2, 0.2)]],
				[[1, Vector3(-0.12, 0.13, -0.08), Vector3(0.48, 0.48, 0.44)], [0, Vector3(0.2, 0.1, 0.1), Vector3(0.4, 0.36, 0.38)],
					[1, Vector3(0.0, 0.07, 0.28), Vector3(0.28, 0.24, 0.26)], [2, Vector3(-0.3, 0.04, 0.22), Vector3(0.26, 0.2, 0.24)]],
			]
			var top_y := 0.0
			for i in layouts[h % 4].size():
				var piece: Array = layouts[h % 4][i]
				var mi := _part(node, TerrainFx.rock_mesh(piece[0] + v), piece[1] * size, stone.darkened(0.06 * ((h + i) % 3)))
				mi.scale = piece[2] * size
				mi.rotation.y = float((h >> i) % 7)
				top_y = maxf(top_y, (piece[1].y + piece[2].y * 0.5) * size)
			if snowy:
				_part(node, _sphere(0.27, 0.12), Vector3(0, top_y - 0.04, 0), snow).scale = Vector3(1.0, 1.0, 0.85) * size
			elif _look in [Biome.Kind.FOREST, Biome.Kind.SWAMP]:
				_part(node, _sphere(0.25, 0.1), Vector3(-0.03, top_y - 0.04, 0), Color(0.3, 0.45, 0.18)).scale = Vector3(1.0, 1.0, 0.8) * size
		Biome.Prop.CACTUS:
			var green := Color(0.3, 0.52, 0.27).lerp(Color(0.42, 0.55, 0.3), float(h % 5) / 8.0)
			match (h >> 2) % 4:
				0, 1:
					# Columnar (saguaro): tronco con costillas y de 0 a 3 brazos que suben a distintas alturas.
					var tall := 0.75 + float(h % 4) * 0.1
					_leaf(node, _capsule(0.12, tall), Vector3(0, tall * 0.5, 0), green, 0.0, 0.0, 5)
					for i in (h >> 4) % 4:
						var a := TAU * float(i) / 3.0 + float(h % 7)
						var out := Vector3(cos(a), 0, sin(a))
						var y := tall * (0.35 + 0.15 * float((h >> (i + 5)) % 3))
						var reach := 0.16 + 0.04 * float((h >> i) % 2)
						var up := 0.18 + 0.08 * float((h >> (i + 3)) % 3)
						var elbow := _leaf(node, _capsule(0.065, reach + 0.1), Vector3(0, y, 0) + out * reach * 0.6, green.darkened(0.05), 0.0, 0.0, 5)
						elbow.basis = Basis(Vector3(-out.z, 0, out.x), PI / 2)
						_leaf(node, _capsule(0.065, up + 0.12), Vector3(0, y + up * 0.5, 0) + out * reach, green.darkened(0.05), 0.0, 0.0, 5)
					if h % 3 == 0:
						_part(node, _sphere(0.04, 0.05), Vector3(0, tall, 0), Color(0.95, 0.45, 0.6))
				2:
					# Barril: bola con costillas, a veces con hijuelos, y una corona de flores amarillas.
					var r := 0.2 + float(h % 3) * 0.03
					_leaf(node, _sphere(r, r * 1.6), Vector3(0, r * 0.75, 0), green, 0.0, 0.0, 5)
					for i in (h >> 4) % 3:
						var a := float(i) * 2.4 + float(h % 5)
						var rr := r * 0.45
						_leaf(node, _sphere(rr, rr * 1.6), Vector3(cos(a), 0, sin(a)) * r * 1.25 + Vector3(0, rr * 0.7, 0), green.lightened(0.05), 0.0, 0.0, 5)
					for i in 4:
						_part(node, _sphere(0.03, 0.04), Vector3(cos(i * 1.57), 0, sin(i * 1.57)) * r * 0.25 + Vector3(0, r * 1.5, 0), Color(1.0, 0.82, 0.25))
				3:
					# Nopal: palas ovaladas que salen unas de otras, con tunas rojas en el borde.
					var pads := [[Vector3(0, 0.2, 0), 0.0, 1.0], [Vector3(0.12, 0.44, 0), -0.5, 0.8], [Vector3(-0.12, 0.42, 0.02), 0.45, 0.75],
						[Vector3(0.22, 0.62, 0.0), -0.8, 0.6], [Vector3(-0.04, 0.66, -0.02), 0.15, 0.6]]
					for i in 3 + (h >> 4) % 3:
						var pad: Array = pads[i]
						var mi := _leaf(node, _sphere(0.16, 0.42), pad[0], green.lightened(0.04 * (i % 2)), 0.0, 0.0, 6)
						mi.scale = Vector3(1.0, 1.0, 0.28) * pad[2]
						mi.rotation.z = pad[1]
						if i >= 3:
							_part(node, _sphere(0.035, 0.06), pad[0] + Vector3(0, 0.2 * pad[2], 0), Color(0.75, 0.15, 0.25))
		Biome.Prop.PALM:
			# Palmera: tronco anillado que se curva y se estrecha, corona de hojas arqueadas con foliolos
			# que cuelgan (TerrainFx.frond_mesh) y un racimo de cocos bajo la corona.
			var bark := Color(0.55, 0.42, 0.28)
			var p := Vector3.ZERO
			var bend := 0.05 + float(h % 4) * 0.02
			var segs := 7
			for i in segs:
				var r := 0.075 - 0.005 * i
				var tilt := -bend * i
				var seg := _leaf(node, _cyl(r * 0.92, r, 0.19, 8), Vector3.ZERO, bark.darkened(0.05 * (i % 2)), 0.5, 0.0, 3)
				seg.rotation.z = tilt
				seg.position = p + Vector3(-sin(tilt), cos(tilt), 0) * 0.095
				var ring := _leaf(node, _cyl(r + 0.01, r + 0.012, 0.03, 8), Vector3.ZERO, bark.darkened(0.25), 0.5, 0.0, 3)
				ring.rotation.z = tilt
				ring.position = p + Vector3(-sin(tilt), cos(tilt), 0) * 0.185
				p += Vector3(-sin(tilt), cos(tilt), 0) * 0.18
			_leaf(node, _sphere(0.08, 0.12), p + Vector3(0, 0.02, 0), Color(0.42, 0.4, 0.2), 1.0, 0.5)
			var count := 9 + h % 3
			for i in count:
				var pivot := Node3D.new()
				pivot.position = p + Vector3(0, 0.03, 0)
				var up := 0.35 if i % 3 == 0 else (0.05 if i % 3 == 1 else -0.2)  # unas suben, otras caen
				pivot.rotation = Vector3(0, TAU * i / count + float(h % 9) * 0.2, up)
				pivot.scale = Vector3.ONE * (0.62 + 0.1 * float((h >> i) % 3))
				node.add_child(pivot)
				var frond := _leaf(pivot, TerrainFx.frond_mesh((h + i) % TerrainFx.VARIANTS), Vector3.ZERO, Color.WHITE, 1.0, 1.4)
				frond.material_override = _live("frond_%.1f" % 1.0, func() -> ShaderMaterial:
					return TerrainFx.foliage_material(Color.WHITE, 1.0, 1.4, true))
			for i in 3 + h % 3:
				var a := float(i) * 2.1
				_part(node, _sphere(0.045, 0.085), p + Vector3(cos(a) * 0.06, -0.05 - 0.02 * (i % 2), sin(a) * 0.06), Color(0.4, 0.28, 0.14).darkened(0.1 * (i % 2)))
			height = 1.25
		Biome.Prop.PILLAR:
			node.rotation.y = 0.0
			node.scale = Vector3.ONE
			_pillar(node, grid.gym_type if _look == Biome.Kind.GYM else "")
			height = 1.4
		Biome.Prop.STALAGMITE:
			# Grupo de estalagmitas de caliza: una alta y afilada con dos o tres pequeñas al pie, y cantos sueltos.
			var main_h := 0.95 + float(h % 5) * 0.1
			var mi := _stalagmite(node, h % 6, Vector3.ZERO, Vector3(0.8, main_h, 0.8))
			mi.rotation.y = float((h >> 3) % 7)
			for i in 2 + (h >> 2) % 2:
				var a := TAU * i / 3.0 + float(h % 9) * 0.7
				var tall := 0.3 + float((h >> (i + 4)) % 4) * 0.1
				var w := 0.32 + tall * 0.35
				_stalagmite(node, (h + i + 1) % 6, Vector3(cos(a), 0, sin(a)) * 0.27, Vector3(w, tall, w)).rotation.y = a
			var a2 := float(h % 13)
			var pebble := _part(node, TerrainFx.rock_mesh(1 + h % 2 * 4), Vector3(cos(a2), 0.02, sin(a2)) * 0.33, Color(0.38, 0.37, 0.36))
			pebble.scale = Vector3(0.12, 0.08, 0.1)
			height = main_h
		Biome.Prop.CRYSTAL:
			# Drusa: una punta grande y varias pequeñas que salen inclinadas de una base de roca. Ilumina
			# el suelo de alrededor con su color.
			var tint := Color(0.65, 0.45, 0.95) if h % 3 else Color(0.45, 0.75, 1.0)
			# En el gimnasio, del color de su tipo (hielo celeste, psíquico magenta, hada rosa); bajo el agua, azules
			if _look == Biome.Kind.GYM:
				tint = {"ice": Color(0.55, 0.85, 1.0), "psychic": Color(0.95, 0.35, 0.75),
					"fairy": Color(1.0, 0.6, 0.85)}.get(grid.gym_type, tint)
				if h % 3 == 0:
					tint = tint.lerp(Color.WHITE, 0.25)
			elif _look == Biome.Kind.UNDERWATER:
				tint = Color(0.3, 0.7, 1.0) if h % 3 else Color(0.35, 0.95, 0.9)
			var base := _part(node, TerrainFx.rock_mesh(h % 4), Vector3(0, 0.03, 0), Color(0.24, 0.22, 0.22))
			base.scale = Vector3(0.6, 0.22, 0.54)
			var count := 5 + h % 3
			for i in count:
				var big := i == 0
				var r := 0.15 if big else 0.055 + float((h >> i) % 5) * 0.012
				var tall := 1.15 if big else 0.3 + float((h >> (i + 2)) % 7) * 0.075
				var a := TAU * i / count + float(h % 11) * 0.3
				var shard := Node3D.new()
				shard.position = Vector3.ZERO if big else Vector3(cos(a), 0, sin(a)) * 0.19
				# Inclinada hacia fuera: gira el eje vertical hacia la dirección `a`.
				shard.basis = Basis(Vector3(sin(a), 0, -cos(a)), 0.06 if big else 0.35 + float((h >> i) % 4) * 0.1)
				node.add_child(shard)
				var col := tint if i % 3 else tint.lerp(Color(0.85, 0.9, 1.0), 0.3)
				_crystal(shard, _cyl(r, r * 1.08, tall, 6), Vector3.UP * tall * 0.5, col)
				_crystal(shard, _cyl(0.0, r, r * 2.4, 6), Vector3.UP * (tall + r * 1.2), col)
			var light := OmniLight3D.new()
			light.light_color = tint
			light.light_energy = CRYSTAL_LIGHT
			light.omni_range = 2.8
			light.position = Vector3(0, 0.65, 0)
			node.add_child(light)
			_crystal_lights.append(light)
		Biome.Prop.DEAD_TREE:
			# Árbol seco: tronco gris torcido con ramas desnudas que se abren hacia arriba y musgo colgando.
			var wood := Color(0.42, 0.38, 0.33)
			var trunk := _leaf(node, _cyl(0.05, 0.11, 0.8, 7), Vector3(0, 0.4, 0), wood, 0.15, 0.0, 3)
			trunk.rotation.z = 0.08
			for i in 3 + h % 2:
				var a := TAU * i / 3.0 + float(h % 5)
				var branch := _leaf(node, _cyl(0.015, 0.035, 0.42, 5), Vector3(cos(a) * 0.12, 0.62 + 0.1 * (i % 2), sin(a) * 0.12), wood.darkened(0.05 * i), 0.3, 0.0, 3)
				branch.basis = Basis(Vector3(-sin(a), 0, cos(a)), 0.7 + 0.15 * (i % 2))
				if i % 2 == 0:
					_leaf(node, _cyl(0.0, 0.04, 0.22, 5), Vector3(cos(a) * 0.24, 0.62, sin(a) * 0.24), Color(0.4, 0.46, 0.3), 0.6, 0.6)
			if _look == Biome.Kind.GYM and grid.gym_type == "ghost":
				# Gimnasio Fantasma: más alto, con un fuego fatuo morado flotando junto a una rama
				node.scale *= 1.7
				var wisp_pos := Vector3(0.28, 0.6, 0.12)
				var wisp := _glow(_part(node, _sphere(0.05, 0.09), wisp_pos, Color.WHITE), Color(0.7, 0.45, 1.0), 2.5)
				wisp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				var light := OmniLight3D.new()
				light.light_color = Color(0.6, 0.4, 1.0)
				light.light_energy = 1.0
				light.omni_range = 2.5
				light.position = wisp_pos
				node.add_child(light)
				_crystal_lights.append(light)  # late como los cristales
			height = 1.0
		Biome.Prop.BUILDING:
			# Edificio: bloque de 1 a 3 plantas en ladrillo, estuco u hormigón, con ventanas en cada cara,
			# puerta, cornisa y a veces una caja en la azotea. No gira, para que las fachadas queden alineadas.
			node.rotation.y = 0.0
			node.scale = Vector3.ONE
			if _look == Biome.Kind.AIRPORT:
				node.set_meta("sway_height", _terminal(node, c))
				return node
			height = _scenery_building(node, h) if _building_scenery else _city_building(node, h)
		Biome.Prop.LAMP:
			# Farola: poste negro con brazo y un farol que brilla tenue.
			node.scale = Vector3.ONE
			var iron := Color(0.16, 0.17, 0.19)
			_part(node, _cyl(0.06, 0.08, 0.08), Vector3(0, 0.04, 0), iron)
			_part(node, _cyl(0.025, 0.03, 1.1), Vector3(0, 0.55, 0), iron)
			_part(node, _cyl(0.015, 0.015, 0.25), Vector3(0.1, 1.08, 0), iron).rotation.z = PI / 2
			var bulb := _part(node, _sphere(0.07, 0.1), Vector3(0.21, 1.02, 0), Color(1.0, 0.9, 0.6))
			var glow: StandardMaterial3D = bulb.material_override.duplicate()
			glow.emission_enabled = true
			glow.emission = Color(1.0, 0.85, 0.5)
			glow.emission_energy_multiplier = 1.5
			bulb.material_override = glow
			_part(node, _cyl(0.0, 0.09, 0.06), Vector3(0.21, 1.09, 0), iron)
		Biome.Prop.PARASOL:
			# Sombrilla de playa: mástil blanco algo inclinado y lona de un color con gajos más claros.
			node.scale = Vector3.ONE
			var cloth: Color = [Color(0.9, 0.25, 0.22), Color(0.98, 0.8, 0.25), Color(0.25, 0.55, 0.9), Color(0.3, 0.7, 0.45)][h % 4]
			var tilt := Node3D.new()
			tilt.rotation.z = 0.12
			node.add_child(tilt)
			_part(tilt, _cyl(0.02, 0.02, 1.1), Vector3(0, 0.55, 0), Color(0.95, 0.95, 0.92))
			for i in 8:
				var gore := _leaf(tilt, _cyl(0.0, 0.6, 0.22, 8), Vector3(0, 1.0, 0), cloth.lightened(0.35 * (i % 2)), 0.25, 0.3)
				gore.scale = Vector3(1.0, 1.0, 1.0) * (1.0 - 0.002 * i)
				gore.rotation.y = TAU * i / 16.0
			_part(tilt, _sphere(0.035, 0.07), Vector3(0, 1.13, 0), Color(0.95, 0.95, 0.92))
			height = 1.15
		Biome.Prop.MACHINE:
			# Máquina de laboratorio: consola de chapa pintada con cantos biselados, zócalo de goma, rejillas de
			# ventilación, teclado, pantalla con una interfaz de análisis en marcha, pilotos y cable al suelo.
			node.rotation.y = float(h % 4) * PI / 2
			node.scale = Vector3.ONE
			var shell := Color(0.86, 0.88, 0.9)
			var dark := Color(0.16, 0.17, 0.19)
			_part(node, _unit_box(), Vector3(0, 0.025, 0), dark).scale = Vector3(0.78, 0.05, 0.56)  # zócalo
			_part(node, _bevel_box(), Vector3(0, 0.32, 0), shell).scale = Vector3(0.82, 0.56, 0.6)
			for k in 0 if _building_scenery else 3:  # rejillas a los lados (fuera no se distinguen)
				for sx in [-1, 1]:
					_part(node, _unit_box(), Vector3(0.412 * sx, 0.18 + 0.07 * k, 0.05), dark).scale = Vector3(0.01, 0.025, 0.32)
			_part(node, _unit_box(), Vector3(0, 0.45, 0.301), shell.darkened(0.2)).scale = Vector3(0.6, 0.004, 0.01)  # junta de la puerta
			# Teclado inclinado sobre la consola
			var deck := _part(node, _bevel_box(), Vector3(0, 0.62, 0.1), shell.darkened(0.12))
			deck.scale = Vector3(0.74, 0.05, 0.3)
			deck.rotation.x = 0.18
			var keys := _part(node, _unit_box(), Vector3(0, 0.655, 0.12), Color(0.3, 0.32, 0.36))
			keys.scale = Vector3(0.5, 0.012, 0.16)
			keys.rotation.x = 0.18
			# Monitor con su marco y la interfaz encendida
			var screen := _part(node, _bevel_box(), Vector3(0, 0.86, -0.18), dark)
			screen.scale = Vector3(0.66, 0.4, 0.05)
			screen.rotation.x = -0.25
			var face := MeshInstance3D.new()
			face.mesh = _quad(0.58, 0.32)
			face.position = Vector3(0, 0.86, -0.18) + Basis(Vector3.RIGHT, -0.25) * Vector3(0, 0, 0.027)
			face.rotation.x = -0.25
			face.material_override = _screen_material([Color(0.3, 0.85, 1.0), Color(0.4, 1.0, 0.6), Color(0.6, 0.5, 1.0)][h % 3], h % 7)
			face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.add_child(face)
			if not _building_scenery:
				_part(node, _cyl(0.03, 0.05, 0.12, 8), Vector3(0, 0.66, -0.2), dark)  # pie del monitor
			for i in 0 if _building_scenery else 4:  # pilotos: fuera no se distinguen y no se pueden fundir
				var led := _part(node, _unit_box(), Vector3(-0.27 + 0.18 * i, 0.5, 0.305), Color.WHITE)
				led.scale = Vector3(0.06, 0.04, 0.01)
				_glow(led, [Color(1.0, 0.25, 0.2), Color(0.3, 1.0, 0.35), Color(1.0, 0.8, 0.2)][(h + i) % 3], 2.0)
			if not _building_scenery:  # cable de la parte de atrás hasta el suelo
				_part(node, _cyl(0.018, 0.018, 0.3, 6), Vector3(0.28, 0.2, -0.32), dark)
				_part(node, _cyl(0.018, 0.018, 0.22, 6), Vector3(0.28, 0.02, -0.42), dark).rotation.x = PI / 2
			height = 1.05
		Biome.Prop.TANK:
			# Incubadora: cilindro de cristal con líquido luminoso y burbujas, sobre base y bajo tapa metálicas.
			node.rotation.y = 0.0
			node.scale = Vector3.ONE
			var metal := Color(0.55, 0.58, 0.62)
			var tint := Color(0.3, 0.95, 0.75) if h % 2 else Color(0.4, 0.75, 1.0)
			_part(node, _cyl(0.36, 0.4, 0.16, 16), Vector3(0, 0.08, 0), metal)
			_part(node, _cyl(0.36, 0.33, 0.14, 16), Vector3(0, 1.36, 0), metal)
			var liquid := _part(node, _cyl(0.27, 0.27, 1.0, 16), Vector3(0, 0.66, 0), tint)
			_glow(liquid, tint, 1.2)
			for i in 3:
				_glow(_part(node, _sphere(0.035, 0.07), Vector3(0.08 * (i - 1), 0.4 + 0.3 * i, 0.06 * (i % 2)), Color.WHITE), tint.lightened(0.5), 1.5)
			var glass := _part(node, _cyl(0.31, 0.31, 1.14, 20), Vector3(0, 0.71, 0), Color.WHITE)
			var gm := StandardMaterial3D.new()
			gm.albedo_color = Color(0.85, 0.95, 1.0, 0.22)
			gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			gm.roughness = 0.05
			gm.metallic_specular = 1.0
			glass.material_override = gm
			glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# Tornillos de la base y la tapa, y dos tubos que bajan por detrás hasta el suelo
			for k in 0 if _building_scenery else 8:  # tornillos: cubitos (fuera ni se ven)
				var a := TAU * k / 8.0
				for y in [0.17, 1.28]:
					_part(node, _unit_box(), Vector3(cos(a) * 0.35, y, sin(a) * 0.35), metal.darkened(0.3)).scale = Vector3.ONE * 0.03
			for sx in [-0.1, 0.1]:
				_part(node, _cyl(0.025, 0.025, 1.3, 8), Vector3(sx, 0.75, -0.36), metal.lightened(0.15))
				_part(node, _cyl(0.025, 0.025, 0.1, 8), Vector3(sx, 1.4, -0.31), metal.lightened(0.15)).rotation.x = PI / 2
			_part(node, _bevel_box(), Vector3(0, 0.3, 0.38), Color(0.2, 0.21, 0.24)).scale = Vector3(0.2, 0.14, 0.04)  # panel
			if not _building_scenery:
				var lamp := _part(node, _sphere(0.02, 0.04), Vector3(0.05, 0.33, 0.405), Color.WHITE)
				_glow(lamp, tint, 3.0)
			height = 1.45
		Biome.Prop.VENT:
			# Fumarola: cono de basalto con la boca al rojo y una columna de humo que sube y se deshace.
			var basalt := Color(0.2, 0.18, 0.18)
			var cone := _part(node, _cyl(0.12, 0.4, 0.45, 9), Vector3(0, 0.22, 0), basalt)
			cone.rotation.y = float(h % 7)
			for i in 3:
				var a := float(i) * 2.1 + float(h % 5)
				_part(node, TerrainFx.rock_mesh(i), Vector3(cos(a) * 0.32, 0.06, sin(a) * 0.32), basalt.lightened(0.05)).scale = Vector3(0.2, 0.15, 0.2)
			_glow(_part(node, _cyl(0.1, 0.1, 0.03, 9), Vector3(0, 0.45, 0), Color(1.0, 0.5, 0.15)), Color(1.0, 0.45, 0.1), 3.0)
			var smoke := CPUParticles3D.new()
			smoke.amount = 14
			smoke.lifetime = 3.0
			smoke.position = Vector3(0, 0.5, 0)
			smoke.direction = Vector3.UP
			smoke.spread = 12.0
			smoke.initial_velocity_min = 0.3
			smoke.initial_velocity_max = 0.5
			smoke.gravity = Vector3(0.08, 0.05, 0.0)
			smoke.scale_amount_min = 0.6
			smoke.scale_amount_max = 1.4
			var puff := QuadMesh.new()
			puff.size = Vector2(0.3, 0.3)
			var pm := StandardMaterial3D.new()
			pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			pm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			pm.vertex_color_use_as_albedo = true
			puff.material = pm
			smoke.mesh = puff
			var fade := Gradient.new()
			fade.set_color(0, Color(0.55, 0.52, 0.5, 0.45))
			fade.set_color(1, Color(0.6, 0.58, 0.56, 0.0))
			smoke.color_ramp = fade
			smoke.preprocess = smoke.lifetime
			node.add_child(smoke)
			height = 0.5
		Biome.Prop.GRAVE:
			# Lápida: losa de piedra con remate redondo o en cruz, algo torcida y con musgo al pie.
			node.rotation.y = float(h % 3 - 1) * 0.12
			node.scale = Vector3.ONE * (0.9 + float(h % 3) * 0.08)
			var granite := Color(0.52, 0.52, 0.55).darkened(0.08 * (h % 3))
			if h % 4 == 0:
				_part(node, _unit_box(), Vector3(0, 0.36, 0), granite).scale = Vector3(0.1, 0.72, 0.1)
				_part(node, _unit_box(), Vector3(0, 0.52, 0), granite).scale = Vector3(0.4, 0.1, 0.1)
			else:
				_part(node, _unit_box(), Vector3(0, 0.25, 0), granite).scale = Vector3(0.44, 0.5, 0.1)
				var cap := _part(node, _cyl(0.22, 0.22, 0.1, 12), Vector3(0, 0.5, 0), granite)
				cap.rotation.x = PI / 2
			_part(node, _unit_box(), Vector3(0, 0.03, 0.12), granite.darkened(0.2)).scale = Vector3(0.56, 0.06, 0.4)
			_part(node, _sphere(0.12, 0.06), Vector3(-0.15, 0.06, 0.1), Color(0.28, 0.38, 0.2))
			node.rotation.x = float(h % 5 - 2) * 0.04
			height = 0.6
		Biome.Prop.SHELF:
			# Estantería de dos caras: zócalo, baldas con canto, tabla central, cornisa y, en los extremos de
			# cada hilera, los costados. Las de al lado se unen en un mueble corrido (sin costados entre medias).
			# Los libros van en hileras ya hechas (`_book_row`) que se agrupan como la hierba.
			var j := _joins(c, prop)
			node.rotation.y = PI / 2 if j.turned else 0.0
			node.scale = Vector3.ONE
			var x0: float = -0.5 if j.neg else -0.46
			var x1: float = 0.5 if j.pos else 0.46
			var w := x1 - x0
			var cx := (x0 + x1) * 0.5
			var d := SHELF_DEPTH
			var wood := Color(0.36, 0.2, 0.11)
			var inner := Color(0.2, 0.11, 0.07)
			_part(node, _unit_box(), Vector3(cx, 0.045, 0), wood.darkened(0.35)).scale = Vector3(w, 0.09, d * 2.0 + 0.02)
			_part(node, _unit_box(), Vector3(cx, 0.76, 0), inner).scale = Vector3(w, 1.34, 0.02)
			var ix0 := x0 + (0.0 if j.neg else 0.045)
			var ix1 := x1 - (0.0 if j.pos else 0.045)
			for k in [-1, 1]:
				if not (j.neg if k < 0 else j.pos):
					_part(node, _unit_box(), Vector3(x0 + 0.0225 if k < 0 else x1 - 0.0225, 0.74, 0), wood).scale = Vector3(0.045, 1.42, d * 2.0)
			if j.pos:  # montante compartido con la siguiente
				_part(node, _unit_box(), Vector3(0.5, 0.76, 0), wood).scale = Vector3(0.03, 1.34, d * 2.0)
			for level in SHELF_LEVELS:
				var y := 0.09 + level * SHELF_STEP
				if level > 0:
					_part(node, _unit_box(), Vector3((ix0 + ix1) * 0.5, y, 0), wood).scale = Vector3(ix1 - ix0, 0.025, d * 2.0 - 0.01)
				for side in [-1, 1]:
					_part(node, _unit_box(), Vector3((ix0 + ix1) * 0.5, y + 0.005, side * (d - 0.008)), wood.lightened(0.1)).scale = \
						Vector3(ix1 - ix0, 0.035, 0.016)
					var row := MeshInstance3D.new()
					row.mesh = _book_row((h + level * 5 + (side + 1) * 11) % BOOK_ROWS)
					row.material_override = _books_material()
					row.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					row.transform = Transform3D(Basis(Vector3.UP, 0.0 if side > 0 else PI).scaled(Vector3((ix1 - ix0 - 0.02) / (BOOK_ROW_HALF * 2.0), 1, 1)),
						Vector3((ix0 + ix1) * 0.5, y + (0.0125 if level > 0 else 0.0), side * (d - 0.02)))
					row.set_meta("batch", "books")
					node.add_child(row)
			var top_y := 0.09 + SHELF_LEVELS * SHELF_STEP
			var over := Vector2(0.0 if j.neg else 0.025, 0.0 if j.pos else 0.025)
			_part(node, _unit_box(), Vector3(cx + (over.y - over.x) * 0.5, top_y + 0.03, 0), wood).scale = Vector3(w + over.x + over.y, 0.06, d * 2.0 + 0.06)
			_part(node, _unit_box(), Vector3(cx, top_y + 0.075, 0), wood.lightened(0.12)).scale = Vector3(w + (over.x + over.y) * 0.4, 0.03, d * 2.0 + 0.02)
			_part(node, _unit_box(), Vector3(cx, top_y + 0.092, 0), inner.lightened(0.1)).scale = Vector3(w - 0.1, 0.006, d * 2.0 - 0.08)
			if h % 9 == 0 and not _building_scenery:
				_library_ladder(node, cx, d, top_y, 1 if h & 2 else -1)
			if h % 5 == 1:  # libros tumbados encima
				for i in 2 + h % 2:
					var book := _part(node, _unit_box(), Vector3(cx - 0.2 + 0.01 * i, top_y + 0.115 + i * 0.04, 0.02 * i), BOOK_COLORS[(h + i * 3) % BOOK_COLORS.size()])
					book.scale = Vector3(0.24 - 0.02 * i, 0.04, 0.17)
					book.rotation.y = 0.15 * (i - 1)
			elif h % 7 == 3:  # globo terráqueo
				_part(node, _cyl(0.05, 0.07, 0.03, 10), Vector3(cx + 0.18, top_y + 0.11, 0), Color(0.55, 0.42, 0.2))
				_part(node, _cyl(0.012, 0.012, 0.08, 6), Vector3(cx + 0.18, top_y + 0.16, 0), Color(0.55, 0.42, 0.2))
				_part(node, _sphere(0.09, 0.18), Vector3(cx + 0.18, top_y + 0.28, 0), Color(0.28, 0.45, 0.42))
				_part(node, _sphere(0.05, 0.08), Vector3(cx + 0.2, top_y + 0.32, 0.05), Color(0.62, 0.55, 0.32))
			elif h % 11 == 6:  # jarrón
				_part(node, _cyl(0.035, 0.06, 0.2, 10), Vector3(cx - 0.15, top_y + 0.2, 0), Color(0.2, 0.32, 0.36))
				_part(node, _sphere(0.065, 0.1), Vector3(cx - 0.15, top_y + 0.15, 0), Color(0.2, 0.32, 0.36))
			height = top_y + 0.1
		Biome.Prop.DESK:
			# Mesa de lectura de madera con tapete verde, sillas a los dos lados y lámpara de banquero encendida
			# (las de al lado se unen en una mesa larga), un libro abierto y alguno apilado.
			var j := _joins(c, prop)
			node.rotation.y = PI / 2 if j.turned else 0.0
			node.scale = Vector3.ONE
			var x0: float = -0.5 if j.neg else -0.44
			var x1: float = 0.5 if j.pos else 0.44
			var cx := (x0 + x1) * 0.5
			var wood := Color(0.4, 0.22, 0.12)
			_part(node, _unit_box(), Vector3(cx, 0.52, 0), wood).scale = Vector3(x1 - x0, 0.045, 0.74)
			_part(node, _unit_box(), Vector3(0, 0.545, 0), Color(0.15, 0.3, 0.2)).scale = Vector3(0.78, 0.006, 0.5)
			_part(node, _unit_box(), Vector3(cx, 0.46, 0), wood.darkened(0.3)).scale = Vector3(x1 - x0 - (0.0 if j.neg else 0.06) - (0.0 if j.pos else 0.06), 0.07, 0.62)
			for k in [-1, 1]:
				if j.neg if k < 0 else j.pos:
					continue
				var lx := (x0 + 0.07) if k < 0 else (x1 - 0.07)
				for z in [-0.29, 0.29]:
					_part(node, _cyl(0.024, 0.03, 0.46, 8), Vector3(lx, 0.23, z), wood.darkened(0.15))
				_part(node, _unit_box(), Vector3(lx, 0.1, 0), wood.darkened(0.25)).scale = Vector3(0.03, 0.03, 0.56)
			for side in [-1, 1]:
				if (h >> (side + 1)) % 4 == 0:
					continue  # un sitio sin silla
				var chair := Node3D.new()
				chair.position = Vector3(float((h >> (side + 3)) % 5 - 2) * 0.04, 0, side * (0.36 + float((h >> (side + 5)) % 3) * 0.03))
				chair.rotation.y = (0.0 if side > 0 else PI) + float((h >> (side + 7)) % 5 - 2) * 0.08
				node.add_child(chair)
				var cw := wood.darkened(0.2)
				_part(chair, _unit_box(), Vector3(0, 0.29, 0), cw).scale = Vector3(0.3, 0.035, 0.27)
				_part(chair, _unit_box(), Vector3(0, 0.315, 0), Color(0.45, 0.1, 0.12)).scale = Vector3(0.26, 0.02, 0.23)
				for lx in [-0.13, 0.13]:
					for lz in [-0.11, 0.11]:
						_part(chair, _unit_box(), Vector3(lx, 0.14, lz), cw).scale = Vector3(0.025, 0.28, 0.025)
					_part(chair, _unit_box(), Vector3(lx, 0.5, 0.125), cw).scale = Vector3(0.03, 0.42, 0.03)
				_part(chair, _unit_box(), Vector3(0, 0.62, 0.125), cw).scale = Vector3(0.28, 0.13, 0.025)
			var lamp_x := 0.24 if h & 1 else -0.24
			var brass := Color(0.7, 0.55, 0.25)
			_part(node, _cyl(0.055, 0.065, 0.02, 10), Vector3(lamp_x, 0.552, 0.05), brass)
			_part(node, _cyl(0.008, 0.008, 0.2, 6), Vector3(lamp_x, 0.66, 0.05), brass)
			var shade := _part(node, _cyl(0.05, 0.05, 0.24, 10), Vector3(lamp_x, 0.77, 0.05), Color.WHITE)
			shade.rotation.z = PI / 2
			_glow(shade, Color(0.1, 0.45, 0.22), 0.7)
			_glow(_part(node, _sphere(0.028, 0.04), Vector3(lamp_x, 0.735, 0.05), Color.WHITE), Color(1.0, 0.85, 0.55), 4.0)
			if not _building_scenery:
				var light := OmniLight3D.new()
				light.light_color = Color(1.0, 0.8, 0.52)
				light.light_energy = 0.9
				light.omni_range = 2.2
				light.omni_attenuation = 1.6
				light.position = Vector3(lamp_x, 0.72, 0.05)
				node.add_child(light)
			var bx := -lamp_x * 0.6
			_part(node, _unit_box(), Vector3(bx, 0.552, -0.04), BOOK_COLORS[h % BOOK_COLORS.size()]).scale = Vector3(0.27, 0.01, 0.19)
			for k in [-1, 1]:
				var page := _part(node, _unit_box(), Vector3(bx + k * 0.065, 0.565, -0.04), Color(0.9, 0.86, 0.74))
				page.scale = Vector3(0.125, 0.012, 0.17)
				page.rotation.z = -k * 0.1
			if h % 3 == 0:
				for i in 2 + h % 2:
					var book := _part(node, _unit_box(), Vector3(lamp_x * 0.2, 0.567 + i * 0.035, 0.18), BOOK_COLORS[(h + i * 5) % BOOK_COLORS.size()])
					book.scale = Vector3(0.2 - 0.015 * i, 0.033, 0.14)
					book.rotation.y = 0.2 * i - 0.1
			height = 0.8
		Biome.Prop.SPOTLIGHT:
			# Foco de plató: trípode, caja negra con viseras y la lente encendida; alumbra el escenario.
			var black := Color(0.1, 0.1, 0.11)
			for i in 3:
				var leg := _part(node, _cyl(0.015, 0.02, 1.0), Vector3(cos(i * 2.1) * 0.15, 0.48, sin(i * 2.1) * 0.15), black)
				leg.basis = Basis(Vector3(-sin(i * 2.1), 0, cos(i * 2.1)), 0.18)
			# Mira al centro del plató (el escenario) y lo alumbra con un cono de luz, como en un rodaje
			var to_stage := -grid.to_world(c)
			node.rotation.y = atan2(to_stage.x, to_stage.z)
			node.scale = Vector3.ONE
			var pitch := 0.22  # algo hacia abajo: el haz cae sobre el escenario
			var head := Node3D.new()
			head.position = Vector3(0, 1.05, 0)
			head.rotation.x = pitch
			node.add_child(head)
			_part(head, _cyl(0.13, 0.11, 0.3, 12), Vector3.ZERO, black).rotation.x = PI / 2
			for k in [-1, 1]:  # viseras
				var flap := _part(head, _unit_box(), Vector3(0.14 * k, 0, 0.19), black)
				flap.scale = Vector3(0.02, 0.2, 0.1)
				flap.rotation.y = 0.5 * k
			var lens := _part(head, _cyl(0.1, 0.1, 0.02, 12), Vector3(0, 0, 0.16), Color.WHITE)
			lens.rotation.x = PI / 2
			_glow(lens, Color(1.0, 0.95, 0.8), 4.0)
			var dir := Vector3(0, -sin(pitch), cos(pitch))
			if _building_scenery:  # fuera del plató: el foco apagado del todo no, pero sin luz ni haz (caros)
				return node
			var spot := SpotLight3D.new()
			spot.light_color = Color(1.0, 0.93, 0.8)
			spot.light_energy = 5.0
			spot.spot_range = 9.0
			spot.spot_angle = 24.0
			spot.spot_attenuation = 0.6
			spot.position = head.position + dir * 0.2
			spot.basis = Basis.looking_at(dir, Vector3.UP)
			node.add_child(spot)
			# Haz visible: cono translúcido que se abre desde la lente
			var beam := MeshInstance3D.new()
			beam.mesh = _cyl(0.09, 0.75, 3.2, 16)
			beam.position = head.position + dir * 1.75
			beam.basis = Basis(Vector3.RIGHT, pitch - PI / 2)  # el extremo estrecho (arriba del cilindro) en la lente
			beam.material_override = _beam_material()
			beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.add_child(beam)
			height = 1.2
		Biome.Prop.CAMERA:
			# Cámara de estudio sobre pedestal con ruedas: base de tres brazos, columna, cabeza con mandos,
			# cuerpo biselado con visor encendido, objetivo con parasol, piloto rojo y cable por el suelo.
			var dark := Color(0.16, 0.16, 0.18)
			var metal := _finish(Color(0.55, 0.57, 0.6), 0.35, 0.6)
			for i in 3:
				var a := i * TAU / 3.0
				var arm := _part(node, _unit_box(), Vector3(cos(a) * 0.14, 0.06, sin(a) * 0.14), dark)
				arm.scale = Vector3(0.3, 0.04, 0.05)
				arm.rotation.y = -a
				_part(node, _sphere(0.04, 0.08), Vector3(cos(a) * 0.28, 0.04, sin(a) * 0.28), Color(0.08, 0.08, 0.09))  # rueda
			_part(node, _cyl(0.04, 0.05, 0.72, 10), Vector3(0, 0.42, 0), Color.WHITE).material_override = metal
			_part(node, _cyl(0.08, 0.08, 0.06, 12), Vector3(0, 0.8, 0), dark)
			for sx in [-1, 1]:  # barras de mando hacia atrás
				var bar := _part(node, _cyl(0.012, 0.012, 0.36, 6), Vector3(0.1 * sx, 0.84, -0.22), dark)
				bar.rotation.x = PI / 2 - 0.3
			_part(node, _bevel_box(), Vector3(0, 0.95, -0.02), Color(0.24, 0.25, 0.27)).scale = Vector3(0.24, 0.24, 0.42)
			_part(node, _unit_box(), Vector3(0.122, 0.95, 0.0), Color(0.33, 0.34, 0.37)).scale = Vector3(0.005, 0.16, 0.3)
			var lens := _part(node, _cyl(0.07, 0.08, 0.24, 14), Vector3(0, 0.95, 0.3), dark)
			lens.rotation.x = PI / 2
			var hood := _part(node, _cyl(0.1, 0.08, 0.07, 14), Vector3(0, 0.95, 0.44), Color(0.1, 0.1, 0.11))
			hood.rotation.x = PI / 2
			_part(node, _bevel_box(), Vector3(0, 1.1, -0.12), dark).scale = Vector3(0.14, 0.09, 0.12)  # visor
			if not _building_scenery:
				var view := MeshInstance3D.new()
				view.mesh = _quad(0.11, 0.065)
				view.position = Vector3(0, 1.1, -0.181)
				view.rotation.y = PI
				view.material_override = _screen_material(Color(0.6, 0.8, 1.0), h % 7)
				node.add_child(view)
				_glow(_part(node, _sphere(0.02, 0.04), Vector3(0.08, 1.08, 0.12), Color.WHITE), Color(1.0, 0.1, 0.1), 3.0)
			_part(node, _cyl(0.012, 0.012, 0.5, 6), Vector3(0, 0.012, -0.4), dark).rotation.x = PI / 2  # cable
			# Mira al centro del tablero
			var to_center := -grid.to_world(c)
			node.rotation.y = atan2(to_center.x, to_center.z)
			height = 1.15
		Biome.Prop.PLANE:
			# Avión de pasajeros aparcado sobre su huella de 3×3: fuselaje con morro afilado y cola levantada,
			# cabina, fila de ventanillas, puertas y franja de la aerolínea; alas en flecha con winglets, motores
			# con toma de aire y pilón, estabilizadores, deriva, tren de aterrizaje y, alrededor, el equipo de
			# tierra (tractor con carros de equipaje, escalera y conos).
			node.scale = Vector3.ONE
			var cells := grid.footprint(c, 3)
			var mid := grid.footprint_center(cells) - grid.to_world(c)
			node.rotation.y = 0.0
			var body := Node3D.new()
			body.position = Vector3(mid.x, 0, mid.z)
			body.rotation.y = PI / 2 if h % 2 else 0.0
			node.add_child(body)
			# Fuselaje, alas, motores, deriva y tren en una malla de superficies suaves (AirlinerMesh), con
			# ventanillas, cabina y puertas pintadas por shader; una por aerolínea, compartida
			var stripe: Color = [Color(0.85, 0.2, 0.2), Color(0.2, 0.4, 0.8), Color(0.95, 0.65, 0.15)][h % 3]
			var key := "%d_%s" % [h % 3, _building_scenery]
			if not _planes.has(key):
				var mesh := AirlinerMesh.build(stripe)
				var shade := 1.0 - SCENERY_PROP_SHADE if _building_scenery else 1.0
				var mats := AirlinerMesh.materials(stripe, shade)
				for i in mats.size():
					mesh.surface_set_material(i, mats[i])
				_planes[key] = mesh
			var plane := MeshInstance3D.new()
			plane.mesh = _planes[key]
			body.add_child(plane)
			if not _building_scenery:
				_ground_crew(body, h)
			height = 1.3
		Biome.Prop.PLANE_PART:
			pass  # lo dibuja el avión de la casilla ancla
		Biome.Prop.CORAL:
			# Coral: ramas que se abren desde la base, de un color vivo, con puntas más claras; se mecen
			# con la corriente.
			var tint: Color = [Color(0.95, 0.45, 0.55), Color(0.98, 0.6, 0.3), Color(0.65, 0.4, 0.85), Color(0.3, 0.8, 0.75)][h % 4]
			_part(node, TerrainFx.rock_mesh(h % 4), Vector3(0, 0.04, 0), Color(0.35, 0.33, 0.3)).scale = Vector3(0.4, 0.12, 0.36)
			for i in 5 + h % 3:
				var a := TAU * i / 5.0 + float(h % 7)
				var tilt := 0.25 + float((h >> i) % 3) * 0.15
				var reach := 0.35 + float((h >> (i + 2)) % 4) * 0.08
				var branch := Node3D.new()
				branch.basis = Basis(Vector3(-sin(a), 0, cos(a)), tilt)
				branch.position = Vector3(cos(a), 0, sin(a)) * 0.06
				node.add_child(branch)
				_leaf(branch, _cyl(0.025, 0.045, reach, 6), Vector3(0, reach * 0.5, 0), tint, 0.5, 0.2)
				_leaf(branch, _sphere(0.04, 0.08), Vector3(0, reach, 0), tint.lightened(0.3), 0.5, 0.2)
			height = 0.6
	node.set_meta("sway_height", height * jitter)
	return node


## Hacia dónde se une el mueble de `c` (estantería, mesa) con los iguales de al lado y a la misma altura:
## {neg, pos: hay uno en ese extremo; turned: la hilera va en columna (solo en el tablero cuadrado)}. Los
## extremos son los del eje local x (con `turned`, -z y +z del mundo).
func _joins(c: Vector2i, prop: int) -> Dictionary:
	var same := func(n: Vector2i) -> bool:
		return grid.props.get(n, Biome.Prop.NONE) == prop and grid.heights.get(n, 0) == grid.heights.get(c, 0)
	var row := [same.call(c + Vector2i(-1, 0)), same.call(c + Vector2i(1, 0))]
	if grid.topology == BoardGrid.Topology.SQUARE and not (row[0] or row[1]):
		var col := [same.call(c + Vector2i(0, 1)), same.call(c + Vector2i(0, -1))]
		if col[0] or col[1]:
			return {"neg": col[0], "pos": col[1], "turned": true}  # girado 90°: el x local mira a -z
	return {"neg": row[0], "pos": row[1], "turned": false}


## Escalera de biblioteca apoyada en una cara de la estantería (`side` 1 o -1), con su barra de latón arriba.
func _library_ladder(node: Node3D, cx: float, d: float, top_y: float, side: int) -> void:
	var wood := Color(0.5, 0.33, 0.18)
	var foot := 0.15
	var tilt := atan2(foot, top_y)
	var length := sqrt(top_y * top_y + foot * foot)
	var x := cx + 0.12
	for k in [-1, 1]:
		var rail := _part(node, _unit_box(), Vector3(x + k * 0.15, top_y * 0.5, side * (d + 0.02 + foot * 0.5)), wood)
		rail.scale = Vector3(0.025, length, 0.03)
		rail.rotation.x = -tilt * side
	for i in 5:
		var t := (i + 1) / 6.0
		_part(node, _unit_box(), Vector3(x, top_y * t, side * (d + 0.02 + foot * (1.0 - t))), wood).scale = Vector3(0.3, 0.02, 0.03)
	var bar := _part(node, _cyl(0.01, 0.01, 0.9, 6), Vector3(cx, top_y - 0.04, side * (d + 0.025)), Color(0.75, 0.6, 0.3))
	bar.rotation.z = PI / 2


## Material de las hileras de libros (color de vértice), más oscuro en el campo de adorno.
func _books_material() -> StandardMaterial3D:
	var key := "books_far" if _building_scenery else "books"
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.albedo_color = Color.WHITE.darkened(SCENERY_PROP_SHADE) if _building_scenery else Color.WHITE
		_mats[key] = m
	return _mats[key]


## Hilera de libros de una balda (malla compartida, con color de vértice): de pie con lomos, grosores,
## alturas y fondos distintos, alguno con bandas doradas o etiqueta, huecos con un libro inclinado y pilas
## tumbadas. Las últimas variantes son baldas medio vacías. Va de -BOOK_ROW_HALF a BOOK_ROW_HALF en x, de
## pie en y = 0 y con los lomos en z = 0 (los libros hacia -z). Solo caras visibles: sin la de abajo ni la
## de atrás.
func _book_row(variant: int) -> ArrayMesh:
	var key := "books_%d" % variant
	if _prims.has(key):
		return _prims[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = variant * 7919 + 13
	var a := [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedInt32Array()]
	var sparse := variant >= BOOK_ROWS - 2
	var end := BOOK_ROW_HALF - (rng.randf_range(0.35, 0.55) if sparse else 0.0)
	var x := -BOOK_ROW_HALF
	var lean := 0.0  # hueco a la izquierda: el libro siguiente se apoya en él
	while x < end - 0.03:
		var r := rng.randf()
		if r < 0.08 and end - x > 0.22:
			var w := rng.randf_range(0.15, 0.2)
			var y := 0.0
			for i in rng.randi_range(2, 4):
				var t := rng.randf_range(0.028, 0.045)
				var depth := rng.randf_range(0.15, 0.2)
				var xf := Transform3D(Basis(Vector3.UP, rng.randf_range(-0.08, 0.08)), Vector3(x + w * 0.5, y + t * 0.5, -depth * 0.5 - 0.01))
				_box_into(a, xf, Vector3(w * rng.randf_range(0.85, 1.0), t, depth), _book_color(rng))
				y += t
			x += w + 0.015
			lean = 0.0
			continue
		if r < 0.14 and lean == 0.0 and end - x > 0.12:
			lean = rng.randf_range(0.04, 0.08)
			x += lean
			continue
		var t := rng.randf_range(0.026, 0.062)
		var tall := rng.randf_range(0.19, 0.29)
		var depth := rng.randf_range(0.16, 0.23)
		var col := _book_color(rng)
		var basis := Basis()
		var center := Vector3(x + t * 0.5, tall * 0.5, -depth * 0.5 - rng.randf_range(0.0, 0.025))
		if lean > 0.0:
			# Se apoya en la esquina de abajo a la derecha y cae hacia el hueco
			var ang := minf(asin(clampf(lean / tall, 0.0, 1.0)), 0.4)
			basis = Basis(Vector3.BACK, ang)
			center = Vector3(x + t, 0.0, center.z) + basis * Vector3(-t * 0.5, tall * 0.5, 0.0)
			lean = 0.0
		var xf := Transform3D(basis, center)
		_box_into(a, xf, Vector3(t, tall, depth), col)
		var face := depth * 0.5 + 0.002
		if rng.randf() < 0.35:
			var band := Color(0.8, 0.64, 0.3) if rng.randf() < 0.7 else col.lightened(0.35)
			for k in [-1, 1]:
				_box_into(a, xf * Transform3D(Basis(), Vector3(0, k * tall * 0.32, face)), Vector3(t * 0.94, 0.012, 0.004), band, true)
		elif rng.randf() < 0.2:
			_box_into(a, xf * Transform3D(Basis(), Vector3(0, tall * 0.18, face)), Vector3(t * 0.7, 0.04, 0.004), Color(0.86, 0.8, 0.66), true)
		x += t + rng.randf_range(0.0, 0.004)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = a[0]
	arrays[Mesh.ARRAY_NORMAL] = a[1]
	arrays[Mesh.ARRAY_COLOR] = a[2]
	arrays[Mesh.ARRAY_INDEX] = a[3]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_prims[key] = mesh
	return mesh


## Color de tapa de un libro: piel, tela o papel, con algo de variación.
func _book_color(rng: RandomNumberGenerator) -> Color:
	var col: Color = BOOK_COLORS[rng.randi_range(0, BOOK_COLORS.size() - 1)]
	var v := rng.randf_range(-0.12, 0.12)
	return col.lightened(v) if v > 0.0 else col.darkened(-v)


## Añade a `a` ([vértices, normales, colores, índices]) una caja de medidas `size` con la transformación `xf`.
## Sin la cara de abajo ni la de atrás (-z); `front_only`: solo la de delante (bandas y etiquetas del lomo).
func _box_into(a: Array, xf: Transform3D, size: Vector3, color: Color, front_only := false) -> void:
	var hs := size * 0.5
	var faces := [Vector3.BACK] if front_only else [Vector3.BACK, Vector3.UP, Vector3.LEFT, Vector3.RIGHT]
	for n: Vector3 in faces:
		# Dos ejes de la cara, en el orden que deja el triángulo mirando hacia fuera
		var u := Vector3.UP if absf(n.y) < 0.5 else Vector3.RIGHT
		var v := n.cross(u)
		var base: int = a[0].size()
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			a[0].append(xf * ((n + u * corner.x + v * corner.y) * hs))
			a[1].append((xf.basis * n).normalized())
			a[2].append(color)
		a[3].append_array([base, base + 2, base + 1, base, base + 3, base + 2])


## Columna del gimnasio con la forma de su tipo (los que no tienen otro obstáculo): clásica de mármol
## (neutral), pilar liso (normal), poste de dojo con cuerdas (lucha), columna fina con alas (volador),
## pararrayos con bobinas encendidas (eléctrico), con anillos de oro y cuernos (dragón), obsidiana con
## vetas rojas (siniestro), acero remachado (acero), basalto con brasas (fuego), mármol con olas (agua) y
## columna con anillos tóxicos (veneno).
func _pillar(node: Node3D, type: String) -> void:
	var style := Biome.gym_style(type)
	var stone: Color = style.pillar
	var line: Color = style.line
	match type:
		"normal":
			_part(node, _unit_box(), Vector3(0, 0.05, 0), stone.darkened(0.15)).scale = Vector3(0.6, 0.1, 0.6)
			_part(node, _unit_box(), Vector3(0, 0.7, 0), stone).scale = Vector3(0.44, 1.2, 0.44)
			_part(node, _unit_box(), Vector3(0, 0.95, 0), line).scale = Vector3(0.46, 0.08, 0.46)
			_part(node, _unit_box(), Vector3(0, 1.34, 0), stone.darkened(0.15)).scale = Vector3(0.58, 0.08, 0.58)
		"fighting":
			var wood := Color(0.5, 0.34, 0.2)
			_part(node, _cyl(0.2, 0.22, 1.35, 8), Vector3(0, 0.68, 0), wood)
			for y in [0.35, 0.5, 0.95, 1.1]:
				_part(node, _cyl(0.23, 0.23, 0.07, 8), Vector3(0, y, 0), Color(0.86, 0.78, 0.6))  # cuerda
			_part(node, _cyl(0.24, 0.24, 0.12, 8), Vector3(0, 0.72, 0), line)  # cinta roja del dojo
			_part(node, _cyl(0.05, 0.26, 0.1, 8), Vector3(0, 1.4, 0), wood.darkened(0.3))
		"flying":
			_part(node, _cyl(0.16, 0.2, 1.25, 12), Vector3(0, 0.62, 0), stone)
			_part(node, _cyl(0.26, 0.26, 0.08, 12), Vector3(0, 1.28, 0), line)
			for k in [-1, 1]:
				var wing := _part(node, _unit_box(), Vector3(0.24 * k, 1.42, 0), stone.lightened(0.1))
				wing.scale = Vector3(0.42, 0.05, 0.18)
				wing.rotation.z = 0.45 * k
		"electric":
			var metal := _finish(Color(0.24, 0.24, 0.27), 0.35, 0.7)
			var shaft := _part(node, _cyl(0.14, 0.2, 1.2, 10), Vector3(0, 0.6, 0), Color.WHITE)
			shaft.material_override = metal
			for i in 3:
				_glow(_part(node, _cyl(0.24, 0.24, 0.06, 12), Vector3(0, 0.4 + 0.3 * i, 0), Color.WHITE), line, 2.2)
			_part(node, _cyl(0.0, 0.04, 0.35, 6), Vector3(0, 1.37, 0), Color.WHITE).material_override = metal
			_glow(_part(node, _sphere(0.07, 0.14), Vector3(0, 1.56, 0), Color.WHITE), line.lightened(0.3), 3.0)
		"dragon":
			_part(node, _cyl(0.22, 0.27, 1.3, 10), Vector3(0, 0.65, 0), stone)
			var gold := _finish(line, 0.25, 1.0)
			for y in [0.15, 0.7, 1.25]:
				_part(node, _cyl(0.29, 0.29, 0.07, 10), Vector3(0, y, 0), Color.WHITE).material_override = gold
			for k in [-1, 1]:
				var horn := _part(node, _cyl(0.0, 0.07, 0.45, 6), Vector3(0.13 * k, 1.45, 0), Color.WHITE)
				horn.material_override = gold
				horn.rotation.z = -0.4 * k
		"dark":
			var obsidian := _finish(stone, 0.2, 0.0)
			_part(node, _cyl(0.26, 0.3, 1.35, 6), Vector3(0, 0.68, 0), Color.WHITE).material_override = obsidian
			for i in 3:
				var a := TAU * i / 3.0 + 0.5
				var vein := _part(node, _unit_box(), Vector3(cos(a), 0, sin(a)) * 0.27 + Vector3(0, 0.7, 0), Color.WHITE)
				vein.scale = Vector3(0.035, 0.9 + 0.15 * i, 0.035)
				_glow(vein, line, 2.0)
			_part(node, _cyl(0.0, 0.3, 0.22, 6), Vector3(0, 1.46, 0), Color.WHITE).material_override = obsidian
		"steel":
			var steel := _finish(stone.lightened(0.15), 0.35, 0.55)  # sin mucho que reflejar, el metal puro sale negro
			_part(node, _cyl(0.24, 0.24, 1.3, 16), Vector3(0, 0.65, 0), Color.WHITE).material_override = steel
			for y in [0.08, 1.32]:
				_part(node, _cyl(0.32, 0.32, 0.1, 16), Vector3(0, y, 0), Color.WHITE).material_override = _finish(line.lightened(0.1), 0.4, 0.5)
			for y in [0.45, 0.9]:
				for i in 8:
					var a := TAU * i / 8.0
					_part(node, _sphere(0.025, 0.05), Vector3(cos(a) * 0.245, y, sin(a) * 0.245), Color.WHITE).material_override = steel
		"fire":
			_part(node, _cyl(0.24, 0.3, 1.2, 8), Vector3(0, 0.6, 0), stone)
			_part(node, _cyl(0.34, 0.22, 0.2, 8), Vector3(0, 1.3, 0), stone.darkened(0.3))
			_glow(_part(node, _cyl(0.28, 0.28, 0.03, 8), Vector3(0, 1.39, 0), Color.WHITE), Color(1.0, 0.45, 0.1), 3.0)
			for i in 2:
				_glow(_part(node, _cyl(0.245 + 0.02 * i, 0.245 + 0.02 * i, 0.04, 8), Vector3(0, 0.5 + 0.35 * i, 0), Color.WHITE), line, 1.6)
		"water":
			_part(node, _cyl(0.22, 0.26, 1.3, 14), Vector3(0, 0.65, 0), stone)
			for i in 3:
				_part(node, _cyl(0.25, 0.25, 0.06, 14), Vector3(0, 0.35 + 0.3 * i, 0), line.lightened(0.15 * i))  # olas
			_part(node, _cyl(0.34, 0.28, 0.1, 14), Vector3(0, 1.33, 0), stone.darkened(0.1))
		"poison":
			_part(node, _cyl(0.22, 0.27, 1.3, 10), Vector3(0, 0.65, 0), stone)
			for i in 2:
				_glow(_part(node, _cyl(0.26, 0.26, 0.08, 10), Vector3(0, 0.45 + 0.5 * i, 0), Color.WHITE), Color(0.75, 0.35, 0.95), 1.8)
			_part(node, _sphere(0.2, 0.3), Vector3(0, 1.38, 0), stone.darkened(0.2))
		_:
			# Neutral (y cualquier columna fuera del gimnasio): mármol clásico con basa, fuste y capitel.
			_part(node, _unit_box(), Vector3(0, 0.06, 0), stone.darkened(0.12)).scale = Vector3(0.66, 0.12, 0.66)
			_part(node, _cyl(0.32, 0.32, 0.08, 16), Vector3(0, 0.16, 0), stone)
			_part(node, _cyl(0.23, 0.27, 1.05, 16), Vector3(0, 0.72, 0), stone)
			for i in 8:
				var a := TAU * i / 8.0
				_part(node, _cyl(0.03, 0.035, 1.0, 5), Vector3(cos(a), 0, sin(a)) * 0.245 + Vector3(0, 0.72, 0), stone.darkened(0.08))
			_part(node, _cyl(0.33, 0.25, 0.12, 16), Vector3(0, 1.3, 0), stone)
			_part(node, _unit_box(), Vector3(0, 1.39, 0), stone.darkened(0.12)).scale = Vector3(0.7, 0.07, 0.7)
			if type == "" and _look == Biome.Kind.GYM:
				_part(node, _cyl(0.275, 0.275, 0.05, 16), Vector3(0, 0.3, 0), line)


## Edificio del campo de adorno de la Ciudad: una de CITY_VARIANTS variantes, cada una hecha y fundida una sola
## vez (cientos de edificios pieza a pieza alargaban la carga). Devuelve la altura de los muros.
func _scenery_building(node: Node3D, h: int) -> float:
	var key := hash(h % CITY_VARIANTS)
	if not _city_variants.has(key):
		var model := Node3D.new()
		var tall := _city_building(model, key)
		_bake(model)
		var parts := []
		for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			parts.append([mi.mesh, mi.material_override])
		model.free()
		_city_variants[key] = [tall, parts]
	for part: Array in _city_variants[key][1]:
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.material_override = part[1]
		node.add_child(mi)
	return _city_variants[key][0]


## Edificio de la Ciudad, según `h`: casa de 1 o 2 plantas con tejado a dos aguas, chimenea, contraventanas y
## porche, o bloque de 2 o 3 plantas con cornisas entre plantas, pretil, depósito o máquinas en la azotea y a
## veces una tienda con toldo de rayas en la planta baja. Ventanas con marco, alféizar y cristal con brillo; la
## puerta da a +z. Fuera del tablero (campo de adorno) se queda la silueta, sin los detalles pequeños. Devuelve
## la altura de los muros.
func _city_building(node: Node3D, h: int) -> float:
	const W := 0.86  # ancho del cuerpo
	const FH := 0.4  # alto de cada planta
	const BASE := 0.08  # zócalo
	var walls := [Color(0.68, 0.38, 0.3), Color(0.9, 0.82, 0.66), Color(0.74, 0.75, 0.76), Color(0.84, 0.64, 0.44),
		Color(0.64, 0.76, 0.84), Color(0.72, 0.82, 0.68), Color(0.9, 0.7, 0.68)]
	var wall: Color = walls[h % walls.size()]
	var trim := Color(0.95, 0.93, 0.88)
	var detail := not _building_scenery
	var house := (h >> 3) % 3 == 0
	var floors := 1 + (h >> 5) % 2 if house else 2 + (h >> 5) % 2
	var shop := not house and (h >> 6) % 2 == 0
	var top := BASE + FH * floors
	var glass_color := Color(0.3, 0.44, 0.56).darkened(SCENERY_PROP_SHADE if _building_scenery else 0.0)
	var glass := _finish(glass_color, 0.08, 0.3)
	var accent: Color = [Color(0.25, 0.45, 0.3), Color(0.24, 0.36, 0.6), Color(0.55, 0.22, 0.2), Color(0.4, 0.3, 0.22)][(h >> 7) % 4]
	_part(node, _unit_box(), Vector3(0, BASE * 0.5, 0), wall.darkened(0.45)).scale = Vector3(W + 0.03, BASE, W + 0.03)
	_part(node, _unit_box(), Vector3(0, BASE + FH * floors * 0.5, 0), wall).scale = Vector3(W, FH * floors, W)
	# Pieza pegada a una fachada: `out` es la cara, `along` el desplazamiento por ella, `stand` cuánto sale
	var face := func(out: Vector3, along: float, y: float, size: Vector3, stand: float, color: Color) -> MeshInstance3D:
		var across := Vector3(-out.z, 0, out.x)
		var p := _part(node, _unit_box(), Vector3(0, y, 0) + out * (W * 0.5 + stand) + across * along, color)
		p.scale = across.abs() * size.x + Vector3(0, size.y, 0) + out.abs() * size.z
		return p
	var window := func(out: Vector3, along: float, y: float, shutters: bool) -> void:
		if detail:
			face.call(out, along, y, Vector3(0.2, 0.25, 0.02), 0.0, trim)  # marco
			face.call(out, along, y - 0.135, Vector3(0.24, 0.025, 0.06), 0.02, trim.darkened(0.08))  # alféizar
			if shutters:
				for k in [-1, 1]:
					face.call(out, along + k * 0.15, y, Vector3(0.07, 0.25, 0.02), 0.005, accent)
		face.call(out, along, y, Vector3(0.15, 0.2, 0.02), 0.008, Color.WHITE).material_override = glass
	var front := Vector3(0, 0, 1)
	for f in floors:
		var y := BASE + FH * f + FH * 0.55
		for side in 4:
			var out := Vector3(cos(side * PI / 2), 0, sin(side * PI / 2)).round()
			var ground_front := f == 0 and out == front
			if ground_front and shop:
				continue
			for k in [-1, 1]:
				window.call(out, (0.27 if ground_front else 0.2) * k, y, house and not ground_front)
		if f > 0 and detail:  # cornisa entre plantas
			_part(node, _unit_box(), Vector3(0, BASE + FH * f, 0), trim.darkened(0.12)).scale = Vector3(W + 0.025, 0.025, W + 0.025)
	# Puerta (o el escaparate de la tienda)
	if shop:
		var awning: Color = [Color(0.85, 0.25, 0.22), Color(0.2, 0.5, 0.75), Color(0.25, 0.6, 0.35), Color(0.9, 0.6, 0.15)][(h >> 8) % 4]
		face.call(front, 0.0, BASE + 0.15, Vector3(0.7, 0.28, 0.02), 0.0, wall.darkened(0.55))  # hueco
		face.call(front, -0.1, BASE + 0.16, Vector3(0.44, 0.24, 0.02), 0.008, Color.WHITE).material_override = glass
		face.call(front, 0.24, BASE + 0.13, Vector3(0.14, 0.26, 0.02), 0.008, accent)  # puerta de la tienda
		face.call(front, 0.0, BASE + 0.34, Vector3(0.6, 0.06, 0.02), 0.01, trim)  # rótulo
		# Toldo inclinado: lona a rayas (lisa fuera del tablero)
		var hold := Node3D.new()
		hold.position = Vector3(0, BASE + 0.31, W * 0.5)
		hold.rotation.x = 0.5
		node.add_child(hold)
		var stripes := 6 if detail else 1
		for i in stripes:
			var col: Color = awning if i % 2 == 0 else trim
			var piece := _part(hold, _unit_box(), Vector3(-0.36 + 0.72 * (i + 0.5) / stripes, 0, 0.11), col)
			piece.scale = Vector3(0.72 / stripes, 0.015, 0.22)
	else:
		face.call(front, 0.0, BASE + 0.15, Vector3(0.2, 0.3, 0.02), 0.0, trim)
		face.call(front, 0.0, BASE + 0.14, Vector3(0.14, 0.26, 0.02), 0.008, accent.darkened(0.2))
		if detail:
			face.call(front, 0.0, BASE - 0.02, Vector3(0.26, 0.04, 0.1), 0.04, wall.darkened(0.35))  # escalón
			face.call(front, 0.04, BASE + 0.13, Vector3(0.02, 0.02, 0.02), 0.02, Color(0.85, 0.75, 0.35))  # pomo
		# Porche (casa) o marquesina (bloque) sobre la puerta
		face.call(front, 0.0, BASE + 0.32, Vector3(0.32, 0.03, 0.14), 0.07, trim.darkened(0.1))
	if house:
		_gable_roof(node, top, W, h, wall)
	else:
		# Azotea: pretil alrededor, tapa y depósito de agua o máquinas de clima
		var cap := wall.darkened(0.25)
		_part(node, _unit_box(), Vector3(0, top + 0.005, 0), cap.darkened(0.2)).scale = Vector3(W - 0.02, 0.01, W - 0.02)
		for side in 4:
			var out := Vector3(cos(side * PI / 2), 0, sin(side * PI / 2)).round()
			var across := Vector3(-out.z, 0, out.x)
			var p := _part(node, _unit_box(), Vector3(0, top + 0.04, 0) + out * (W * 0.5 - 0.01), cap)
			p.scale = across.abs() * (W + 0.04) + Vector3(0, 0.08, 0) + out.abs() * 0.05
		if (h >> 9) % 2 == 0:
			var metal := Color(0.5, 0.52, 0.55)
			for k in 4:
				var leg := Vector3(0.06 * (1 if k % 2 else -1), 0, 0.06 * (1 if k >= 2 else -1))
				_part(node, _unit_box(), Vector3(0.16, top + 0.07, -0.14) + leg, metal.darkened(0.3)).scale = Vector3(0.02, 0.14, 0.02)
			_part(node, _cyl(0.11, 0.11, 0.18, 12), Vector3(0.16, top + 0.23, -0.14), Color(0.62, 0.5, 0.38))
			_part(node, _cyl(0.0, 0.12, 0.06, 12), Vector3(0.16, top + 0.35, -0.14), Color(0.45, 0.36, 0.28))
		else:
			for k in (2 if detail else 1):
				var box := _part(node, _bevel_box(), Vector3(-0.18 + 0.3 * k, top + 0.08, -0.16), Color(0.82, 0.83, 0.84))
				box.scale = Vector3(0.2, 0.14, 0.16)
				if detail:
					_part(node, _cyl(0.05, 0.05, 0.01, 10), Vector3(-0.18 + 0.3 * k, top + 0.155, -0.16), Color(0.3, 0.31, 0.33))
	return top


## Tejado a dos aguas de una casa de la Ciudad sobre muros de ancho `w` y alto `top`: hastiales del color del muro,
## faldones de teja con hileras, cumbrera y chimenea de ladrillo.
func _gable_roof(node: Node3D, top: float, w: float, h: int, wall: Color) -> void:
	var tile: Color = [Color(0.7, 0.32, 0.22), Color(0.36, 0.38, 0.44), Color(0.45, 0.3, 0.24), Color(0.3, 0.45, 0.48)][(h >> 10) % 4]
	var rise := 0.3
	var run := w * 0.5
	# Hastial: un prisma (caja girada 45° y aplastada) que llena el triángulo de las dos fachadas laterales
	var gable := Node3D.new()
	gable.position = Vector3(0, top, 0)
	gable.scale = Vector3(1, rise / run, 1)
	node.add_child(gable)
	var prism := _part(gable, _unit_box(), Vector3.ZERO, wall)
	prism.rotation.x = PI / 4
	prism.scale = Vector3(w - 0.01, w / sqrt(2.0), w / sqrt(2.0))
	# Faldones con alero
	var slope := atan2(rise, run)
	var length := Vector2(run + 0.08, rise + 0.08 * rise / run).length()
	var rows := 3 if not _building_scenery else 0
	for s in [-1, 1]:
		var hold := Node3D.new()
		hold.position = Vector3(0, top + rise, 0)
		hold.rotation.x = s * slope
		node.add_child(hold)
		var slab := _part(hold, _unit_box(), Vector3(0, 0.02, s * length * 0.5), tile)
		slab.scale = Vector3(w + 0.12, 0.04, length)
		for i in rows:  # hileras de teja
			var row := _part(hold, _unit_box(), Vector3(0, 0.045, s * length * (0.25 + 0.25 * i)), tile.darkened(0.18))
			row.scale = Vector3(w + 0.12, 0.012, 0.025)
	_part(node, _unit_box(), Vector3(0, top + rise + 0.035, 0), tile.darkened(0.25)).scale = Vector3(w + 0.14, 0.05, 0.06)
	# Chimenea
	var chim := Vector3(0.22 * (1 if h % 2 else -1), 0, -0.14)
	var brick := Color(0.6, 0.32, 0.26)
	var base_y := top + rise * (1.0 - absf(chim.z) / run)
	_part(node, _unit_box(), Vector3(chim.x, base_y + 0.08, chim.z), brick).scale = Vector3(0.1, 0.3, 0.1)
	_part(node, _unit_box(), Vector3(chim.x, base_y + 0.24, chim.z), brick.darkened(0.3)).scale = Vector3(0.13, 0.03, 0.13)


## Tramo de la terminal del aeropuerto (una casilla de la fila): fachada de cristal con montantes blancos,
## zócalo de hormigón y cubierta en voladizo; la casilla central lleva la torre de control. Devuelve la altura.
func _terminal(node: Node3D, c: Vector2i) -> float:
	var white := Color(0.92, 0.93, 0.95)
	var concrete := Color(0.7, 0.69, 0.66)
	var glass := _finish(Color(0.32, 0.5, 0.64), 0.08, 0.4)
	_part(node, _unit_box(), Vector3(0, 0.06, 0), concrete).scale = Vector3(1.0, 0.12, 0.9)
	var pane := _part(node, _unit_box(), Vector3(0, 0.52, 0), Color.WHITE)
	pane.scale = Vector3(0.98, 0.8, 0.8)
	pane.material_override = glass
	for i in 5:
		var x := -0.48 + 0.24 * i
		for z in [-0.405, 0.405]:
			_part(node, _unit_box(), Vector3(x, 0.52, z), white).scale = Vector3(0.03, 0.8, 0.02)
	for z in [-0.405, 0.405]:
		_part(node, _unit_box(), Vector3(0, 0.5, z), white).scale = Vector3(0.98, 0.025, 0.02)
	_part(node, _unit_box(), Vector3(0, 0.96, 0), white).scale = Vector3(1.04, 0.08, 1.1)  # cubierta en voladizo
	_part(node, _unit_box(), Vector3(0, 1.01, 0), concrete.darkened(0.2)).scale = Vector3(1.02, 0.02, 1.06)
	# Aleros verticales sobre la fachada y, en el tejado, máquinas de climatización con rejilla
	for x in [-0.36, 0.0, 0.36]:
		for z in [-0.5, 0.5]:
			_part(node, _unit_box(), Vector3(x, 0.92, z), white.darkened(0.05)).scale = Vector3(0.04, 0.1, 0.12)
	if (c.x + c.y) % 3 == 0:
		_part(node, _bevel_box(), Vector3(0.18, 1.1, -0.1), Color(0.75, 0.76, 0.78)).scale = Vector3(0.3, 0.16, 0.26)
		_part(node, _cyl(0.07, 0.07, 0.02, 12), Vector3(0.18, 1.19, -0.1), Color(0.3, 0.31, 0.33))
	if c.x % 4 == 1:  # puerta de entrada con su marquesina y letrero luminoso
		_part(node, _unit_box(), Vector3(0, 0.3, 0.42), Color(0.2, 0.22, 0.26)).scale = Vector3(0.34, 0.48, 0.01)
		_part(node, _unit_box(), Vector3(0, 0.6, 0.48), white).scale = Vector3(0.5, 0.03, 0.14)
		if not _building_scenery:
			_glow(_part(node, _unit_box(), Vector3(0, 0.74, 0.415), Color.WHITE), Color(0.35, 0.6, 1.0), 1.5).scale = Vector3(0.4, 0.08, 0.01)
	if c.x != grid.width / 2:
		return 1.0
	# Torre de control: fuste, cabina acristalada (más ancha) con techo oscuro y antena con baliza roja
	_part(node, _cyl(0.16, 0.2, 1.4, 12), Vector3(0, 1.7, 0), white)
	_part(node, _cyl(0.36, 0.26, 0.12, 12), Vector3(0, 2.44, 0), white)
	_part(node, _cyl(0.38, 0.32, 0.36, 12), Vector3(0, 2.68, 0), Color.WHITE).material_override = glass
	_part(node, _cyl(0.2, 0.42, 0.1, 12), Vector3(0, 2.91, 0), Color(0.25, 0.27, 0.3))
	_part(node, _cyl(0.012, 0.012, 0.4, 5), Vector3(0, 3.16, 0), Color(0.6, 0.62, 0.65))
	_glow(_part(node, _sphere(0.035, 0.07), Vector3(0, 3.38, 0), Color.WHITE), Color(1.0, 0.15, 0.1), 4.0)
	return 3.4


var _beam_mat: StandardMaterial3D


## Haz de luz de los focos: aditivo, sin sombra y que se desvanece hacia los lados.
func _beam_material() -> StandardMaterial3D:
	if _beam_mat == null:
		_beam_mat = StandardMaterial3D.new()
		_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_beam_mat.albedo_color = Color(1.0, 0.92, 0.75, 0.07)
		_beam_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_beam_mat.rim_enabled = false
		_beam_mat.proximity_fade_enabled = true
		_beam_mat.proximity_fade_distance = 0.6
	return _beam_mat


## Material con acabado propio (metal, obsidiana pulida), compartido por color y acabado.
func _finish(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var key := "finish_%s_%.2f_%.2f" % [color.to_html(), roughness, metallic]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = roughness
		m.metallic = metallic
		_mats[key] = m
	return _mats[key]


## Puente de madera sobre el agua: tablones atravesados al paso, vigas por debajo y, en los lados que
## dan al agua, barandilla con postes.
func _bridge(root: Node3D, c: Vector2i, top: Vector3) -> void:
	var liquid := Biome.Tile.LAVA if _look == Biome.Kind.VOLCANO else Biome.Tile.WATER
	var wood := Color(0.3, 0.24, 0.2) if liquid == Biome.Tile.LAVA else Color(0.52, 0.37, 0.23)  # chamuscada sobre la lava
	var on_water := func(n: Vector2i) -> bool:
		return not grid.is_inside(n) or grid.tiles.get(n, 0) in [liquid, Biome.Tile.BRIDGE]
	# Los tablones van de lado a lado (hacia donde hay agua o más puente) y se suceden en el sentido del paso
	var across := Vector3.RIGHT
	if grid.topology == BoardGrid.Topology.SQUARE and not (on_water.call(c + Vector2i(1, 0)) and on_water.call(c - Vector2i(1, 0))):
		across = Vector3.BACK
	var along := Vector3(-across.z, 0, across.x)
	var count := 5
	for i in count:
		var plank := _part(root, _unit_box(), top + Vector3(0, -0.035, 0) + along * ((i + 0.5) / count - 0.5), wood.darkened(0.06 * ((hash(c) + i) % 3)))
		plank.scale = (across * 0.98 + along * (0.9 / count)).abs() + Vector3(0, 0.05, 0)
	for k in [-0.3, 0.3]:
		var beam := _part(root, _unit_box(), top + Vector3(0, -0.1, 0) + across * k, wood.darkened(0.3))
		beam.scale = (along + across * 0.08).abs() + Vector3(0, 0.08, 0)
	var edge := 1.0 if grid.topology == BoardGrid.Topology.SQUARE else 1.0 / sqrt(3.0)
	for n in grid.neighbors(c):
		if grid.tiles.get(n, 0) != liquid:
			continue
		var out := grid.to_world(n) - grid.to_world(c)
		out.y = 0.0
		out = out.normalized()
		var side := Vector3(-out.z, 0, out.x)
		var rail := _part(root, _unit_box(), top + out * 0.44 + Vector3(0, 0.3, 0), wood.darkened(0.1))
		rail.scale = (side * edge + out * 0.06).abs() + Vector3(0, 0.05, 0)
		for k in [-0.5, 0.5]:
			var post := _part(root, _unit_box(), top + out * 0.44 + side * edge * k * 0.9 + Vector3(0, 0.05, 0), wood.darkened(0.2))
			post.scale = Vector3(0.07, 0.6, 0.07)


## Línea discontinua blanca en el centro de una calle de dos carriles (solo en tramos rectos, no en cruces).
func _road_marks(root: Node3D, c: Vector2i, top: Vector3) -> void:
	if grid.topology != BoardGrid.Topology.SQUARE:
		return
	var road := func(n: Vector2i) -> bool: return grid.tiles.get(n, -1) == Biome.Tile.ROAD
	for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
		var side := Vector2i(-d.y, d.x)
		# El otro carril está en `d`, al otro lado no hay calle y la calle sigue recta hacia los dos lados
		if road.call(c + d) and not road.call(c - d) and road.call(c + side) and road.call(c - side):
			var dash := _part(root, _unit_box(), top + Vector3(d.x, 0, d.y) * 0.5 + Vector3(0, 0.004, 0), Color(0.92, 0.9, 0.82))
			dash.scale = (Vector3(side.x, 0, side.y) * 0.45 + Vector3(d.x, 0, d.y) * 0.06).abs() + Vector3(0, 0.008, 0)
			dash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Hace que una pieza brille con luz propia (pantallas, pilotos, líquidos, la boca de una fumarola).
func _glow(mi: MeshInstance3D, color: Color, energy: float) -> MeshInstance3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	mi.material_override = m
	return mi


## Da a las partes que se mecen (las de material con viento) su base y altura en el mundo.
func _root_sway(node: Node3D, base_y: float) -> void:
	var height: float = node.get_meta("sway_height", 1.0)
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mi.material_override is ShaderMaterial:
			mi.set_instance_shader_parameter("base_y", base_y)
			mi.set_instance_shader_parameter("height", height)


## Parte con viento: `sway` cuánto se dobla, `flutter` cuánto tiemblan las hojas.
## `pattern`: textura del shader (1 copa de hojas, 2 agujas de pino, 3 corteza, 4 corteza con musgo).
func _leaf(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color, sway: float, flutter := 0.0, pattern := 0) -> MeshInstance3D:
	if _building_scenery:
		color = color.darkened(SCENERY_PROP_SHADE)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = _live("leaf_%s_%.2f_%.2f_%d" % [color.to_html(), sway, flutter, pattern],
		func() -> ShaderMaterial:
			var m := TerrainFx.foliage_material(color, sway, flutter)
			m.set_shader_parameter("pattern", pattern)
			return m)
	parent.add_child(mi)
	return mi


## Punta de cristal: facetas, refracción y un pulso lento de luz (TerrainFx.CRYSTAL_SHADER).
func _crystal(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = _live("crystal_%s" % color.to_html(), func() -> ShaderMaterial:
		return TerrainFx.crystal_material(color))
	parent.add_child(mi)
	return mi


## Material con viento, compartido por clave (así `set_wind` llega a todos).
func _live(key: String, make: Callable) -> ShaderMaterial:
	if not _live_mats.has(key):
		var m: ShaderMaterial = make.call()
		m.set_shader_parameter("wind", _wind)
		_live_mats[key] = m
	return _live_mats[key]


## Color propio de cada suelo en este bioma (y estilo de gimnasio), antes de manchas y ajedrezado.
func _base_color(tile_kind: int) -> Color:
	var color: Color = Biome.TILE_COLORS[tile_kind]
	if tile_kind == Biome.Tile.GRASS and _look == Biome.Kind.FOREST:
		color = Color(0.32, 0.56, 0.28)
	elif tile_kind == Biome.Tile.GRASS and _look == Biome.Kind.SWAMP:
		color = Color(0.36, 0.48, 0.24)  # hierba de pantano, oliva
	elif tile_kind == Biome.Tile.ROCK and _look == Biome.Kind.DESERT:
		color = Color(0.74, 0.52, 0.38)  # arenisca
	elif _look == Biome.Kind.VOLCANO and tile_kind in [Biome.Tile.ROCK, Biome.Tile.DIRT]:
		color = Color(0.24, 0.21, 0.2) if tile_kind == Biome.Tile.ROCK else Color(0.46, 0.43, 0.41)  # basalto y ceniza
	elif _look == Biome.Kind.LAB and tile_kind in [Biome.Tile.FLOOR, Biome.Tile.FLOOR_LINE]:
		color = Color(0.84, 0.88, 0.92) if tile_kind == Biome.Tile.FLOOR else Color(0.3, 0.78, 0.92)
	elif _look == Biome.Kind.CEMETERY and tile_kind == Biome.Tile.GRASS:
		color = Color(0.3, 0.42, 0.26)  # hierba oscura
	elif _look == Biome.Kind.LIBRARY and tile_kind == Biome.Tile.FLOOR_LINE:
		color = Color(0.55, 0.14, 0.16)  # alfombra granate
	elif _look == Biome.Kind.STUDIO and tile_kind in [Biome.Tile.FLOOR, Biome.Tile.FLOOR_LINE]:
		color = Color(0.2, 0.2, 0.22) if tile_kind == Biome.Tile.FLOOR else Color(0.95, 0.8, 0.2)  # suelo negro y cinta
	elif _look == Biome.Kind.AIRPORT and tile_kind == Biome.Tile.FLOOR:
		color = Color(0.68, 0.67, 0.64)  # hormigón de la plataforma
	elif _look == Biome.Kind.UNDERWATER and tile_kind in [Biome.Tile.CAVE, Biome.Tile.ROCK, Biome.Tile.SAND]:
		color = Biome.TILE_COLORS[tile_kind].lerp(Color(0.25, 0.45, 0.6), 0.35)  # todo teñido de azul
	elif _look == Biome.Kind.GYM and tile_kind in [Biome.Tile.FLOOR, Biome.Tile.FLOOR_LINE]:
		color = Biome.gym_style(grid.gym_type).floor if tile_kind == Biome.Tile.FLOOR else Biome.gym_style(grid.gym_type).line
	elif tile_kind == Biome.Tile.ICE:
		# Más azul que la nieve; en el gimnasio de Hielo, cian verdoso para no confundirse con sus líneas azules
		color = Color(0.58, 0.88, 0.9) if _look == Biome.Kind.GYM else Color(0.5, 0.76, 0.93)
	return color


## Color de la cara de arriba: el del suelo con manchas suaves (hierba más seca o más verde, arena más
## clara...), algo más claro cuanto más alto, y un ajedrezado tenue para distinguir las casillas.
func _tile_color(c: Vector2i, tile_kind: int) -> Color:
	if _building_scenery:
		return _scenery_color(c, tile_kind)
	var color := _base_color(tile_kind)
	var w := grid.to_world(c)
	var n := snappedf(_tint_noise.get_noise_2d(w.x, w.z), 0.25)
	if tile_kind == Biome.Tile.SNOW:
		# Nieve: ventisqueros iluminados y hondonadas en sombra azulada, en vez de un blanco plano
		# (el blanco puro se quema al sol: la nieve base es algo más gris para que se noten las sombras)
		color = Color(0.86, 0.89, 0.95).lerp(Color(0.97, 0.98, 1.0) if n > 0 else Color(0.62, 0.69, 0.86), minf(absf(n) * 1.4, 1.0))
	elif tile_kind == Biome.Tile.GRASS:
		color = color.lerp(Color(0.62, 0.7, 0.32) if n > 0 else Color(0.26, 0.52, 0.26), absf(n) * 0.45)
		if _tall_grass(c):
			color = color.darkened(0.12)  # bajo la hierba alta el suelo queda en sombra
	else:
		color = color.lightened(n * 0.08) if n > 0 else color.darkened(-n * 0.1)
	color = color.lightened(0.04 * grid.get_height(c))
	if (c.x + c.y) % 2 == 0:
		color = color.darkened(0.04)
	return color


func _side_material(tile_kind: int) -> ShaderMaterial:
	var key := "%d_%d_%s" % [tile_kind, _look, grid.gym_type]
	if not _side_mats.has(key):
		var bedrock: Color = BEDROCK[_look]
		var top: Color = SIDE_TOP.get(tile_kind, Biome.SIDE_COLORS[_look])
		if tile_kind == Biome.Tile.ROCK and _look == Biome.Kind.DESERT:
			top = Color(0.66, 0.44, 0.3)
		if _look == Biome.Kind.GYM:
			top = Biome.gym_style(grid.gym_type).side
		_side_mats[key] = TerrainFx.side_material(top, bedrock)
	return _side_mats[key]


## Superficie del agua: un plano subdividido (para las olas) del tamaño entero de la casilla, sin
## huecos, para que el agua de casillas vecinas sea continua.
func _water_mesh() -> Mesh:
	if grid.topology == BoardGrid.Topology.SQUARE:
		var plane := PlaneMesh.new()
		plane.size = Vector2.ONE
		plane.subdivide_width = 5
		plane.subdivide_depth = 5
		return plane
	var cyl := CylinderMesh.new()
	cyl.radial_segments = 6
	cyl.rings = 1
	cyl.top_radius = 1.0 / sqrt(3.0)
	cyl.bottom_radius = cyl.top_radius
	cyl.height = 0.02
	return cyl


## Lados de una casilla de agua que dan a tierra (este, sur, oeste, norte), para la espuma de la orilla.
func _shore(c: Vector2i) -> Vector4:
	if grid.topology != BoardGrid.Topology.SQUARE:
		return Vector4.ZERO
	var out := Vector4.ZERO
	var dirs := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
	var same := [Biome.Tile.LAVA] if grid.tiles.get(c, 0) == Biome.Tile.LAVA else [Biome.Tile.WATER, Biome.Tile.BRIDGE]
	if _look == Biome.Kind.VOLCANO:
		same = [Biome.Tile.LAVA, Biome.Tile.BRIDGE]
	for i in 4:
		var n: Vector2i = c + dirs[i]
		if grid.is_inside(n) and grid.tiles.get(n, 0) not in same:
			out[i] = 1.0
	return out


## La hierba crece en zonas: matorrales de hierba alta separados por claros de césped corto.
func _tall_grass(c: Vector2i) -> bool:
	if _building_scenery:
		return false  # el campo de adorno, de césped corto: la hierba alta es lo que más cuesta dibujar
	if grid.tiles.get(c, -1) != Biome.Tile.GRASS or grid.props.get(c, Biome.Prop.NONE) != Biome.Prop.NONE:
		return false
	if _look == Biome.Kind.GYM:
		# Gimnasio Planta/Bicho: césped segado en la arena y jardines de hierba alta a los lados
		var mid := grid.height / 2
		var side := c.x >= 2 and c.x <= 5 or c.x >= grid.width - 6 and c.x <= grid.width - 3
		return side and absi(c.y - mid) <= 4
	var w := grid.to_world(c)
	var threshold := 0.05
	match _look:
		Biome.Kind.FOREST: threshold = 0.2
		Biome.Kind.SWAMP: threshold = -0.15  # juncales
		Biome.Kind.MOUNTAIN, Biome.Kind.DESERT: threshold = 0.35
		Biome.Kind.CITY: threshold = 1.0  # césped cortado en el parque
		Biome.Kind.BEACH: threshold = 0.3
		Biome.Kind.CEMETERY: threshold = 0.25
		Biome.Kind.AIRPORT: threshold = 1.0  # hierba segada junto a la pista
	return _grass_noise.get_noise_2d(w.x, w.z) > threshold


## Detalles pequeños del suelo (no estorban): hierba, flores, helechos, setas, juncos y nenúfares en la
## orilla, piedrecillas, matojos secos, montoncitos de nieve. Elegidos de forma estable por casilla.
func _decorate(root: Node3D, c: Vector2i, tile_kind: int, top: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(c) * 31 + _look
	var b := _look
	var grass := Color(0.45, 0.72, 0.3)
	match b:
		Biome.Kind.FOREST: grass = Color(0.3, 0.55, 0.25)
		Biome.Kind.MOUNTAIN: grass = Color(0.42, 0.62, 0.3)
		Biome.Kind.SWAMP: grass = Color(0.42, 0.52, 0.24)
	var stone := Color(0.55, 0.52, 0.48) if b != Biome.Kind.CAVE else Color(0.36, 0.33, 0.31)
	if b == Biome.Kind.VOLCANO:
		stone = Color(0.18, 0.16, 0.16)
	var list := []  # [tipo, tinte, se mece, altura]
	var r1 := rng.randf()
	var r2 := rng.randf()
	match tile_kind:
		Biome.Tile.GRASS:
			if _tall_grass(c):
				list.append(["tallgrass", grass, 0.9, 0.4])
			else:
				list.append(["grass", grass, 0.45, 0.1])
				if b == Biome.Kind.FOREST:
					if r1 < 0.45: list.append(["fern", grass, 0.5, 0.2])
					if r2 < 0.1: list.append(["mushrooms", Color(0.85, 0.22, 0.15), 0.0, 0.1])
				elif r2 < (0.3 if b in [Biome.Kind.MEADOW, Biome.Kind.CITY] else 0.1):
					list.append(["flowers", grass, 0.6, 0.15])
		Biome.Tile.DIRT:
			if r1 < 0.3: list.append(["pebbles", stone if b == Biome.Kind.VOLCANO else Color(0.5, 0.42, 0.34), 0.0, 0.1])
			if b == Biome.Kind.FOREST and r2 < 0.35: list.append(["fern", grass.darkened(0.1), 0.5, 0.2])
			if b == Biome.Kind.FOREST and r2 > 0.9: list.append(["mushrooms", Color(0.85, 0.7, 0.45), 0.0, 0.1])
		Biome.Tile.SAND:
			if b == Biome.Kind.DESERT and r1 < 0.07: list.append(["shrub", Color(0.62, 0.52, 0.32), 0.35, 0.2])
			elif b == Biome.Kind.BEACH and r1 < 0.2: list.append(["pebbles", Color(0.95, 0.9, 0.85), 0.0, 0.1])  # conchas
			elif r1 < (0.25 if b == Biome.Kind.LAKE else 0.08): list.append(["pebbles", Color(0.7, 0.64, 0.55), 0.0, 0.1])
		Biome.Tile.ROCK:
			if r1 < 0.3: list.append(["pebbles", stone, 0.0, 0.1])
			if r2 > 0.75: list.append(["stones", stone, 0.0, 0.1])
			if b == Biome.Kind.MOUNTAIN and r2 < 0.15: list.append(["grass", grass.darkened(0.1), 0.6, 0.13])
			# Neveros en la roca de las cumbres y en la del bioma nevado
			if (b == Biome.Kind.SNOW or b == Biome.Kind.MOUNTAIN and grid.get_height(c) >= 2) and r1 > 0.5:
				list.append(["mound", Color(0.95, 0.97, 1.0), 0.0, 0.1])
		Biome.Tile.ICE:
			if r1 < 0.6: list.append(["cracks", Color(0.88, 0.96, 1.0), 0.0, 0.1])
		Biome.Tile.SNOW:
			if r1 < 0.45: list.append(["mound", Color(0.95, 0.97, 1.0), 0.0, 0.1])
			if r2 < 0.08: list.append(["grass", Color(0.62, 0.55, 0.38), 0.6, 0.13])
		Biome.Tile.CAVE:
			if r1 < 0.6: list.append(["pebbles", stone, 0.0, 0.1])
			if r2 > 0.5: list.append(["stones", stone, 0.0, 0.1])
			if r2 < 0.07: list.append(["glowshroom", Color(0.4, 0.9, 1.0), 0.0, 0.1])
		Biome.Tile.MUD:
			if r1 < 0.35: list.append(["pebbles", Color(0.3, 0.25, 0.18), 0.0, 0.1])
			if r2 < 0.2: list.append(["reeds", Color(0.45, 0.52, 0.26), 0.9, 0.45])
			elif r2 > 0.92: list.append(["mushrooms", Color(0.75, 0.68, 0.5), 0.0, 0.1])
		Biome.Tile.WATER:
			if b == Biome.Kind.UNDERWATER and r1 < 0.3:
				list.append(["reeds", Color(0.2, 0.45, 0.32), 0.9, 0.45])  # algas
			elif b not in [Biome.Kind.CAVE, Biome.Kind.CITY, Biome.Kind.BEACH, Biome.Kind.LAB, Biome.Kind.GYM, Biome.Kind.UNDERWATER, Biome.Kind.AIRPORT] and _shore(c) != Vector4.ZERO and r1 < (0.7 if b == Biome.Kind.SWAMP else 0.45):
				list.append(["reeds", Color(0.4, 0.6, 0.28), 0.9, 0.45])
			if b in [Biome.Kind.LAKE, Biome.Kind.MEADOW, Biome.Kind.SWAMP] and r2 < (0.45 if b == Biome.Kind.SWAMP else 0.25):
				list.append(["lily", Color(0.3, 0.58, 0.25), 0.15, 0.3])
	if _building_scenery:
		var dim := snappedf(_scenery_dim(c), 0.1)  # pocos tonos: cada uno es una malla distinta
		for d: Array in list:
			d[1] = d[1].darkened(dim)
	for d: Array in list:
		var kind: String = d[0]
		var mi := MeshInstance3D.new()
		mi.mesh = TerrainFx.decor_mesh("mushrooms" if kind == "glowshroom" else kind, rng.randi() % TerrainFx.VARIANTS, d[1])
		var y := top.y - (WATER_DROP - 0.03 if tile_kind == Biome.Tile.WATER and kind == "lily" else 0.0)
		if tile_kind == Biome.Tile.WATER and kind == "reeds":
			y -= WATER_DROP + 0.02
		mi.position = Vector3(top.x, y, top.z)
		mi.rotation.y = rng.randi_range(0, 3) * PI / 2
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if kind in SHADOW_DECOR and not _building_scenery \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var sway: float = d[2]
		if kind == "glowshroom":
			mi.material_override = _live("glowshroom", func() -> ShaderMaterial:
				var m := TerrainFx.foliage_material(Color.WHITE, 0.0, 0.0, true)
				m.set_shader_parameter("glow", 1.2)
				m.set_shader_parameter("pulse", 0.5)
				return m)
		elif sway > 0.0:
			var grassy := kind in ["grass", "tallgrass"]  # hojas de una cara: material de dos caras
			mi.material_override = _live("decor_%s%.2f" % ["grass_" if grassy else "", sway], func() -> ShaderMaterial:
				var m := TerrainFx.foliage_material(Color.WHITE, sway, sway, true, grassy)
				m.set_shader_parameter("push", 1.0)
				return m)
			mi.set_instance_shader_parameter("base_y", y)
			mi.set_instance_shader_parameter("height", d[3])
		else:
			mi.material_override = _vcol_material()
		mi.set_meta("batch", "decor")
		mi.set_meta("sway_base", Vector2(y, d[3]))
		root.add_child(mi)


## Bolitas de granizo acumuladas (solo se ven con granizo) en las casillas de tierra.
func _hail_pile(root: Node3D, c: Vector2i, tile_kind: int, top: Vector3) -> void:
	if tile_kind in [Biome.Tile.WATER, Biome.Tile.LAVA] or (hash(c) * 13 + 5) % 100 >= 55:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = TerrainFx.decor_mesh("hailstones", hash(c) % TerrainFx.VARIANTS, Color(0.78, 0.88, 1.0))
	mi.position = top
	mi.rotation.y = float(hash(c) % 4) * PI / 2
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = _ice_pile_material()
	mi.visible = _hail > 0.02
	mi.scale = Vector3.ONE * _hail
	root.add_child(mi)
	_hail_piles.append(mi)


var _ice_pile_mat: StandardMaterial3D


func _ice_pile_material() -> StandardMaterial3D:
	if _ice_pile_mat == null:
		_ice_pile_mat = WeatherFx.ice_material()
		_ice_pile_mat.vertex_color_use_as_albedo = true
		_ice_pile_mat.vertex_color_is_srgb = true
		_ice_pile_mat.disable_fog = false
	return _ice_pile_mat


## Charco (solo se ve con lluvia) en casillas llanas de hierba, tierra o roca sin obstáculo.
func _maybe_puddle(root: Node3D, c: Vector2i, tile_kind: int, top: Vector3) -> void:
	if tile_kind not in [Biome.Tile.GRASS, Biome.Tile.DIRT, Biome.Tile.ROCK, Biome.Tile.FLOOR, Biome.Tile.ROAD, Biome.Tile.MUD]:
		return
	if grid.props.get(c, Biome.Prop.NONE) != Biome.Prop.NONE or (hash(c) * 7 + 3) % 100 >= 22:
		return
	for n in grid.neighbors(c):
		if grid.get_height(n) != grid.get_height(c):
			return
	var mi := MeshInstance3D.new()
	mi.mesh = TerrainFx.puddle_mesh(hash(c) % 4)
	mi.position = Vector3(top.x, top.y + 0.006, top.z)
	mi.rotation.y = float(hash(c) % 4) * PI / 2
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = _live("puddle", func() -> ShaderMaterial:
		var m := TerrainFx.water_material(Color(0.34, 0.42, 0.52), Color(0.5, 0.58, 0.68))
		m.set_shader_parameter("waves", 0.0)
		return m)
	mi.visible = _wet > 0.02
	mi.scale = Vector3(_wet, 1.0, _wet)
	root.add_child(mi)
	_puddles.append(mi)


var _stalag_mat: StandardMaterial3D


## Estalagmita con su malla de color por vértice y un material algo brillante (roca húmeda).
func _stalagmite(parent: Node3D, v: int, pos: Vector3, size: Vector3) -> MeshInstance3D:
	if _stalag_mat == null:
		_stalag_mat = StandardMaterial3D.new()
		_stalag_mat.vertex_color_use_as_albedo = true
		_stalag_mat.vertex_color_is_srgb = true
		_stalag_mat.roughness = 0.4
		_mats["stalagmite"] = _stalag_mat  # para que también se moje
	var mi := MeshInstance3D.new()
	mi.mesh = TerrainFx.stalagmite_mesh(v)
	mi.material_override = _stalag_mat
	mi.position = pos
	mi.scale = size
	parent.add_child(mi)
	return mi


var _caustic_mesh: Mesh
var _caustic_mat: ShaderMaterial


## Cueva submarina: capa de cáusticas (TerrainFx.CAUSTIC_SHADER) sobre la cara de arriba de la casilla. Una
## malla y un material compartidos: en combate se agrupan como los detalles del suelo.
func _caustics(root: Node3D, top: Vector3) -> void:
	if _caustic_mesh == null:
		_caustic_mesh = _tile_mesh(0.002, 0.0)
		_caustic_mat = TerrainFx.caustic_material()
	var mi := MeshInstance3D.new()
	mi.mesh = _caustic_mesh
	mi.material_override = _caustic_mat
	mi.position = Vector3(top.x, top.y + 0.004, top.z)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("batch", "decor")
	mi.set_meta("sway_base", Vector2(top.y, 0.0))
	root.add_child(mi)


## Funde en una sola malla (color por vértice) las piezas opacas de color liso de un obstáculo: se ve igual
## y se dibuja en una llamada en vez de una por pieza (una estantería tenía ~100 libros sueltos). Las
## piezas con viento, brillo o transparencia se quedan como están. Una malla por cada acabado (mate,
## brillante, metálico).
func _bake(node: Node3D) -> void:
	var groups := {}  # acabado -> [vértices, normales, colores, índices, material de muestra]
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		# Las que llevan piezas colgando (la pantalla con su imagen encendida) se quedan sueltas
		var m := mi.material_override as StandardMaterial3D
		if m == null or m.emission_enabled or m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED \
				or m.albedo_texture or mi.mesh == null or mi.mesh.get_surface_count() != 1 or mi.get_child_count() > 0 \
				or mi.has_meta("batch"):
			continue
		if not _mesh_arrays.has(mi.mesh):  # las primitivas compartidas se leen una sola vez
			_mesh_arrays[mi.mesh] = mi.mesh.surface_get_arrays(0)
		var arrays: Array = _mesh_arrays[mi.mesh]
		if arrays[Mesh.ARRAY_NORMAL] == null:
			continue
		var xf := _relative_transform(mi, node)
		var key := "%.2f_%.2f_%.2f" % [m.roughness, m.metallic, m.metallic_specular]
		if not groups.has(key):
			groups[key] = [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedInt32Array(), m]
		var g: Array = groups[key]
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var colors = arrays[Mesh.ARRAY_COLOR]
		var nb := xf.basis.inverse().transposed()
		var base: int = g[0].size()
		g[0].append_array(xf * verts)  # de una vez (en el motor): vértice a vértice era lo más lento de la carga
		var turned := Transform3D(nb, Vector3.ZERO) * normals
		if not (nb.is_conformal() and nb.get_scale().is_equal_approx(Vector3.ONE)):  # solo giro: siguen unitarias
			for i in turned.size():
				turned[i] = turned[i].normalized()
		g[1].append_array(turned)
		var tinted := m.vertex_color_use_as_albedo and colors != null
		if tinted and m.albedo_color == Color.WHITE:  # ya fundida (_merge_baked): el color va en los vértices
			g[2].append_array(colors)
		else:
			var cols := PackedColorArray()
			cols.resize(verts.size())
			cols.fill(m.albedo_color)
			if tinted:
				for i in verts.size():
					cols[i] *= colors[i]
			g[2].append_array(cols)
		var indices = arrays[Mesh.ARRAY_INDEX]
		if indices == null:
			for i in verts.size():
				g[3].append(base + i)
		else:
			# Un reflejo (escala negativa) invierte el orden de los triángulos
			var flip := xf.basis.determinant() < 0.0
			for i in range(0, indices.size(), 3):
				g[3].append(base + indices[i])
				g[3].append(base + indices[i + (2 if flip else 1)])
				g[3].append(base + indices[i + (1 if flip else 2)])
		mi.get_parent().remove_child(mi)
		mi.free()
	for key: String in groups:
		var g: Array = groups[key]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = g[0]
		arrays[Mesh.ARRAY_NORMAL] = g[1]
		arrays[Mesh.ARRAY_COLOR] = g[2]
		arrays[Mesh.ARRAY_INDEX] = g[3]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _baked_material(g[4])
		node.add_child(mi)


## Transformación de `mi` en el espacio de `node` (sus padres intermedios incluidos).
func _relative_transform(mi: Node3D, node: Node3D) -> Transform3D:
	var xf := mi.transform
	var p := mi.get_parent() as Node3D
	while p and p != node:
		xf = p.transform * xf
		p = p.get_parent() as Node3D
	return xf


## Material de las piezas fundidas: el acabado de `like` con el color de cada vértice. Compartido y
## registrado para que también se moje con la lluvia.
func _baked_material(like: StandardMaterial3D) -> StandardMaterial3D:
	var key := "baked_%.2f_%.2f_%.2f" % [like.roughness, like.metallic, like.metallic_specular]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.roughness = like.roughness
		m.metallic = like.metallic
		m.metallic_specular = like.metallic_specular
		_mats[key] = m
	return _mats[key]


var _vcol_mat: StandardMaterial3D


func _vcol_material() -> StandardMaterial3D:
	if _vcol_mat == null:
		_vcol_mat = StandardMaterial3D.new()
		_vcol_mat.vertex_color_use_as_albedo = true
		_vcol_mat.vertex_color_is_srgb = true
		_mats["vcol"] = _vcol_mat  # para que también se moje
		_vcol_mat.roughness = 0.9
	return _vcol_mat


## Equipo de tierra del avión: tractor con cabina abierta y luz giratoria tirando de dos carros de equipaje con
## toldo y maletas (detrás del ala izquierda), camión escalera con peldaños, barandillas y plataforma en la puerta
## delantera derecha, y conos alrededor.
func _ground_crew(body: Node3D, h: int) -> void:
	var yellow := Color(0.95, 0.75, 0.15)
	var tire := Color(0.08, 0.08, 0.09)
	var steel := Color(0.6, 0.62, 0.66)
	var dark := Color(0.15, 0.15, 0.17)
	var wheels := func(at: Vector3, half: Vector2, r: float) -> void:
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var p := at + Vector3(half.x * sx, r, half.y * sz)
				_part(body, _cyl(r, r, 0.035, 12), p, tire).rotation.z = PI / 2
				_part(body, _cyl(r * 0.45, r * 0.45, 0.04, 8), p, steel).rotation.z = PI / 2
	var bar := func(from: Vector3, to: Vector3, r: float, color: Color) -> void:  # tubo entre dos puntos
		var d := to - from
		var tube := _part(body, _cyl(r, r, d.length(), 6), (from + to) * 0.5, color)
		tube.basis = Basis(Quaternion(Vector3.UP, d.normalized()))
	# Tractor: chasis, capó, asiento con arco antivuelco y techo, faros y luz giratoria
	var t := Vector3(-0.85, 0, -0.5)
	_part(body, _bevel_box(), t + Vector3(0, 0.1, 0), yellow).scale = Vector3(0.2, 0.07, 0.32)
	_part(body, _bevel_box(), t + Vector3(0, 0.16, 0.08), yellow).scale = Vector3(0.18, 0.06, 0.15)
	_part(body, _bevel_box(), t + Vector3(0, 0.17, -0.07), dark).scale = Vector3(0.1, 0.05, 0.08)  # asiento
	_part(body, _bevel_box(), t + Vector3(0, 0.21, -0.11), dark).scale = Vector3(0.1, 0.07, 0.02)
	for sx in [-0.085, 0.085]:
		for sz in [-0.13, 0.0]:
			bar.call(t + Vector3(sx, 0.14, sz), t + Vector3(sx, 0.31, sz), 0.008, dark)
		_part(body, _unit_box(), t + Vector3(sx * 0.8, 0.16, 0.16), Color(1.0, 0.95, 0.75)).scale = Vector3(0.035, 0.02, 0.01)
	_part(body, _bevel_box(), t + Vector3(0, 0.315, -0.065), yellow.darkened(0.15)).scale = Vector3(0.2, 0.015, 0.18)
	_part(body, _cyl(0.015, 0.015, 0.025, 8), t + Vector3(0, 0.335, -0.065), Color(1.0, 0.5, 0.1))
	bar.call(t + Vector3(0, 0.2, 0.0), t + Vector3(0, 0.24, 0.05), 0.006, dark)  # volante
	wheels.call(t, Vector2(0.105, 0.1), 0.045)
	# Carros de equipaje: plataforma, postes, toldo de color y maletas de varios tamaños
	var prev := t + Vector3(0, 0.07, -0.16)
	for k in 2:
		var cart := t + Vector3(0, 0, -0.45 - 0.34 * k)
		bar.call(prev, cart + Vector3(0, 0.07, 0.14), 0.007, dark)  # enganche
		_part(body, _bevel_box(), cart + Vector3(0, 0.085, 0), steel).scale = Vector3(0.22, 0.025, 0.26)
		var hood: Color = [Color(0.25, 0.42, 0.75), Color(0.3, 0.32, 0.36), Color(0.75, 0.3, 0.25)][(h + k) % 3]
		for sx in [-0.1, 0.1]:
			for sz in [-0.115, 0.115]:
				bar.call(cart + Vector3(sx, 0.1, sz), cart + Vector3(sx, 0.29, sz), 0.006, steel)
		_part(body, _bevel_box(), cart + Vector3(0, 0.3, 0), hood).scale = Vector3(0.24, 0.02, 0.28)
		for i in 4:
			var r := (h >> (i + k * 3)) % 4
			var size := Vector3(0.07 + 0.02 * (r % 2), 0.05 + 0.02 * (r / 2), 0.1)
			var suitcase: Color = [Color(0.2, 0.22, 0.3), Color(0.55, 0.15, 0.15), Color(0.2, 0.4, 0.3), Color(0.5, 0.42, 0.3)][(r + i) % 4]
			_part(body, _bevel_box(), cart + Vector3(-0.05 + 0.1 * (i % 2), 0.1 + size.y * 0.5, -0.06 + 0.12 * (i / 2)), suitcase).scale = size
		wheels.call(cart, Vector2(0.1, 0.09), 0.035)
		prev = cart + Vector3(0, 0.07, -0.14)
	# Camión escalera en la puerta delantera derecha: chasis y cabina, escalera con peldaños, largueros,
	# barandillas y puntales, y plataforma a la altura de la puerta
	var z := 0.98
	_part(body, _bevel_box(), Vector3(0.82, 0.1, z), yellow).scale = Vector3(0.7, 0.06, 0.2)
	_part(body, _bevel_box(), Vector3(1.1, 0.21, z), yellow).scale = Vector3(0.17, 0.16, 0.2)
	_part(body, _unit_box(), Vector3(1.19, 0.24, z), Color(0.12, 0.16, 0.22)).scale = Vector3(0.01, 0.07, 0.16)  # parabrisas
	_part(body, _unit_box(), Vector3(1.1, 0.24, z - 0.101), Color(0.12, 0.16, 0.22)).scale = Vector3(0.1, 0.06, 0.01)
	_part(body, _unit_box(), Vector3(1.1, 0.24, z + 0.101), Color(0.12, 0.16, 0.22)).scale = Vector3(0.1, 0.06, 0.01)
	_part(body, _cyl(0.015, 0.015, 0.025, 8), Vector3(1.1, 0.3, z), Color(1.0, 0.5, 0.1))
	wheels.call(Vector3(0.82, 0, z), Vector2(0.27, 0.1), 0.045)
	var low := Vector3(0.98, 0.15, z)
	var high := Vector3(0.44, 0.53, z)
	for i in 9:
		var p := low.lerp(high, (i + 0.5) / 9.0)
		_part(body, _unit_box(), p, steel.lightened(0.2)).scale = Vector3(0.05, 0.012, 0.15)
	for sz in [-0.08, 0.08]:
		var off := Vector3(0, 0, sz)
		bar.call(low + off, high + off, 0.012, steel)  # larguero
		bar.call(low + off + Vector3(0, 0.15, 0), high + off + Vector3(-0.08, 0.15, 0), 0.006, steel)  # barandilla
		for i in 4:
			var p: Vector3 = low.lerp(high, i / 3.0) + off
			bar.call(p, p + Vector3(0, 0.15, 0), 0.005, steel)
		bar.call(Vector3(0.58, 0.13, z + sz), low.lerp(high, 0.7) + off, 0.01, dark)  # puntal
	_part(body, _bevel_box(), Vector3(0.38, 0.53, z), steel).scale = Vector3(0.14, 0.02, 0.18)
	bar.call(Vector3(0.36, 0.53, z + 0.09), Vector3(0.36, 0.68, z + 0.09), 0.005, steel)
	bar.call(Vector3(0.36, 0.68, z + 0.09), Vector3(0.44, 0.68, z + 0.09), 0.005, steel)
	bar.call(Vector3(0.36, 0.53, z - 0.09), Vector3(0.36, 0.68, z - 0.09), 0.005, steel)
	bar.call(Vector3(0.36, 0.68, z - 0.09), Vector3(0.44, 0.68, z - 0.09), 0.005, steel)
	# Conos con franja blanca
	for cone in [Vector3(1.45, 0, 0.2), Vector3(-1.45, 0, 0.2), Vector3(0, 0, 1.45), Vector3(0.2, 0, -1.6)]:
		_part(body, _cyl(0.0, 0.04, 0.12, 10), cone + Vector3(0, 0.07, 0), Color(1.0, 0.45, 0.1))
		_part(body, _cyl(0.026, 0.031, 0.025, 10), cone + Vector3(0, 0.08, 0), Color.WHITE)
		_part(body, _unit_box(), cone + Vector3(0, 0.005, 0), Color(1.0, 0.45, 0.1)).scale = Vector3(0.1, 0.01, 0.1)


func _part(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color) -> MeshInstance3D:
	if _building_scenery:
		color = color.darkened(SCENERY_PROP_SHADE)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = _material(color)
	parent.add_child(mi)
	return mi


## Las primitivas se comparten por medidas (nadie las modifica después de crearlas).
var _prims := {}
var _mesh_arrays := {}  # malla -> sus datos (para fundir obstáculos sin leerla cada vez)


## Caja de lado 1 compartida: las piezas le dan su tamaño con la escala.
## Cubo unidad con los cantos biselados (para escalar como `_unit_box`): las aristas reflejan la luz en una
## franja fina en vez de cortarse en seco, como la chapa y el plástico moldeado de verdad.
func _bevel_box() -> Mesh:
	if _building_scenery:
		return _unit_box()  # fuera, a esa distancia, el bisel no se distingue
	if _prims.has("bevel"):
		return _prims["bevel"]
	var b := 0.07  # parte biselada de cada cara
	var pts := PackedVector3Array()
	for sx in [-1, 1]:
		for sy in [-1, 1]:
			for sz in [-1, 1]:
				var corner := Vector3(sx, sy, sz) * 0.5
				pts.append(corner - Vector3(sx * b, 0, 0))
				pts.append(corner - Vector3(0, sy * b, 0))
				pts.append(corner - Vector3(0, 0, sz * b))
	# Envolvente convexa de los 24 puntos (cada esquina recortada en tres): caras, biseles y esquinas
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f: Array in _hull_faces(pts):
		var poly: PackedVector3Array = f[1]
		for k in range(1, poly.size() - 1):
			for v in [poly[0], poly[k + 1], poly[k]]:  # Godot: caras de frente en sentido horario
				st.set_normal(f[0])
				st.add_vertex(v)
	_prims["bevel"] = st.commit()
	return _prims["bevel"]


## Caras de la envolvente convexa de `pts` (pocos puntos): [normal, polígono ordenado].
func _hull_faces(pts: PackedVector3Array) -> Array:
	var faces := []
	var seen := {}
	var n := pts.size()
	for i in n:
		for j in range(i + 1, n):
			for k in range(j + 1, n):
				var normal := (pts[j] - pts[i]).cross(pts[k] - pts[i])
				if normal.length() < 1e-6:
					continue
				normal = normal.normalized()
				var d := normal.dot(pts[i])
				var above := false
				var below := false
				for p in pts:
					var e := normal.dot(p) - d
					if e > 1e-5:
						above = true
					elif e < -1e-5:
						below = true
				if above and below:
					continue
				if above:
					normal = -normal
					d = -d
				var key := "%.3f_%.3f_%.3f" % [normal.x, normal.y, normal.z]
				if seen.has(key):
					continue
				seen[key] = true
				var on: Array[Vector3] = []
				for p in pts:
					if absf(normal.dot(p) - d) < 1e-5 and p not in on:
						on.append(p)
				var c := Vector3.ZERO
				for p in on:
					c += p
				c /= on.size()
				var u := (on[0] - c).normalized()
				var v := normal.cross(u)
				on.sort_custom(func(a: Vector3, b: Vector3) -> bool:
					return atan2((a - c).dot(v), (a - c).dot(u)) < atan2((b - c).dot(v), (b - c).dot(u)))
				faces.append([normal, PackedVector3Array(on)])
	return faces


## Ala en flecha y estrechándose hacia la punta (para alas, estabilizadores y deriva): raíz en x = 0, punta
## en x = 1,3; en z, la cuerda (de 0,7 en la raíz a 0,22 en la punta, echada hacia atrás).
func _wing_mesh() -> Mesh:
	if _prims.has("wing"):
		return _prims["wing"]
	var t := 0.035
	var pts := PackedVector3Array([
		Vector3(0, -t, 0.35), Vector3(0, -t, -0.35), Vector3(1.3, -t * 0.5, -0.35), Vector3(1.3, -t * 0.5, -0.57),
		Vector3(0, t, 0.35), Vector3(0, t, -0.35), Vector3(1.3, t * 0.5, -0.35), Vector3(1.3, t * 0.5, -0.57)])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f: Array in _hull_faces(pts):
		var poly: PackedVector3Array = f[1]
		for k in range(1, poly.size() - 1):
			for v in [poly[0], poly[k + 1], poly[k]]:  # Godot: caras de frente en sentido horario
				st.set_normal(f[0])
				st.add_vertex(v)
	_prims["wing"] = st.commit()
	return _prims["wing"]


func _quad(w: float, h: float) -> QuadMesh:
	var key := "q%.3f_%.3f" % [w, h]
	if not _prims.has(key):
		var m := QuadMesh.new()
		m.size = Vector2(w, h)
		_prims[key] = m
	return _prims[key]


## Pantalla encendida con una interfaz de análisis: rejilla, una gráfica que avanza, barras que suben y bajan
## y una línea de estado que parpadea. Sin luz propia (emisión), compartida por color y variante.
func _screen_material(color: Color, variant: int) -> ShaderMaterial:
	var key := "%s_%d" % [color.to_html(), variant]
	if not _screen_mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = TerrainFx.shader(SCREEN_SHADER)
		m.set_shader_parameter("tint", color)
		m.set_shader_parameter("seed", float(variant))
		_screen_mats[key] = m
	return _screen_mats[key]


var _planes := {}  # aerolínea y adorno -> malla del avión con sus materiales
var _screen_mats := {}  # aparte de `_mats`: la lluvia moja esos y estas no son StandardMaterial3D
const SCREEN_SHADER := """
shader_type spatial;
render_mode unshaded;
uniform vec4 tint : source_color = vec4(0.3, 0.85, 1.0, 1.0);
uniform float seed = 0.0;
void fragment() {
	vec2 uv = UV;
	float t = TIME * (0.6 + fract(seed * 0.37) * 0.6) + seed * 3.0;
	vec3 col = tint.rgb * 0.08;
	vec2 g = abs(fract(uv * vec2(8.0, 5.0)) - 0.5);
	col += tint.rgb * 0.12 * step(0.46, max(g.x, g.y));
	float wave = 0.55 + 0.2 * sin(uv.x * 14.0 + t * 2.0) * sin(uv.x * 5.0 - t);
	if (uv.x < 0.62) {
		col += tint.rgb * smoothstep(0.03, 0.0, abs(uv.y - wave)) * step(uv.x, fract(t * 0.25) * 0.62 + 0.02);
	} else {
		float bar = floor((uv.x - 0.62) / 0.076);
		float hgt = 0.25 + 0.5 * fract(sin(bar * 12.9 + floor(t * 1.5) + seed) * 437.5);
		col += tint.rgb * 0.8 * step(1.0 - uv.y, hgt) * step(0.015, fract((uv.x - 0.62) / 0.076)) * step(0.15, uv.y);
	}
	col += vec3(1.0) * 0.6 * step(uv.y, 0.08) * step(uv.x, 0.3) * step(0.5, fract(t * 0.8));
	ALBEDO = col;
	EMISSION = col * 1.6;
}
"""


func _unit_box() -> BoxMesh:
	if not _prims.has("box"):
		_prims["box"] = BoxMesh.new()
	return _prims["box"]


func _cyl(top_r: float, bottom_r: float, h: float, segments := 10) -> CylinderMesh:
	var key := "c%.4f_%.4f_%.4f_%d" % [top_r, bottom_r, h, segments]
	if not _prims.has(key):
		var m := CylinderMesh.new()
		m.top_radius = top_r
		m.bottom_radius = bottom_r
		m.height = h
		m.radial_segments = segments
		m.rings = 0  # lados rectos: los anillos intermedios no cambian nada y multiplican los triángulos
		_prims[key] = m
	return _prims[key]


func _sphere(r: float, h: float) -> SphereMesh:
	var key := "s%.4f_%.4f" % [r, h]
	if not _prims.has(key):
		var m := SphereMesh.new()
		m.radius = r
		m.height = h
		m.radial_segments = 12
		m.rings = 6
		_prims[key] = m
	return _prims[key]


func _capsule(r: float, h: float) -> CapsuleMesh:
	var key := "k%.4f_%.4f" % [r, h]
	if not _prims.has(key):
		var m := CapsuleMesh.new()
		m.radius = r
		m.height = h
		_prims[key] = m
	return _prims[key]


## Prisma de la forma de la casilla. `inset` encoge la casilla por los lados.
func _tile_mesh(thickness: float, inset: float) -> Mesh:
	if grid.topology == BoardGrid.Topology.SQUARE:
		var box := BoxMesh.new()
		var s := 1.0 - TILE_GAP - inset * 2.0
		box.size = Vector3(s, thickness, s)
		return box
	var cyl := CylinderMesh.new()
	cyl.radial_segments = 6
	cyl.rings = 1
	# Radio circunscrito de un hexágono de 1 de ancho entre lados planos.
	var r := (1.0 - TILE_GAP - inset * 2.0) / sqrt(3.0)
	cyl.top_radius = r
	cyl.bottom_radius = r
	cyl.height = thickness
	return cyl


func _material(color: Color, glossy := false) -> StandardMaterial3D:
	var key := color if not glossy else Color(color, 0.5)
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		if glossy:
			m.roughness = 0.15
			m.metallic_specular = 0.9
		_mats[key] = m
	return _mats[key]


## Resaltado de casilla (movimiento, alcance, área, orientación...): el color con un borde más claro y
## opaco para que cada opción se distinga aunque esté pegada a otras, y un filo oscuro por fuera para que
## también se lea sobre suelos claros (agua con reflejos, arena, nieve). La casilla señalada (`selected`)
## lleva un borde blanco ancho y late, así no depende del color del suelo ni se confunde con las de alrededor.
const HIGHLIGHT_SHADER := "
shader_type spatial;
render_mode unshaded, shadows_disabled, depth_draw_never;
uniform vec4 color : source_color;
uniform float half_size = 0.4;
uniform bool hex = false;
uniform bool selected = false;
varying vec2 lp;

void vertex() {
	lp = VERTEX.xz;
}

void fragment() {
	vec2 p = abs(lp);
	float d = half_size - (hex ? max(p.x, dot(p, vec2(0.5, 0.8660254))) : max(p.x, p.y));
	float rim = 1.0 - smoothstep(0.012, 0.022, d);
	if (selected) {
		float beat = 0.5 + 0.5 * sin(TIME * 5.0);
		float dark = 1.0 - smoothstep(0.03, 0.04, d);
		float band = (1.0 - smoothstep(0.085, 0.1, d)) * (1.0 - dark);
		vec3 fill = color.rgb * (0.95 + 0.2 * beat);
		ALBEDO = mix(mix(fill, vec3(1.0), band * (0.8 + 0.2 * beat)), vec3(0.03, 0.04, 0.06), dark);
		ALPHA = max(mix(0.92, 1.0, band), dark * 0.95);
	} else {
		float edge = 1.0 - smoothstep(0.035, 0.065, d);
		ALBEDO = mix(mix(color.rgb, mix(color.rgb, vec3(1.0), 0.45), edge), vec3(0.03, 0.04, 0.06), rim * 0.8);
		ALPHA = max(mix(color.a, min(1.0, color.a + 0.3), edge), rim * 0.55);
	}
}
"
var _highlight_mats := {}


func _highlight_material(color: Color, selected := false) -> ShaderMaterial:
	var key := [color, selected]
	if not _highlight_mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = TerrainFx.shader(HIGHLIGHT_SHADER)
		m.set_shader_parameter("color", color)
		m.set_shader_parameter("half_size", (1.0 - TILE_GAP - 0.16) * 0.5)
		m.set_shader_parameter("hex", grid.topology != BoardGrid.Topology.SQUARE)
		m.set_shader_parameter("selected", selected)
		_highlight_mats[key] = m
	return _highlight_mats[key]


func _overlay_material(color: Color) -> StandardMaterial3D:
	if not _overlay_mats.has(color):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_overlay_mats[color] = m
	return _overlay_mats[color]

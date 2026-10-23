class_name BoardView
extends Node3D
## Dibuja las casillas de una BoardGrid (suelo, laterales y obstáculos) y gestiona los resaltados.

const TILE_GAP := 0.04
const BASE_THICKNESS := 0.25
const TOP_THICKNESS := 0.06

var grid: BoardGrid
var _cells := {} # Vector2i -> Node3D con todo lo de esa casilla
var _overlays := {} # Vector2i -> MeshInstance3D
var _mats := {} # Color -> StandardMaterial3D
var _overlay_mats := {} # Color -> StandardMaterial3D
var _marks_root: Node3D
var _traps_root: Node3D


func build(p_grid: BoardGrid) -> void:
	grid = p_grid
	for child in get_children():
		child.queue_free()
	_cells.clear()
	_overlays.clear()
	for c in grid.all_cells():
		_build_cell(c)
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
				var rock := _part(node, BoxMesh.new(), Vector3(-0.15 + i * 0.3, 0.55 + i * 0.1, 0), Color(0.55, 0.48, 0.4))
				rock.scale = Vector3.ONE * 0.16
				rock.rotation = Vector3(0.5, 0.8 * i, 0.3)


## Reconstruye una casilla (el editor la llama al cambiar altura, suelo u obstáculo).
func refresh_cell(c: Vector2i) -> void:
	if _cells.has(c):
		_cells[c].queue_free()
	_build_cell(c)


func clear_highlights() -> void:
	for overlay: MeshInstance3D in _overlays.values():
		overlay.visible = false


func highlight(cells: Array[Vector2i], color: Color) -> void:
	for c in cells:
		var overlay: MeshInstance3D = _overlays.get(c)
		if overlay:
			overlay.material_override = _overlay_material(color)
			overlay.visible = true


func _build_cell(c: Vector2i) -> void:
	var root := Node3D.new()
	add_child(root)
	_cells[c] = root
	var top := grid.to_world(c)
	var thickness := BASE_THICKNESS + top.y
	var tile_kind: int = grid.tiles.get(c, Biome.Tile.GRASS)

	var color: Color = Biome.TILE_COLORS[tile_kind]
	color = color.lightened(0.04 * grid.get_height(c))
	if (c.x + c.y) % 2 == 0:
		color = color.darkened(0.05)
	var top_mesh := MeshInstance3D.new()
	top_mesh.mesh = _tile_mesh(TOP_THICKNESS, 0.0)
	top_mesh.position = Vector3(top.x, top.y - TOP_THICKNESS * 0.5, top.z)
	top_mesh.material_override = _material(color, tile_kind == Biome.Tile.WATER or tile_kind == Biome.Tile.ICE)
	root.add_child(top_mesh)

	var side := MeshInstance3D.new()
	side.mesh = _tile_mesh(thickness - TOP_THICKNESS, 0.0)
	side.position = Vector3(top.x, top.y - TOP_THICKNESS - (thickness - TOP_THICKNESS) * 0.5, top.z)
	side.material_override = _material(Biome.SIDE_COLORS[grid.biome])
	root.add_child(side)

	var body := StaticBody3D.new()
	body.set_meta("cell", c)
	var shape := CollisionShape3D.new()
	shape.shape = _tile_mesh(thickness, 0.0).create_convex_shape()
	body.position = Vector3(top.x, top.y - thickness * 0.5, top.z)
	body.add_child(shape)
	root.add_child(body)

	var prop: int = grid.props.get(c, Biome.Prop.NONE)
	if prop != Biome.Prop.NONE:
		var p := _prop_node(prop, c)
		p.position = top
		root.add_child(p)

	var overlay := MeshInstance3D.new()
	overlay.mesh = _tile_mesh(0.02, 0.08)
	overlay.position = Vector3(top.x, top.y + 0.012, top.z)
	overlay.visible = false
	overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(overlay)
	_overlays[c] = overlay


## Obstáculo hecho con primitivas. Tamaño y giro varían de forma estable según la celda.
func _prop_node(prop: int, c: Vector2i) -> Node3D:
	var node := Node3D.new()
	var h := hash(c)
	var jitter := 0.85 + float(h % 30) / 100.0
	node.rotation.y = float(h % 360) * PI / 180.0
	node.scale = Vector3.ONE * jitter
	match prop:
		Biome.Prop.TREE:
			_part(node, _cyl(0.07, 0.09, 0.5), Vector3(0, 0.25, 0), Color(0.42, 0.28, 0.16))
			_part(node, _sphere(0.36, 0.5), Vector3(0, 0.75, 0), Color(0.24, 0.52, 0.22))
		Biome.Prop.PINE:
			_part(node, _cyl(0.06, 0.08, 0.35), Vector3(0, 0.17, 0), Color(0.4, 0.26, 0.15))
			_part(node, _cyl(0.0, 0.38, 0.6), Vector3(0, 0.6, 0), Color(0.16, 0.38, 0.24))
			_part(node, _cyl(0.0, 0.28, 0.45), Vector3(0, 0.95, 0), Color(0.18, 0.42, 0.26))
		Biome.Prop.BOULDER:
			_part(node, _sphere(0.36, 0.42), Vector3(0, 0.14, 0), Color(0.5, 0.48, 0.46))
		Biome.Prop.CACTUS:
			var green := Color(0.3, 0.55, 0.28)
			_part(node, _capsule(0.12, 0.8), Vector3(0, 0.4, 0), green)
			_part(node, _capsule(0.07, 0.35), Vector3(0.17, 0.45, 0), green)
			_part(node, _capsule(0.07, 0.3), Vector3(-0.15, 0.55, 0), green)
		Biome.Prop.PILLAR:
			_part(node, _cyl(0.25, 0.28, 1.3), Vector3(0, 0.65, 0), Color(0.82, 0.8, 0.76))
			_part(node, _cyl(0.33, 0.33, 0.1), Vector3(0, 1.32, 0), Color(0.7, 0.68, 0.64))
		Biome.Prop.CRYSTAL:
			var crystal := _cyl(0.0, 0.18, 0.8, 6)
			var mi := _part(node, crystal, Vector3(0, 0.4, 0), Color(0.65, 0.45, 0.95))
			var mat: StandardMaterial3D = mi.material_override.duplicate()
			mat.emission_enabled = true
			mat.emission = Color(0.55, 0.35, 0.95)
			mat.emission_energy_multiplier = 1.2
			mi.material_override = mat
			_part(node, _cyl(0.0, 0.1, 0.45, 6), Vector3(0.18, 0.22, 0.05), Color(0.6, 0.4, 0.9)).rotation.z = -0.4
	return node


func _part(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = _material(color)
	parent.add_child(mi)
	return mi


func _cyl(top_r: float, bottom_r: float, h: float, segments := 10) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top_r
	m.bottom_radius = bottom_r
	m.height = h
	m.radial_segments = segments
	return m


func _sphere(r: float, h: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 12
	m.rings = 6
	return m


func _capsule(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	return m


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


func _overlay_material(color: Color) -> StandardMaterial3D:
	if not _overlay_mats.has(color):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_overlay_mats[color] = m
	return _overlay_mats[color]

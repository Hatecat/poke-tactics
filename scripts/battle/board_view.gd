class_name BoardView
extends Node3D
## Dibuja las casillas de una BoardGrid y gestiona los resaltados.

const TILE_GAP := 0.04
const BASE_THICKNESS := 0.25
const GROUND_COLORS: Array[Color] = [
	Color(0.36, 0.62, 0.32), Color(0.45, 0.66, 0.34), Color(0.55, 0.62, 0.38), Color(0.6, 0.55, 0.42),
]
const SIDE_COLOR := Color(0.42, 0.32, 0.22)

var grid: BoardGrid
var _overlays := {} # Vector2i -> MeshInstance3D
var _overlay_mats := {} # Color -> StandardMaterial3D


func build(p_grid: BoardGrid) -> void:
	grid = p_grid
	for child in get_children():
		child.queue_free()
	_overlays.clear()
	for c in grid.all_cells():
		_build_tile(c)


func clear_highlights() -> void:
	for overlay: MeshInstance3D in _overlays.values():
		overlay.visible = false


func highlight(cells: Array[Vector2i], color: Color) -> void:
	for c in cells:
		var overlay: MeshInstance3D = _overlays.get(c)
		if overlay:
			overlay.material_override = _overlay_material(color)
			overlay.visible = true


func _build_tile(c: Vector2i) -> void:
	var top := grid.to_world(c)
	var thickness := BASE_THICKNESS + top.y

	# Cara superior de hierba sobre un bloque de tierra.
	const GRASS := 0.06
	var tile := MeshInstance3D.new()
	tile.mesh = _tile_mesh(GRASS, 0.0)
	tile.position = Vector3(top.x, top.y - GRASS * 0.5, top.z)
	var mat := StandardMaterial3D.new()
	var h := grid.get_height(c)
	mat.albedo_color = GROUND_COLORS[clampi(h, 0, GROUND_COLORS.size() - 1)]
	if (c.x + c.y) % 2 == 0:
		mat.albedo_color = mat.albedo_color.darkened(0.06)
	tile.material_override = mat
	add_child(tile)

	var side := MeshInstance3D.new()
	side.mesh = _tile_mesh(thickness - GRASS, 0.0)
	side.position = Vector3(top.x, top.y - GRASS - (thickness - GRASS) * 0.5, top.z)
	var side_mat := StandardMaterial3D.new()
	side_mat.albedo_color = SIDE_COLOR
	side.material_override = side_mat
	add_child(side)

	var body := StaticBody3D.new()
	body.set_meta("cell", c)
	var shape := CollisionShape3D.new()
	shape.shape = _tile_mesh(thickness, 0.0).create_convex_shape()
	body.position = Vector3(top.x, top.y - thickness * 0.5, top.z)
	body.add_child(shape)
	add_child(body)

	var overlay := MeshInstance3D.new()
	overlay.mesh = _tile_mesh(0.02, 0.08)
	overlay.position = Vector3(top.x, top.y + 0.012, top.z)
	overlay.visible = false
	overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(overlay)
	_overlays[c] = overlay


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


func _overlay_material(color: Color) -> StandardMaterial3D:
	if not _overlay_mats.has(color):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_overlay_mats[color] = m
	return _overlay_mats[color]

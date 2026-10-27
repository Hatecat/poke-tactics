class_name BoardView
extends Node3D
## Dibuja las casillas de una BoardGrid (suelo, laterales, detalles y obstáculos) y gestiona los resaltados.
## La vegetación y el agua se mueven con el viento (TerrainFx); `set_wind` cambia su fuerza según el clima.

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
	Biome.Kind.BEACH: Color(0.62, 0.5, 0.36),
}


func build(p_grid: BoardGrid) -> void:
	grid = p_grid
	for child in get_children():
		child.queue_free()
	_cells.clear()
	_overlays.clear()
	_puddles.clear()
	_hail_piles.clear()
	_crystal_lights.clear()
	_hail_bounce = null
	_tint_noise.seed = 7
	_tint_noise.frequency = 0.18
	_grass_noise.seed = grid.width * 131 + grid.height * 17 + grid.biome
	_grass_noise.frequency = 0.22
	for c in grid.all_cells():
		_build_cell(c)
	var w0 := grid.to_world(Vector2i.ZERO)
	var w1 := grid.to_world(Vector2i(grid.width - 1, grid.height - 1))
	var amb := TerrainFx.ambient(grid.biome, Vector3((w0.x + w1.x) * 0.5, 0.0, (w0.z + w1.z) * 0.5),
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
				var rock := _part(node, BoxMesh.new(), Vector3(-0.15 + i * 0.3, 0.55 + i * 0.1, 0), Color(0.55, 0.48, 0.4))
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


## Reconstruye una casilla (el editor la llama al cambiar altura, suelo u obstáculo).
func refresh_cell(c: Vector2i) -> void:
	if _cells.has(c):
		_cells[c].queue_free()
	_build_cell(c)


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


func highlight(cells: Array[Vector2i], color: Color) -> void:
	for c in cells:
		var overlay: MeshInstance3D = _overlays.get(c)
		if overlay:
			overlay.material_override = _overlay_material(_contrast(c, color))
			overlay.visible = true


## Los resaltados azules (movimiento, despliegue) no se distinguen sobre el agua ni el hielo:
## ahí se usa un tono claro (agua) u oscuro (hielo y nieve) que contraste.
func _contrast(c: Vector2i, color: Color) -> Color:
	if not (color.b > color.r + 0.3 and color.b >= color.g):
		return color
	match grid.tiles.get(c, Biome.Tile.GRASS):
		Biome.Tile.WATER:
			return Color(0.85, 1.0, 1.0, maxf(color.a, 0.6))
		Biome.Tile.ICE, Biome.Tile.SNOW:
			return Color(0.1, 0.3, 0.95, maxf(color.a, 0.6))
	return color


func _build_cell(c: Vector2i) -> void:
	var root := Node3D.new()
	add_child(root)
	_cells[c] = root
	var top := grid.to_world(c)
	var thickness := BASE_THICKNESS + top.y
	var tile_kind: int = grid.tiles.get(c, Biome.Tile.GRASS)

	var water := tile_kind in [Biome.Tile.WATER, Biome.Tile.BRIDGE, Biome.Tile.LAVA]  # el puente va sobre el agua
	if water:
		var surface := MeshInstance3D.new()
		surface.mesh = _water_mesh()
		surface.position = Vector3(top.x, top.y - WATER_DROP, top.z)
		if tile_kind == Biome.Tile.LAVA:
			surface.material_override = _live("lava", func() -> ShaderMaterial: return TerrainFx.lava_material())
			if (c.x * 3 + c.y) % 4 == 0:  # la lava ilumina lo que tiene cerca (una luz cada pocas casillas)
				var light := OmniLight3D.new()
				light.light_color = Color(1.0, 0.45, 0.15)
				light.light_energy = 0.9
				light.omni_range = 2.2
				light.position = Vector3(top.x, top.y + 0.3, top.z)
				root.add_child(light)
		else:
			var tint: Array = Biome.gym_style(grid.gym_type).get("water", [Color(0.1, 0.3, 0.62), Color(0.28, 0.6, 0.86)]) \
					if grid.biome == Biome.Kind.GYM else [Color(0.1, 0.3, 0.62), Color(0.28, 0.6, 0.86)]
			surface.material_override = _live("water_%s" % tint[0].to_html(), func() -> ShaderMaterial:
				return TerrainFx.water_material(tint[0], tint[1]))
		surface.set_instance_shader_parameter("shore", _shore(c))
		surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(surface)
		if tile_kind == Biome.Tile.BRIDGE:
			_bridge(root, c, top)
	else:
		var top_mesh := MeshInstance3D.new()
		top_mesh.mesh = _tile_mesh(TOP_THICKNESS, 0.0)
		top_mesh.position = Vector3(top.x, top.y - TOP_THICKNESS * 0.5, top.z)
		var col := _tile_color(c, tile_kind)
		if tile_kind in [Biome.Tile.CAVE, Biome.Tile.ROCK]:
			top_mesh.material_override = _live("stone_%s" % col.to_html(), func() -> ShaderMaterial:
				return TerrainFx.stone_material(col))
		else:
			top_mesh.material_override = _material(col, tile_kind in [Biome.Tile.ICE, Biome.Tile.MUD])  # el lodo brilla mojado
		root.add_child(top_mesh)

	var side_top := top.y - (WATER_DROP + 0.1 if water else TOP_THICKNESS)  # bajo el seno de las olas
	var side := MeshInstance3D.new()
	side.mesh = _tile_mesh(side_top + BASE_THICKNESS, 0.0)
	side.position = Vector3(top.x, (side_top - BASE_THICKNESS) * 0.5, top.z)
	side.material_override = _side_material(tile_kind)
	side.set_instance_shader_parameter("top_y", top.y)
	root.add_child(side)

	_decorate(root, c, tile_kind, top)
	if tile_kind == Biome.Tile.ROAD:
		_road_marks(root, c, top)
	_maybe_puddle(root, c, tile_kind, top)
	_hail_pile(root, c, tile_kind, top)

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
		p.position = top - (Vector3.UP * WATER_DROP if water else Vector3.ZERO)
		root.add_child(p)
		_root_sway(p, top.y)

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
	var snowy: bool = grid.biome == Biome.Kind.SNOW or grid.tiles.get(c, 0) == Biome.Tile.SNOW
	var snow := Color(0.95, 0.97, 1.0)
	var height := 1.0
	match prop:
		Biome.Prop.TREE:
			var leaf := Color(0.22, 0.48, 0.2) if grid.biome == Biome.Kind.FOREST else Color(0.28, 0.56, 0.24)
			if grid.biome == Biome.Kind.SWAMP:
				leaf = Color(0.3, 0.38, 0.16)  # sauce de pantano, verde oliva
			leaf = leaf.lerp(Color(0.45, 0.55, 0.18), float(h % 7) / 20.0)
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
			match grid.biome:
				Biome.Kind.DESERT: stone = Color(0.66, 0.47, 0.34)
				Biome.Kind.CAVE: stone = Color(0.34, 0.31, 0.3)
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
			elif grid.biome in [Biome.Kind.FOREST, Biome.Kind.SWAMP]:
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
			var marble: Color = Biome.gym_style(grid.gym_type).pillar if grid.biome == Biome.Kind.GYM else Color(0.82, 0.8, 0.76)
			_part(node, _cyl(0.25, 0.28, 1.3), Vector3(0, 0.65, 0), marble)
			_part(node, _cyl(0.33, 0.33, 0.1), Vector3(0, 1.32, 0), marble.darkened(0.15))
		Biome.Prop.STALAGMITE:
			# Estalagmita gastada: bloques de roca redondeados que se funden en una sola roca que se estrecha
			# hacia arriba, y piedras al pie.
			var stone := Color(0.42, 0.37, 0.34)
			var pieces := [[Vector3(0, 0.24, 0), Vector3(0.62, 0.52, 0.56)], [Vector3(0.03, 0.47, 0.02), Vector3(0.46, 0.52, 0.42)],
				[Vector3(0.05, 0.7, 0.02), Vector3(0.3, 0.4, 0.28)], [Vector3(0.27, 0.07, 0.13), Vector3(0.24, 0.17, 0.22)],
				[Vector3(-0.22, 0.06, 0.2), Vector3(0.19, 0.14, 0.18)]]
			for i in pieces.size():
				var mi := _part(node, TerrainFx.rock_mesh([0, 0, 3, 1, 1][i] + (h >> i) % 2 * 4), pieces[i][0], stone.darkened(0.05 * (i % 3)))
				mi.scale = pieces[i][1]
				mi.rotation.y = float((h >> i) % 6)
				var mat: StandardMaterial3D = mi.material_override.duplicate()
				mat.roughness = 0.45  # roca húmeda
				mi.material_override = mat
		Biome.Prop.CRYSTAL:
			# Drusa: una punta grande y varias pequeñas que salen inclinadas de una base de roca. Ilumina
			# el suelo de alrededor con su color.
			var tint := Color(0.65, 0.45, 0.95) if h % 3 else Color(0.45, 0.75, 1.0)
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
			height = 1.0
		Biome.Prop.BUILDING:
			# Edificio: bloque de 1 a 3 plantas en ladrillo, estuco u hormigón, con ventanas en cada cara,
			# puerta, cornisa y a veces una caja en la azotea. No gira, para que las fachadas queden alineadas.
			node.rotation.y = 0.0
			node.scale = Vector3.ONE
			var walls := [Color(0.62, 0.36, 0.28), Color(0.82, 0.76, 0.62), Color(0.62, 0.64, 0.66), Color(0.7, 0.55, 0.42)]
			var wall: Color = walls[h % 4]
			var floors := 1 + (h >> 2) % 3
			var tall := 0.45 * floors + 0.2
			_part(node, BoxMesh.new(), Vector3(0, tall * 0.5, 0), wall).scale = Vector3(0.9, tall, 0.9)
			_part(node, BoxMesh.new(), Vector3(0, tall + 0.03, 0), wall.darkened(0.3)).scale = Vector3(0.96, 0.06, 0.96)
			var glass := Color(0.35, 0.5, 0.62)
			for f in floors:
				var y := 0.42 + 0.45 * f
				for side in 4:
					var out := Vector3(cos(side * PI / 2), 0, sin(side * PI / 2))
					var across := Vector3(-out.z, 0, out.x)
					for k in [-1, 1]:
						var win := _part(node, BoxMesh.new(), Vector3(0, y, 0) + out * 0.452 + across * 0.2 * k, glass.lightened(0.15 * ((h >> (f + side)) % 2)))
						win.scale = Vector3(0.02, 0.2, 0.02) + (across * 0.16).abs()
			_part(node, BoxMesh.new(), Vector3(0, 0.15, 0.452), wall.darkened(0.45)).scale = Vector3(0.2, 0.3, 0.02)
			if (h >> 5) % 2 == 0:
				_part(node, BoxMesh.new(), Vector3(0.18, tall + 0.14, -0.15), Color(0.55, 0.56, 0.58)).scale = Vector3(0.25, 0.2, 0.22)
			height = tall
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
			# Máquina de laboratorio: consola blanca con pantalla encendida inclinada y pilotos de colores.
			node.rotation.y = float(h % 4) * PI / 2
			node.scale = Vector3.ONE
			var shell := Color(0.86, 0.88, 0.9)
			_part(node, BoxMesh.new(), Vector3(0, 0.3, 0), shell).scale = Vector3(0.82, 0.6, 0.6)
			_part(node, BoxMesh.new(), Vector3(0, 0.62, -0.18), shell.darkened(0.15)).scale = Vector3(0.82, 0.05, 0.25)
			var screen := _part(node, BoxMesh.new(), Vector3(0, 0.82, -0.2), Color(0.1, 0.12, 0.15))
			screen.scale = Vector3(0.66, 0.38, 0.04)
			screen.rotation.x = -0.25
			var face := _part(screen, BoxMesh.new(), Vector3(0, 0, 0.6), Color(0.2, 0.6, 0.8))
			face.scale = Vector3(0.9, 0.85, 0.3)
			_glow(face, [Color(0.3, 0.85, 1.0), Color(0.4, 1.0, 0.6), Color(0.6, 0.5, 1.0)][h % 3], 1.6)
			for i in 4:
				var led := _part(node, BoxMesh.new(), Vector3(-0.27 + 0.18 * i, 0.5, 0.305), Color.WHITE)
				led.scale = Vector3(0.06, 0.04, 0.01)
				_glow(led, [Color(1.0, 0.25, 0.2), Color(0.3, 1.0, 0.35), Color(1.0, 0.8, 0.2)][(h + i) % 3], 2.0)
			height = 1.0
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
	node.set_meta("sway_height", height * jitter)
	return node


## Puente de madera sobre el agua: tablones atravesados al paso, vigas por debajo y, en los lados que
## dan al agua, barandilla con postes.
func _bridge(root: Node3D, c: Vector2i, top: Vector3) -> void:
	var wood := Color(0.52, 0.37, 0.23)
	var on_water := func(n: Vector2i) -> bool:
		return not grid.is_inside(n) or grid.tiles.get(n, 0) in [Biome.Tile.WATER, Biome.Tile.BRIDGE]
	# Los tablones van de lado a lado (hacia donde hay agua o más puente) y se suceden en el sentido del paso
	var across := Vector3.RIGHT
	if grid.topology == BoardGrid.Topology.SQUARE and not (on_water.call(c + Vector2i(1, 0)) and on_water.call(c - Vector2i(1, 0))):
		across = Vector3.BACK
	var along := Vector3(-across.z, 0, across.x)
	var count := 5
	for i in count:
		var plank := _part(root, BoxMesh.new(), top + Vector3(0, -0.035, 0) + along * ((i + 0.5) / count - 0.5), wood.darkened(0.06 * ((hash(c) + i) % 3)))
		plank.scale = (across * 0.98 + along * (0.9 / count)).abs() + Vector3(0, 0.05, 0)
	for k in [-0.3, 0.3]:
		var beam := _part(root, BoxMesh.new(), top + Vector3(0, -0.1, 0) + across * k, wood.darkened(0.3))
		beam.scale = (along + across * 0.08).abs() + Vector3(0, 0.08, 0)
	var edge := 1.0 if grid.topology == BoardGrid.Topology.SQUARE else 1.0 / sqrt(3.0)
	for n in grid.neighbors(c):
		if grid.tiles.get(n, 0) != Biome.Tile.WATER:
			continue
		var out := grid.to_world(n) - grid.to_world(c)
		out.y = 0.0
		out = out.normalized()
		var side := Vector3(-out.z, 0, out.x)
		var rail := _part(root, BoxMesh.new(), top + out * 0.44 + Vector3(0, 0.3, 0), wood.darkened(0.1))
		rail.scale = (side * edge + out * 0.06).abs() + Vector3(0, 0.05, 0)
		for k in [-0.5, 0.5]:
			var post := _part(root, BoxMesh.new(), top + out * 0.44 + side * edge * k * 0.9 + Vector3(0, 0.05, 0), wood.darkened(0.2))
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
			var dash := _part(root, BoxMesh.new(), top + Vector3(d.x, 0, d.y) * 0.5 + Vector3(0, 0.004, 0), Color(0.92, 0.9, 0.82))
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


## Color de la cara de arriba: el del suelo con manchas suaves (hierba más seca o más verde, arena más
## clara...), algo más claro cuanto más alto, y un ajedrezado tenue para distinguir las casillas.
func _tile_color(c: Vector2i, tile_kind: int) -> Color:
	var color: Color = Biome.TILE_COLORS[tile_kind]
	if tile_kind == Biome.Tile.GRASS and grid.biome == Biome.Kind.FOREST:
		color = Color(0.32, 0.56, 0.28)
	elif tile_kind == Biome.Tile.GRASS and grid.biome == Biome.Kind.SWAMP:
		color = Color(0.36, 0.48, 0.24)  # hierba de pantano, oliva
	elif tile_kind == Biome.Tile.ROCK and grid.biome == Biome.Kind.DESERT:
		color = Color(0.74, 0.52, 0.38)  # arenisca
	elif grid.biome == Biome.Kind.VOLCANO and tile_kind in [Biome.Tile.ROCK, Biome.Tile.DIRT]:
		color = Color(0.24, 0.21, 0.2) if tile_kind == Biome.Tile.ROCK else Color(0.46, 0.43, 0.41)  # basalto y ceniza
	elif grid.biome == Biome.Kind.LAB and tile_kind in [Biome.Tile.FLOOR, Biome.Tile.FLOOR_LINE]:
		color = Color(0.84, 0.88, 0.92) if tile_kind == Biome.Tile.FLOOR else Color(0.3, 0.78, 0.92)
	elif grid.biome == Biome.Kind.GYM and tile_kind in [Biome.Tile.FLOOR, Biome.Tile.FLOOR_LINE]:
		color = Biome.gym_style(grid.gym_type).floor if tile_kind == Biome.Tile.FLOOR else Biome.gym_style(grid.gym_type).line
	var w := grid.to_world(c)
	var n := snappedf(_tint_noise.get_noise_2d(w.x, w.z), 0.25)
	if tile_kind == Biome.Tile.GRASS:
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
	var key := "%d_%d_%s" % [tile_kind, grid.biome, grid.gym_type]
	if not _side_mats.has(key):
		var bedrock: Color = BEDROCK[grid.biome]
		var top: Color = SIDE_TOP.get(tile_kind, Biome.SIDE_COLORS[grid.biome])
		if tile_kind == Biome.Tile.ROCK and grid.biome == Biome.Kind.DESERT:
			top = Color(0.66, 0.44, 0.3)
		if grid.biome == Biome.Kind.GYM:
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
	for i in 4:
		var n: Vector2i = c + dirs[i]
		if grid.is_inside(n) and grid.tiles.get(n, 0) not in same:
			out[i] = 1.0
	return out


## La hierba crece en zonas: matorrales de hierba alta separados por claros de césped corto.
func _tall_grass(c: Vector2i) -> bool:
	if grid.tiles.get(c, -1) != Biome.Tile.GRASS or grid.props.get(c, Biome.Prop.NONE) != Biome.Prop.NONE:
		return false
	var w := grid.to_world(c)
	var threshold := 0.05
	match grid.biome:
		Biome.Kind.FOREST: threshold = 0.2
		Biome.Kind.SWAMP: threshold = -0.15  # juncales
		Biome.Kind.MOUNTAIN, Biome.Kind.DESERT: threshold = 0.35
		Biome.Kind.CITY: threshold = 1.0  # césped cortado en el parque
		Biome.Kind.BEACH: threshold = 0.3
	return _grass_noise.get_noise_2d(w.x, w.z) > threshold


## Detalles pequeños del suelo (no estorban): hierba, flores, helechos, setas, juncos y nenúfares en la
## orilla, piedrecillas, matojos secos, montoncitos de nieve. Elegidos de forma estable por casilla.
func _decorate(root: Node3D, c: Vector2i, tile_kind: int, top: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(c) * 31 + grid.biome
	var b := grid.biome
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
		Biome.Tile.SNOW:
			if r1 < 0.25: list.append(["mound", Color(0.95, 0.97, 1.0), 0.0, 0.1])
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
			if b not in [Biome.Kind.CAVE, Biome.Kind.CITY, Biome.Kind.BEACH, Biome.Kind.LAB, Biome.Kind.GYM] and _shore(c) != Vector4.ZERO and r1 < (0.7 if b == Biome.Kind.SWAMP else 0.45):
				list.append(["reeds", Color(0.4, 0.6, 0.28), 0.9, 0.45])
			if b in [Biome.Kind.LAKE, Biome.Kind.MEADOW, Biome.Kind.SWAMP] and r2 < (0.45 if b == Biome.Kind.SWAMP else 0.25):
				list.append(["lily", Color(0.3, 0.58, 0.25), 0.15, 0.3])
	for d: Array in list:
		var kind: String = d[0]
		var mi := MeshInstance3D.new()
		mi.mesh = TerrainFx.decor_mesh("mushrooms" if kind == "glowshroom" else kind, rng.randi() % TerrainFx.VARIANTS, d[1])
		var y := top.y - (WATER_DROP - 0.03 if tile_kind == Biome.Tile.WATER and kind == "lily" else 0.0)
		if tile_kind == Biome.Tile.WATER and kind == "reeds":
			y -= WATER_DROP + 0.02
		mi.position = Vector3(top.x, y, top.z)
		mi.rotation.y = rng.randi_range(0, 3) * PI / 2
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if kind in SHADOW_DECOR \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var sway: float = d[2]
		if kind == "glowshroom":
			mi.material_override = _live("glowshroom", func() -> ShaderMaterial:
				var m := TerrainFx.foliage_material(Color.WHITE, 0.0, 0.0, true)
				m.set_shader_parameter("glow", 1.2)
				m.set_shader_parameter("pulse", 0.5)
				return m)
		elif sway > 0.0:
			mi.material_override = _live("decor_%.2f" % sway, func() -> ShaderMaterial:
				var m := TerrainFx.foliage_material(Color.WHITE, sway, sway, true)
				m.set_shader_parameter("push", 1.0)
				return m)
			mi.set_instance_shader_parameter("base_y", y)
			mi.set_instance_shader_parameter("height", d[3])
		else:
			mi.material_override = _vcol_material()
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


var _vcol_mat: StandardMaterial3D


func _vcol_material() -> StandardMaterial3D:
	if _vcol_mat == null:
		_vcol_mat = StandardMaterial3D.new()
		_vcol_mat.vertex_color_use_as_albedo = true
		_vcol_mat.vertex_color_is_srgb = true
		_mats["vcol"] = _vcol_mat  # para que también se moje
		_vcol_mat.roughness = 0.9
	return _vcol_mat


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

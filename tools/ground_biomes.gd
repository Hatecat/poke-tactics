extends SceneTree
## Prueba visual del apoyo en partida real en cada bioma: coloca a los Pokémon en agua, lava, casillas altas y
## bordes de desnivel, apunta la distancia de su punto más bajo a la casilla y guarda una captura por bioma.
##
##     godot --path . --resolution 1600x900 --script tools/ground_biomes.gd   (con POKE_TACTICS_NO_SAVE=1 y OUT=carpeta/)
var OUT := OS.get_environment("OUT")
var KINDS := OS.get_environment("KINDS")

func _initialize() -> void:
	_run.call_deferred()

func _wait(s: float) -> void:
	await create_timer(s).timeout

func _lowest(u) -> float:
	var lo := INF
	for m: MeshInstance3D in u._model.find_children("*", "MeshInstance3D", true, false):
		if m.is_visible_in_tree():
			lo = minf(lo, (u._lift.transform * u._model.transform * Unit._skinned_aabb(u._model, m)).position.y)
	return lo

func _run() -> void:
	var game = root.get_node("Game")
	await process_frame
	var tm = load("res://scripts/data/team_member.gd")
	var by_id := {}
	for d in game.roster:
		by_id[d.id] = d
	var log := FileAccess.open(OUT + "biomas.txt", FileAccess.WRITE)
	var kinds := range(18) if not KINDS else Array(KINDS.split(",")).map(func(s): return int(s))
	for kind in kinds:
		var pt: Array = []
		var et: Array = []
		for id in ["lapras", "magikarp", "charmander", "arcanine", "pidgeot", "gastly"]:
			pt.append(tm.create(by_id[id], by_id[id].moves))
		for id in ["machamp", "onix", "ekans", "geodude", "tentacruel", "ponyta"]:
			et.append(tm.create(by_id[id], by_id[id].moves))
		game.player_team.assign(pt)
		game.enemy_team.assign(et)
		game.map = null
		game.mode = "quick"
		game.biome = kind
		game.weather = 0
		game.rng.seed = 40 + kind
		change_scene_to_file("res://scenes/battle.tscn")
		await process_frame
		await process_frame
		var b = current_scene
		while b.state != b.State.DEPLOY:
			await process_frame
		var g = b.grid
		var taken := {}
		for u in b.units:
			for c in u.footprint:
				taken[c] = true
		var free := func(c: Vector2i, u) -> bool:
			for f in g.footprint(c, u.data.size):
				if not g.is_inside(f) or g.is_blocked(f) or taken.has(f):
					return false
			return b._fits(u, c)
		var cells: Array = []
		for y in g.height:
			for x in g.width:
				cells.append(Vector2i(x, y))
		var water := cells.filter(func(c): return g.tiles.get(c, 0) == Biome.Tile.WATER)
		var lava := cells.filter(func(c): return g.tiles.get(c, 0) == Biome.Tile.LAVA)
		var high := cells.duplicate()
		high.sort_custom(func(a, c): return g.get_height(a) > g.get_height(c))
		# Borde de desnivel: casilla con una vecina al menos un escalón más baja.
		var edge := cells.filter(func(c):
			for d in g.direction_count():
				var n = g.step(c, d)
				if g.is_inside(n) and g.get_height(c) - g.get_height(n) >= 1:
					return true
			return false)
		var plan := {"lapras": water, "magikarp": water, "machamp": water, "pidgeot": water,
			"charmander": lava if lava else edge, "ponyta": lava if lava else high, "arcanine": high, "onix": edge,
			"ekans": edge, "geodude": high, "gastly": edge, "tentacruel": water}
		var placed: Array = []
		var mine: Array = b.units.filter(func(u): return u.team == 0)
		for u in b.units:
			var list: Array = plan.get(u.data.id, [])
			for c in list:
				if free.call(c, u):
					for f in u.footprint:
						taken.erase(f)
					b._place(u, c)
					u.position = g.footprint_center(u.footprint)
					for f in u.footprint:
						taken[f] = true
					placed.append(u)
					break
		await _wait(1.0)
		var c := Vector3.ZERO
		for u in placed:
			c += u.global_position
		if placed:
			c /= placed.size()
		b._cam_rig.focus(c, 0.6)
		await _wait(0.9)
		log.store_line("== bioma %d %s (agua %d, lava %d, bordes %d)" % [kind, Biome.Kind.keys()[kind], water.size(), lava.size(), edge.size()])
		for u in b.units:
			var tile: int = g.tiles.get(u.cell, 0)
			var lo: float = _lowest(u)
			log.store_line("  %-10s casilla %s %-6s altura %d  punto más bajo %+.3f m  (vuelo %.2f, hunde %.2f)" % [u.data.id, u.cell, Biome.Tile.keys()[tile], g.get_height(u.cell), lo, u._ground.get("lift", 0.0) * u.data.model_height, u._surface_drop])
		log.flush()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT + "bioma_%02d_%s.png" % [kind, Biome.Kind.keys()[kind].to_lower()])
		print("bioma ", kind)
	log.close()
	quit()

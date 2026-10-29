extends SceneTree
## Comprueba el apoyo de todos los Pokémon con la corrección de data/pokemon_ground.json aplicada: en cada clip
## mide el punto más bajo de la malla (60 veces por segundo, como bake_ground) y avisa si se hunde o flota más de
## TOL de su altura (en el reposo, al andar y en los estados, también si se despega del suelo en algún momento).
##
##     godot --headless --path . --script tools/check_ground.gd [-- especie1,especie2]
##
## Sale con código 1 si encuentra alguno. No avisa de los voladores que flotan (bake_ground.FLYERS), de los
## debilitados que caen ni de Diglett y Dugtrio, que se meten en su agujero.

const TOL := 0.02


func _initialize() -> void:
	_run.call_deferred()


func _lowest(u) -> float:
	var lo := INF
	for m: MeshInstance3D in u._model.find_children("*", "MeshInstance3D", true, false):
		if m.is_visible_in_tree():
			lo = minf(lo, (u._model.transform * Unit._skinned_aabb(u._model, m)).position.y)
	return lo + u.ground_offset()


func _run() -> void:
	await process_frame
	var game = root.get_node("Game")
	var bake = load("res://tools/bake_ground.gd")
	var args := OS.get_cmdline_user_args()
	var only := args[0].split(",") if args.size() > 0 else PackedStringArray()
	var world := Node3D.new()
	root.add_child(world)
	var TM = load("res://scripts/data/team_member.gd")
	var problems := 0
	var species := 0
	var clips := 0
	for d in game.roster:
		if only and not d.id in only:
			continue
		var u = load("res://scripts/battle/unit.gd").new()
		world.add_child(u)
		u.setup(TM.create(d, d.moves), 0)
		await process_frame
		species += 1
		if u._anim:
			for clip in u._anim.get_animation_list():
				if clip.ends_with("RESET"):
					continue
				var key: String = clip.get_slice("|", clip.get_slice_count("|") - 1)
				var anim: Animation = u._anim.get_animation(clip)
				u._anim.play(clip, 0.0)
				var n := clampi(ceili(anim.length * bake.RATE) + 1, 2, bake.MAX_SAMPLES)
				var lo := INF
				var hi := -INF  # el punto más alto que alcanza el más bajo (en los clips `glued` debe seguir en el suelo)
				for i in n:
					u._anim.seek(anim.length * i / (n - 1), true)
					var y: float = _lowest(u) / d.model_height
					lo = minf(lo, y)
					hi = maxf(hi, y)
				if bake.glued(key) and not d.id in bake.IN_GROUND and not d.id in bake.FLYERS:
					lo = minf(lo, 0.0) if hi <= TOL else hi
				clips += 1
				if lo < -TOL and not d.id in bake.IN_GROUND:
					print("SE HUNDE  %-11s %-18s %+.3f" % [d.id, key, lo])
					problems += 1
				elif lo > TOL and not d.id in bake.FLYERS and key != "ko":
					print("FLOTA     %-11s %-18s %+.3f" % [d.id, key, lo])
					problems += 1
		u.queue_free()
	print("%d especies, %d clips revisados: %d fuera de tolerancia (%.0f %% de la altura)" % [species, clips, problems, TOL * 100])
	quit(1 if problems else 0)

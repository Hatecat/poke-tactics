extends SceneTree
## Calcula cuánto hay que subir o bajar cada Pokémon en cada clip para que no atraviese el suelo ni flote, y lo
## guarda en data/pokemon_ground.json (Unit lo aplica en el juego con su nodo `_lift`).
##
##     godot --headless --path . --script tools/bake_ground.gd [-- especie1,especie2]
##
## Unit.fit_model apoya el modelo con la pose del primer fotograma del reposo; lo que la animación baja después
## (el vaivén de un fantasma, el aleteo de un ave, las posturas de estado que agachan la cadera) atravesaba el
## suelo, y las posturas que lo levantan lo dejaban en el aire. Aquí se mide el punto más bajo de la malla
## deformada ~60 veces por segundo en cada clip (en el espacio del Unit: y = 0 es la cara de la casilla) y:
##   - terrestres: se suben los fotogramas que se hunden; si un clip no toca el suelo en ningún momento
##     (nunca es un salto: todos empiezan en el reposo), se baja entero hasta apoyarlo; en el reposo, al andar y
##     en los estados (`glued`: no hay saltos) el punto más bajo va pegado al suelo todo el clip (el vaivén del
##     reposo levantaba a Onix entero 0,17 m);
##   - voladores y levitadores (FLYERS): flotan a una altura fija, la justa para que en el reposo y al andar ni
##     las alas ni la cola toquen el suelo, más su holgura; al debilitarse bajan hasta posarse, y dormidos o
##     congelados se posan;
##   - los que viven bajo tierra (IN_GROUND: Diglett y Dugtrio salen de su agujero) solo se bajan si flotan.
## Los valores van en fracciones de data.model_height. Vuelve a ejecutarlo tras cambiar animaciones o modelos.

const OUT := "res://data/pokemon_ground.json"
const RATE := 60.0  # muestras por segundo (la parálisis tiembla deprisa)
const MAX_SAMPLES := 241
const TOL := 0.005  # lo que se permite hundir o flotar sin corregir (fracción de la altura)
## Holgura sobre el suelo de los que vuelan o levitan, además de lo que pidan sus alas o su vaivén.
## Las aves e insectos que aletean tocan casi el suelo con la punta del ala; gases, fantasmas e imanes
## flotan claramente (en los juegos nunca se posan).
const FLYERS := {
	"pidgey": 0.03, "pidgeotto": 0.03, "pidgeot": 0.03, "spearow": 0.03, "fearow": 0.03,
	"articuno": 0.03, "zapdos": 0.03, "moltres": 0.03, "aerodactyl": 0.03,
	"beedrill": 0.08, "scyther": 0.03, "butterfree": 0.1, "venomoth": 0.1, "zubat": 0.12, "golbat": 0.1,
	"gastly": 0.15, "haunter": 0.12, "koffing": 0.15, "weezing": 0.12, "magnemite": 0.2, "magneton": 0.15,
	"abra": 0.08,
}
## Clips en los que un volador se posa en el suelo.
const LANDS := ["status_sleep", "status_freeze"]
const IN_GROUND := ["diglett", "dugtrio"]


## Clips sin saltos: el punto más bajo no se separa del suelo.
static func glued(key: String) -> bool:
	return key in ["idle", "walk"] or key.begins_with("status_")


func _initialize() -> void:
	_run.call_deferred()


## Punto más bajo de la malla deformada, en el espacio del nodo que sostiene el modelo.
func _lowest(u) -> float:
	var lo := INF
	for m: MeshInstance3D in u._model.find_children("*", "MeshInstance3D", true, false):
		if not m.is_visible_in_tree():
			continue
		lo = minf(lo, (u._model.transform * Unit._skinned_aabb(u._model, m)).position.y)
	return lo


func _short(clip: String) -> String:
	return clip.get_slice("|", clip.get_slice_count("|") - 1)


func _run() -> void:
	await process_frame
	var game = root.get_node("Game")
	var args := OS.get_cmdline_user_args()
	var only := args[0].split(",") if args.size() > 0 else PackedStringArray()
	var result := {}
	if only and FileAccess.file_exists(OUT):
		result = JSON.parse_string(FileAccess.get_file_as_string(OUT))
	var world := Node3D.new()
	root.add_child(world)
	var TM = load("res://scripts/data/team_member.gd")
	for d in game.roster:
		if only and not d.id in only:
			continue
		var u = load("res://scripts/battle/unit.gd").new()
		u.ground_enabled = false
		world.add_child(u)
		u.setup(TM.create(d, d.moves), 0)
		await process_frame
		if u._anim == null:
			result.erase(d.id)
			u.queue_free()
			continue
		var h: float = d.model_height
		var lows := {}
		for clip in u._anim.get_animation_list():
			if clip.ends_with("RESET"):
				continue
			var anim: Animation = u._anim.get_animation(clip)
			var n := clampi(ceili(anim.length * RATE) + 1, 2, MAX_SAMPLES)
			u._anim.play(clip, 0.0)
			var ys := PackedFloat32Array()
			for i in n:
				u._anim.seek(anim.length * i / (n - 1), true)
				ys.append(_lowest(u) / h)
			lows[clip] = ys
		var lift := 0.0
		if d.id in FLYERS:
			for clip in lows:
				if _short(clip) in ["idle", "walk"]:
					for y in lows[clip]:
						lift = maxf(lift, -y)
			lift += FLYERS[d.id]
		var clips := {}
		for clip in lows:
			var ys: PackedFloat32Array = lows[clip]
			var key := _short(clip)
			var lo := INF
			for y in ys:
				lo = minf(lo, y)
			var ground := []
			var glue: bool = glued(key) and not d.id in IN_GROUND
			for y in ys:
				if glue and absf(y) > TOL:
					ground.append(-y)
				elif lo > TOL:
					ground.append(-lo)  # no toca el suelo en todo el clip: se apoya
				elif d.id in IN_GROUND or y >= -TOL:
					ground.append(0.0)
				else:
					ground.append(-y)
			var off := []
			for i in ys.size():
				if lift == 0.0 or key in LANDS:
					off.append(ground[i])
				elif key == "ko":  # cae mientras se debilita hasta posarse
					var k := float(i) / (ys.size() - 1)
					k = k * k * (3.0 - 2.0 * k)
					off.append(lerpf(maxf(lift, -ys[i]), ground[i], k))
				else:
					off.append(maxf(lift, -ys[i]))
			if off.any(func(v: float) -> bool: return absf(v - lift) > 0.001):
				clips[clip] = off.map(func(v: float) -> float: return snappedf(v, 0.001))
		result[d.id] = {"lift": snappedf(lift, 0.001), "clips": clips}
		u.queue_free()
		print("%s: altura de vuelo %.3f, %d clips corregidos" % [d.id, lift, clips.size()])
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(JSON.stringify(result))
	f.close()
	print("Guardado ", OUT)
	quit()

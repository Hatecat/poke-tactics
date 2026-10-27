class_name StoryRun
extends RefCounted
## Partida del modo historia: capítulo y paso del guion en que va, equipo de Cristina y lo que la próxima
## escena tiene que contar antes de seguir (experiencia y niveles del último combate).
## Cada capítulo es un JSON de data/story/ con sus personajes, el equipo inicial y una lista de pasos:
## "titulo" (rótulo de capítulo), "escena" (escena 3D con diálogos, ver Cutscene) y "combate".

const CHAPTERS := ["res://data/story/capitulo1.json"]
const BOARD_SIZE := Vector2i(20, 20)
const DEPLOY_ROWS := 4

var chapter := 0
var step := 0
var party: Array[TeamMember] = []
var report := PackedStringArray()
var _data := {}


static func new_game() -> StoryRun:
	var run := StoryRun.new()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for d: Dictionary in run.data().get("equipo", []):
		var m := member(d, rng)
		if m:
			run.party.append(m)
	return run


## Pokémon de la historia: {"especie", "nivel", "genero" (1 macho, 2 hembra), "ataques" (opcional)}.
static func member(d: Dictionary, rng: RandomNumberGenerator) -> TeamMember:
	var p := Game.find_species(d.get("especie", ""))
	if p == null:
		push_warning("Historia: especie desconocida %s" % d.get("especie", ""))
		return null
	var m := TeamMember.wild(p, int(d.get("nivel", 5)), rng)
	m.ability = p.abilities[0] if not p.abilities.is_empty() else ""
	if d.has("genero") and int(d.genero) in TeamMember.genders_for(p):
		m.gender = int(d.genero)
	if d.has("ataques"):
		var list: Array[MoveData] = []
		for id: String in d.ataques:
			if ResourceLoader.exists(TeamMember.MOVES_DIR + id + ".tres"):
				list.append(load(TeamMember.MOVES_DIR + id + ".tres"))
		if not list.is_empty():
			m.moves = list
	return m


func data() -> Dictionary:
	if _data.is_empty() and chapter < CHAPTERS.size():
		var text := FileAccess.get_file_as_string(CHAPTERS[chapter])
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary:
			_data = parsed
		else:
			push_error("Historia: no se pudo leer %s" % CHAPTERS[chapter])
	return _data


func steps() -> Array:
	return data().get("pasos", [])


func finished() -> bool:
	return step >= steps().size()


func current() -> Dictionary:
	return {} if finished() else steps()[step]


func advance() -> void:
	step += 1


## Datos de un personaje del capítulo: nombre, colores de su figura y retrato.
func character(id: String) -> Dictionary:
	return data().get("personajes", {}).get(id, {"nombre": id.capitalize()})


## Va a la pantalla del paso actual (escena o combate); al terminar el capítulo, al menú.
func go(tree: SceneTree) -> void:
	if finished():
		tree.change_scene_to_file("res://scenes/main_menu.tscn")
		return
	match current().get("tipo", ""):
		"combate":
			Game.mode = "story"
			Game.map = null
			tree.change_scene_to_file("res://scenes/battle.tscn")
		_:
			tree.change_scene_to_file("res://scenes/story.tscn")


## Tablero de un lugar: {"bioma": nombre de Biome.Kind, "semilla", "ancho", "alto", "obstaculos"}.
## "obstaculos" coloca a mano, después de generar, obstáculos de Biome.Prop: {"BUILDING": [[x, y], ...]}. Con la misma
## semilla sale el mismo tablero en la escena y en el combate (el combate usa la zona de despliegue
## de siempre: 4 filas abajo para Cristina y 4 arriba para el rival). Devuelve {grid, zones}.
static func build_grid(place: Dictionary) -> Dictionary:
	var w := int(place.get("ancho", BOARD_SIZE.x))
	var h := int(place.get("alto", BOARD_SIZE.y))
	var grid := BoardGrid.new(BoardGrid.Topology.SQUARE, w, h)
	var zones := [MapData.default_zone(w, h, 0, DEPLOY_ROWS), MapData.default_zone(w, h, 1, DEPLOY_ROWS)]
	var clear: Array[Vector2i] = []
	clear.append_array(zones[0])
	clear.append_array(zones[1])
	for c: Array in place.get("despejar", []):
		clear.append(Vector2i(c[0], c[1]))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(place.get("semilla", 1))
	grid.gym_type = place.get("gimnasio", "")
	Biome.generate(grid, biome_kind(place), rng, clear, zones[0], zones[1])
	var props: Dictionary = place.get("obstaculos", {})
	for key: String in props:
		for c: Array in props[key]:
			var cell := Vector2i(c[0], c[1])
			if grid.is_inside(cell):
				grid.props[cell] = Biome.Prop.get(key, Biome.Prop.NONE)
	return {"grid": grid, "zones": zones}


static func biome_kind(place: Dictionary) -> Biome.Kind:
	var key: String = place.get("bioma", "MEADOW")
	return Biome.Kind.get(key, Biome.Kind.MEADOW)


static func weather_kind(place: Dictionary) -> Weather.Kind:
	var key: String = place.get("clima", "CLEAR")
	return Weather.Kind.get(key, Weather.Kind.CLEAR)


func to_dict() -> Dictionary:
	return {"chapter": chapter, "step": step, "party": party.map(func(m: TeamMember) -> Dictionary: return m.to_dict()),
		"report": Array(report)}


static func from_dict(d: Dictionary) -> StoryRun:
	var run := StoryRun.new()
	run.chapter = d.get("chapter", 0)
	run.step = d.get("step", 0)
	for md: Dictionary in d.get("party", []):
		var m := TeamMember.from_dict(md, Game.find_species)
		if m:
			run.party.append(m)
	run.report = PackedStringArray(d.get("report", []))
	return run

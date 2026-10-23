extends Node
## Autoload "Game": roster disponible, equipos del jugador (guardados en disco),
## equipo rival y opciones de la próxima batalla.

const MAX_TEAM := 6
const MAX_TEAMS := 6
enum Difficulty { EASY, NORMAL, HARD }
const DIFFICULTY_NAMES := ["Fácil", "Normal", "Difícil"]
## Nivel de los rivales en cada dificultad (los tuyos siempre son 50).
const DIFFICULTY_LEVELS := [45, 50, 55]
const DIFFICULTY_DESC := [
	"Rivales a nivel 45; a veces eligen mal.",
	"Rivales a nivel 50.",
	"Rivales a nivel 55; evitan exponerse y rematan a los débiles.",
]


## Un equipo guardado: nombre y hasta 6 Pokémon.
class TeamSlot:
	var name := ""
	var members: Array[TeamMember] = []
const SAVE_PATH := "user://save.cfg"
const POKEMON_DIR := "res://data/pokemon/"
## Escenarios del juego (se guardan aquí al ejecutar desde el editor de Godot, para
## que entren en el repo y en las builds) y escenarios del jugador.
const GAME_MAPS_DIR := "res://data/maps/"
const USER_MAPS_DIR := "user://maps/"

var roster: Array[PokemonData] = []
var teams: Array[TeamSlot] = []
var current_team := 0
var difficulty := Difficulty.NORMAL
## Equipo con el que se juega (el seleccionado).
var player_team: Array[TeamMember]:
	get:
		return teams[current_team].members
	set(value):
		teams[current_team].members = value
var enemy_team: Array[TeamMember] = []
var topology := BoardGrid.Topology.SQUARE
var biome := Biome.Kind.MEADOW
## Clima de la partida rápida (-1 = aleatorio según el campo).
var weather := -1
## Escenario fijo para la próxima batalla (null = generar uno aleatorio).
var map: MapData
## Escenario abierto en el editor (se conserva al ir a probarlo y volver).
var editor_map: MapData
## La batalla actual es una prueba lanzada desde el editor de escenarios.
var testing_map := false
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	_load_roster()
	_load_save()


func _load_roster() -> void:
	for file in DirAccess.get_files_at(POKEMON_DIR):
		# En builds exportados los recursos aparecen como ".tres.remap".
		file = file.trim_suffix(".remap")
		if file.ends_with(".tres"):
			roster.append(load(POKEMON_DIR + file))
	roster.sort_custom(func(a: PokemonData, b: PokemonData) -> bool: return a.dex_number < b.dex_number)


## Busca por id ("mrmime") o por nombre ("Mr. Mime").
func find_species(key: String) -> PokemonData:
	for p in roster:
		if p.id == key or p.species_name == key:
			return p
	return null


func add_team(team_name := "") -> int:
	if teams.size() >= MAX_TEAMS:
		return -1
	var slot := TeamSlot.new()
	slot.name = team_name if team_name else "Equipo %d" % (teams.size() + 1)
	teams.append(slot)
	save()
	return teams.size() - 1


func remove_team(index: int) -> void:
	if teams.size() <= 1:
		return
	teams.remove_at(index)
	current_team = clampi(current_team, 0, teams.size() - 1)
	save()


func select_team(index: int) -> void:
	current_team = clampi(index, 0, teams.size() - 1)
	save()


func add_to_team(p: PokemonData) -> bool:
	if player_team.size() >= MAX_TEAM:
		return false
	player_team.append(TeamMember.create(p))
	save()
	return true


func remove_from_team(index: int) -> void:
	player_team.remove_at(index)
	save()


## Rival aleatorio (especies y ataques) del mismo tamaño que el equipo del jugador.
func roll_enemy_team() -> void:
	enemy_team.clear()
	for i in maxi(player_team.size(), 1):
		enemy_team.append(TeamMember.random(roster[rng.randi_range(0, roster.size() - 1)], rng))


## Rutas de todos los escenarios guardados (del juego y del jugador).
func list_maps() -> PackedStringArray:
	var paths := PackedStringArray()
	for dir in [GAME_MAPS_DIR, USER_MAPS_DIR]:
		if not DirAccess.dir_exists_absolute(dir):
			continue
		for file in DirAccess.get_files_at(dir):
			file = file.trim_suffix(".remap")
			if file.ends_with(".tres"):
				paths.append(dir + file)
	return paths


func save_map(data: MapData) -> String:
	var dir := GAME_MAPS_DIR if OS.has_feature("editor") else USER_MAPS_DIR
	DirAccess.make_dir_recursive_absolute(dir)
	var slug := data.map_name.to_lower().strip_edges().replace(" ", "_").validate_filename()
	var path := dir + (slug if slug else "escenario") + ".tres"
	data.take_over_path(path)
	return path if ResourceSaver.save(data, path) == OK else ""


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("teams", "list", teams.map(func(t: TeamSlot) -> Dictionary:
		return {"name": t.name, "members": t.members.map(func(m: TeamMember) -> Dictionary: return m.to_dict())}))
	cfg.set_value("teams", "current", current_team)
	cfg.set_value("options", "difficulty", difficulty)
	cfg.set_value("options", "topology", topology)
	cfg.set_value("options", "biome", biome)
	cfg.set_value("options", "weather", weather)
	cfg.save(SAVE_PATH)


func _load_save() -> void:
	var cfg := ConfigFile.new()
	var loaded := cfg.load(SAVE_PATH) == OK
	if loaded:
		for t: Dictionary in cfg.get_value("teams", "list", []):
			var slot := TeamSlot.new()
			slot.name = t.get("name", "Equipo %d" % (teams.size() + 1))
			for d: Dictionary in t.get("members", []):
				var m := TeamMember.from_dict(d, find_species)
				if m and slot.members.size() < MAX_TEAM:
					slot.members.append(m)
			if teams.size() < MAX_TEAMS:
				teams.append(slot)
		if teams.is_empty():
			# Formatos antiguos: un solo equipo (con ataques, o solo nombres de especie).
			var slot := TeamSlot.new()
			slot.name = "Equipo 1"
			for d: Dictionary in cfg.get_value("team", "members", []):
				var m := TeamMember.from_dict(d, find_species)
				if m and slot.members.size() < MAX_TEAM:
					slot.members.append(m)
			for species_name: String in cfg.get_value("team", "species", []):
				var p := find_species(species_name)
				if p and slot.members.size() < MAX_TEAM:
					slot.members.append(TeamMember.create(p))
			teams.append(slot)
		current_team = clampi(cfg.get_value("teams", "current", 0), 0, teams.size() - 1)
		difficulty = cfg.get_value("options", "difficulty", Difficulty.NORMAL)
	if teams.is_empty():
		var slot := TeamSlot.new()
		slot.name = "Equipo 1"
		teams.append(slot)
	if loaded:
		topology = cfg.get_value("options", "topology", BoardGrid.Topology.SQUARE)
		biome = cfg.get_value("options", "biome", Biome.Kind.MEADOW)
		weather = cfg.get_value("options", "weather", -1)
	# Primera vez que se abre el juego: un equipo inicial.
	if not loaded and player_team.is_empty():
		for id in ["bulbasaur", "charmander", "squirtle"]:
			var p := find_species(id)
			if p:
				player_team.append(TeamMember.create(p))

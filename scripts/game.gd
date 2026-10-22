extends Node
## Autoload "Game": roster disponible, equipo del jugador (guardado en disco),
## equipo rival y opciones de la próxima batalla.

const MAX_TEAM := 6
const SAVE_PATH := "user://save.cfg"
const POKEMON_DIR := "res://data/pokemon/"
## Escenarios del juego (se guardan aquí al ejecutar desde el editor de Godot, para
## que entren en el repo y en las builds) y escenarios del jugador.
const GAME_MAPS_DIR := "res://data/maps/"
const USER_MAPS_DIR := "user://maps/"

var roster: Array[PokemonData] = []
var player_team: Array[TeamMember] = []
var enemy_team: Array[TeamMember] = []
var topology := BoardGrid.Topology.SQUARE
var biome := Biome.Kind.MEADOW
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
	cfg.set_value("team", "members", player_team.map(func(m: TeamMember) -> Dictionary: return m.to_dict()))
	cfg.set_value("options", "topology", topology)
	cfg.set_value("options", "biome", biome)
	cfg.save(SAVE_PATH)


func _load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		for d: Dictionary in cfg.get_value("team", "members", []):
			var m := TeamMember.from_dict(d, find_species)
			if m and player_team.size() < MAX_TEAM:
				player_team.append(m)
		# Formato antiguo: solo nombres de especie.
		for species_name: String in cfg.get_value("team", "species", []):
			var p := find_species(species_name)
			if p and player_team.size() < MAX_TEAM:
				player_team.append(TeamMember.create(p))
		topology = cfg.get_value("options", "topology", BoardGrid.Topology.SQUARE)
		biome = cfg.get_value("options", "biome", Biome.Kind.MEADOW)
	if player_team.is_empty():
		for id in ["bulbasaur", "charmander", "squirtle"]:
			var p := find_species(id)
			if p:
				player_team.append(TeamMember.create(p))

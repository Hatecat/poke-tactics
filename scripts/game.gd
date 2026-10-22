extends Node
## Autoload "Game": roster disponible, equipo del jugador (guardado en disco),
## equipo rival y opciones de la próxima batalla.

const MAX_TEAM := 6
const SAVE_PATH := "user://save.cfg"
const POKEMON_DIR := "res://data/pokemon/"

var roster: Array[PokemonData] = []
var player_team: Array[PokemonData] = []
var enemy_team: Array[PokemonData] = []
var topology := BoardGrid.Topology.SQUARE


func _ready() -> void:
	_load_roster()
	_load_save()


func _load_roster() -> void:
	for file in DirAccess.get_files_at(POKEMON_DIR):
		# En builds exportados los recursos aparecen como ".tres.remap".
		file = file.trim_suffix(".remap")
		if file.ends_with(".tres"):
			roster.append(load(POKEMON_DIR + file))
	roster.sort_custom(func(a: PokemonData, b: PokemonData) -> bool: return a.dex_number < b.dex_number)


func find_species(species_name: String) -> PokemonData:
	for p in roster:
		if p.species_name == species_name:
			return p
	return null


func add_to_team(p: PokemonData) -> bool:
	if player_team.size() >= MAX_TEAM:
		return false
	player_team.append(p)
	save()
	return true


func remove_from_team(index: int) -> void:
	player_team.remove_at(index)
	save()


## Rival aleatorio del mismo tamaño que el equipo del jugador.
func roll_enemy_team() -> void:
	enemy_team.clear()
	for i in maxi(player_team.size(), 1):
		enemy_team.append(roster.pick_random())


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("team", "species", player_team.map(func(p: PokemonData) -> String: return p.species_name))
	cfg.set_value("options", "topology", topology)
	cfg.save(SAVE_PATH)


func _load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		for species_name: String in cfg.get_value("team", "species", []):
			var p := find_species(species_name)
			if p and player_team.size() < MAX_TEAM:
				player_team.append(p)
		topology = cfg.get_value("options", "topology", BoardGrid.Topology.SQUARE)
	if player_team.is_empty():
		for species_name in ["Bulbasaur", "Charmander", "Squirtle"]:
			var p := find_species(species_name)
			if p:
				player_team.append(p)

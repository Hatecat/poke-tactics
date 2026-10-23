class_name TeamMember
extends RefCounted
## Un Pokémon concreto de un equipo: su especie y los (hasta 4) ataques elegidos.

const MAX_MOVES := 4
const MOVES_DIR := "res://data/moves/"

var data: PokemonData
var moves: Array[MoveData] = []
## Habilidad elegida (id de data/abilities.json).
var ability := ""
## 0 = sin género, 1 = macho, 2 = hembra.
var gender := 0

const GENDER_SYMBOLS := ["", "♂", "♀"]


## Géneros posibles de la especie.
static func genders_for(p_data: PokemonData) -> Array[int]:
	if p_data.male_ratio < 0.0:
		return [0]
	if p_data.male_ratio >= 1.0:
		return [1]
	if p_data.male_ratio <= 0.0:
		return [2]
	return [1, 2]


static func create(p_data: PokemonData, p_moves: Array[MoveData] = []) -> TeamMember:
	var m := TeamMember.new()
	m.data = p_data
	m.moves = p_moves.duplicate() if not p_moves.is_empty() else p_data.moves.duplicate()
	m.ability = p_data.abilities[0] if not p_data.abilities.is_empty() else ""
	m.gender = 0 if p_data.male_ratio < 0.0 else (1 if p_data.male_ratio >= 0.5 else 2)
	return m


## Set aleatorio pero sensato: al menos dos ataques de daño, sin repetir.
static func random(p_data: PokemonData, rng: RandomNumberGenerator) -> TeamMember:
	var damaging := p_data.learnset.filter(func(mv: MoveData) -> bool: return mv.category != MoveData.Category.STATUS)
	var status := p_data.learnset.filter(func(mv: MoveData) -> bool: return mv.category == MoveData.Category.STATUS)
	_shuffle(damaging, rng)
	_shuffle(status, rng)
	var chosen: Array[MoveData] = []
	for mv: MoveData in damaging.slice(0, 2):
		chosen.append(mv)
	var rest := damaging.slice(2) + status
	_shuffle(rest, rng)
	for mv: MoveData in rest:
		if chosen.size() >= MAX_MOVES:
			break
		chosen.append(mv)
	var m := create(p_data, chosen)
	if not p_data.abilities.is_empty():
		m.ability = p_data.abilities[rng.randi_range(0, p_data.abilities.size() - 1)]
	if p_data.male_ratio >= 0.0:
		m.gender = 1 if rng.randf() < p_data.male_ratio else 2
	return m


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func to_dict() -> Dictionary:
	return {"species": data.id, "moves": moves.map(func(mv: MoveData) -> String: return mv.id), "ability": ability, "gender": gender}


## `species_lookup` recibe un id y devuelve el PokemonData (o null).
static func from_dict(d: Dictionary, species_lookup: Callable) -> TeamMember:
	var p: PokemonData = species_lookup.call(d.get("species", ""))
	if p == null:
		return null
	var list: Array[MoveData] = []
	for move_id: String in d.get("moves", []):
		var path := MOVES_DIR + move_id + ".tres"
		if ResourceLoader.exists(path):
			list.append(load(path))
	var m := create(p, list)
	var ab: String = d.get("ability", "")
	if ab in p.abilities:
		m.ability = ab
	var g: int = d.get("gender", m.gender)
	if g in genders_for(p):
		m.gender = g
	return m

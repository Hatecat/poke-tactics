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
## Nivel y experiencia (la Partida rápida usa siempre 50; la Torre empieza en 5).
var level := 50
var exp := 0
## Ataques aprendidos subiendo de nivel (la Torre deja elegir 4 de aquí).
var known: Array[MoveData] = []
## Objeto equipado (o null).
var item: ItemData

const MAX_LEVEL := 100
## Experiencia para pasar de nivel N a N+1: N × EXP_PER_LEVEL.
const EXP_PER_LEVEL := 20

const GENDER_SYMBOLS := ["", "♂", "♀"]


## Nombre con el símbolo de género (Nidoran♀ ya lo lleva en el nombre: no se repite).
static func display(p_data: PokemonData, p_gender: int) -> String:
	var n := p_data.species_name
	if n.ends_with("♀") or n.ends_with("♂"):
		return n
	return n + GENDER_SYMBOLS[p_gender]


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


## Pokémon salvaje (o del draft) a un nivel: conoce sus ataques de nivel y usa los 4 últimos.
static func wild(p_data: PokemonData, p_level: int, rng: RandomNumberGenerator) -> TeamMember:
	var m := create(p_data)
	m.level = p_level
	m.known = moves_up_to(p_data, p_level)
	var last: Array[MoveData] = []
	for mv in m.known.slice(maxi(0, m.known.size() - MAX_MOVES)):
		last.append(mv)
	if last.is_empty() and not p_data.level_moves.is_empty():
		# Ninguno a su nivel: el primero que aprendería.
		var first_id: String = p_data.level_moves.keys()[0]
		for id: String in p_data.level_moves:
			if p_data.level_moves[id] < p_data.level_moves[first_id]:
				first_id = id
		if ResourceLoader.exists(MOVES_DIR + first_id + ".tres"):
			last.append(load(MOVES_DIR + first_id + ".tres"))
	m.moves = last if not last.is_empty() else p_data.moves.slice(0, 1)
	if not p_data.abilities.is_empty():
		m.ability = p_data.abilities[rng.randi_range(0, p_data.abilities.size() - 1)]
	if p_data.male_ratio >= 0.0:
		m.gender = 1 if rng.randf() < p_data.male_ratio else 2
	return m


## Ataques que la especie aprende hasta `p_level`, en orden de nivel.
static func moves_up_to(p_data: PokemonData, p_level: int) -> Array[MoveData]:
	var list: Array[MoveData] = []
	for id: String in p_data.level_moves:
		if p_data.level_moves[id] <= p_level and ResourceLoader.exists(MOVES_DIR + id + ".tres"):
			list.append(load(MOVES_DIR + id + ".tres"))
	return list


func exp_to_next() -> int:
	return level * EXP_PER_LEVEL


## Suma experiencia. Devuelve lo ocurrido (subidas de nivel, ataques nuevos, evolución).
## `species_lookup` resuelve el id de la especie a la que evoluciona.
func gain_exp(amount: int, species_lookup: Callable, rng: RandomNumberGenerator) -> PackedStringArray:
	var events := PackedStringArray()
	exp += amount
	while level < MAX_LEVEL and exp >= exp_to_next():
		exp -= exp_to_next()
		level += 1
		events.append("%s subió a nivel %d." % [TeamMember.display(data, gender), level])
		for id: String in data.level_moves:
			if data.level_moves[id] == level:
				_learn(id, events)
		if not data.evolves_to.is_empty() and level >= data.evolve_level and not (item and item.effect == "everstone"):
			var target: PokemonData = species_lookup.call(data.evolves_to[rng.randi_range(0, data.evolves_to.size() - 1)])
			if target:
				events.append("¡%s evolucionó a %s!" % [TeamMember.display(data, gender), target.species_name])
				var slot := data.abilities.find(ability)
				data = target
				ability = target.abilities[clampi(slot, 0, target.abilities.size() - 1)] if not target.abilities.is_empty() else ""
				if gender not in genders_for(target):
					gender = genders_for(target)[0]
				# Ataques que la nueva forma aprende justo al evolucionar (nivel 1 o su nivel actual).
				for id: String in target.level_moves:
					if target.level_moves[id] <= 1 or target.level_moves[id] == level:
						_learn(id, events)
	if level >= MAX_LEVEL:
		exp = 0
	return events


## Evoluciona con una piedra. Devuelve el mensaje, o "" si la especie no reacciona a esa piedra.
func evolve_with_stone(stone_id: String, species_lookup: Callable) -> String:
	if not data.stone_evolutions.has(stone_id):
		return ""
	var target: PokemonData = species_lookup.call(data.stone_evolutions[stone_id])
	if target == null:
		return ""
	var text := "¡%s evolucionó a %s!" % [TeamMember.display(data, gender), target.species_name]
	var slot := data.abilities.find(ability)
	data = target
	ability = target.abilities[clampi(slot, 0, target.abilities.size() - 1)] if not target.abilities.is_empty() else ""
	if gender not in genders_for(target):
		gender = genders_for(target)[0]
	return text


func _learn(id: String, events: PackedStringArray) -> void:
	if not ResourceLoader.exists(MOVES_DIR + id + ".tres"):
		return
	var mv: MoveData = load(MOVES_DIR + id + ".tres")
	if mv in known:
		return
	known.append(mv)
	if moves.size() < MAX_MOVES:
		moves.append(mv)
		events.append("%s aprendió %s." % [TeamMember.display(data, gender), mv.display_name])
	else:
		events.append("%s puede aprender %s (cámbialo en su ficha)." % [TeamMember.display(data, gender), mv.display_name])


func to_dict() -> Dictionary:
	return {"species": data.id, "moves": moves.map(func(mv: MoveData) -> String: return mv.id), "ability": ability, "gender": gender,
		"level": level, "exp": exp, "known": known.map(func(mv: MoveData) -> String: return mv.id),
		"item": item.id if item else ""}


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
	m.level = d.get("level", 50)
	m.item = Items.find(d.get("item", ""))
	m.exp = d.get("exp", 0)
	for move_id: String in d.get("known", []):
		var path := MOVES_DIR + move_id + ".tres"
		if ResourceLoader.exists(path):
			m.known.append(load(path))
	if d.has("known"):
		for mv in moves_up_to(p, m.level):
			if mv not in m.known:
				m.known.append(mv)
	# Guardados de antes de que existiera su ataque (Ditto, Abra): solo tenían Forcejeo.
	if m.moves.size() == 1 and m.moves[0].id == "struggle":
		var pool: Array[MoveData] = m.known if not m.known.is_empty() else p.moves
		if not pool.is_empty() and pool[0].id != "struggle":
			m.moves = pool.slice(maxi(0, pool.size() - MAX_MOVES))
	return m

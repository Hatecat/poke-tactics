class_name VsMatch
extends RefCounted
## Reglas del modo VS fuera del combate: equipos como datos (con su comprobación de legalidad) y el mensaje
## "start" que arranca una partida igual en los dos PCs. Lo usan la pantalla VS y la revancha en el combate.
##
## La partida vive en `Game.vs`: {side, seed, topology, biome, biome_choice, teams: [anfitrión, invitado]
## (Array[TeamMember]), nicks: [anfitrión, invitado]}. El lado 0 es el anfitrión.

## Nivel de todos los Pokémon en VS (sin experiencia ni evolución).
const LEVEL := 50


## Equipo como datos para la red: especie, ataques, habilidad, género y objeto de cada Pokémon.
static func team_data(team: Array[TeamMember]) -> Array:
	return team.map(func(m: TeamMember) -> Dictionary:
		return {"species": m.data.id, "moves": m.moves.map(func(mv: MoveData) -> String: return mv.id),
			"ability": m.ability, "gender": m.gender, "item": m.item.id if m.item else ""})


## Motivo por el que un equipo recibido no es legal ("" si lo es): 1-6 Pokémon que existen, de 1 a 4 ataques
## distintos que su especie puede aprender, y habilidad, género y objeto posibles.
static func illegal_reason(data: Variant) -> String:
	if not data is Array or data.is_empty() or data.size() > Game.MAX_TEAM:
		return "size"
	for d: Variant in data:
		if not d is Dictionary:
			return "format"
		var p: PokemonData = Game.find_species(str(d.get("species", "")))
		if p == null:
			return "species"
		var moves: Variant = d.get("moves")
		if not moves is Array or moves.is_empty() or moves.size() > TeamMember.MAX_MOVES:
			return "moves"
		var seen := {}
		for id: Variant in moves:
			if not id is String or seen.has(id) or not _learnable(p, id):
				return "moves"
			seen[id] = true
		var ability: Variant = d.get("ability")
		if not ability is String or (ability not in p.abilities and not (p.abilities.is_empty() and ability == "")):
			return "ability"
		if not d.get("gender") is int or d.gender not in TeamMember.genders_for(p):
			return "gender"
		var item: Variant = d.get("item")
		if not item is String or (item != "" and not Items.holdable().any(func(it: ItemData) -> bool: return it.id == item)):
			return "item"
	return ""


## Equipo a partir de datos ya comprobados con illegal_reason (todos a nivel LEVEL).
static func team_from_data(data: Array) -> Array[TeamMember]:
	var team: Array[TeamMember] = []
	for d: Dictionary in data:
		var p := Game.find_species(d.species)
		var moves: Array[MoveData] = []
		for id: String in d.moves:
			moves.append(_move(p, id))
		var m := TeamMember.create(p, moves)
		m.ability = d.ability
		m.gender = d.gender
		m.item = Items.find(d.item)
		m.level = LEVEL
		team.append(m)
	return team


## Mensaje "start" del anfitrión: semilla nueva, tablero y los dos equipos (anfitrión primero).
## `biome_choice` -1 = bioma al azar (lo decide la semilla del anfitrión).
static func make_start(host_team: Array, guest_team: Array, topology: int, biome_choice: int, nicks: Array) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var biome := biome_choice if biome_choice >= 0 else Biome.random_kind(rng)
	return {"t": "start", "seed": rng.randi_range(1, 0x7fffffff), "topology": topology, "biome": biome,
		"biome_choice": biome_choice, "teams": [host_team, guest_team], "nicks": nicks}


## Prepara `Game.vs` con un "start" recibido o propio. Devuelve "" o el motivo por el que no vale.
static func apply_start(msg: Dictionary, side: int) -> String:
	if not msg.get("seed") is int or msg.seed == 0 or not msg.get("topology") is int or not msg.get("biome") is int:
		return "format"
	if msg.topology not in [BoardGrid.Topology.SQUARE, BoardGrid.Topology.HEX] or msg.biome < 0 or msg.biome >= Biome.Kind.TEST:
		return "format"
	var teams: Variant = msg.get("teams")
	var nicks: Variant = msg.get("nicks")
	if not teams is Array or teams.size() != 2 or not nicks is Array or nicks.size() != 2:
		return "format"
	for t: Variant in teams:
		var why := illegal_reason(t)
		if not why.is_empty():
			return why
	Game.vs = {"side": side, "seed": msg.seed, "topology": msg.topology, "biome": msg.biome,
		"biome_choice": int(msg.get("biome_choice", -1)), "team_data": teams,
		"teams": [team_from_data(teams[0]), team_from_data(teams[1])],
		"nicks": [Protocol.clean_nick(str(nicks[0])), Protocol.clean_nick(str(nicks[1]))]}
	Game.mode = "vs"
	return ""


## Texto para el jugador de un motivo de illegal_reason / apply_start.
static func reason_text(code: String) -> String:
	match code:
		"size":
			return TranslationServer.translate("El equipo debe tener de 1 a 6 Pokémon.")
		"species", "moves", "ability", "gender", "item":
			return TranslationServer.translate("El equipo del rival tiene algo que no se puede usar.")
	return TranslationServer.translate("Los datos de la partida no son válidos.")


static func _learnable(p: PokemonData, id: String) -> bool:
	return _move(p, id) != null


static func _move(p: PokemonData, id: String) -> MoveData:
	for mv in p.learnset:
		if mv.id == id:
			return mv
	for mv in p.moves:
		if mv.id == id:
			return mv
	return null

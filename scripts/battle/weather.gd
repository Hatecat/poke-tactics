class_name Weather
extends RefCounted
## Clima del combate y cómo modifica a los ataques y a los Pokémon (reglas de los juegos).

enum Kind { CLEAR, SUN, RAIN, SAND, HAIL }

const NAMES := { # i18n
	Kind.CLEAR: "Despejado", Kind.SUN: "Sol intenso", Kind.RAIN: "Lluvia",
	Kind.SAND: "Tormenta de arena", Kind.HAIL: "Granizo",
}
## Nombre corto, para los botones.
const SHORT_NAMES := {Kind.CLEAR: "Despejado", Kind.SUN: "Sol", Kind.RAIN: "Lluvia", Kind.SAND: "Arena", Kind.HAIL: "Granizo"} # i18n
## Símbolos que existen en la fuente por defecto (los emojis de clima no).
const ICONS := {Kind.CLEAR: "○", Kind.SUN: "☀", Kind.RAIN: "☂", Kind.SAND: "≋", Kind.HAIL: "❄"}
## Tipo de Meteorobola con cada clima.
const BALL_TYPES := {Kind.CLEAR: "normal", Kind.SUN: "fire", Kind.RAIN: "water", Kind.SAND: "rock", Kind.HAIL: "ice"}
## Tipos que no sufren daño con arena / granizo.
const SAND_IMMUNE: PackedStringArray = ["rock", "ground", "steel"]
## Probabilidad de cada clima en partida rápida según el campo (el resto, despejado).
const BIOME_ODDS := {
	Biome.Kind.MEADOW: {Kind.SUN: 0.2, Kind.RAIN: 0.2},
	Biome.Kind.FOREST: {Kind.RAIN: 0.3, Kind.SUN: 0.1},
	Biome.Kind.MOUNTAIN: {Kind.HAIL: 0.2, Kind.SAND: 0.15, Kind.SUN: 0.1},
	Biome.Kind.DESERT: {Kind.SUN: 0.4, Kind.SAND: 0.35},
	Biome.Kind.LAKE: {Kind.RAIN: 0.45, Kind.SUN: 0.1},
	Biome.Kind.SNOW: {Kind.HAIL: 0.6},
	Biome.Kind.CAVE: {Kind.SAND: 0.15},
	Biome.Kind.GYM: {},
	Biome.Kind.SWAMP: {Kind.RAIN: 0.5},
	Biome.Kind.CITY: {Kind.RAIN: 0.25, Kind.SUN: 0.15},
	Biome.Kind.LAB: {},
	Biome.Kind.VOLCANO: {Kind.SUN: 0.45, Kind.SAND: 0.1},
	Biome.Kind.BEACH: {Kind.SUN: 0.4, Kind.RAIN: 0.15},
	Biome.Kind.CEMETERY: {Kind.RAIN: 0.35},
	Biome.Kind.STUDIO: {},
	Biome.Kind.LIBRARY: {},
	Biome.Kind.AIRPORT: {Kind.SUN: 0.25, Kind.RAIN: 0.2},
	Biome.Kind.UNDERWATER: {},
}
## Los climas provocados por ataques duran estas rondas (una ronda = un turno de cada Pokémon).
const MOVE_ROUNDS := 4


static func roll(biome: Biome.Kind, rng: RandomNumberGenerator) -> Kind:
	var r := rng.randf()
	for kind: int in BIOME_ODDS.get(biome, {}):
		r -= BIOME_ODDS[biome][kind]
		if r < 0.0:
			return kind
	return Kind.CLEAR


## Tipo real del ataque (Meteorobola cambia de tipo).
static func move_type(kind: Kind, move: MoveData) -> String:
	return BALL_TYPES[kind] if move.weather_tag == "weather_ball" else move.type


static func power_mult(kind: Kind, move: MoveData) -> float:
	var mult := 1.0
	var t := move_type(kind, move)
	match kind:
		Kind.SUN:
			mult *= 1.5 if t == "fire" else (0.5 if t == "water" else 1.0)
		Kind.RAIN:
			mult *= 1.5 if t == "water" else (0.5 if t == "fire" else 1.0)
	if move.weather_tag == "weather_ball" and kind != Kind.CLEAR:
		mult *= 2.0
	if move.weather_tag == "solar" and kind in [Kind.RAIN, Kind.SAND, Kind.HAIL]:
		mult *= 0.5
	return mult


## Multiplicador defensivo: Roca con arena (Def. Esp.) e Hielo con granizo (Defensa).
static func defense_mult(kind: Kind, defender_types: PackedStringArray, physical: bool) -> float:
	if kind == Kind.SAND and not physical and "rock" in defender_types:
		return 1.5
	if kind == Kind.HAIL and physical and "ice" in defender_types:
		return 1.5
	return 1.0


## Precisión con el clima: -1 = no falla.
static func accuracy(kind: Kind, move: MoveData) -> int:
	match move.weather_tag:
		"storm":
			if kind == Kind.RAIN:
				return -1
			if kind == Kind.SUN:
				return 50
		"blizzard":
			if kind == Kind.HAIL:
				return -1
	return move.accuracy


static func extra_ct(kind: Kind, move: MoveData) -> int:
	return 0 if move.weather_tag == "solar" and kind == Kind.SUN else move.extra_ct


static func heal_fraction(kind: Kind, move: MoveData) -> float:
	if move.weather_tag != "solar_heal":
		return move.heal
	match kind:
		Kind.SUN: return 2.0 / 3.0
		Kind.CLEAR: return 0.5
	return 0.25


static func self_stages(kind: Kind, move: MoveData) -> Dictionary:
	if move.weather_tag == "growth" and kind == Kind.SUN:
		var doubled := {}
		for key: String in move.self_stat_changes:
			doubled[key] = move.self_stat_changes[key] * 2
		return doubled
	return move.self_stat_changes


## Casillas de movimiento que pierde un Pokémon: con granizo, los de tipo Volador (salvo los de tipo
## Hielo); los que el granizo no afecta por habilidad se comprueban en Unit.move_range.
static func move_penalty(kind: Kind, types: PackedStringArray) -> int:
	if kind == Kind.HAIL and "flying" in types and "ice" not in types:
		return 1
	return 0


## Resumen de efectos del clima (tooltip del indicador de clima en combate).
static func effects_text(kind: Kind) -> String:
	match kind:
		Kind.SUN:
			return "Fuego ×1,5 · Agua ×0,5 · Rayo Solar sin carga · no se puede congelar"
		Kind.RAIN:
			return "Agua ×1,5 · Fuego ×0,5 · Trueno y Vendaval no fallan"
		Kind.SAND:
			return "Daña 1/16 por turno (salvo Roca, Tierra y Acero) · Roca: Def. Esp. ×1,5"
		Kind.HAIL:
			return "Daña 1/16 por turno (salvo Hielo) · Hielo: Defensa ×1,5 · Ventisca no falla\nLos de tipo Volador pierden 1 casilla de movimiento (salvo Hielo)"
	return "Sin efectos"


## Daño al terminar el turno (arena y granizo), como fracción de los PS máximos.
static func chip_fraction(kind: Kind, types: PackedStringArray) -> float:
	if kind == Kind.SAND and not Array(types).any(func(t: String) -> bool: return t in SAND_IMMUNE):
		return 1.0 / 16.0
	if kind == Kind.HAIL and "ice" not in types:
		return 1.0 / 16.0
	return 0.0


static func can_freeze(kind: Kind) -> bool:
	return kind != Kind.SUN


## Texto para la ficha de un ataque, o "" si el clima no le afecta.
static func describe(move: MoveData) -> String:
	if move.sets_weather:
		return "Cambia el clima a %s (%d rondas)" % [NAMES[move.sets_weather], MOVE_ROUNDS]
	match move.weather_tag:
		"weather_ball": return "Con clima: doble potencia y cambia de tipo"
		"storm": return "No falla con lluvia; 50% de precisión con sol"
		"blizzard": return "No falla con granizo"
		"solar": return "Sin carga con sol; mitad de potencia con lluvia, arena o granizo"
		"solar_heal": return "Cura 2/3 con sol y 1/4 con otros climas"
		"growth": return "Con sol, sube el doble"
	return ""

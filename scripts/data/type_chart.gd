class_name TypeChart
extends RefCounted
## Tabla de efectividades. Solo se listan los multiplicadores distintos de 1.

const CHART := {
	"normal": {"rock": 0.5, "ghost": 0.0, "steel": 0.5},
	"fire": {"fire": 0.5, "water": 0.5, "grass": 2.0, "ice": 2.0, "bug": 2.0, "rock": 0.5, "dragon": 0.5, "steel": 2.0},
	"water": {"fire": 2.0, "water": 0.5, "grass": 0.5, "ground": 2.0, "rock": 2.0, "dragon": 0.5},
	"electric": {"water": 2.0, "electric": 0.5, "grass": 0.5, "ground": 0.0, "flying": 2.0, "dragon": 0.5},
	"grass": {"fire": 0.5, "water": 2.0, "grass": 0.5, "poison": 0.5, "ground": 2.0, "flying": 0.5, "bug": 0.5, "rock": 2.0, "dragon": 0.5, "steel": 0.5},
	"ice": {"fire": 0.5, "water": 0.5, "grass": 2.0, "ice": 0.5, "ground": 2.0, "flying": 2.0, "dragon": 2.0, "steel": 0.5},
	"fighting": {"normal": 2.0, "ice": 2.0, "poison": 0.5, "flying": 0.5, "psychic": 0.5, "bug": 0.5, "rock": 2.0, "ghost": 0.0, "dark": 2.0, "steel": 2.0, "fairy": 0.5},
	"poison": {"grass": 2.0, "poison": 0.5, "ground": 0.5, "rock": 0.5, "ghost": 0.5, "steel": 0.0, "fairy": 2.0},
	"ground": {"fire": 2.0, "electric": 2.0, "grass": 0.5, "poison": 2.0, "flying": 0.0, "bug": 0.5, "rock": 2.0, "steel": 2.0},
	"flying": {"electric": 0.5, "grass": 2.0, "fighting": 2.0, "bug": 2.0, "rock": 0.5, "steel": 0.5},
	"psychic": {"fighting": 2.0, "poison": 2.0, "psychic": 0.5, "dark": 0.0, "steel": 0.5},
	"bug": {"fire": 0.5, "grass": 2.0, "fighting": 0.5, "poison": 0.5, "flying": 0.5, "psychic": 2.0, "ghost": 0.5, "dark": 2.0, "steel": 0.5, "fairy": 0.5},
	"rock": {"fire": 2.0, "ice": 2.0, "fighting": 0.5, "ground": 0.5, "flying": 2.0, "bug": 2.0, "steel": 0.5},
	"ghost": {"normal": 0.0, "psychic": 2.0, "ghost": 2.0, "dark": 0.5},
	"dragon": {"dragon": 2.0, "steel": 0.5, "fairy": 0.0},
	"dark": {"fighting": 0.5, "psychic": 2.0, "ghost": 2.0, "dark": 0.5, "fairy": 0.5},
	"steel": {"fire": 0.5, "water": 0.5, "electric": 0.5, "ice": 2.0, "rock": 2.0, "steel": 0.5, "fairy": 2.0},
	"fairy": {"fire": 0.5, "fighting": 2.0, "poison": 0.5, "dragon": 2.0, "dark": 2.0, "steel": 0.5},
}


const TYPES: PackedStringArray = [
	"normal", "fire", "water", "electric", "grass", "ice", "fighting", "poison", "ground",
	"flying", "psychic", "bug", "rock", "ghost", "dragon", "dark", "steel", "fairy",
]
const COLORS := {
	"normal": Color("a8a77a"), "fire": Color("ee8130"), "water": Color("6390f0"), "electric": Color("f7d02c"),
	"grass": Color("7ac74c"), "ice": Color("96d9d6"), "fighting": Color("c22e28"), "poison": Color("a33ea1"),
	"ground": Color("e2bf65"), "flying": Color("a98ff3"), "psychic": Color("f95587"), "bug": Color("a6b91a"),
	"rock": Color("b6a136"), "ghost": Color("735797"), "dragon": Color("6f35fc"), "dark": Color("705746"),
	"steel": Color("b7b7ce"), "fairy": Color("d685ad"),
}


static func color(type: String) -> Color:
	return COLORS.get(type, Color.GRAY)


## Multiplicador que recibe un Pokémon de `defender_types` por cada tipo atacante.
static func defensive_profile(defender_types: PackedStringArray) -> Dictionary:
	var result := {}
	for t in TYPES:
		result[t] = effectiveness(t, defender_types)
	return result


static func effectiveness(attack_type: String, defender_types: PackedStringArray) -> float:
	var mult := 1.0
	var row: Dictionary = CHART.get(attack_type, {})
	for t in defender_types:
		mult *= row.get(t, 1.0)
	return mult

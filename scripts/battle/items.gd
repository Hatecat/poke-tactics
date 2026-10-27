class_name Items
extends RefCounted
## Objetos: catálogo (data/items) y sus efectos pasivos en el combate. Los que se consumen o
## reaccionan a algo (bayas, Banda Focus, Casco Dentado...) los gestiona Effects.

const ITEMS_DIR := "res://data/items/"

static var _all: Array[ItemData] = []


static func all() -> Array[ItemData]:
	if _all.is_empty():
		for file in DirAccess.get_files_at(ITEMS_DIR):
			file = file.trim_suffix(".remap")
			if file.ends_with(".tres"):
				_all.append(load(ITEMS_DIR + file))
		_all.sort_custom(func(a: ItemData, b: ItemData) -> bool:
			return a.category < b.category or (a.category == b.category and TranslationServer.translate(a.display_name) < TranslationServer.translate(b.display_name)))
	return _all


static func find(id: String) -> ItemData:
	if id == "":
		return null
	for it in all():
		if it.id == id:
			return it
	return null


## Objetos que se pueden equipar (bayas y equipables; las piedras se usan, no se llevan).
static func holdable() -> Array[ItemData]:
	return all().filter(func(it: ItemData) -> bool: return it.category != ItemData.Category.STONE)


static func effect(u: Unit) -> String:
	return u.item.effect if u and u.item else ""


static func param(u: Unit, key: String, default = null):
	return u.item.params.get(key, default) if u and u.item else default


# --- Modificadores pasivos -----------------------------------------------------------

## Daño del atacante: Vidasfera, Elección, potenciadores de tipo, Cinta Experto, Cinta Fuerte...
static func attack_mult(att: Unit, move: MoveData, type: String, physical: bool, eff: float) -> float:
	match effect(att):
		"life_orb":
			return param(att, "boost", 1.3)
		"choice":
			var stat: String = param(att, "stat", "")
			if (stat == "attack" and physical) or (stat == "sp_attack" and not physical):
				return 1.5
		"type_boost":
			if param(att, "type", "") == type:
				return param(att, "boost", 1.2)
		"expert_belt":
			if eff > 1.0:
				return param(att, "boost", 1.2)
		"category_boost":
			if param(att, "category", -1) == move.category:
				return param(att, "boost", 1.1)
	return 1.0


## Daño recibido: Mineral Evolutivo (si aún puede evolucionar) y Chaleco Asalto (especial).
static func defense_mult(def: Unit, physical: bool) -> float:
	match effect(def):
		"eviolite":
			if not def.data.evolves_to.is_empty() or not def.data.stone_evolutions.is_empty():
				return 1.0 / 1.5
		"assault_vest":
			if not physical:
				return 1.0 / 1.5
	return 1.0


static func speed_mult(u: Unit) -> float:
	return 1.5 if effect(u) == "choice" and param(u, "stat", "") == "speed" else 1.0


static func crit_bonus(u: Unit) -> int:
	return param(u, "stages", 0) if effect(u) == "crit" else 0


static func accuracy_mult(att: Unit, def: Unit) -> float:
	var m := 1.0
	if effect(att) == "accuracy":
		m *= param(att, "mult", 1.1)
	if effect(def) == "evasion":
		m *= param(def, "mult", 0.9)
	return m


static func flinch_bonus(att: Unit) -> int:
	return param(att, "chance", 0) if effect(att) == "flinch" else 0


static func floats(u: Unit) -> bool:
	return effect(u) == "air_balloon"


static func ignores_traps(u: Unit) -> bool:
	return effect(u) == "boots"


## Rondas extra de clima (rocas) o de pantallas (Refleluz).
static func weather_rounds(u: Unit, kind: int, base: int) -> int:
	return 8 if effect(u) == "weather_rock" and param(u, "weather", 0) == kind else base


static func zone_rounds(u: Unit, base: int) -> int:
	return param(u, "rounds", base) if effect(u) == "light_clay" else base

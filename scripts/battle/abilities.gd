class_name Abilities
extends RefCounted
## Habilidades: nombres y textos (data/abilities.json) y sus efectos en el combate.
## Cada función es un "enganche" que la batalla o Combat consultan en el momento justo.

const DATA_PATH := "res://data/abilities.json"
## Habilidades con efecto en el tablero. El resto se muestran como "sin efecto (todavía)".
const IMPLEMENTED: PackedStringArray = [
	"adaptability", "aftermath", "angerpoint", "battlearmor", "bigpecks", "blaze", "chlorophyll",
	"clearbody", "cloudnine", "competitive", "compoundeyes", "damp", "defiant", "download", "drought",
	"dryskin", "earlybird", "effectspore", "filter", "flamebody", "flashfire", "friendguard", "guts",
	"healer", "hustle", "hydration", "hypercutter", "icebody", "immunity", "infiltrator", "innerfocus",
	"insomnia", "intimidate", "ironfist", "justified", "keeneye", "leafguard", "levitate", "lightningrod",
	"limber", "liquidooze", "magicguard", "magmaarmor", "marvelscale", "moldbreaker", "moxie",
	"multiscale", "naturalcure", "noguard", "oblivious", "overcoat", "overgrow", "owntempo",
	"poisonpoint", "poisontouch", "pressure", "quickfeet", "raindish", "rattled", "reckless",
	"rockhead", "sandforce", "sandrush", "sandveil", "scrappy", "serenegrace", "shedskin", "sheerforce",
	"shellarmor", "shielddust", "skilllink", "sniper", "snowcloak", "solarpower", "soundproof",
	"static", "steadfast", "stench", "sturdy", "superluck", "swarm", "swiftswim", "synchronize",
	"tangledfeet", "technician", "thickfat", "tintedlens", "torrent", "unaware", "vitalspirit",
	"voltabsorb", "waterabsorb", "waterveil", "weakarmor", "wonderskin",
]
const PINCH := {"blaze": "fire", "torrent": "water", "overgrow": "grass", "swarm": "bug"}

static var _info := {}


static func _load() -> void:
	if not _info.is_empty():
		return
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f:
		_info = JSON.parse_string(f.get_as_text())


static func display_name(id: String) -> String:
	_load()
	return _info.get(id, {}).get("name", id.capitalize()) if id else "—"


static func describe(id: String) -> String:
	_load()
	var text: String = _info.get(id, {}).get("desc", "")
	return text if id in IMPLEMENTED else text + " [Sin efecto en el tablero (todavía).]"


static func has(u: Unit, id: String) -> bool:
	return u != null and u.ability == id


## La habilidad del defensor se ignora si el atacante tiene Rompemoldes.
static func defender_has(att: Unit, def: Unit, id: String) -> bool:
	return has(def, id) and not has(att, "moldbreaker")


# --- Daño ------------------------------------------------------------------------

## Multiplicador de daño por la habilidad del atacante.
static func attack_mult(att: Unit, move: MoveData, type: String, physical: bool, crit: bool, weather: int) -> float:
	var m := 1.0
	var a := att.ability
	if PINCH.has(a) and PINCH[a] == type and att.hp * 3 <= att.max_hp:
		m *= 1.5
	match a:
		"guts":
			if physical and att.status != MoveData.Status.NONE:
				m *= 1.5
		"hustle":
			if physical:
				m *= 1.5
		"technician":
			if move.power <= 60:
				m *= 1.5
		"ironfist":
			if "punch" in move.flags:
				m *= 1.2
		"reckless":
			if move.recoil > 0.0:
				m *= 1.2
		"sheerforce":
			if "secondary" in move.flags:
				m *= 1.3
		"sandforce":
			if weather == Weather.Kind.SAND and type in ["rock", "ground", "steel"]:
				m *= 1.3
		"solarpower":
			if weather == Weather.Kind.SUN and not physical:
				m *= 1.5
		"sniper":
			if crit:
				m *= 1.5
		"skilllink":
			if "multihit" in move.flags:
				m *= 5.0 / 3.0
	if type == "fire" and att.volatiles.has("flashfire"):
		m *= 1.5
	if type == "electric" and att.volatiles.has("charge"):
		m *= 2.0
	return m


## Multiplicador de daño por la habilidad del defensor (`eff` = efectividad de tipos).
static func defense_mult(att: Unit, def: Unit, type: String, physical: bool, eff: float) -> float:
	if has(att, "moldbreaker"):
		return 1.0
	var m := 1.0
	match def.ability:
		"thickfat":
			if type in ["fire", "ice"]:
				m *= 0.5
		"multiscale":
			if def.hp >= def.max_hp:
				m *= 0.5
		"marvelscale":
			if physical and def.status != MoveData.Status.NONE:
				m /= 1.5
		"filter":
			if eff > 1.0:
				m *= 0.75
		"dryskin":
			if type == "fire":
				m *= 1.25
	return m


static func stab(att: Unit) -> float:
	return 2.0 if has(att, "adaptability") else 1.5


## Efectividad tras habilidades: Cromolente dobla lo "poco eficaz"; Intrépido golpea a Fantasma.
static func effectiveness(att: Unit, type: String, def_types: PackedStringArray) -> float:
	var types := def_types
	if has(att, "scrappy") and type in ["normal", "fighting"] and "ghost" in def_types:
		types = PackedStringArray(Array(def_types).filter(func(t: String) -> bool: return t != "ghost"))
	var eff := TypeChart.effectiveness(type, types)
	if has(att, "tintedlens") and eff > 0.0 and eff < 1.0:
		eff *= 2.0
	return eff


## Inmunidades por habilidad. Devuelve "" (sin efecto) o lo que ocurre:
## "immune", "heal" (cura 1/4), "flashfire", "spa_up" (Pararrayos).
static func absorb(att: Unit, def: Unit, move: MoveData, type: String) -> String:
	if has(att, "moldbreaker") or att == def:
		return ""
	match def.ability:
		"levitate":
			if type == "ground" and move.category != MoveData.Category.STATUS:
				return "immune"
		"flashfire":
			if type == "fire":
				return "flashfire"
		"waterabsorb", "dryskin":
			if type == "water":
				return "heal"
		"voltabsorb":
			if type == "electric":
				return "heal"
		"lightningrod":
			if type == "electric":
				return "spa_up"
		"soundproof":
			if "sound" in move.flags:
				return "immune"
		"overcoat":
			if "powder" in move.flags:
				return "immune"
	return ""


# --- Precisión, crítico y velocidad ---------------------------------------------

static func always_hits(att: Unit, def: Unit) -> bool:
	return has(att, "noguard") or has(def, "noguard")


static func accuracy_mult(att: Unit, def: Unit, move: MoveData, weather: int) -> float:
	var m := 1.0
	if has(att, "compoundeyes"):
		m *= 1.3
	if has(att, "hustle") and move.category == MoveData.Category.PHYSICAL:
		m *= 0.8
	if defender_has(att, def, "sandveil") and weather == Weather.Kind.SAND:
		m *= 0.8
	if defender_has(att, def, "snowcloak") and weather == Weather.Kind.HAIL:
		m *= 0.8
	if defender_has(att, def, "tangledfeet") and def.volatiles.has("confusion"):
		m *= 0.5
	if defender_has(att, def, "wonderskin") and move.category == MoveData.Category.STATUS:
		m = minf(m, 50.0 / maxf(move.accuracy, 1.0))
	return m


static func crit_bonus(att: Unit) -> int:
	return 1 if has(att, "superluck") else 0


static func blocks_crit(att: Unit, def: Unit) -> bool:
	return defender_has(att, def, "battlearmor") or defender_has(att, def, "shellarmor")


static func speed_mult(u: Unit, weather: int) -> float:
	match u.ability:
		"swiftswim":
			return 2.0 if weather == Weather.Kind.RAIN else 1.0
		"chlorophyll":
			return 2.0 if weather == Weather.Kind.SUN else 1.0
		"sandrush":
			return 2.0 if weather == Weather.Kind.SAND else 1.0
		"quickfeet":
			return 1.5 if u.status != MoveData.Status.NONE else 1.0
	return 1.0


# --- Estados y stats --------------------------------------------------------------

static func blocks_status(att: Unit, def: Unit, status: int, weather: int) -> bool:
	var ability := "" if has(att, "moldbreaker") else def.ability
	match ability:
		"limber": return status == MoveData.Status.PARALYSIS
		"insomnia", "vitalspirit": return status == MoveData.Status.SLEEP
		"immunity": return status == MoveData.Status.POISON
		"waterveil": return status == MoveData.Status.BURN
		"magmaarmor": return status == MoveData.Status.FREEZE
		"leafguard": return weather == Weather.Kind.SUN
	return false


static func blocks_volatile(att: Unit, def: Unit, volatile: String) -> bool:
	if has(att, "moldbreaker"):
		return false
	return (volatile == "confusion" and def.ability == "owntempo") \
		or (volatile == "taunt" and def.ability == "oblivious") \
		or (volatile == "flinch" and def.ability == "innerfocus")


## ¿La habilidad impide que un rival le baje este stat?
static func blocks_drop(att: Unit, def: Unit, stat: String) -> bool:
	if has(att, "moldbreaker"):
		return false
	match def.ability:
		"clearbody": return true
		"keeneye": return stat == "accuracy"
		"hypercutter": return stat == "attack"
		"bigpecks": return stat == "defense"
	return false


## Tras sufrir una bajada de stats de un rival: Competitivo / Tenacidad.
static func on_stat_dropped(u: Unit) -> Dictionary:
	match u.ability:
		"defiant": return {"attack": 2}
		"competitive": return {"sp_attack": 2}
	return {}


## Daño indirecto (veneno, clima, Drenadoras, retroceso, trampas): Muro Mágico lo anula.
static func takes_indirect(u: Unit) -> bool:
	return not has(u, "magicguard")


static func weather_immune(u: Unit, weather: int) -> bool:
	match u.ability:
		"overcoat", "magicguard": return true
		"sandveil", "sandrush", "sandforce": return weather == Weather.Kind.SAND
		"icebody", "snowcloak": return weather == Weather.Kind.HAIL
	return false


## Probabilidad de efecto secundario con Dicha (Serene Grace) y Polvo Escudo / Potencia Bruta.
static func secondary_chance(att: Unit, def: Unit, chance: int) -> int:
	if has(att, "sheerforce") or defender_has(att, def, "shielddust"):
		return 0
	return mini(100, chance * 2) if has(att, "serenegrace") else chance


## Estado que provoca una habilidad al recibir (o dar) un golpe de contacto, o NONE.
static func contact_status(holder: Unit, rng: RandomNumberGenerator) -> int:
	if rng.randf() >= 0.3:
		return MoveData.Status.NONE
	match holder.ability:
		"static": return MoveData.Status.PARALYSIS
		"poisonpoint", "poisontouch": return MoveData.Status.POISON
		"flamebody": return MoveData.Status.BURN
		"effectspore": return [MoveData.Status.POISON, MoveData.Status.PARALYSIS, MoveData.Status.SLEEP][rng.randi_range(0, 2)]
	return MoveData.Status.NONE


## Mejoras al recibir un golpe (Armadura Frágil, Justiciero, Cobardía).
static func on_hit(def: Unit, physical: bool, type: String) -> Dictionary:
	match def.ability:
		"weakarmor":
			if physical:
				return {"defense": -1, "speed": 2}
		"justified":
			if type == "dark":
				return {"attack": 1}
		"rattled":
			if type in ["bug", "dark", "ghost"]:
				return {"speed": 1}
	return {}


## Daño o curación al empezar el turno según el clima (fracción de PS; negativo = daño).
static func weather_hp(u: Unit, weather: int) -> float:
	match u.ability:
		"raindish": return 1.0 / 16.0 if weather == Weather.Kind.RAIN else 0.0
		"icebody": return 1.0 / 16.0 if weather == Weather.Kind.HAIL else 0.0
		"dryskin":
			if weather == Weather.Kind.RAIN:
				return 1.0 / 8.0
			if weather == Weather.Kind.SUN:
				return -1.0 / 8.0
		"solarpower": return -1.0 / 8.0 if weather == Weather.Kind.SUN else 0.0
	return 0.0

class_name Effects
extends RefCounted
## Estados volátiles, efectos de campo y habilidades durante la batalla.
## La batalla lo llama en momentos concretos (inicio de turno, al recibir un ataque, al moverse...)
## y este módulo usa sus utilidades (_log, _popup, _heal...) para mostrar lo que ocurre.

const CONFUSION_SELF_HIT := 1.0 / 3.0
const CONFUSION_POWER := 40.0
const VOLATILE_TURNS := {"confusion": [2, 5], "taunt": [3, 3], "magnetrise": [5, 5], "perish": [3, 3]}
const INTIMIDATE_RANGE := 2
const HEALER_CHANCE := 0.3
const SHED_SKIN_CHANCE := 0.3
const ATTRACT_TURNS := 5
## Turnos propios que dura Constricción o un remolino (Giro Fuego, Torbellino...).
const BIND_TURNS := 2
## Pausas al comerse una baya: tras el golpe, entre el nombre de la baya y su efecto, y al terminar.
const BERRY_DELAYS: Array[float] = [0.45, 0.6, 0.4]

# --- Tablero ---
## Daño por cada nivel de altura a favor (+) o en contra (-), con topes.
const HEIGHT_STEP := 0.1
const HEIGHT_MAX := 0.3
const HEIGHT_MIN := -0.2
## Frente, lado, espalda: multiplicador de daño y de precisión.
const FLANK_DAMAGE: Array[float] = [1.0, 1.1, 1.25]
const FLANK_ACCURACY: Array[float] = [1.0, 1.1, 1.25]
const FLANK_NAMES := ["de frente", "por el flanco", "por la espalda"]
## Atacar desde una casilla afín potencia ese tipo.
const TILE_AFFINITY := {
	Biome.Tile.GRASS: "grass", Biome.Tile.WATER: "water", Biome.Tile.SAND: "ground", Biome.Tile.DIRT: "ground",
	Biome.Tile.ROCK: "rock", Biome.Tile.CAVE: "rock", Biome.Tile.SNOW: "ice", Biome.Tile.ICE: "ice",
}
const AFFINITY_MULT := 1.2
const WATER_FIRE_MULT := 0.8
const SAND_EVASION := 0.85
const SAND_DWELLERS: PackedStringArray = ["ground", "rock", "steel"]

var b # la batalla (scripts/battle/battle.gd)
var field := FieldState.new()
## Pokémon cuya baya debe activarse: se la comen en la siguiente pausa (eat_pending), así se ve antes el golpe.
var _pending_berries: Array[Unit] = []


func _init(battle) -> void:
	b = battle
	Combat.field = field


func _alive_count() -> int:
	return maxi(1, b.units.filter(func(u: Unit) -> bool: return u.is_alive()).size())


# --- Clima efectivo (Aclimatación anula el clima) ---------------------------------

func effective_weather(kind: int) -> int:
	for u: Unit in b.units:
		if u.is_alive() and u.ability == "cloudnine":
			return Weather.Kind.CLEAR
	return kind


# --- Modificadores situacionales de daño --------------------------------------------

## Pantallas, terreno, altura, flanqueo, casilla y Compiescolta: dependen de dónde está cada uno.
func situational(att: Unit, def: Unit, move: MoveData, crit: bool) -> float:
	var m := 1.0
	var physical := move.category == MoveData.Category.PHYSICAL
	var type := Combat.move_type(move)
	if att != def:
		m *= 1.0 + clampf(height_diff(att, def) * HEIGHT_STEP, HEIGHT_MIN, HEIGHT_MAX)
		m *= FLANK_DAMAGE[flank(att, def)]
	var tile: int = b.grid.tiles.get(att.cell, -1)
	if TILE_AFFINITY.get(tile, "") == type:
		m *= AFFINITY_MULT
	if tile == Biome.Tile.WATER and type == "fire":
		m *= WATER_FIRE_MULT
	if Abilities.has(att, "rivalry") and att.gender != 0 and def.gender != 0:
		m *= 1.25 if att.gender == def.gender else 0.75
	if not crit and not Abilities.has(att, "infiltrator") and att.team != def.team:
		var screen := "reflect" if physical else "lightscreen"
		if field.zone_at(screen, def.team, def.footprint) or field.zone_at("auroraveil", def.team, def.footprint):
			m *= 0.5
	if field.terrain:
		if _terrain_boosts(type) and field.grounded(att):
			m *= 1.3
		if field.terrain == "mistyterrain" and type == "dragon" and field.grounded(def):
			m *= 0.5
		if field.terrain == "grassyterrain" and move.id in ["earthquake", "bulldoze", "magnitude"] and field.grounded(def):
			m *= 0.5
	for ally: Unit in b.units:
		if ally != def and ally.team == def.team and ally.is_alive() and ally.ability == "friendguard" \
				and b.grid.distance_to_set(ally.footprint, def.cell) <= 1:
			m *= 0.75
			break
	return m


## Niveles de altura del atacante sobre el defensor (negativo si está más bajo).
func height_diff(att: Unit, def: Unit) -> int:
	return b.grid.footprint_height(att.footprint) - b.grid.footprint_height(def.footprint)


## 0 = de frente, 1 = por el flanco, 2 = por la espalda (según hacia dónde mira el defensor).
func flank(att: Unit, def: Unit) -> int:
	var d := Vector2(att.position.x - def.position.x, att.position.z - def.position.z)
	if d.length() < 0.01:
		return 0
	var dot := d.normalized().dot(def.facing)
	return 0 if dot > 0.5 else (2 if dot < -0.5 else 1)


## Precisión según la posición: flanqueo, atacar hacia arriba y Pokémon de tierra en la arena.
func accuracy_mult(att: Unit, def: Unit) -> float:
	if att == def:
		return 1.0
	var m := FLANK_ACCURACY[flank(att, def)]
	if height_diff(att, def) <= -2:
		m *= 0.9
	if b.grid.tiles.get(def.cell, -1) == Biome.Tile.SAND and Array(def.data.types).any(func(t: String) -> bool: return t in SAND_DWELLERS):
		m *= SAND_EVASION
	return m


## Roca, Acero y Tierra no pueden pisar el agua (salvo si también son Agua/Volador o flotan).
func water_blocked(u: Unit) -> bool:
	var types := Array(u.data.types)
	if "water" in types or not field.grounded(u):
		return false
	return types.any(func(t: String) -> bool: return t in ["rock", "steel", "ground"])


## ¿Se mueve por el agua sin coste extra?
func swims(u: Unit) -> bool:
	return "water" in u.data.types or not field.grounded(u)


## Texto con lo que hace una casilla (para la información al pasar el ratón).
func tile_info(c: Vector2i) -> String:
	var tile: int = b.grid.tiles.get(c, Biome.Tile.GRASS)
	var parts := PackedStringArray(["%s · altura %d" % [Biome.TILE_NAMES[tile], b.grid.get_height(c)]])
	if TILE_AFFINITY.has(tile):
		parts.append("%s ×1,2 desde aquí" % Combat.TYPE_NAMES[TILE_AFFINITY[tile]])
	match tile:
		Biome.Tile.WATER:
			parts.append("cuesta el doble (no a voladores) · tipo Agua nada al doble y sin penalización por peso · Roca/Acero/Tierra no pueden entrar · Fuego ×0,8")
		Biome.Tile.SAND:
			parts.append("Tierra/Roca/Acero esquivan más")
		Biome.Tile.ICE:
			parts.append("los empujones deslizan 1 casilla más")
	var trap: Dictionary = field.traps.get(c, {})
	if not trap.is_empty():
		var t := PackedStringArray()
		if trap.spikes:
			t.append("Púas x%d" % trap.spikes)
		if trap.toxic:
			t.append("Púas Tóxicas")
		if trap.rocks:
			t.append("Trampa Rocas")
		parts.append("[color=#ffaa66]%s (%s)[/color]" % [", ".join(t), "tuyas" if trap.team == 0 else "rivales"])
	if b.grid.is_blocked(c):
		parts.append("obstáculo")
	return " · ".join(parts)


func _terrain_boosts(type: String) -> bool:
	return FieldState.TERRAIN_TYPES.get(field.terrain, "") == type


# --- Inicio de turno -------------------------------------------------------------

## Volátiles y habilidades al empezar el turno de `u`: lo que decide si puede actuar.
## El daño y la curación residuales van en end_of_turn. Devuelve false si pierde el turno.
func start_of_turn(u: Unit) -> bool:
	check_binds()
	for key in ["protect", "endure", "destinybond"]:
		u.volatiles.erase(key)
	if not u.volatiles.has("protect_used"):
		u.protect_streak = 0
	u.volatiles.erase("protect_used")

	await _abilities_start(u)
	if not u.is_alive():
		return false

	# Atracción: 50 % de no poder atacar este turno (sí puede moverse).
	if u.volatiles.has("attract"):
		var by: Unit = u.volatiles.attract.by
		u.volatiles.attract.turns -= 1
		if by == null or not by.is_alive() or u.volatiles.attract.turns <= 0:
			u.volatiles.erase("attract")
			b._log("%s ya no está enamorado." % u.display_name())
		else:
			u.volatiles.attract.blocked = b.rng.randf() < 0.5
			if u.volatiles.attract.blocked:
				b._popup(u, "♥", Color(1.0, 0.5, 0.7))
				b._log("¡%s está enamorado de %s y no puede atacar!" % [u.display_name(), by.display_name()])

	# Contadores.
	if u.volatiles.has("perish"):
		u.volatiles.perish.turns -= 1
		if u.volatiles.perish.turns <= 0:
			b._log("¡%s cayó por el Canto Mortal!" % u.display_name())
			u.take_damage(u.hp)
			return false
	for key in ["taunt", "magnetrise"]:
		if u.volatiles.has(key):
			u.volatiles[key].turns -= 1
			if u.volatiles[key].turns <= 0:
				u.volatiles.erase(key)
				b._log("%s: %s terminó." % [u.display_name(), Unit.VOLATILE_SHORT[key]])
	if u.volatiles.has("yawn"):
		u.volatiles.yawn.turns -= 1
		if u.volatiles.yawn.turns <= 0:
			u.volatiles.erase("yawn")
			if can_status(null, u, MoveData.Status.SLEEP) == "":
				set_status(null, u, MoveData.Status.SLEEP)
				u.refresh_label()
				return false
	u.refresh_label()

	# Confusión: puede herirse a sí mismo y perder el turno.
	if u.volatiles.has("confusion"):
		u.volatiles.confusion.turns -= 1
		if u.volatiles.confusion.turns <= 0:
			u.volatiles.erase("confusion")
			b._log("%s ya no está confuso." % u.display_name())
			u.refresh_label()
		elif b.rng.randf() < CONFUSION_SELF_HIT:
			# Golpe físico sin tipo de potencia 40 contra sí mismo, con la fórmula de daño normal (según su nivel).
			var dmg := maxi(1, int((2.0 * u.level / 5.0 + 2.0) * CONFUSION_POWER * u.stat("attack") / u.stat("defense") / 50.0 + 2.0))
			b._popup(u, "?!", Color(1.0, 0.8, 1.0))
			_hurt(u, dmg, "¡%s está tan confuso que se hirió a sí mismo!" % u.display_name(), Color(1.0, 0.7, 0.9))
			await b._wait(0.5)
			return false
	return true


# --- Fin de turno ------------------------------------------------------------------

## Daño y curación residuales de `u` después de actuar (como en los juegos: primero se
## actúa y luego pasan factura el veneno, el clima, Drenadoras...). Ver también
## battle._end_of_turn, que añade el clima y los estados.
func end_of_turn(u: Unit) -> void:
	await _abilities_end(u)
	if not u.is_alive():
		return
	await _items_end(u)
	if not u.is_alive():
		return

	# Daño y curación por volátiles.
	if u.volatiles.has("leechseed") and Abilities.takes_indirect(u):
		var seeder: Unit = u.volatiles.leechseed.by
		var dmg := maxi(1, u.max_hp / 8)
		_hurt(u, dmg, "Drenadoras le roba PS a %s." % u.display_name(), Color(0.5, 0.9, 0.4))
		if seeder and seeder.is_alive():
			if Abilities.has(u, "liquidooze"):
				_hurt(seeder, dmg, "¡%s absorbió Viscosecreción!" % seeder.display_name(), Color(0.7, 0.4, 0.9))
			else:
				b._heal(seeder, dmg)
		await b._wait(0.35)
	if u.is_alive() and u.volatiles.has("curse") and Abilities.takes_indirect(u):
		_hurt(u, maxi(1, u.max_hp / 4), "La maldición daña a %s." % u.display_name(), Color(0.5, 0.3, 0.6))
		await b._wait(0.35)
	if u.is_alive() and u.volatiles.has("nightmare"):
		if u.status == MoveData.Status.SLEEP and Abilities.takes_indirect(u):
			_hurt(u, maxi(1, u.max_hp / 4), "%s tiene una pesadilla." % u.display_name(), Color(0.4, 0.3, 0.5))
			await b._wait(0.35)
		elif u.status != MoveData.Status.SLEEP:
			u.volatiles.erase("nightmare")
	# Atrapado (Constricción...) o en un remolino (Giro Fuego...): pierde 1/8 por turno mientras dure.
	for key in ["wrapped", "vortex"]:
		if u.is_alive() and u.volatiles.has(key):
			if u.volatiles[key].turns <= 0:
				release_bind(u, key)
			else:
				u.volatiles[key].turns -= 1
				if Abilities.takes_indirect(u):
					var text := "%s sufre dentro del remolino." if key == "vortex" else "%s sufre al estar atrapado."
					_hurt(u, maxi(1, u.max_hp / 8), text % u.display_name(), Color(0.9, 0.6, 0.4))
					await b._wait(0.35)
	for key in ["ingrain", "aquaring"]:
		if u.is_alive() and u.volatiles.has(key):
			b._heal(u, maxi(1, u.max_hp / 16))
	if u.is_alive() and field.terrain == "grassyterrain" and field.grounded(u):
		b._heal(u, maxi(1, u.max_hp / 16))


## Habilidades que se activan al empezar el turno (las de entrada: Sequía, Intimidación...).
func _abilities_start(u: Unit) -> void:
	# Clima por habilidad (Sequía) en su primer turno.
	if u.ability == "drought" and not u.volatiles.has("ability_used"):
		u.volatiles["ability_used"] = {}
		b._set_weather(Weather.Kind.SUN, Weather.MOVE_ROUNDS * _alive_count())
		b._log("¡La Sequía de %s intensificó el sol!" % u.display_name())
	if u.ability == "download" and not u.volatiles.has("ability_used"):
		u.volatiles["ability_used"] = {}
		var foe := _nearest_foe(u)
		if foe:
			var key := "attack" if foe.stat("defense") < foe.stat("sp_defense") else "sp_attack"
			_boost(u, {key: 1}, "Descarga")
	if u.ability == "imposter" and not u.volatiles.has("ability_used") and not u.is_transformed():
		u.volatiles["ability_used"] = {}
		var foe := _nearest_foe(u)
		if foe:
			b._log("¡Impostor de %s!" % u.display_name())
			await b._transform(u, foe)
	if u.ability == "intimidate":
		for foe: Unit in b.units:
			if foe.team != u.team and foe.is_alive() and not u.intimidated.has(foe) \
					and b.grid.distance_to_set(u.footprint, foe.cell) <= INTIMIDATE_RANGE + foe.data.size - 1:
				u.intimidated[foe] = true
				b._log("¡%s intimida a %s!" % [u.display_name(), foe.display_name()])
				drop_stats(u, foe, {"attack": -1})


## Habilidades de fin de turno: curan estados (Mudar, Hidratación) o dañan/curan con el clima.
func _abilities_end(u: Unit) -> void:
	var weather: int = Combat.weather
	# Curar estados.
	if u.status != MoveData.Status.NONE:
		var cure: bool = (u.ability in ["shedskin", "naturalcure"] and b.rng.randf() < SHED_SKIN_CHANCE) \
			or (u.ability == "hydration" and weather == Weather.Kind.RAIN)
		if cure:
			b._log("¡%s se curó gracias a %s!" % [u.display_name(), Abilities.display_name(u.ability)])
			u.status = MoveData.Status.NONE
			u.refresh_label()
	if u.ability == "healer":
		for ally: Unit in b.units:
			if ally != u and ally.team == u.team and ally.is_alive() and ally.status != MoveData.Status.NONE \
					and b.grid.distance_to_set(u.footprint, ally.cell) <= 1 and b.rng.randf() < HEALER_CHANCE:
				ally.status = MoveData.Status.NONE
				ally.refresh_label()
				b._log("¡%s curó a %s!" % [u.display_name(), ally.display_name()])
	var hp_frac := Abilities.weather_hp(u, weather)
	if hp_frac > 0.0:
		b._heal(u, maxi(1, int(u.max_hp * hp_frac)))
	elif hp_frac < 0.0 and Abilities.takes_indirect(u):
		_hurt(u, maxi(1, int(u.max_hp * -hp_frac)), "%s sufre por %s." % [u.display_name(), Abilities.display_name(u.ability)], Color(1.0, 0.7, 0.3))
		await b._wait(0.3)


## Objetos de fin de turno (Restos, Lodo Negro, esferas de estado) y Cosecha.
func _items_end(u: Unit) -> void:
	match Items.effect(u):
		"leftovers":
			if u.hp < u.max_hp:
				b._log("Los Restos curan a %s." % u.display_name())
				b._heal(u, maxi(1, u.max_hp / 16))
		"black_sludge":
			if "poison" in u.data.types:
				if u.hp < u.max_hp:
					b._heal(u, maxi(1, u.max_hp / 16))
			elif Abilities.takes_indirect(u):
				_hurt(u, maxi(1, u.max_hp / 8), "El Lodo Negro daña a %s." % u.display_name(), Color(0.4, 0.3, 0.4))
				await b._wait(0.3)
		"status_orb":
			var st: int = MoveData.Status.POISON if Items.param(u, "status") == "psn" else MoveData.Status.BURN
			if u.status == MoveData.Status.NONE and can_status(null, u, st) == "":
				b._log("¡%s se activó!" % u.item.display_name)
				set_status(null, u, st)
	# Cosecha: recupera la baya que se comió (siempre con sol, 50 % si no).
	if u.ability == "harvest" and u.item == null and u.consumed_item and u.consumed_item.category == ItemData.Category.BERRY \
			and (Combat.weather == Weather.Kind.SUN or b.rng.randf() < 0.5):
		u.item = u.consumed_item
		u.consumed_item = null
		b._log("¡%s recogió una %s gracias a Cosecha!" % [u.display_name(), u.item.display_name])
	check_berries(u)
	await eat_pending()


# --- Bayas y objetos que reaccionan ---------------------------------------------------

## ¿Puede comerse su baya? (Nerviosismo de un rival a 3 casillas o menos lo impide).
func can_eat(u: Unit) -> bool:
	if u.item == null or u.item.category != ItemData.Category.BERRY:
		return false
	for foe: Unit in b.units:
		if foe.team != u.team and foe.is_alive() and foe.ability == "unnerve" and b.grid.distance_to_set(foe.footprint, u.cell) <= 3:
			return false
	return true


## Comprueba si su baya debe activarse (PS bajos, estados, sin PP) y la deja en cola: se la come en la
## siguiente pausa del combate (eat_pending).
func check_berries(u: Unit) -> void:
	if berry_ready(u) and u not in _pending_berries:
		_pending_berries.append(u)


func berry_ready(u: Unit) -> bool:
	if not u.is_alive() or not can_eat(u):
		return false
	var it := u.item
	match it.effect:
		"heal_flat", "heal_frac":
			return u.hp <= u.max_hp * it.params.get("threshold", 0.5) and u.hp < u.max_hp
		"cure":
			var which: String = it.params.status
			var has_status: bool = u.status != MoveData.Status.NONE and (which == "all" or STATUS_CODES.get(which, -1) == u.status)
			return has_status or (u.volatiles.has("confusion") and which in ["all", "confusion"])
		"pinch":
			return u.hp <= u.max_hp * (0.5 if u.ability == "gluttony" else 0.25)
		"pp":
			return u.moves.any(func(mv: MoveData) -> bool: return u.pp.get(mv, 1) <= 0)
	return false


## Se comen las bayas en cola, de una en una y con pausas: golpe, nombre de la baya, efecto.
func eat_pending() -> void:
	while not _pending_berries.is_empty():
		var u: Unit = _pending_berries.pop_front()
		if not berry_ready(u):
			continue
		await b._wait(BERRY_DELAYS[0])
		var it := u.item
		_eat(u)
		await b._wait(BERRY_DELAYS[1])
		_berry_effect(u, it)
		await b._wait(BERRY_DELAYS[2])


## Se come la baya al momento, sin pausas (Picadura, Ladrón...).
func apply_berry(u: Unit) -> void:
	var it := u.item
	_eat(u)
	_berry_effect(u, it)


func _berry_effect(u: Unit, it: ItemData) -> void:
	match it.effect:
		"heal_flat", "heal_frac":
			var amount: int = it.params.amount if it.effect == "heal_flat" else int(u.max_hp * it.params.amount)
			b._heal(u, maxi(1, amount))
		"cure":
			var which: String = it.params.status
			var has_status: bool = u.status != MoveData.Status.NONE and (which == "all" or STATUS_CODES.get(which, -1) == u.status)
			var confused: bool = u.volatiles.has("confusion") and which in ["all", "confusion"]
			if has_status:
				u.status = MoveData.Status.NONE
				u.status_turns = 0
			if confused:
				u.volatiles.erase("confusion")
			u.refresh_label()
			Fx.aura(b, u.position, Fx.HEAL_COLOR, u.data.model_height)
			b._popup(u, "¡Curado!", Color(0.4, 1.0, 0.5))
			b._log("%s se recuperó." % u.display_name())
		"pinch":
			_boost(u, {it.params.stat: 1}, it.display_name)
		"pp":
			for mv in u.moves:
				if u.pp.get(mv, 1) <= 0:
					u.pp[mv] = it.params.amount
					b._popup(u, "+%d PP" % it.params.amount, Color(0.5, 0.85, 1.0))
					b._log("%s recuperó PP de %s." % [u.display_name(), mv.display_name])
					break


const STATUS_CODES := {"par": MoveData.Status.PARALYSIS, "slp": MoveData.Status.SLEEP, "psn": MoveData.Status.POISON,
	"brn": MoveData.Status.BURN, "frz": MoveData.Status.FREEZE}


func _eat(u: Unit) -> void:
	b._log("¡%s se comió su %s!" % [u.display_name(), u.item.display_name])
	b._popup(u, u.item.display_name, Color(0.6, 1.0, 0.6), 1.2)
	Audio.sfx("heal", -8.0, 1.2)
	Fx.aura(b, u.position, Color(0.6, 1.0, 0.6), u.data.model_height * 0.6, false)
	u.lose_item(true)
	u.refresh_label()


## Bayas que reducen un golpe supereficaz de su tipo (se consumen). Devuelve el multiplicador.
func resist_berry(att: Unit, t: Unit, type: String, eff: float) -> float:
	if Items.effect(t) == "resist" and t.item.params.type == type and (eff > 1.0 or type == "normal") and can_eat(t):
		b._log("¡La %s de %s debilitó el ataque!" % [t.item.display_name, t.display_name()])
		t.lose_item(true)
		return 0.5
	return 1.0


func _nearest_foe(u: Unit) -> Unit:
	var best: Unit = null
	var best_d := 1 << 30
	for foe: Unit in b.units:
		if foe.team != u.team and foe.is_alive():
			var d: int = b.grid.distance_to_set(u.footprint, foe.cell)
			if d < best_d:
				best_d = d
				best = foe
	return best


func _hurt(u: Unit, dmg: int, text: String, color: Color) -> void:
	b._log(text)
	b._popup(u, str(dmg), color)
	u.take_damage(dmg)


func _boost(u: Unit, changes: Dictionary, source: String) -> void:
	var text := u.apply_stages(changes)
	if text:
		Audio.sfx("buff" if changes.values()[0] > 0 else "debuff", -6.0)
		b._log("%s (%s): %s." % [u.display_name(), source, text])
		var up: bool = changes.values()[0] > 0
		Fx.aura(b, u.position, Fx.BUFF_COLOR if up else Fx.DEBUFF_COLOR, u.data.model_height, up)


# --- Estados ----------------------------------------------------------------------

## Motivo por el que `t` no puede recibir `status` (o "" si puede).
func can_status(att: Unit, t: Unit, status: int) -> String:
	if not Combat.can_receive_status(t, status):
		return "no tiene efecto"
	if status == MoveData.Status.FREEZE and not Weather.can_freeze(Combat.weather):
		return "el sol lo impide"
	if Abilities.blocks_status(att if att else t, t, status, Combat.weather):
		return "su %s lo impide" % Abilities.display_name(t.ability)
	if att and att.team != t.team and field.zone_at("safeguard", t.team, t.footprint):
		return "Velo Sagrado lo protege"
	if field.grounded(t) and field.terrain == "mistyterrain":
		return "el Campo de Niebla lo protege"
	if status == MoveData.Status.SLEEP and field.grounded(t) and field.terrain == "electricterrain":
		return "el Campo Eléctrico no le deja dormir"
	return ""


func set_status(att: Unit, t: Unit, status: int) -> void:
	Audio.sfx("status", -6.0)
	t.status = status
	t.status_turns = b.rng.randi_range(1, 3) if status == MoveData.Status.SLEEP else 0
	if status == MoveData.Status.SLEEP and t.ability == "earlybird":
		t.status_turns = t.status_turns / 2
	t.refresh_label()
	b._log("¡%s está %s!" % [t.display_name(), Combat.STATUS_NAMES[status]])
	check_berries(t)
	# Sincronía devuelve veneno, quemadura o parálisis a quien se lo causó.
	if att and att != t and t.ability == "synchronize" and status in [MoveData.Status.POISON, MoveData.Status.BURN, MoveData.Status.PARALYSIS] \
			and can_status(t, att, status) == "":
		b._log("¡Sincronía de %s!" % t.display_name())
		set_status(t, att, status)


## Bajadas (o subidas) de stats provocadas por `att` en `t`, respetando Neblina y habilidades.
func drop_stats(att: Unit, t: Unit, changes: Dictionary) -> void:
	var allowed := {}
	for key: String in changes:
		if changes[key] < 0 and att and att.team != t.team:
			if field.zone_at("mist", t.team, t.footprint):
				b._log("¡Neblina protege a %s!" % t.display_name())
				continue
			if Abilities.blocks_drop(att, t, key):
				b._log("¡%s de %s lo impide!" % [Abilities.display_name(t.ability), t.display_name()])
				continue
		allowed[key] = changes[key]
	if allowed.is_empty():
		return
	var text := t.apply_stages(allowed)
	if text:
		Audio.sfx("buff" if allowed.values()[0] > 0 else "debuff", -6.0)
		b._log("%s: %s." % [t.display_name(), text])
		var up: bool = allowed.values()[0] > 0
		Fx.aura(b, t.position, Fx.BUFF_COLOR if up else Fx.DEBUFF_COLOR, t.data.model_height, up)
		if not up and att and att.team != t.team:
			var reaction := Abilities.on_stat_dropped(t)
			if not reaction.is_empty():
				_boost(t, reaction, Abilities.display_name(t.ability))
		if not up and Items.effect(t) == "white_herb":
			for key: String in t.stages.keys():
				if t.stages[key] < 0:
					t.stages[key] = 0
			b._log("¡La Hierba Blanca de %s restauró sus stats!" % t.display_name())
			t.lose_item(true)
			t.refresh_label()


## Aplica un volátil del ataque al objetivo. Devuelve true si lo aplicó.
func apply_volatile(att: Unit, t: Unit, vol: String) -> bool:
	if t.volatiles.has(vol) or Abilities.blocks_volatile(att, t, vol):
		return false
	if att.team != t.team and vol in ["confusion", "yawn"] and field.zone_at("safeguard", t.team, t.footprint):
		return false
	match vol:
		"leechseed":
			if "grass" in t.data.types:
				return false
			t.volatiles[vol] = {"by": att}
			b._log("¡%s quedó sembrado!" % t.display_name())
		"nightmare":
			if t.status != MoveData.Status.SLEEP:
				return false
			t.volatiles[vol] = {}
			b._log("¡%s tiene pesadillas!" % t.display_name())
		"yawn":
			if t.status != MoveData.Status.NONE:
				return false
			t.volatiles[vol] = {"turns": 2}
			b._log("%s se está quedando dormido..." % t.display_name())
		"curse":
			t.volatiles[vol] = {}
			b._log("¡%s ha sido maldecido!" % t.display_name())
		"wrapped", "vortex":
			if t.volatiles.has("wrapped") or t.volatiles.has("vortex"):
				return false
			if "ghost" in t.data.types:
				b._log("%s es de tipo Fantasma: no se le puede atrapar." % t.display_name())
				return false
			t.volatiles[vol] = {"turns": BIND_TURNS, "by": att}
			if vol == "wrapped":
				# Quien sujeta tampoco se mueve (y solo puede sujetar a uno).
				if att.volatiles.has("holding"):
					var prev: Unit = att.volatiles.holding.target
					if prev and prev.volatiles.has("wrapped"):
						release_bind(prev, "wrapped")
				att.volatiles["holding"] = {"target": t}
				att.refresh_label()
				b._log("¡%s atrapa a %s! Ninguno de los dos puede moverse." % [att.display_name(), t.display_name()])
			else:
				b._log("¡%s queda atrapado en el remolino y no puede moverse!" % t.display_name())
		"attract":
			if not att.opposite_gender(t):
				return false
			t.volatiles[vol] = {"by": att, "turns": ATTRACT_TURNS, "blocked": false}
			b._log("¡%s se ha enamorado de %s!" % [t.display_name(), att.display_name()])
		_:
			var turns: Array = VOLATILE_TURNS.get(vol, [3, 3])
			t.volatiles[vol] = {"turns": b.rng.randi_range(turns[0], turns[1])}
			b._log("¡%s está %s!" % [t.display_name(), "confuso" if vol == "confusion" else Unit.VOLATILE_SHORT[vol].to_lower()])
	t.refresh_label()
	Fx.aura(b, t.position, Color(0.8, 0.6, 1.0), t.data.model_height)
	if vol in ["taunt", "attract"] and Items.effect(t) == "mental_herb":
		t.volatiles.erase(vol)
		b._log("¡La Hierba Mental de %s lo libera!" % t.display_name())
		t.lose_item(true)
		t.refresh_label()
	check_berries(t)
	return true


## Libera a `t` de Constricción o del remolino (y a quien lo sujetaba).
func release_bind(t: Unit, key: String) -> void:
	var by: Unit = t.volatiles[key].get("by")
	t.volatiles.erase(key)
	if t.is_alive():
		b._log("¡%s se liberó!" % t.display_name())
		t.refresh_label()
	if key == "wrapped" and by and by.volatiles.has("holding") and by.volatiles.holding.target == t:
		by.volatiles.erase("holding")
		by.refresh_label()


## Rompe las ataduras que ya no tienen sentido: el que sujeta cayó o ya no está pegado
## (empujado, teletransportado...), o el atrapado cayó.
func check_binds() -> void:
	for u: Unit in b.units:
		if u.volatiles.has("wrapped"):
			var by: Unit = u.volatiles.wrapped.get("by")
			var touching := false
			if by and by.is_alive():
				for c in u.footprint:
					if b.grid.distance_to_set(by.footprint, c) <= 1:
						touching = true
						break
			if not u.is_alive() or not touching:
				release_bind(u, "wrapped")
	for u: Unit in b.units:
		if u.volatiles.has("holding"):
			var t: Unit = u.volatiles.holding.get("target")
			if not u.is_alive() or t == null or not t.is_alive() or not t.volatiles.has("wrapped"):
				u.volatiles.erase("holding")
				if u.is_alive():
					u.refresh_label()


## Volátiles sobre el propio usuario (Protección, Sustituto...). Devuelve false si falla.
func apply_self_volatile(u: Unit, vol: String) -> bool:
	match vol:
		"protect", "endure":
			# Cada uso seguido tiene 1/3 de probabilidad de éxito respecto al anterior.
			var chance := pow(1.0 / 3.0, u.protect_streak)
			u.protect_streak += 1
			u.volatiles["protect_used"] = {}
			if b.rng.randf() >= chance:
				b._log("¡Pero falló!")
				return false
			u.volatiles[vol] = {}
			Audio.sfx("protect", -4.0)
			b._log("¡%s se %s!" % [u.display_name(), "protege" if vol == "protect" else "prepara para aguantar"])
		"substitute":
			var cost := u.max_hp / 4
			if u.volatiles.has("substitute") or u.hp <= cost:
				b._log("¡Pero falló!")
				return false
			u.take_damage(cost)
			u.volatiles[vol] = {"hp": cost}
			b._log("¡%s creó un sustituto!" % u.display_name())
		"magnetrise":
			u.volatiles[vol] = {"turns": VOLATILE_TURNS.magnetrise[0]}
			b._log("¡%s levita gracias al electromagnetismo!" % u.display_name())
		_:
			u.volatiles[vol] = {}
			b._log("%s: %s." % [u.display_name(), Unit.VOLATILE_SHORT.get(vol, vol)])
	u.refresh_label()
	Fx.aura(b, u.position, Color(0.6, 0.9, 1.0), u.data.model_height)
	return true


# --- Recibir un ataque ------------------------------------------------------------

## ¿Bloquea `t` el ataque antes de que haga nada? Devuelve el motivo o "".
func blocks_move(att: Unit, t: Unit, move: MoveData) -> String:
	if t == att:
		return ""
	if t.volatiles.has("protect"):
		return "protect"
	if t.volatiles.has("substitute") and move.category == MoveData.Category.STATUS \
			and "sound" not in move.flags and not Abilities.has(att, "infiltrator"):
		return "substitute"
	return ""


## Aplica el daño: lo absorbe el sustituto, o Aguante/Robustez dejan 1 PS. Devuelve el daño real a los PS.
func absorb_damage(att: Unit, t: Unit, dmg: int) -> int:
	if t.volatiles.has("substitute") and att != t and not Abilities.has(att, "infiltrator"):
		t.volatiles.substitute.hp -= dmg
		b._log("¡El sustituto recibió el daño por %s!" % t.display_name())
		if t.volatiles.substitute.hp <= 0:
			t.volatiles.erase("substitute")
			b._log("¡El sustituto de %s se rompió!" % t.display_name())
		t.refresh_label()
		return 0
	if dmg >= t.hp:
		if t.volatiles.has("endure"):
			b._log("¡%s aguantó el golpe!" % t.display_name())
			return t.hp - 1
		if Abilities.defender_has(att, t, "sturdy") and t.hp == t.max_hp:
			b._log("¡%s resistió gracias a Robustez!" % t.display_name())
			return t.hp - 1
		if Items.effect(t) == "focus_sash" and t.hp == t.max_hp:
			b._log("¡%s resistió gracias a su Banda Focus!" % t.display_name())
			t.lose_item(true)
			return t.hp - 1
		if Items.effect(t) == "focus_band" and b.rng.randf() < Items.param(t, "chance", 0.1):
			b._log("¡%s resistió gracias a su Cinta Focus!" % t.display_name())
			return t.hp - 1
	return dmg


## Después de un golpe que hizo daño: habilidades de contacto, reacciones y KO.
func after_hit(att: Unit, t: Unit, move: MoveData, crit: bool) -> void:
	var physical := move.category == MoveData.Category.PHYSICAL
	if Items.effect(t) == "air_balloon":
		b._log("¡El Globo Helio de %s explotó!" % t.display_name())
		t.lose_item(false)
	if "contact" in move.flags and Items.effect(t) == "rocky_helmet" and att.is_alive() and att != t and Abilities.takes_indirect(att):
		_hurt(att, maxi(1, int(att.max_hp * Items.param(t, "amount", 1.0 / 6.0))), "¡El Casco Dentado de %s hiere a %s!" % [t.display_name(), att.display_name()], Color(0.7, 0.7, 0.7))
	check_berries(t)
	if not t.is_alive():
		if Abilities.has(att, "moxie"):
			_boost(att, {"attack": 1}, "Autoestima")
		if t.volatiles.has("destinybond") and att.is_alive():
			b._log("¡%s se llevó a %s con Mismo Destino!" % [t.display_name(), att.display_name()])
			att.take_damage(att.hp)
		if "contact" in move.flags and t.ability == "aftermath" and att.is_alive() and Abilities.takes_indirect(att):
			_hurt(att, maxi(1, att.max_hp / 4), "¡Detonación de %s!" % t.display_name(), Color(1.0, 0.5, 0.3))
		return
	if crit and t.ability == "angerpoint":
		_boost(t, {"attack": 12}, "Irascible")
	var reaction := Abilities.on_hit(t, physical, Combat.move_type(move))
	if not reaction.is_empty():
		_boost(t, reaction, Abilities.display_name(t.ability))
	if "contact" in move.flags and att.is_alive():
		var st := Abilities.contact_status(t, b.rng)
		if st != MoveData.Status.NONE and can_status(t, att, st) == "":
			b._log("¡%s de %s!" % [Abilities.display_name(t.ability), t.display_name()])
			set_status(t, att, st)
		if t.ability == "cutecharm" and t.opposite_gender(att) and b.rng.randf() < 0.3 and not att.volatiles.has("attract"):
			b._log("¡Gran Encanto de %s!" % t.display_name())
			apply_volatile(t, att, "attract")
		var st2 := Abilities.contact_status(att, b.rng) if att.ability == "poisontouch" else MoveData.Status.NONE
		if st2 != MoveData.Status.NONE and can_status(att, t, st2) == "":
			b._log("¡Toque Tóxico de %s!" % att.display_name())
			set_status(att, t, st2)


## Probabilidad de retroceso con habilidades (Hedor añade 10 % a los golpes que no lo tienen).
func flinch_chance(att: Unit, t: Unit, move: MoveData) -> int:
	var chance := move.flinch_chance
	if chance == 0 and Abilities.has(att, "stench"):
		chance = 10
	if chance == 0 and move.power > 0:
		chance = Items.flinch_bonus(att)
	chance = Abilities.secondary_chance(att, t, chance)
	return 0 if Abilities.blocks_volatile(att, t, "flinch") else chance


# --- Efectos de campo -------------------------------------------------------------

func apply_field(user: Unit, move: MoveData, area: Array[Vector2i]) -> void:
	var fe := move.field_effect
	var alive := _alive_count()
	match fe:
		"reflect", "lightscreen", "auroraveil", "safeguard", "mist":
			if fe == "auroraveil" and Combat.weather != Weather.Kind.HAIL:
				b._log("¡Pero falló! (necesita granizo)")
				return
			var cells := {}
			for c in user.footprint:
				for n in b.grid.cells_in_range(c, 0, FieldState.ZONE_RADIUS):
					cells[n] = true
			field.zones = field.zones.filter(func(z: Dictionary) -> bool: return not (z.kind == fe and z.team == user.team))
			field.zones.append({"kind": fe, "team": user.team, "cells": cells, "turns": Items.zone_rounds(user, FieldState.ZONE_ROUNDS) * alive})
			b._log("¡%s protege la zona de %s!" % [FieldState.NAMES[fe], user.display_name()])
		"tailwind":
			field.tailwind[user.team] = FieldState.TAILWIND_ROUNDS * alive
			b._log("¡Sopla un viento afín para el equipo de %s!" % user.display_name())
		"spikes", "toxicspikes", "stealthrock":
			for c in area:
				if b.grid.is_blocked(c):
					continue
				var trap: Dictionary = field.traps.get(c, {"team": user.team, "spikes": 0, "toxic": 0, "rocks": false})
				trap.team = user.team
				match fe:
					"spikes": trap.spikes = mini(trap.spikes + 1, FieldState.MAX_SPIKES)
					"toxicspikes": trap.toxic = mini(trap.toxic + 1, 2)
					"stealthrock": trap.rocks = true
				field.traps[c] = trap
			b._log("¡%s esparció %s por el terreno!" % [user.display_name(), move.display_name])
			Audio.sfx("trap", -4.0)
		"electricterrain", "grassyterrain", "mistyterrain", "psychicterrain":
			field.terrain = fe
			field.terrain_turns = FieldState.GLOBAL_ROUNDS * alive
			b._log("¡El terreno se convirtió en %s!" % FieldState.NAMES[fe])
		"trickroom":
			field.trick_room = 0 if field.trick_room > 0 else FieldState.GLOBAL_ROUNDS * alive
			b._log("¡%s las dimensiones!" % ("Se normalizaron" if field.trick_room == 0 else "Se retorcieron"))
		"gravity":
			field.gravity = FieldState.GLOBAL_ROUNDS * alive
			b._log("¡La gravedad se intensificó!")
		"haze":
			for u: Unit in b.units:
				if u.is_alive() and (u == user or b._others_at(user, area).has(u)):
					u.stages.clear()
					u.stage_turns.clear()
					u.refresh_label()
			b._log("¡Se eliminaron los cambios de stats en la zona!")
		"perishsong":
			var hit: Array[Unit] = b._others_at(user, area)
			hit.append(user)
			for u in hit:
				if u.is_alive() and not u.volatiles.has("perish") and not Abilities.has(u, "soundproof"):
					u.volatiles["perish"] = {"turns": VOLATILE_TURNS.perish[0]}
					u.refresh_label()
			b._log("¡Todos los que oyeron el Canto Mortal caerán en 3 turnos!")
	refresh_visuals()


## Trampas al entrar en una casilla (`cells` = huella nueva). Solo afectan a rivales de quien las puso.
func enter_cells(u: Unit, cells: Array[Vector2i]) -> void:
	# Los voladores esquivan las Púas, pero no la Trampa Rocas.
	for c in cells:
		var trap: Dictionary = field.traps.get(c, {})
		if trap.is_empty() or trap.team == u.team or not u.is_alive() or Items.ignores_traps(u):
			continue
		Audio.sfx("trap", -4.0)
		if trap.rocks and Abilities.takes_indirect(u):
			var eff := TypeChart.effectiveness("rock", u.data.types)
			_hurt(u, maxi(1, int(u.max_hp / 8.0 * eff)), "¡Las piedras puntiagudas dañan a %s!" % u.display_name(), Color(0.7, 0.6, 0.5))
		if not field.grounded(u):
			continue
		if trap.spikes > 0 and Abilities.takes_indirect(u):
			var frac: float = [0.0, 1.0 / 8.0, 1.0 / 6.0, 1.0 / 4.0][trap.spikes]
			_hurt(u, maxi(1, int(u.max_hp * frac)), "¡Las púas hieren a %s!" % u.display_name(), Color(0.8, 0.8, 0.8))
		if trap.toxic > 0:
			if "poison" in u.data.types:
				trap.toxic = 0
				b._log("¡%s absorbió las púas tóxicas!" % u.display_name())
				refresh_visuals()
			elif can_status(null, u, MoveData.Status.POISON) == "":
				set_status(null, u, MoveData.Status.POISON)


func refresh_visuals() -> void:
	var marks := {}
	if field.terrain:
		marks["terrain"] = [b.grid.all_cells(), FieldState.COLORS[field.terrain]]
	for i in field.zones.size():
		var z: Dictionary = field.zones[i]
		var cells: Array[Vector2i] = []
		cells.assign(z.cells.keys())
		marks["zone%d" % i] = [cells, FieldState.COLORS[z.kind]]
	b._board.set_marks(marks)
	b._board.set_traps(field.traps)
	b._refresh_weather_label()

class_name Combat
extends RefCounted
## Reglas puras de combate: celdas apuntables, área de efecto y cálculo de daño.

const AREA_NAMES := {
	MoveData.AreaShape.SINGLE: "individual",
	MoveData.AreaShape.CIRCLE: "círculo",
	MoveData.AreaShape.CROSS: "cruz",
	MoveData.AreaShape.LINE: "línea",
}
const TYPE_NAMES := {
	"normal": "Normal", "fire": "Fuego", "water": "Agua", "electric": "Eléctrico",
	"grass": "Planta", "ice": "Hielo", "fighting": "Lucha", "poison": "Veneno",
	"ground": "Tierra", "flying": "Volador", "psychic": "Psíquico", "bug": "Bicho",
	"rock": "Roca", "ghost": "Fantasma", "dragon": "Dragón", "dark": "Siniestro",
	"steel": "Acero", "fairy": "Hada",
}
const STATUS_NAMES := {
	MoveData.Status.POISON: "envenenado",
	MoveData.Status.SLEEP: "dormido",
	MoveData.Status.PARALYSIS: "paralizado",
	MoveData.Status.BURN: "quemado",
	MoveData.Status.FREEZE: "congelado",
}
## Tipos inmunes a cada estado.
const STATUS_IMMUNITIES := {
	MoveData.Status.POISON: ["poison", "steel"],
	MoveData.Status.PARALYSIS: ["electric"],
	MoveData.Status.BURN: ["fire"],
	MoveData.Status.FREEZE: ["ice"],
}


## Celdas que se pueden elegir como objetivo. `origin` son las celdas que ocupa el
## atacante; el alcance se mide desde la más cercana.
static func target_cells(grid: BoardGrid, move: MoveData, origin: Array[Vector2i]) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if move.targets_self:
		return origin.duplicate()
	if move.area_shape != MoveData.AreaShape.LINE:
		# Los ataques a distancia llegan más lejos desde lo alto (+1 por cada 2 niveles).
		var ranged := move.range_max >= 2
		var origin_h := grid.footprint_height(origin)
		var reach := move.range_max + (MAX_HEIGHT_RANGE_BONUS if ranged else 0)
		for o in origin:
			for c in grid.cells_in_range(o, 0, reach):
				if c in result or (move.range_min > 0 and c in origin):
					continue
				var d := grid.distance_to_set(origin, c)
				var bonus := clampi((origin_h - grid.get_height(c)) / 2, 0, MAX_HEIGHT_RANGE_BONUS) if ranged else 0
				if d >= move.range_min and d <= move.range_max + bonus:
					result.append(c)
		return result
	for o in origin:
		for dir in grid.direction_count():
			for c in grid.line(o, dir, move.range_max):
				if c not in origin and c not in result and grid.distance_to_set(origin, c) >= move.range_min:
					result.append(c)
	return result


## Celdas afectadas si se lanza `move` desde `origin` apuntando a `target`.
static func area_cells(grid: BoardGrid, move: MoveData, origin: Array[Vector2i], target: Vector2i) -> Array[Vector2i]:
	if move.targets_self:
		return origin.duplicate()
	match move.area_shape:
		MoveData.AreaShape.CIRCLE:
			return grid.cells_in_range(target, 0, move.area_size)
		MoveData.AreaShape.CROSS:
			var cells: Array[Vector2i] = [target]
			for dir in grid.direction_count():
				cells.append_array(grid.line(target, dir, move.area_size))
			return cells
		MoveData.AreaShape.LINE:
			var from := origin[0]
			for o in origin:
				if grid.distance(o, target) < grid.distance(from, target):
					from = o
			# Rayo: atraviesa Pokémon, pero se corta en obstáculos y paredes.
			var cells: Array[Vector2i] = []
			for c in grid.line(from, grid.direction_towards(from, target), maxi(move.area_size, move.range_max)):
				if c in origin:
					continue
				if grid.blocks_sight(c, from, c):
					break
				cells.append(c)
			return cells
	return [target]


## Recorrido de un proyectil desde la celda de `origin` más cercana a `target`.
## `unit_at` devuelve el Pokémon de una celda (o null); se ignoran las celdas de `origin`.
## Devuelve {"cell": celda de impacto, "path": celdas recorridas, "blocker": "", "obstacle" o "unit"}.
static func trace(grid: BoardGrid, origin: Array[Vector2i], target: Vector2i, unit_at: Callable) -> Dictionary:
	var from := origin[0]
	for o in origin:
		if grid.distance(o, target) < grid.distance(from, target):
			from = o
	var path: Array[Vector2i] = []
	for c in grid.ray(from, target):
		if c in origin:
			continue
		path.append(c)
		if c != target and grid.blocks_sight(c, from, target):
			return {"cell": c, "path": path, "blocker": "obstacle"}
		if c != target and unit_at.call(c) != null:
			return {"cell": c, "path": path, "blocker": "unit"}
	return {"cell": target, "path": path, "blocker": ""}


## Clima efectivo del combate y efectos de campo (los fija la batalla).
static var weather := Weather.Kind.CLEAR
static var field: FieldState


## Tipo real del ataque con el clima actual (Meteorobola cambia).
static func move_type(move: MoveData) -> String:
	return Weather.move_type(weather, move)


## Probabilidad de crítico por índice (6.ª generación en adelante): 1/24, 1/8, 1/2, siempre.
const CRIT_CHANCES: Array[float] = [1.0 / 24.0, 1.0 / 8.0, 0.5, 1.0]
const CRIT_MULT := 1.5
const MAX_HEIGHT_RANGE_BONUS := 2


static func crit_chance(attacker: Unit, move: MoveData, defender: Unit = null) -> float:
	if move.category == MoveData.Category.STATUS or move.fixed_damage > 0:
		return 0.0
	if defender and Abilities.blocks_crit(attacker, defender):
		return 0.0
	if move.always_crit:
		return 1.0
	var stage := clampi(move.crit_stage + attacker.stages.get("crit", 0) + Abilities.crit_bonus(attacker), 0, CRIT_CHANCES.size() - 1)
	return CRIT_CHANCES[stage]


## Fórmula clásica de daño a nivel 50. `roll` es el factor aleatorio (0.85 - 1.0).
## Un crítico multiplica ×1,5 e ignora las bajadas de ataque y las subidas de defensa.
## `situational` lo calcula la batalla (pantallas, terreno, Compiescolta...).
static func damage(attacker: Unit, defender: Unit, move: MoveData, roll: float, crit := false, situational := 1.0) -> int:
	if move.category == MoveData.Category.STATUS:
		return 0
	var type := move_type(move)
	var eff := Abilities.effectiveness(attacker, type, defender.data.types)
	if move.fixed_damage > 0:
		return move.fixed_damage if eff > 0.0 else 0
	if move.power <= 0 or eff == 0.0:
		return 0
	var physical := move.category == MoveData.Category.PHYSICAL
	var atk_stat := move.attack_stat if move.attack_stat else ("attack" if physical else "sp_attack")
	# Ignorante: quien lo tiene no ve las mejoras del rival.
	var atk_ignore := 2 if Abilities.defender_has(attacker, defender, "unaware") else (1 if crit else 0)
	var def_ignore := 2 if Abilities.has(attacker, "unaware") else (-1 if crit else 0)
	var atk := attacker.stat(atk_stat, atk_ignore)
	var def := defender.stat("defense" if physical else "sp_defense", def_ignore)
	def *= Weather.defense_mult(weather, defender.data.types, physical)
	if physical and attacker.status == MoveData.Status.BURN and attacker.ability != "guts":
		atk *= 0.5
	var power := move.power * Weather.power_mult(weather, move)
	var base := floorf((2.0 * attacker.level / 5.0 + 2.0) * power * atk / def / 50.0) + 2.0
	var stab := Abilities.stab(attacker) if type in attacker.data.types else 1.0
	var mods := Abilities.attack_mult(attacker, move, type, physical, crit, weather) \
		* Abilities.defense_mult(attacker, defender, type, physical, eff) * situational
	return maxi(1, int(base * stab * eff * roll * (CRIT_MULT if crit else 1.0) * mods))


## Probabilidad de acierto (0-100) con clima, precisión del atacante y evasión del objetivo.
static func hit_chance(attacker: Unit, defender: Unit, move: MoveData) -> int:
	if move.always_hits or defender == attacker or Abilities.always_hits(attacker, defender):
		return 100
	var base := Weather.accuracy(weather, move)
	if base < 0:
		return 100
	var acc_stage: int = 0 if Abilities.defender_has(attacker, defender, "unaware") else attacker.stages.get("accuracy", 0)
	var eva_stage: int = 0 if Abilities.has(attacker, "unaware") else defender.stages.get("evasion", 0)
	var n := clampi(acc_stage - eva_stage, -6, 6)
	var mult := (3.0 + n) / 3.0 if n >= 0 else 3.0 / (3.0 - n)
	mult *= Abilities.accuracy_mult(attacker, defender, move, weather)
	if field and field.gravity > 0:
		mult *= 5.0 / 3.0
	return clampi(roundi(base * mult), 1, 100)


const VOLATILE_DESC := {
	"confusion": "Confunde (2-5 turnos; 1/3 de herirse y perder el turno)",
	"leechseed": "Drenadoras: le roba 1/8 de PS cada turno",
	"yawn": "Bostezo: se dormirá al turno siguiente",
	"taunt": "Mofa: solo podrá usar ataques de daño (3 turnos)",
	"nightmare": "Pesadilla: 1/4 de PS por turno mientras duerma",
	"attract": "Enamora al sexo opuesto: 50% de no poder atacar cada turno (5 turnos)",
	"curse": "Fantasma: paga 1/2 de PS y maldice (1/4 por turno). Otros: Atq/Def +1, Vel -1",
	"protect": "Bloquea todos los ataques hasta su próximo turno (falla más si se repite)",
	"endure": "Aguanta con 1 PS hasta su próximo turno",
	"substitute": "Paga 1/4 de PS: un sustituto recibe los golpes y bloquea los de estado",
	"ingrain": "Arraigo: recupera 1/16 por turno, pero ya no puede moverse ni ser empujado",
	"aquaring": "Recupera 1/16 de PS por turno",
	"destinybond": "Si lo debilitan antes de su próximo turno, el atacante cae con él",
	"charge": "Su próximo ataque eléctrico hace el doble",
	"magnetrise": "Levita 5 turnos: inmune a Tierra y a las púas",
}
const FIELD_DESC := {
	"reflect": "Zona de radio 2: los aliados reciben la mitad de daño físico (5 rondas)",
	"lightscreen": "Zona de radio 2: los aliados reciben la mitad de daño especial (5 rondas)",
	"auroraveil": "Solo con granizo. Zona: mitad de daño físico y especial (5 rondas)",
	"safeguard": "Zona de radio 2: los aliados no reciben estados (5 rondas)",
	"mist": "Zona de radio 2: a los aliados no les bajan los stats (5 rondas)",
	"tailwind": "Duplica la velocidad de todo su equipo (4 rondas)",
	"spikes": "Siembra púas: dañan a los rivales que las pisen (acumulables x3; no a voladores)",
	"toxicspikes": "Púas tóxicas: envenenan a los rivales que las pisen (no a voladores)",
	"stealthrock": "Piedras flotantes: dañan a los rivales que pasen según su debilidad a Roca",
	"electricterrain": "Campo Eléctrico: Eléctrico ×1,3 y nadie se duerme (5 rondas, solo en el suelo)",
	"grassyterrain": "Campo de Hierba: Planta ×1,3 y cura 1/16 por turno (5 rondas, solo en el suelo)",
	"mistyterrain": "Campo de Niebla: sin estados y Dragón a la mitad (5 rondas, solo en el suelo)",
	"psychicterrain": "Campo Psíquico: Psíquico ×1,3 (5 rondas, solo en el suelo)",
	"trickroom": "Espacio Raro: los más lentos actúan antes (5 rondas)",
	"gravity": "Gravedad: todos tocan el suelo y la precisión sube (5 rondas)",
	"haze": "Elimina los cambios de stats de todos en el área (incluido él)",
	"perishsong": "Todos los que lo oigan (incluido él) caerán en 3 turnos",
}


static func can_receive_status(target: Unit, status: MoveData.Status) -> bool:
	if target.status != MoveData.Status.NONE:
		return false
	for t in STATUS_IMMUNITIES.get(status, []):
		if t in target.data.types:
			return false
	return true


static func describe(move: MoveData) -> String:
	var cat: String = ["Físico", "Especial", "Estado"][move.category]
	var lines := PackedStringArray()
	lines.append("%s · %s" % [TYPE_NAMES.get(move.type, move.type), cat])
	if move.fixed_damage > 0:
		lines.append("Daño fijo %d · Precisión %d" % [move.fixed_damage, move.accuracy])
	elif move.power > 0:
		lines.append("Potencia %d · Precisión %d" % [move.power, move.accuracy])
	else:
		lines.append("Precisión %d" % move.accuracy)
	if move.targets_self:
		lines.append("Sobre sí mismo")
	else:
		var area: String = AREA_NAMES[move.area_shape]
		if move.area_shape != MoveData.AreaShape.SINGLE:
			area += " %d" % maxi(move.area_size, move.range_max if move.area_shape == MoveData.AreaShape.LINE else 0)
		var reach := "alrededor de sí" if move.range_max == 0 else "Alcance %d-%d" % [move.range_min, move.range_max]
		lines.append("%s · Área: %s" % [reach, area])
		if move.projectile:
			lines.append("Proyectil: choca con lo primero que encuentre")
		elif move.area_shape == MoveData.AreaShape.LINE:
			lines.append("Rayo: atraviesa Pokémon, no obstáculos")
	if move.status != MoveData.Status.NONE:
		lines.append("%d%% de dejar %s" % [move.status_chance, STATUS_NAMES[move.status]])
	if move.volatile:
		var vol_text: String = VOLATILE_DESC.get(move.volatile, move.volatile)
		lines.append(vol_text if move.volatile_chance >= 100 else "%d%%: %s" % [move.volatile_chance, vol_text.to_lower()])
	if move.self_volatile:
		lines.append(VOLATILE_DESC.get(move.self_volatile, move.self_volatile))
	if move.field_effect:
		lines.append(FIELD_DESC.get(move.field_effect, move.field_effect))
	var weather_note := Weather.describe(move)
	if weather_note:
		lines.append(weather_note)
	if move.opposite_gender:
		lines.append("Solo contra el sexo opuesto")
	if move.always_crit:
		lines.append("Siempre es crítico")
	elif move.crit_stage > 0:
		lines.append("Alta probabilidad de crítico (%d%%)" % roundi(CRIT_CHANCES[mini(move.crit_stage, 3)] * 100))
	if move.flinch_chance > 0:
		lines.append("%d%% de hacer retroceder (retrasa su turno)" % move.flinch_chance)
	if move.always_hits and not move.targets_self:
		lines.append("No falla nunca")
	if move.attack_stat == "defense":
		lines.append("Ataca con su Defensa")
	if move.hp_cost > 0.0:
		lines.append("Cuesta %d%% de sus PS" % int(move.hp_cost * 100))
	if move.knockback > 0:
		lines.append("Empuja %d casilla(s)" % move.knockback)
	if move.drain > 0.0:
		lines.append("Absorbe %d%% del daño" % int(move.drain * 100))
	if move.heal > 0.0:
		lines.append("Recupera %d%% de sus PS" % int(move.heal * 100))
	if move.recoil > 0.0:
		lines.append("Sufre %d%% del daño causado" % int(move.recoil * 100))
	if move.self_ko:
		lines.append("¡El usuario se debilita!")
	if not move.stat_changes.is_empty():
		lines.append("%s al objetivo%s" % [_stages_text(move.stat_changes), "" if move.stat_chance >= 100 else " (%d%%)" % move.stat_chance])
	if not move.self_stat_changes.is_empty():
		lines.append("%s al usuario (%d turnos)" % [_stages_text(move.self_stat_changes), Unit.STAGE_TURNS])
	if move.extra_ct > 0:
		lines.append("Turno más lento (+%d CT)" % move.extra_ct)
	if move.id != "struggle":
		lines.append("PP: %d usos por combate" % move.pp)
	return "\n".join(lines)


static func _stages_text(changes: Dictionary) -> String:
	var parts := PackedStringArray()
	for key: String in changes:
		parts.append("%s %s%d" % [Unit.STAT_LABELS.get(key, key), "+" if changes[key] > 0 else "", changes[key]])
	return ", ".join(parts)

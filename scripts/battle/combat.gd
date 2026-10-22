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
		for o in origin:
			for c in grid.cells_in_range(o, 0, move.range_max):
				if c in result or (move.range_min > 0 and c in origin):
					continue
				if grid.distance_to_set(origin, c) >= move.range_min:
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


## Fórmula clásica de daño a nivel 50. `roll` es el factor aleatorio (0.85 - 1.0).
static func damage(attacker: Unit, defender: Unit, move: MoveData, roll: float) -> int:
	if move.category == MoveData.Category.STATUS:
		return 0
	if move.fixed_damage > 0:
		return move.fixed_damage if TypeChart.effectiveness(move.type, defender.data.types) > 0.0 else 0
	if move.power <= 0:
		return 0
	var physical := move.category == MoveData.Category.PHYSICAL
	var atk := attacker.stat("attack") if physical else attacker.stat("sp_attack")
	var def := defender.stat("defense") if physical else defender.stat("sp_defense")
	if physical and attacker.status == MoveData.Status.BURN:
		atk *= 0.5
	var base := floorf((2.0 * Unit.LEVEL / 5.0 + 2.0) * move.power * atk / def / 50.0) + 2.0
	var stab := 1.5 if move.type in attacker.data.types else 1.0
	var eff := TypeChart.effectiveness(move.type, defender.data.types)
	if eff == 0.0:
		return 0
	return maxi(1, int(base * stab * eff * roll))


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

class_name Unit
extends Node3D
## Un Pokémon en el tablero: stats calculados, estado, CT y su modelo animado.

signal fainted(unit: Unit)

const LEVEL := 50
const TEAM_COLORS: Array[Color] = [Color(0.25, 0.55, 1.0), Color(1.0, 0.3, 0.25)]
const LOOPING_ANIMS: PackedStringArray = ["idle", "walk", "run", "status_sleep", "status_paralysis",
	"status_poison", "status_confusion", "status_freeze", "status_burn"]
## Color de la capa de hielo que cubre al Pokémon congelado.
const FROZEN_TINT := Color(0.62, 0.86, 1.0, 0.5)
## Tinte rojo que palpita sobre el Pokémon quemado (alfa mínimo y máximo).
## (Multiplica el color del modelo, como el del envenenado: fuerza mínima y máxima.)
const BURN_TINT := Color(1.0, 0.35, 0.22)
const BURN_STRENGTH := Vector2(0.5, 0.85)
## Tinte morado que palpita, más lento, sobre el envenenado: multiplica el color del modelo (conserva sus
## sombras), con esta fuerza mínima y máxima.
const POISON_TINT := Color(0.62, 0.25, 0.95)
const POISON_STRENGTH := Vector2(0.65, 0.95)
## Destello amarillo del paralizado cuando le saltan las chispas.
const PARALYSIS_TINT := Color(1.0, 0.92, 0.2)
## Altura de la etiqueta (nombre, PS, estado) sobre la cabeza: por encima de las estrellas del confuso.
const LABEL_HEIGHT := 0.6
## Radio del anillo de equipo según el tamaño del Pokémon.
const RING_SCALE := [1.0, 1.0, 2.1, 2.9]
## Las mejoras de stats duran estos turnos propios (aplicar otra reinicia la cuenta).
const STAGE_TURNS := 3
const MAX_STAGE := 6
const STRUGGLE_PATH := "res://data/moves/struggle.tres"
const STAT_SHORT := {"attack": "Atq", "defense": "Def", "sp_attack": "AtE", "sp_defense": "DfE", "speed": "Vel", # i18n
	"accuracy": "Pre", "evasion": "Eva", "crit": "Crít"}
const STAT_LABELS := {"attack": "Ataque", "defense": "Defensa", "sp_attack": "At. Esp.", "sp_defense": "Def. Esp.", # i18n
	"speed": "Velocidad", "accuracy": "Precisión", "evasion": "Evasión", "crit": "Índice crítico"}
## El índice de crítico va de 0 a 3 (no se puede bajar).
const MAX_CRIT_STAGE := 3
## Pokémon que sueltan gas todo el rato (Fx.toxic_gas): colores al salir y al deshacerse.
const GAS := {
	"koffing": [Color(0.6, 0.38, 0.75, 0.75), Color(0.55, 0.7, 0.3)],
	"weezing": [Color(0.6, 0.38, 0.75, 0.75), Color(0.55, 0.7, 0.3)],
	"gastly": [Color(0.55, 0.35, 0.72, 0.6), Color(0.78, 0.6, 0.95)],
}

var data: PokemonData
## Especie original (Transformación cambia `data` y `moves` durante el combate).
var base_data: PokemonData
var base_moves: Array[MoveData] = []
## Nivel (el jugador siempre 50; el rival según la dificultad).
var level := LEVEL
## Ataques de este Pokémon concreto (los elegidos en el editor de equipo).
var moves: Array[MoveData] = []
var team := 0
## Aliado de tu bando que juega la IA (Gengar en la historia): no lo mueves tú ni cuenta para perder.
var ally_ai := false
## Celda ancla; `footprint` son todas las celdas que ocupa (ver BoardGrid.footprint).
var cell := Vector2i.ZERO
var footprint: Array[Vector2i] = []
var ct := 0.0
var max_hp := 1
var hp := 1
var stats := {}
var status := MoveData.Status.NONE
var status_turns := 0
## Niveles de mejora de stats (-6..+6), como en los juegos.
var stages := {}
## Turnos propios que le quedan a cada mejora antes de disiparse.
var stage_turns := {}
## Usos restantes de cada ataque en este combate.
var pp := {}
var ability := ""
## Objeto equipado, el último que consumió (para Reciclaje) y el ataque al que le ata un objeto Elección.
var item: ItemData
var consumed_item: ItemData
var choice_lock: MoveData
## Liviano: velocidad ×2 tras perder el objeto.
var unburdened := false
## 0 = sin género, 1 = macho, 2 = hembra.
var gender := 0
## Hacia dónde mira (dirección en el plano XZ); decide el flanqueo.
var facing := Vector2(0, 1)
## Estados volátiles activos: nombre -> datos (turnos restantes, quién lo causó...).
## confusion, leechseed, yawn, taunt, nightmare, curse, perish, protect, endure, substitute,
## ingrain, aquaring, destinybond, charge, magnetrise, flashfire.
var volatiles := {}
## Usos seguidos de Protección/Aguante (cada uno reduce la probabilidad de éxito).
var protect_streak := 0
## Rivales a los que ya intimidó (Intimidación actúa una vez por rival).
var intimidated := {}

var _model: Node3D
var _anim: AnimationPlayer
var _label: Label3D
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _marker: MeshInstance3D
## Flechita sobre el anillo que indica hacia dónde mira.
var _facing_arrow: Node3D
var _active := false
var _time := 0.0
# Animación procedural para modelos sin clips: "", "idle" o "walk".
var _proc_mode := ""
var _model_base_pos := Vector3.ZERO
var _model_base_scale := Vector3.ONE
var _gas: CPUParticles3D
## Última acción pedida a play() y, si era "idle", el clip de reposo que tocó según el estado.
var _current_key := ""
var _idle_key := ""
## La acción que se está viendo, ya resuelta ("status_burn" si se pidió idle estando quemado).
var _visual_key := ""
## Aspecto del estado sobre el modelo: "" nada, "ice" congelado, "burn" quemado (tinte y llamas), "sleep"
## dormido (zetas), "poison" envenenado (tinte y burbujas) o "paralysis" paralizado (chispas y destellos).
var _look := ""
var _overlay: StandardMaterial3D
var _status_fx: Node3D
## Silueta de luz al entrar o salir de la Poké Ball (set_energy); mientras, tapa la capa del estado.
var _energy: StandardMaterial3D
## Animación con Poké Ball en curso: el modelo lo mueve materialize/dematerialize (sin respiración procedural).
var _in_ball := false
## Estrellas que giran sobre la cabeza del confuso (va aparte: se puede estar confuso y además quemado).
var _dizzy: Node3D


func setup(member: TeamMember, p_team: int, p_level := LEVEL) -> void:
	level = p_level
	data = member.data
	base_data = data
	moves = member.moves.duplicate()
	base_moves = moves.duplicate()
	ability = member.ability
	item = member.item
	gender = member.gender
	for mv in moves:
		pp[mv] = mv.pp
	team = p_team
	max_hp = int((2 * data.base_hp + 31) * level / 100.0) + level + 10
	hp = max_hp
	stats = {
		"attack": _stat(data.base_attack),
		"defense": _stat(data.base_defense),
		"sp_attack": _stat(data.base_sp_attack),
		"sp_defense": _stat(data.base_sp_defense),
		"speed": _stat(data.base_speed),
	}
	name = "%s_%d" % [data.species_name, team]
	_build_visuals()


func _stat(base: int) -> int:
	return int((2 * base + 31) * level / 100.0) + 5


func is_alive() -> bool:
	return hp > 0


## Stat con sus mejoras aplicadas: ×(2+n)/2 si sube, ×2/(2+n) si baja.
## Un crítico ignora las bajadas del atacante (`ignore = 1`) y las subidas del defensor (`ignore = -1`).
func stat(stat_name: String, ignore := 0) -> float:
	var n: int = stages.get(stat_name, 0)
	if ignore == 2 or (ignore == 1 and n < 0) or (ignore == -1 and n > 0):
		n = 0
	var mult := (2.0 + n) / 2.0 if n >= 0 else 2.0 / (2.0 - n)
	return stats[stat_name] * mult


## Aplica cambios de stats y devuelve un texto para el registro ("" si no cambió nada).
func apply_stages(changes: Dictionary) -> String:
	var parts := PackedStringArray()
	for key: String in changes:
		var before: int = stages.get(key, 0)
		var lo := 0 if key == "crit" else -MAX_STAGE
		var hi := MAX_CRIT_STAGE if key == "crit" else MAX_STAGE
		var after := clampi(before + int(changes[key]), lo, hi)
		stages[key] = after
		stage_turns[key] = STAGE_TURNS
		if after == before:
			parts.append((tr("%s no puede subir más") if changes[key] > 0 else tr("%s no puede bajar más")) % tr(STAT_LABELS.get(key, key)))
		else:
			var amount := absi(after - before)
			var text := (tr("%s subió mucho") if amount >= 2 else tr("%s subió")) if after > before \
				else (tr("%s bajó mucho") if amount >= 2 else tr("%s bajó"))
			parts.append(text % tr(STAT_LABELS.get(key, key)))
	refresh_label()
	return ", ".join(parts)


## Al empezar su turno: las mejoras pierden un turno y las agotadas se disipan.
## Devuelve los nombres de los stats que volvieron a la normalidad.
func tick_stages() -> PackedStringArray:
	var expired := PackedStringArray()
	for key: String in stage_turns.keys():
		stage_turns[key] -= 1
		if stage_turns[key] <= 0:
			stage_turns.erase(key)
			if stages.get(key, 0) != 0:
				expired.append(STAT_LABELS.get(key, key))
			stages.erase(key)
	refresh_label()
	return expired


## Ataques que aún puede usar. Sin PP en ninguno, solo le queda Forcejeo.
func usable_moves() -> Array[MoveData]:
	var list: Array[MoveData] = []
	for mv in moves:
		# Con Mofa o Chaleco Asalto solo puede usar ataques que hacen daño; un objeto Elección le ata a uno.
		var no_status := volatiles.has("taunt") or (item != null and item.effect == "assault_vest")
		if pp.get(mv, 0) > 0 and not (no_status and mv.category == MoveData.Category.STATUS) \
				and (choice_lock == null or choice_lock == mv):
			list.append(mv)
	if list.is_empty():
		list.append(load(STRUGGLE_PATH))
	return list


## Pierde el objeto (consumido o quitado). `consumed` = se lo comió o lo usó (Reciclaje lo recupera).
func lose_item(consumed := true) -> void:
	if item == null:
		return
	if consumed:
		consumed_item = item
	item = null
	choice_lock = null
	unburdened = true


func spend_pp(mv: MoveData) -> void:
	if pp.has(mv):
		pp[mv] = maxi(pp[mv] - 1, 0)


## Texto corto de las mejoras activas, p. ej. "Atq+2 Vel-1".
func stages_text() -> String:
	var parts := PackedStringArray()
	for key: String in stages:
		if stages[key] != 0:
			parts.append("%s%s%d" % [tr(STAT_SHORT.get(key, key)), "+" if stages[key] > 0 else "", stages[key]])
	return " ".join(parts)


func effective_speed() -> float:
	var s := stat("speed") * Abilities.speed_mult(self, Combat.weather) * Items.speed_mult(self)
	if unburdened and ability == "unburden":
		s *= 2.0
	if status == MoveData.Status.PARALYSIS and ability != "quickfeet":
		s *= 0.5
	if Combat.field and Combat.field.tailwind[team] > 0:
		s *= 2.0
	return s


## Casillas por turno: 2 + velocidad base / 45 (redondeado), entre 2 y 6.
## Shuckle 2 · Bulbasaur/Scizor 3 · Pikachu 4 · Jolteon 5 · Ninjask 6.
## `in_water`: los de tipo Agua no sufren la penalización por peso mientras nadan.
func move_range(in_water := false) -> int:
	var tiles := clampi(2 + roundi(data.base_speed / 45.0), 2, 6) + data.move_modifier
	if in_water and data.move_modifier < 0:
		tiles -= data.move_modifier
	# Granizo: a los voladores les cuesta avanzar (salvo Hielo o habilidades que lo ignoran).
	if not Abilities.weather_immune(self, Combat.weather):
		tiles -= Weather.move_penalty(Combat.weather, data.types)
	if status == MoveData.Status.PARALYSIS:
		tiles -= 1
	return maxi(tiles, 1)


## Casillas por turno nadando (solo tipo Agua): el doble y sin penalización por peso.
func swim_range() -> int:
	return move_range(true) * 2 if "water" in data.types else 0


## ¿Puede desplazarse? Arraigo, estar atrapado o sujetar a otro lo impiden (sí puede atacar).
func can_move() -> bool:
	return not (volatiles.has("ingrain") or volatiles.has("wrapped") or volatiles.has("vortex") or volatiles.has("holding"))


func display_name() -> String:
	return "%s%s" % [TeamMember.display(base_data, gender), "" if team == 0 else tr(" (rival)")]


## ¿Son de sexos opuestos? (los sin género no cuentan).
func opposite_gender(other: Unit) -> bool:
	return gender != 0 and other.gender != 0 and gender != other.gender


## ¿Puede atacar este turno? (Atracción puede impedirlo).
func can_attack() -> bool:
	return not (volatiles.has("attract") and volatiles.attract.get("blocked", false))


func status_text() -> String:
	match status:
		MoveData.Status.POISON: return "ENV"
		MoveData.Status.SLEEP: return "DOR"
		MoveData.Status.PARALYSIS: return "PAR"
		MoveData.Status.BURN: return "QUE"
		MoveData.Status.FREEZE: return "CON"
	return ""


const VOLATILE_SHORT := { # i18n
	"confusion": "Confuso", "leechseed": "Drenadoras", "yawn": "Somnoliento", "taunt": "Mofa",
	"nightmare": "Pesadilla", "curse": "Maldito", "perish": "Canto Mortal", "protect": "Protegido",
	"endure": "Aguante", "substitute": "Sustituto", "ingrain": "Arraigado", "aquaring": "Acua Aro",
	"destinybond": "Mismo Destino", "charge": "Carga", "magnetrise": "Levitón", "flashfire": "Absorbe Fuego",
	"attract": "Enamorado", "wrapped": "Atrapado", "vortex": "Remolino", "holding": "Sujetando",
}


func volatiles_text() -> String:
	var parts := PackedStringArray()
	for key: String in volatiles:
		# Las marcas internas (ability_used, protect_used) no tienen nombre y no se muestran.
		if not VOLATILE_SHORT.has(key):
			continue
		var label: String = tr(VOLATILE_SHORT[key])
		if key == "perish":
			label += " %d" % volatiles[key].turns
		parts.append(label)
	return ", ".join(parts)


## Solo el modelo, sin anillo, nombre ni colisión (para vistas previas).
func hide_overlays() -> void:
	_ring.visible = false
	_facing_arrow.visible = false
	_label.visible = false
	for body in find_children("*", "StaticBody3D", false, false):
		body.queue_free()


## Marca (o desmarca) al Pokémon como el que tiene el turno.
func set_active(on: bool) -> void:
	_active = on
	_marker.visible = on
	_ring_mat.emission_energy_multiplier = 0.6
	_ring.scale = Vector3(RING_SCALE[data.size], 0.15, RING_SCALE[data.size])


func _process(delta: float) -> void:
	_time += delta
	if _active:
		_marker.position.y = data.model_height + LABEL_HEIGHT + 0.4 + sin(_time * 4.0) * 0.1
		_marker.rotation.y += delta * 2.0
		var pulse := 0.5 + 0.5 * sin(_time * 5.0)
		_ring_mat.emission_energy_multiplier = 0.6 + pulse * 2.0
		var r: float = RING_SCALE[data.size] * (1.0 + pulse * 0.12)
		_ring.scale = Vector3(r, 0.15, r)
	match "" if _in_ball else _proc_mode:
		"idle":
			_model.scale = _model_base_scale * Vector3(1.0, 1.0 + 0.025 * sin(_time * 2.5), 1.0)
		"walk":
			_model.position.y = _model_base_pos.y + absf(sin(_time * 14.0)) * 0.06 * data.model_height
	# En reposo, el clip sigue al estado: si se duerme, se paraliza o se cura, cambia solo.
	if _current_key == "idle" and is_alive() and idle_key() != _idle_key:
		play("idle")
	var look := _status_look()
	if look != _look:
		_set_look(look)
	match _look:
		"burn":
			var k := lerpf(BURN_STRENGTH.x, BURN_STRENGTH.y, 0.5 + 0.5 * sin(_time * 6.0))
			_overlay.albedo_color = Color.WHITE.lerp(BURN_TINT, k)
		"poison":
			var k := lerpf(POISON_STRENGTH.x, POISON_STRENGTH.y, 0.5 + 0.5 * sin(_time * 2.5))
			_overlay.albedo_color = Color.WHITE.lerp(POISON_TINT, k)
	var dizzy := is_alive() and (volatiles.has("confusion") or _visual_key == "status_confusion")
	if dizzy != (_dizzy != null):
		_set_dizzy(dizzy)
	if _dizzy:
		_dizzy.rotation = Vector3(0.18 * sin(_time * 2.0), _time * 3.5, 0.18 * cos(_time * 2.0))


## Clip de reposo según el estado: congelado, dormido, paralizado, confuso, envenenado o el normal.
## (Las quemaduras no cambian la postura.)
func idle_key() -> String:
	match status:
		MoveData.Status.FREEZE: return "status_freeze"
		MoveData.Status.SLEEP: return "status_sleep"
		MoveData.Status.PARALYSIS: return "status_paralysis"
	if volatiles.has("confusion"):
		return "status_confusion"
	match status:
		MoveData.Status.BURN: return "status_burn"
		MoveData.Status.POISON: return "status_poison"
	return "idle"


## Aspecto que toca según el estado (o el clip que se está viendo, para el visor de animaciones).
func _status_look() -> String:
	if not is_alive():
		return ""
	if status == MoveData.Status.FREEZE or _visual_key == "status_freeze":
		return "ice"
	if status == MoveData.Status.SLEEP or _visual_key == "status_sleep":
		return "sleep"
	if status == MoveData.Status.PARALYSIS or _visual_key == "status_paralysis":
		return "paralysis"
	if status == MoveData.Status.BURN or _visual_key == "status_burn":
		return "burn"
	if status == MoveData.Status.POISON or _visual_key == "status_poison":
		return "poison"
	return ""


## Congelado: capa de hielo encima (como el bloque de hielo de los juegos). Quemado: tinte rojo que palpita y
## llamitas que brotan del cuerpo mientras dure (como en los juegos de DS). Dormido: zetas que suben de la
## cabeza. Envenenado: tinte morado y burbujas. Paralizado: chispas a ratos y destellos amarillos.
func _set_look(look: String) -> void:
	_look = look
	_overlay = null
	if look in ["ice", "burn", "poison", "paralysis"]:
		_overlay = StandardMaterial3D.new()
		_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_overlay.emission_enabled = true
	if look == "ice":
		_overlay.albedo_color = FROZEN_TINT
		_overlay.emission = Color(0.45, 0.75, 1.0)
		_overlay.emission_energy_multiplier = 0.35
		_overlay.metallic_specular = 1.0
		_overlay.roughness = 0.1
	elif look == "burn":
		_overlay.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		_overlay.emission_enabled = false
		_overlay.blend_mode = BaseMaterial3D.BLEND_MODE_MUL
		_overlay.albedo_color = Color.WHITE.lerp(BURN_TINT, BURN_STRENGTH.x)
		_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		# Encima, una capa roja suave: solo con multiplicar, los verdes y azules quedaban marrones.
		var glow := StandardMaterial3D.new()
		glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.albedo_color = Color(1.0, 0.22, 0.05, 0.28)
		_overlay.next_pass = glow
	elif look == "poison":
		_overlay.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		_overlay.emission_enabled = false
		_overlay.blend_mode = BaseMaterial3D.BLEND_MODE_MUL
		_overlay.albedo_color = Color.WHITE.lerp(POISON_TINT, POISON_STRENGTH.x)
		_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	elif look == "paralysis":
		_overlay.albedo_color = Color(PARALYSIS_TINT, 0.0)
		_overlay.emission = PARALYSIS_TINT
		_overlay.emission_energy_multiplier = 1.0
		_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_apply_overlay()
	if _status_fx:
		_status_fx.queue_free()
		_status_fx = null
	match look:
		"burn": _status_fx = Fx.burning(self, data.model_height, 0.6 * data.size)
		"ice": _status_fx = Fx.ice_block(self, data.model_height, maxf(0.3, 0.55 * data.size))
		"sleep": _status_fx = Fx.sleeping(self, data.model_height)
		"poison": _status_fx = Fx.poisoned(self, data.model_height, 0.6 * data.size)
		"paralysis": _status_fx = Fx.paralyzed(self, data.model_height, 0.6 * data.size, _overlay)


func _apply_overlay() -> void:
	for m: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		m.material_overlay = _energy if _energy else _overlay


## Silueta de luz del color dado sobre el modelo (al entrar o salir de la Poké Ball): `amount` 0 = el modelo
## normal (vuelve la capa del estado), 1 = todo del color.
func set_energy(color: Color, amount: float) -> void:
	if amount <= 0.0:
		if _energy:
			_energy = null
			_apply_overlay()
		return
	if _energy == null:
		_energy = StandardMaterial3D.new()
		_energy.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_energy.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_apply_overlay()
	_energy.albedo_color = Color(color, amount)


## Sale de una Poké Ball abierta en `from` (posición global): una silueta de luz crece desde la bola hasta su
## sitio y tamaño y se desvanece (blanca al salir; roja si se escapa de la bola al intentar capturarlo).
func materialize(from: Vector3, duration := 0.45, color := Color.WHITE) -> void:
	_in_ball = true
	visible = true
	set_energy(color, 1.0)
	_model.position = to_local(from)
	_model.scale = _model_base_scale * 0.02
	var tw := create_tween().set_parallel()
	tw.tween_property(_model, "position", _model_base_pos, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(_model, "scale", _model_base_scale, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.chain().tween_method(func(a: float) -> void: set_energy(color, a), 1.0, 0.0, 0.3)
	await tw.finished
	set_energy(color, 0.0)
	_in_ball = false


## Entra en una Poké Ball abierta en `to` (posición global): se vuelve una silueta roja y se encoge hacia la bola.
## Al terminar queda oculto (visible = false) y con el modelo de vuelta en su sitio.
func dematerialize(to: Vector3, duration := 0.4) -> void:
	_in_ball = true
	var red := Color(1.0, 0.3, 0.32)
	var tw := create_tween()
	tw.tween_method(func(a: float) -> void: set_energy(red, a), 0.0, 1.0, 0.15)
	tw.tween_property(_model, "position", to_local(to), duration).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(_model, "scale", _model_base_scale * 0.02, duration).set_ease(Tween.EASE_IN)
	await tw.finished
	visible = false
	_model.position = _model_base_pos
	_model.scale = _model_base_scale
	set_energy(red, 0.0)
	_in_ball = false


func _set_dizzy(on: bool) -> void:
	if _dizzy:
		_dizzy.queue_free()
		_dizzy = null
	if on:
		_dizzy = Fx.dizzy(self, data.model_height, 0.6 * data.size)


func take_damage(amount: int) -> void:
	hp = clampi(hp - amount, 0, max_hp)
	refresh_label()
	if hp == 0:
		var ko_time := play("ko")
		# Fuera del tablero: sin anillo, nombre ni colisión (no tapa los clics) y el modelo se desvanece.
		hide_overlays()
		_fade_out(clampf(ko_time, 0.6, 1.4))
		fainted.emit(self)
	elif amount > 0:
		var duration := play("hit")
		if is_inside_tree():
			get_tree().create_timer(maxf(duration, 0.3)).timeout.connect(_back_to_idle)


func _fade_out(delay: float) -> void:
	if _gas:
		_gas.emitting = false
	if not is_inside_tree():
		_model.visible = false
		return
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_property(_model, "scale", _model.scale * 0.05, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void: _model.visible = false)


func _back_to_idle() -> void:
	if is_alive() and _proc_mode != "walk":
		play("idle")


func heal(amount: int) -> void:
	hp = clampi(hp + amount, 0, max_hp)
	refresh_label()


func face_towards(world_target: Vector3) -> void:
	var d := world_target - global_position
	if Vector2(d.x, d.z).length() > 0.01:
		_model.rotation.y = atan2(d.x, d.z)
		facing = Vector2(d.x, d.z).normalized()
		if _facing_arrow:
			_facing_arrow.rotation.y = _model.rotation.y


## Reproduce la animación de la acción `key` (idle, walk, fight_b, fight_d, hit, ko o un
## status_*). Para un ataque, en orden: el clip que data.anim_map asigne a `move_id` (p. ej.
## {"lowkick": "fight_b_kick_low"}), "<key>_<variant>" (fight_b_kick) y `key` (fight_b).
## "idle" toca el reposo de su estado (idle_key); un status_* sin clip usa el idle.
## Si el modelo no tiene ninguno (la mayoría del repo no trae animaciones), usa una
## versión procedural. Devuelve la duración.
func play(key: String, variant := "", move_id := "") -> float:
	_reset_procedural()
	_current_key = key
	if key == "idle":
		_idle_key = idle_key()
		key = _idle_key
	_visual_key = key
	if key.begins_with("status_") and not clip_for(key):
		key = "idle"
	if _anim:
		var anim_name := clip_for(key, variant, move_id)
		if anim_name:
			var anim := _anim.get_animation(anim_name)
			anim.loop_mode = Animation.LOOP_LINEAR if key in LOOPING_ANIMS else Animation.LOOP_NONE
			_anim.play(anim_name, 0.15)
			return anim.length
		# Sin clip para esta acción: congelar el anterior (si no, p. ej. el de caminar
		# seguiría en bucle) y usar la versión procedural.
		_anim.pause()
	return _play_procedural(key)


## Clip que play() usaría para esa acción, o "" si no hay y se usa la versión procedural.
func clip_for(key: String, variant := "", move_id := "") -> String:
	if _anim == null:
		return ""
	var anim_name := _find_clip(move_id) if move_id and data.anim_map.has(move_id) else ""
	if not anim_name and variant:
		anim_name = _find_clip(key + "_" + variant)
	if not anim_name:
		anim_name = _find_clip(key)
	return anim_name


## Clip del modelo para `key`, mapeado por data.anim_map. Primero uno que termine en la
## clave (los rips llevan prefijos: "model_skeleton|001fight_b"); si no, uno que la contenga,
## pero no una variante suya: pedir "fight_b" no debe sonar "fight_b_bite".
func _find_clip(key: String) -> String:
	var clip_key: String = data.anim_map.get(key, key)
	var clips := _anim.get_animation_list()
	for anim_name in clips:
		if anim_name.ends_with(clip_key):
			return anim_name
	for anim_name in clips:
		if clip_key in anim_name and not (clip_key + "_") in anim_name:
			return anim_name
	return ""


func _play_procedural(key: String) -> float:
	if key == "idle":
		_proc_mode = "idle"
	elif key == "walk" or key == "run":
		_proc_mode = "walk"
	elif key == "ko":
		var tw := create_tween().set_parallel()
		tw.tween_property(_model, "rotation:z", PI * 0.5, 0.5).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw.tween_property(_model, "position:y", _model_base_pos.y - data.model_height * 0.15, 0.5)
		return 0.6
	elif key == "hit":
		# Retrocede un poco, como encajando el golpe.
		var back := -Vector3(sin(_model.rotation.y), 0.0, cos(_model.rotation.y)) * 0.12 * data.size
		var tw := create_tween()
		tw.tween_property(_model, "position", _model_base_pos + back, 0.08).set_ease(Tween.EASE_OUT)
		tw.tween_property(_model, "position", _model_base_pos, 0.2)
		return 0.3
	elif key.begins_with("fight"):
		# Embestida hacia delante y vuelta.
		var fwd := Vector3(sin(_model.rotation.y), 0.0, cos(_model.rotation.y)) * 0.3 * data.size
		var tw := create_tween()
		tw.tween_property(_model, "position", _model_base_pos + fwd + Vector3.UP * 0.1, 0.15).set_ease(Tween.EASE_OUT)
		tw.tween_property(_model, "position", _model_base_pos, 0.25).set_ease(Tween.EASE_IN_OUT)
		return 0.8
	return 0.0


func _reset_procedural() -> void:
	_proc_mode = ""
	if _model and hp > 0:
		_model.position = _model_base_pos
		_model.scale = _model_base_scale
		_model.rotation.z = 0.0


## Muestra u oculta las letras de encima (nombre, PS, estado), p. ej. mientras una Poké Ball pasa por ahí.
## Devuelve si se veían antes, para dejarlas como estaban.
## Escenas de historia: sin anillo de equipo, cartel de PS ni flecha de orientación.
func hide_battle_marks() -> void:
	_ring.visible = false
	_label.visible = false
	_marker.visible = false
	if _facing_arrow:
		_facing_arrow.visible = false


func show_label(on: bool) -> bool:
	var was := _label.visible
	_label.visible = on
	return was


func refresh_label() -> void:
	var st := status_text()
	var boosts := stages_text()
	var vols := volatiles_text()
	_label.text = "%s\n%d/%d%s%s%s" % [TeamMember.display(base_data, gender), hp, max_hp, "  " + st if st else "",
		"\n" + boosts if boosts else "", "\n" + vols if vols else ""]


func is_transformed() -> bool:
	return data != base_data


## Transformación: copia el aspecto, tipos, stats (salvo PS), cambios de stats, habilidad y ataques
## de `t`. Conserva su tamaño en el tablero (el modelo se escala a su huella).
func transform_into(t: Unit) -> void:
	var copy: PokemonData = t.data.duplicate()
	copy.size = data.size
	copy.model_height = t.data.model_height / t.data.size * data.size
	var rot := _model.rotation.y
	_model.queue_free()
	data = copy
	stats = t.stats.duplicate()
	stages = t.stages.duplicate()
	stage_turns = t.stage_turns.duplicate()
	ability = t.ability
	moves = t.moves.duplicate()
	pp.clear()
	for mv in moves:
		pp[mv] = ceili(mv.pp / 2.0)
	choice_lock = null
	_load_model()
	_set_look(_look)  # el modelo nuevo aún no lleva la capa de hielo o el tinte
	_set_dizzy(_dizzy != null)  # a la altura del modelo nuevo
	_model.rotation.y = rot
	_label.position.y = data.model_height + LABEL_HEIGHT
	refresh_label()


func _build_visuals() -> void:
	_load_model()

	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.3
	torus.outer_radius = 0.38
	_ring.mesh = torus
	_ring.position.y = 0.02
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.albedo_color = TEAM_COLORS[team]
	_ring_mat.emission_enabled = true
	_ring_mat.emission = TEAM_COLORS[team]
	_ring.material_override = _ring_mat
	add_child(_ring)

	# Flecha que flota sobre el Pokémon activo.
	_marker = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.22
	cone.bottom_radius = 0.0
	cone.height = 0.42
	cone.radial_segments = 4
	_marker.mesh = cone
	var marker_mat := StandardMaterial3D.new()
	marker_mat.albedo_color = Color(1.0, 0.85, 0.2)
	marker_mat.emission_enabled = true
	marker_mat.emission = Color(1.0, 0.75, 0.1)
	marker_mat.emission_energy_multiplier = 1.5
	_marker.material_override = marker_mat
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_marker)
	set_active(false)

	_facing_arrow = Node3D.new()
	add_child(_facing_arrow)
	var arrow := MeshInstance3D.new()
	var tri := CylinderMesh.new()
	tri.top_radius = 0.0
	tri.bottom_radius = 0.11
	tri.height = 0.2
	tri.radial_segments = 3
	arrow.mesh = tri
	arrow.rotation.x = PI * 0.5
	arrow.position = Vector3(0, 0.04, 0.42 * RING_SCALE[data.size])
	arrow.scale = Vector3(1, 1, 0.35)
	arrow.material_override = _ring_mat
	arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_facing_arrow.add_child(arrow)

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0012
	_label.font_size = 22
	_label.outline_size = 8
	_label.modulate = TEAM_COLORS[team].lightened(0.5)
	_label.position.y = data.model_height + LABEL_HEIGHT
	add_child(_label)
	refresh_label()

	# Colisión para poder hacer clic sobre el Pokémon.
	var body := StaticBody3D.new()
	body.set_meta("unit", self)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6 * data.size, data.model_height, 0.6 * data.size)
	shape.shape = box
	shape.position.y = data.model_height * 0.5
	body.add_child(shape)
	add_child(body)


func _load_model() -> void:
	_model = data.model.instantiate()
	add_child(_model)
	_fix_fire_materials()
	_fix_palette_materials()
	_vivid_materials()
	var players := _model.find_children("*", "AnimationPlayer", true, false)
	_anim = players[0] if not players.is_empty() else null
	# Aplicar la pose de idle antes de medir: en estos modelos las animaciones
	# compensan una escala enorme del nodo raíz, así que la malla en reposo no sirve.
	play("idle")
	if _anim:
		_anim.advance(0.0)
	_normalize_model()
	_model_base_pos = _model.position
	_model_base_scale = _model.scale
	if _gas:
		_gas.queue_free()
		_gas = null
	if data.id in GAS:
		_gas = Fx.toxic_gas(self, data.model_height, GAS[data.id][0], GAS[data.id][1])
	play("idle")


## Las llamas de los rips (Rapidash, Magmar: FireCore / FireSten) traen máscaras en gris que en los
## juegos colorea un shader propio; con el material normal se ven negras. Se cambian por fuego aditivo.
func _fix_fire_materials() -> void:
	for m: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		for i in m.mesh.get_surface_count():
			var mat := m.get_active_material(i) as BaseMaterial3D
			if mat == null or not (mat.resource_name.begins_with("FireCore") or mat.resource_name.begins_with("FireSten")):
				continue
			var fire := StandardMaterial3D.new()
			fire.albedo_texture = mat.albedo_texture
			fire.albedo_color = Color(1.0, 0.85, 0.35) if mat.resource_name.begins_with("FireCore") else Color(1.0, 0.45, 0.1)
			fire.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			fire.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			fire.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			fire.cull_mode = BaseMaterial3D.CULL_DISABLED
			fire.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
			m.set_surface_override_material(i, fire)


## Algunos rips (Gastly) traen una textura de paleta cuyas coordenadas caen en el color equivocado (el cuerpo
## negro salía lavanda). El color bueno va en el nombre de cada pieza ("s_0068_Phong_0C0010_0": RRGGBB, y
## AA si es translúcida, como el gas): se usa ese color liso. Las piezas con alfa son el gas: brillan un poco.
func _fix_palette_materials() -> void:
	var hex := RegEx.create_from_string("_([0-9A-Fa-f]{6})([0-9A-Fa-f]{2})?_\\d+$")
	for m: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		var found := hex.search(m.name)
		if found == null:
			continue
		for i in m.mesh.get_surface_count():
			var mat := m.get_active_material(i) as BaseMaterial3D
			if mat == null or mat.albedo_texture == null or not mat.albedo_texture.resource_path.contains("Palette"):
				continue
			var key := found.get_string(0)
			if not _palette_mats.has(key):
				var col := Color.html(found.get_string(1))
				if found.get_string(2):
					# Gas fantasmal: halo transparente en el centro y denso en el borde, con luz propia.
					col.a = clampf(found.get_string(2).hex_to_int() / 255.0, 0.0, 1.0)
					var halo := ShaderMaterial.new()
					halo.shader = _halo_shader()
					halo.set_shader_parameter("color", col)
					halo.set_meta("vivid", true)
					_palette_mats[key] = halo
				else:
					var fixed := mat.duplicate() as StandardMaterial3D
					fixed.albedo_texture = null
					fixed.albedo_color = col
					_palette_mats[key] = fixed
			m.set_surface_override_material(i, _palette_mats[key])


static var _palette_mats := {}
static var _halo: Shader
const HALO_SHADER := "
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 color : source_color;
void fragment() {
	float rim = 1.0 - abs(dot(NORMAL, VIEW));
	float breath = 0.85 + 0.15 * sin(TIME * 2.4);
	ALBEDO = color.rgb * 1.6;
	ALPHA = clamp(color.a * (0.18 + 2.4 * rim * rim), 0.0, 1.0) * breath;
}
"


static func _halo_shader() -> Shader:
	if _halo == null:
		_halo = Shader.new()
		_halo.code = HALO_SHADER
	return _halo
## Texturas originales -> versión con más color (se calculan una vez).
static var _vivid_textures := {}
## Los rips vienen de juegos cuyo shader satura el color; con la luz normal se ven desteñidos (Charmander
## melocotón en vez de naranja). Se sube la saturación y algo el contraste: el blanco sigue blanco.
const VIVID_SATURATION := 1.6
const VIVID_CONTRAST := 1.08
## Versión ajustada de cada textura (tools/tune_textures.py): satura según cada píxel y oscurece los claros
## saturados para que el sol del tablero no los queme (Charizard salía amarillo). Si no hay, se usa la saturación de arriba.
const TUNED_DIR := "res://assets/models/pokemon/tuned/"


## Da más color a las texturas del modelo. Los materiales son del modelo
## compartido entre instancias: se marcan para no saturarlos dos veces.
func _vivid_materials() -> void:
	for m: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		for i in m.mesh.get_surface_count():
			var mat := m.get_active_material(i) as BaseMaterial3D
			if mat == null or mat.has_meta("vivid") or mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
				continue
			mat.set_meta("vivid", true)
			if mat.albedo_texture:
				mat.albedo_texture = _vivid_texture(mat.albedo_texture)
			else:  # color liso (Haunter): el mismo ajuste que tools/tune_textures.py hace a cada píxel
				mat.albedo_color = _tuned_color(mat.albedo_color)


## Igual que `tune()` en tools/tune_textures.py: los pálidos ganan color, los fuertes bajan un poco, grises y blancos
## quedan, y los claros saturados se oscurecen para que el sol no los queme.
static func _tuned_color(c: Color) -> Color:
	var w := smoothstep(0.1, 0.38, c.s) * 0.7
	var s := c.s + (0.74 - c.s) * w
	return Color.from_hsv(c.h, s, c.v * (1.0 - 0.24 * s * c.v), c.a)


static func _vivid_texture(tex: Texture2D) -> Texture2D:
	if _vivid_textures.has(tex):
		return _vivid_textures[tex]
	var tuned := TUNED_DIR + tex.resource_path.get_file()
	if tex.resource_path and ResourceLoader.exists(tuned):
		_vivid_textures[tex] = load(tuned)
		return _vivid_textures[tex]
	var img := tex.get_image()
	if img == null:
		return tex
	if img.is_compressed():
		img.decompress()
	img.adjust_bcs(1.0, VIVID_CONTRAST, VIVID_SATURATION)
	img.generate_mipmaps()
	var out := ImageTexture.create_from_image(img)
	_vivid_textures[tex] = out
	return out


func _normalize_model() -> void:
	fit_model(_model, data.model_height)


## Escala `model` (en su pose actual) para que mida `height` de alto y lo apoya en el suelo.
## También lo usan las estatuas del gimnasio.
static func fit_model(model: Node3D, height: float) -> void:
	var aabb := AABB()
	var first := true
	for m: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var a := _skinned_aabb(model, m)
		aabb = a if first else aabb.merge(a)
		first = false
	if first or aabb.size.y <= 0.0:
		return
	var s := height / aabb.size.y
	model.scale = Vector3.ONE * s
	model.position.y = -aabb.position.y * s


## AABB de la malla deformada por la pose actual del esqueleto, relativa a `model`.
## Muestrea como mucho ~2000 vértices; basta para medir el tamaño.
static func _skinned_aabb(model: Node3D, m: MeshInstance3D) -> AABB:
	var skel := m.get_node_or_null(m.skeleton) as Skeleton3D
	if m.skin == null or skel == null:
		return _relative_transform(model, m) * m.get_aabb()
	var binds: Array[Transform3D] = []
	for b in m.skin.get_bind_count():
		var bone := m.skin.get_bind_bone(b)
		if bone < 0:
			bone = skel.find_bone(m.skin.get_bind_name(b))
		binds.append(skel.get_bone_global_pose(bone) * m.skin.get_bind_pose(b))
	var to_model := _relative_transform(model, skel)
	var aabb := AABB()
	var first := true
	for surface in m.mesh.get_surface_count():
		var arrays := m.mesh.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if verts.is_empty() or bones.is_empty():
			continue
		var per := bones.size() / verts.size()
		for i in range(0, verts.size(), maxi(1, verts.size() / 2000)):
			var p := Vector3.ZERO
			for k in per:
				var w := weights[i * per + k]
				if w > 0.0:
					p += (binds[bones[i * per + k]] * verts[i]) * w
			p = to_model * p
			if first:
				aabb = AABB(p, Vector3.ZERO)
				first = false
			else:
				aabb = aabb.expand(p)
	return aabb


static func _relative_transform(model: Node3D, node: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != model and n is Node3D:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t

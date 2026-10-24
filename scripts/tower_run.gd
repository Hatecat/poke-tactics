class_name TowerRun
extends RefCounted
## Partida de la Torre de Batallas: draft inicial, pisos contra Pokémon salvajes, Poké Balls,
## experiencia y caja de capturados. Se guarda en save.cfg para continuarla después.

const DRAFT_PICKS := 4
const DRAFT_CHOICES := 6
const START_LEVEL := 5
const START_BALLS := 5
## Poké Balls que se ganan al superar un piso.
const BALLS_PER_WIN := 1
const MAX_PARTY := 6
## Probabilidad de cada rareza en las recompensas (común, poco común, rara).
const RARITY_WEIGHTS := [0.6, 0.3, 0.1]
## Probabilidad de encontrar un objeto al superar un piso (cada 5 pisos es seguro y mejor).
const ITEM_DROP_CHANCE := 0.35
## Probabilidad de que un salvaje lleve una baya, y de que Recogida encuentre algo.
const WILD_BERRY_CHANCE := 0.15
const PICKUP_CHANCE := 0.2
## Dinero (₽): inicial y por piso superado (base + por piso + por nivel de cada rival vencido).
const START_MONEY := 500
const MONEY_BASE := 150
const MONEY_PER_FLOOR := 25
const MONEY_PER_ENEMY_LEVEL := 5
## Tienda: objetos al azar por piso y precios por rareza (las piedras y las Poké Balls aparte).
const SHOP_SIZE := 6
const PRICES := [200, 500, 1200]
const STONE_PRICE := 1500
## Tipos de Ball: nombre, precio, multiplicador de captura (0 = captura segura), piso tras el cual se venden
## siempre (0 = nunca: solo en el lote al azar) y probabilidad de salir en el lote al azar de cada piso.
const BALL_KINDS := ["poke", "great", "ultra", "master"]
const BALLS := {
	"poke": {"name": "Poké Ball", "price": 200, "mult": 1.0, "unlock": 0, "shop_chance": 0.0,
		"desc": "Para capturar Pokémon salvajes durante el combate.",
		"icon": preload("res://assets/items/pokeball.png"), "color": Color(0.85, 0.12, 0.12)},
	"great": {"name": "Super Ball", "price": 600, "mult": 1.5, "unlock": 20, "shop_chance": 0.4,
		"desc": "Captura mejor que la Poké Ball (×1,5).",
		"icon": preload("res://assets/items/greatball.png"), "color": Color(0.15, 0.4, 0.9)},
	"ultra": {"name": "Ultra Ball", "price": 1200, "mult": 2.0, "unlock": 40, "shop_chance": 0.25,
		"desc": "Captura mucho mejor que la Poké Ball (×2).",
		"icon": preload("res://assets/items/ultraball.png"), "color": Color(0.12, 0.12, 0.12)},
	"master": {"name": "Master Ball", "price": 5000, "mult": 0.0, "unlock": -1, "shop_chance": 0.05,
		"desc": "Captura cualquier Pokémon salvaje sin fallar, incluso legendarios.",
		"icon": preload("res://assets/items/masterball.png"), "color": Color(0.5, 0.2, 0.7)},
}
## Prefijo de las Balls en la lista de la tienda (junto a los ids de objetos).
const SHOP_BALL_PREFIX := "ball:"
## Captura base: con el rival a tope de vida es un tercio de esto; casi debilitado, casi todo.
const CATCH_BASE := 0.6
## Experiencia por rival derrotado o capturado: su nivel × esto (para cada miembro del equipo).
const EXP_PER_ENEMY_LEVEL := 10
## Los salvajes de especies que evolucionan con piedra aparecen evolucionados desde este nivel.
const STONE_WILD_LEVEL := 30
## Un legendario salvaje cada 10 pisos (en el piso x5, o el x4 si el x5 es de entrenador).
const LEGENDARY_EVERY := 10
## Antes de este piso no aparecen legendarios (el primero, en el 25).
const LEGENDARY_FIRST_FLOOR := 25
## Cada estos pisos, un entrenador (2 pisos de salvajes y 1 de entrenador); cada 10, el líder de turno.
const TRAINER_EVERY := 3
const LEADER_EVERY := 10
## Niveles extra de los Pokémon de un líder (y de su as, el último).
const LEADER_LEVEL_BONUS := 2
const LEADER_ACE_BONUS := 2
## Recompensas de entrenadores: multiplican el dinero y la experiencia del piso.
const TRAINER_MONEY_MULT := 2.0
const LEADER_MONEY_MULT := 3.0
const TRAINER_EXP_MULT := 1.5
## Los básicos muy fuertes (Snorlax, Lapras...) solo aparecen como rivales cuando su suma de stats base
## no pasa de BASE_TOTAL_CAP + piso × BASE_TOTAL_PER_FLOOR (Snorlax, 540: desde el piso 14).
const BASE_TOTAL_CAP := 400
const BASE_TOTAL_PER_FLOOR := 10
## Probabilidad de que cada Pokémon de un entrenador lleve una baya.
const TRAINER_BERRY_CHANCE := 0.3
## Ajuste de nivel de los salvajes según la dificultad (Fácil, Normal, Difícil).
const DIFFICULTY_LEVEL_OFFSET := [-2, 0, 2]

var floor_number := 1
## Balls por tipo (ver BALL_KINDS).
var balls := {"poke": START_BALLS}
var party: Array[TeamMember] = []
var box: Array[TeamMember] = []
var topology := BoardGrid.Topology.SQUARE
var difficulty := 1
## Draft: elecciones que faltan y las 6 opciones actuales.
var picks_left := DRAFT_PICKS
var offer: Array[PokemonData] = []
## Piso en curso: rivales, campo y clima.
var enemies: Array[TeamMember] = []
## Rival del piso: {} si son salvajes; si no, un entrenador o líder (ver Trainers).
var trainer := {}
## Medallas conseguidas (nombres).
var badges: PackedStringArray = []
## Mochila: {id de objeto: cantidad}.
var bag := {}
var money := START_MONEY
## Tienda del piso actual: ids de objetos a la venta (cada uno se puede comprar una vez).
var shop: PackedStringArray = []
var biome := Biome.Kind.MEADOW
var weather := Weather.Kind.CLEAR
## Resumen del último combate (para la pantalla entre pisos).
var last_report := PackedStringArray()
## Lo destacado del último piso para el anuncio: [{"kind": level/move/evolve/item/badge/catch/money,
## "text", "item" (id, opcional)}]. No se guarda: se muestra una vez al volver del combate.
var news: Array[Dictionary] = []
var finished := false

var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.randomize()


static func basics() -> Array[PokemonData]:
	var list: Array[PokemonData] = []
	for p in Game.roster:
		if p.stage == 1 and not p.legendary:
			list.append(p)
	return list


func roll_offer() -> void:
	var pool := basics().filter(func(p: PokemonData) -> bool: return not party.any(func(m: TeamMember) -> bool: return m.data == p))
	offer.clear()
	for i in DRAFT_CHOICES:
		if pool.is_empty():
			break
		offer.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))


func pick(p: PokemonData) -> void:
	party.append(TeamMember.wild(p, START_LEVEL, rng))
	picks_left -= 1
	if picks_left > 0:
		roll_offer()
	else:
		offer.clear()
		roll_shop()


func average_level() -> int:
	var total := 0
	for m in party:
		total += m.level
	return maxi(1, roundi(float(total) / maxi(1, party.size())))


## "wild", "trainer" o "leader".
static func floor_kind(n: int) -> String:
	if n % LEADER_EVERY == 0:
		return "leader"
	if n % TRAINER_EVERY == 0:
		return "trainer"
	return "wild"


static func legendary_floor(n: int) -> bool:
	if n < LEGENDARY_FIRST_FLOOR - 1:
		return false
	var r := n % LEGENDARY_EVERY
	return floor_kind(n) == "wild" and (r == 5 or (r == 4 and floor_kind(n + 1) != "wild"))


## Texto del próximo piso para la pantalla de gestión.
func floor_preview() -> String:
	match floor_kind(floor_number):
		"leader":
			var l := Trainers.leader_for(floor_number)
			return "%s (%s)%s" % [Trainers.full_name(l), Trainers.types_text(l.types), " · revancha" if l.rematch else ""]
		"trainer":
			return "Combate contra un entrenador"
	return "Pokémon salvajes" + (" · ¡se siente algo poderoso!" if legendary_floor(floor_number) else "")


## Genera el piso actual: salvajes, entrenador o líder; campo y clima.
func prepare_floor() -> void:
	enemies.clear()
	trainer = {}
	var count := clampi(2 + floor_number / 3, 2, mini(6, party.size() + 1))
	var level := maxi(2, average_level() + floor_number / 5 + DIFFICULTY_LEVEL_OFFSET[difficulty])
	biome = rng.randi_range(0, Biome.NAMES.size() - 1)
	match floor_kind(floor_number):
		"leader":
			trainer = Trainers.leader_for(floor_number)
			_leader_team(count, level)
			biome = Biome.Kind.GYM
		"trainer":
			trainer = Trainers.random(rng)
			for species in _typed_species(trainer.types, count):
				var lv := maxi(2, level + rng.randi_range(-1, 1))
				enemies.append(_trainer_member(_evolve_for(species, lv), lv))
		_:
			var pool := _floor_pool()
			for i in count:
				var species: PokemonData = pool[rng.randi_range(0, pool.size() - 1)]
				var lv := maxi(2, level + rng.randi_range(-1, 1))
				var wild := TeamMember.wild(_evolve_for(species, lv), lv, rng)
				if rng.randf() < WILD_BERRY_CHANCE:
					wild.item = _random_item(0, true)
				enemies.append(wild)
			if legendary_floor(floor_number):
				# Mismo tope de stats que los básicos: los aves antes que Mew, y Mewtwo el último.
				var all_legends := Game.roster.filter(func(p: PokemonData) -> bool: return p.legendary)
				var legends := all_legends.filter(func(p: PokemonData) -> bool: return _base_total(p) <= _base_total_cap())
				if legends.is_empty() and not all_legends.is_empty():
					all_legends.sort_custom(func(a: PokemonData, b: PokemonData) -> bool: return _base_total(a) < _base_total(b))
					legends = [all_legends[0]]
				if not legends.is_empty():
					enemies.append(TeamMember.wild(legends[rng.randi_range(0, legends.size() - 1)], level + 3, rng))
	weather = Weather.roll(biome, rng)


## Equipo del líder: el clásico (más fuerte, con objetos), completado con Pokémon de su tipo.
func _leader_team(count: int, level: int) -> void:
	var classic: Array[PokemonData] = []
	for id: String in trainer.team:
		var p := Game.find_species(id)
		if p:
			classic.append(p)
	# Primero los de relleno (evolucionan según el nivel), al final su equipo clásico con el as.
	var extra := _typed_species(trainer.types, clampi(count - classic.size(), 0, 6 - classic.size()))
	var team: Array[PokemonData] = []
	for p in extra:
		team.append(_evolve_for(p, level + LEADER_LEVEL_BONUS))
	team.append_array(classic)
	for i in team.size():
		var ace := i == team.size() - 1
		var m := _trainer_member(team[i], level + LEADER_LEVEL_BONUS + (LEADER_ACE_BONUS if ace else 0))
		m.item = _random_item(1 if ace else 0, not ace)
		enemies.append(m)


func _trainer_member(p: PokemonData, lv: int) -> TeamMember:
	var m := TeamMember.wild(p, lv, rng)
	if rng.randf() < TRAINER_BERRY_CHANCE:
		m.item = _random_item(0, true)
	return m


## `count` especies básicas al azar de alguno de `types` (sin legendarios). Si hay pocas, también
## las que lo consiguen al evolucionar.
func _typed_species(types: Array, count: int) -> Array[PokemonData]:
	var pool := _floor_pool()
	if not types.is_empty():
		var typed := pool.filter(func(p: PokemonData) -> bool:
			return types.any(func(t: String) -> bool: return t in p.types))
		if typed.size() < 3:
			typed = pool.filter(func(p: PokemonData) -> bool: return _line_has_type(p, types))
		if not typed.is_empty():
			pool = typed
	# Sin repetir especie mientras haya otras (nada de dos Snorlax).
	var out: Array[PokemonData] = []
	var left := pool.duplicate()
	for i in count:
		if left.is_empty():
			left = pool.duplicate()
		out.append(left.pop_at(rng.randi_range(0, left.size() - 1)))
	return out


static func _base_total(p: PokemonData) -> int:
	return p.base_hp + p.base_attack + p.base_defense + p.base_sp_attack + p.base_sp_defense + p.base_speed


func _base_total_cap() -> int:
	return BASE_TOTAL_CAP + floor_number * BASE_TOTAL_PER_FLOOR


## Básicos que pueden salir como rivales en este piso (los muy fuertes, más arriba).
func _floor_pool() -> Array[PokemonData]:
	var pool := basics().filter(func(p: PokemonData) -> bool: return _base_total(p) <= _base_total_cap())
	return pool if pool.size() >= DRAFT_CHOICES else basics()


func _line_has_type(p: PokemonData, types: Array, depth := 0) -> bool:
	if p == null or depth > 3:
		return false
	if types.any(func(t: String) -> bool: return t in p.types):
		return true
	var next: Array = Array(p.evolves_to) + p.stone_evolutions.values()
	return next.any(func(id: String) -> bool: return _line_has_type(Game.find_species(id), types, depth + 1))


## Sigue la línea evolutiva mientras el nivel lo permita (un salvaje de nivel 20 puede ser Charmeleon).
func _evolve_for(species: PokemonData, level: int) -> PokemonData:
	var p := species
	while true:
		var options: Array = []
		if not p.evolves_to.is_empty() and level >= p.evolve_level:
			options = Array(p.evolves_to)
		elif not p.stone_evolutions.is_empty() and level >= STONE_WILD_LEVEL:
			options = p.stone_evolutions.values()
		if options.is_empty():
			break
		var next := Game.find_species(options[rng.randi_range(0, options.size() - 1)])
		if next == null:
			break
		p = next
	return p


## Cierra el piso. `beaten` = niveles de los rivales derrotados o capturados.
func finish_floor(victory: bool, beaten: Array[int], caught: Array[TeamMember]) -> void:
	last_report.clear()
	news.clear()
	for m in caught:
		box.append(m)
		last_report.append("¡%s (Nv. %d) capturado! Está en la caja." % [TeamMember.display(m.data, m.gender), m.level])
		news.append({"kind": "catch", "text": "¡%s capturado! (Nv. %d)" % [TeamMember.display(m.data, m.gender), m.level]})
	if not victory:
		finished = true
		Game.tower_best = maxi(Game.tower_best, floor_number)
		last_report.append("Tu equipo fue derrotado en el piso %d." % floor_number)
		return
	var total := 0
	for lv in beaten:
		total += lv * EXP_PER_ENEMY_LEVEL
	if not trainer.is_empty():
		total = int(total * TRAINER_EXP_MULT)
		last_report.append("¡Has vencido a %s!" % Trainers.full_name(trainer))
		if trainer.leader and trainer.badge and trainer.badge not in badges:
			badges.append(trainer.badge)
			last_report.append("¡Consigues la %s! (%d medalla%s)" % [trainer.badge, badges.size(), "" if badges.size() == 1 else "s"])
			news.append({"kind": "badge", "text": "¡%s! Ya tienes %d." % [trainer.badge, badges.size()]})
	last_report.append("¡Piso %d superado! Cada Pokémon gana %d de experiencia." % [floor_number, total])
	for m in party:
		var before := m.level
		var who := TeamMember.display(m.data, m.gender)
		var events := m.gain_exp(total, Game.find_species, rng)
		last_report.append_array(events)
		if m.level > before:
			news.append({"kind": "level", "text": "%s subió al nivel %d" % [who, m.level]})
		for e in events:
			if "evolucionó" in e:
				news.append({"kind": "evolve", "text": e})
			elif "aprend" in e:
				news.append({"kind": "move", "text": e})
	balls.poke = balls.get("poke", 0) + BALLS_PER_WIN
	last_report.append("Recibes %d Poké Ball. Tienes %d." % [BALLS_PER_WIN, balls.poke])
	var earned := MONEY_BASE + MONEY_PER_FLOOR * floor_number
	for lv in beaten:
		earned += lv * MONEY_PER_ENEMY_LEVEL
	if not trainer.is_empty():
		earned = int(earned * (LEADER_MONEY_MULT if trainer.leader else TRAINER_MONEY_MULT))
	money += earned
	last_report.append("Ganas %d ₽ (tienes %d ₽)." % [earned, money])
	news.push_front({"kind": "money", "text": "+%d ₽  ·  +%d Poké Ball" % [earned, BALLS_PER_WIN]})
	# Recompensas: a veces un objeto, y cada 5 pisos uno seguro (poco común o raro).
	var rewards: Array[ItemData] = []
	if not trainer.is_empty() and trainer.leader:
		rewards.append(_random_item(2))
	elif floor_number % 5 == 0:
		rewards.append(_random_item(maxi(1, _roll_rarity())))
	elif rng.randf() < ITEM_DROP_CHANCE:
		rewards.append(_random_item(_roll_rarity()))
	for m in party:
		if m.ability == "pickup" and rng.randf() < PICKUP_CHANCE:
			rewards.append(_random_item(0))
			last_report.append("¡%s encontró algo con Recogida!" % TeamMember.display(m.data, m.gender))
	for it in rewards:
		if it:
			add_item(it)
			last_report.append("Obtienes: %s." % it.display_name)
			news.append({"kind": "item", "text": "Obtienes: %s" % it.display_name, "item": it.id})
	floor_number += 1
	Game.tower_best = maxi(Game.tower_best, floor_number - 1)
	roll_shop()


## Nueva tienda: a veces Super, Ultra o Master Ball (si aún no se venden siempre), y objetos al azar hasta
## SHOP_SIZE (sin repetir; las piedras son menos frecuentes).
func roll_shop() -> void:
	shop.clear()
	for kind: String in BALL_KINDS:
		if not ball_always_sold(kind) and rng.randf() < BALLS[kind].shop_chance:
			shop.append(SHOP_BALL_PREFIX + kind)
	var pool := Items.all().duplicate()
	while shop.size() < SHOP_SIZE and not pool.is_empty():
		var it: ItemData = pool.pop_at(rng.randi_range(0, pool.size() - 1))
		if it.category == ItemData.Category.STONE and rng.randf() < 0.6:
			continue
		shop.append(it.id)


static func price(it: ItemData) -> int:
	return STONE_PRICE if it.category == ItemData.Category.STONE else PRICES[it.rarity]


func buy(it: ItemData) -> bool:
	if it.id not in shop or money < price(it):
		return false
	money -= price(it)
	shop.remove_at(shop.find(it.id))
	add_item(it)
	return true


## La Poké Ball se vende siempre; la Super Ball tras el piso 20 y la Ultra Ball tras el 40.
func ball_always_sold(kind: String) -> bool:
	var unlock: int = BALLS[kind].unlock
	return unlock == 0 or (unlock > 0 and floor_number > unlock)


## Compra una Ball: las que se venden siempre, sin límite; las del lote del piso, una vez.
func buy_ball(kind: String) -> bool:
	var lot := shop.find(SHOP_BALL_PREFIX + kind)
	if money < BALLS[kind].price or (not ball_always_sold(kind) and lot < 0):
		return false
	money -= BALLS[kind].price
	if not ball_always_sold(kind):
		shop.remove_at(lot)
	balls[kind] = balls.get(kind, 0) + 1
	return true


func ball_count(kind: String) -> int:
	return balls.get(kind, 0)


func total_balls() -> int:
	var n := 0
	for kind in balls:
		n += balls[kind]
	return n


func add_item(it: ItemData, count := 1) -> void:
	bag[it.id] = bag.get(it.id, 0) + count


func take_item(it: ItemData) -> bool:
	if bag.get(it.id, 0) <= 0:
		return false
	bag[it.id] -= 1
	if bag[it.id] <= 0:
		bag.erase(it.id)
	return true


## Equipa un objeto de la mochila (el que llevaba vuelve a la mochila).
func equip(m: TeamMember, it: ItemData) -> void:
	if not take_item(it):
		return
	if m.item:
		add_item(m.item)
	m.item = it


func unequip(m: TeamMember) -> void:
	if m.item:
		add_item(m.item)
		m.item = null


## Usa una piedra de la mochila sobre un miembro. Devuelve el mensaje ("" si no reacciona).
func use_stone(m: TeamMember, stone: ItemData) -> String:
	var text := m.evolve_with_stone(stone.id, Game.find_species)
	if text:
		take_item(stone)
	return text


func _roll_rarity() -> int:
	var r := rng.randf()
	for i in RARITY_WEIGHTS.size():
		r -= RARITY_WEIGHTS[i]
		if r < 0.0:
			return i
	return 0


func _random_item(rarity: int, berries_only := false) -> ItemData:
	var pool := Items.all().filter(func(it: ItemData) -> bool:
		return it.rarity == rarity and (not berries_only or it.category == ItemData.Category.BERRY))
	if pool.is_empty():
		pool = Items.all().filter(func(it: ItemData) -> bool: return not berries_only or it.category == ItemData.Category.BERRY)
	return pool[rng.randi_range(0, pool.size() - 1)] if not pool.is_empty() else null


## Posibilidad de captura (0-1): mejor con el rival herido y dormido/congelado, y con mejores Balls;
## los legendarios cuestan más. La Master Ball no falla.
static func catch_chance(u: Unit, kind := "poke") -> float:
	var mult: float = BALLS[kind].mult
	if mult <= 0.0:
		return 1.0
	var hp_factor := 1.0 - (2.0 / 3.0) * float(u.hp) / u.max_hp
	var status := 1.0
	if u.status in [MoveData.Status.SLEEP, MoveData.Status.FREEZE]:
		status = 2.0
	elif u.status != MoveData.Status.NONE:
		status = 1.5
	var legendary := 0.25 if u.data.legendary else 1.0
	return clampf(hp_factor * status * legendary * mult * CATCH_BASE, 0.05, 0.95)


func to_dict() -> Dictionary:
	var pack := func(list: Array[TeamMember]) -> Array: return list.map(func(m: TeamMember) -> Dictionary: return m.to_dict())
	return {
		"floor": floor_number, "balls": balls, "topology": topology, "difficulty": difficulty,
		"picks_left": picks_left, "offer": offer.map(func(p: PokemonData) -> String: return p.id),
		"party": pack.call(party), "box": pack.call(box), "finished": finished, "bag": bag,
		"money": money, "shop": shop, "badges": badges,
	}


static func from_dict(d: Dictionary) -> TowerRun:
	var run := TowerRun.new()
	run.floor_number = d.get("floor", 1)
	var saved_balls = d.get("balls", START_BALLS)
	# Partidas antiguas guardaban solo el número de Poké Balls.
	run.balls = saved_balls if saved_balls is Dictionary else {"poke": int(saved_balls)}
	run.topology = d.get("topology", BoardGrid.Topology.SQUARE)
	run.difficulty = d.get("difficulty", 1)
	run.picks_left = d.get("picks_left", 0)
	run.finished = d.get("finished", false)
	run.bag = d.get("bag", {})
	run.money = d.get("money", START_MONEY)
	run.shop = PackedStringArray(d.get("shop", []))
	run.badges = PackedStringArray(d.get("badges", []))
	for id: String in d.get("offer", []):
		var p := Game.find_species(id)
		if p:
			run.offer.append(p)
	for key in ["party", "box"]:
		var list: Array[TeamMember] = run.party if key == "party" else run.box
		for md: Dictionary in d.get(key, []):
			var m := TeamMember.from_dict(md, Game.find_species)
			if m:
				list.append(m)
	return run

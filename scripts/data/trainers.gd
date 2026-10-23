class_name Trainers
extends RefCounted
## Entrenadores de la Torre de Batallas: clases (con sus tipos), nombres al azar y los líderes
## de gimnasio de Kanto, seguidos del Alto Mando y el Campeón.

## Clase de entrenador: título, tipos de sus Pokémon y sexo (para elegir el nombre).
const CLASSES: Array[Dictionary] = [
	{"title": "Cazabichos", "types": ["bug"], "gender": 1},
	{"title": "Nadador", "types": ["water"], "gender": 1},
	{"title": "Nadadora", "types": ["water"], "gender": 2},
	{"title": "Pescador", "types": ["water"], "gender": 1},
	{"title": "Ornitólogo", "types": ["flying"], "gender": 1},
	{"title": "Pokémaníaco", "types": ["dragon", "rock", "ground"], "gender": 1},
	{"title": "Montañero", "types": ["rock", "ground"], "gender": 1},
	{"title": "Karateka", "types": ["fighting"], "gender": 1},
	{"title": "Médium", "types": ["ghost", "psychic"], "gender": 2},
	{"title": "Psíquico", "types": ["psychic"], "gender": 1},
	{"title": "Motorista", "types": ["poison"], "gender": 1},
	{"title": "Científico", "types": ["electric", "steel", "poison"], "gender": 1},
	{"title": "Supernecio", "types": ["fire", "electric"], "gender": 1},
	{"title": "Ladrón", "types": ["fire"], "gender": 1},
	{"title": "Ecologista", "types": ["grass"], "gender": 2},
	{"title": "Esquiadora", "types": ["ice", "water"], "gender": 2},
	{"title": "Belleza", "types": ["fairy", "normal"], "gender": 2},
	{"title": "Joven", "types": ["normal"], "gender": 1},
	{"title": "Chica", "types": ["normal", "grass", "fairy"], "gender": 2},
	{"title": "Domadragón", "types": ["dragon", "water"], "gender": 1},
]

const NAMES_M: PackedStringArray = [
	"Pedro", "Lucas", "Mateo", "Diego", "Javier", "Pablo", "Andrés", "Tomás", "Hugo", "Iván", "Raúl",
	"Bruno", "Marcos", "Óscar", "Rubén", "Sergio", "Álvaro", "Gonzalo", "Nico", "Dani", "Félix", "Ramón",
	"Joaquín", "Emilio", "Martín", "Rodrigo", "Simón", "Gabriel", "Leo", "Víctor",
]
const NAMES_F: PackedStringArray = [
	"Lucía", "Marta", "Elena", "Sofía", "Paula", "Clara", "Irene", "Nuria", "Carla", "Alba", "Rocío",
	"Inés", "Julia", "Sara", "Noelia", "Lorena", "Andrea", "Valeria", "Olga", "Celia", "Ana", "Eva",
	"Marina", "Teresa", "Pilar", "Aurora", "Laura", "Miriam", "Vera", "Carmen",
]

## Líderes en orden (uno cada 10 pisos); al terminar la lista se vuelve a empezar (revancha).
## `team`: su equipo clásico; si la Torre pide más Pokémon se completa con su tipo.
const LEADERS: Array[Dictionary] = [
	{"name": "Brock", "title": "Líder de gimnasio", "types": ["rock", "ground"], "badge": "Medalla Roca",
		"team": ["geodude", "onix"]},
	{"name": "Misty", "title": "Líder de gimnasio", "types": ["water"], "badge": "Medalla Cascada",
		"team": ["staryu", "starmie"]},
	{"name": "Teniente Surge", "title": "Líder de gimnasio", "types": ["electric"], "badge": "Medalla Trueno",
		"team": ["voltorb", "pikachu", "raichu"]},
	{"name": "Erika", "title": "Líder de gimnasio", "types": ["grass"], "badge": "Medalla Arcoíris",
		"team": ["victreebel", "tangela", "vileplume"]},
	{"name": "Koga", "title": "Líder de gimnasio", "types": ["poison"], "badge": "Medalla Alma",
		"team": ["koffing", "muk", "koffing", "weezing"]},
	{"name": "Sabrina", "title": "Líder de gimnasio", "types": ["psychic"], "badge": "Medalla Pantano",
		"team": ["kadabra", "mrmime", "venomoth", "alakazam"]},
	{"name": "Blaine", "title": "Líder de gimnasio", "types": ["fire"], "badge": "Medalla Volcán",
		"team": ["growlithe", "ponyta", "rapidash", "arcanine"]},
	{"name": "Giovanni", "title": "Líder de gimnasio", "types": ["ground"], "badge": "Medalla Tierra",
		"team": ["rhyhorn", "dugtrio", "nidoqueen", "nidoking", "rhydon"]},
	{"name": "Lorelei", "title": "Alto Mando", "types": ["ice", "water"], "badge": "",
		"team": ["dewgong", "cloyster", "slowbro", "jynx", "lapras"]},
	{"name": "Bruno", "title": "Alto Mando", "types": ["fighting"], "badge": "",
		"team": ["onix", "hitmonchan", "hitmonlee", "onix", "machamp"]},
	{"name": "Agatha", "title": "Alto Mando", "types": ["ghost", "poison"], "badge": "",
		"team": ["gengar", "golbat", "haunter", "arbok", "gengar"]},
	{"name": "Lance", "title": "Alto Mando", "types": ["dragon", "flying"], "badge": "",
		"team": ["gyarados", "dragonair", "dragonair", "aerodactyl", "dragonite"]},
	{"name": "Azul", "title": "Campeón", "types": [], "badge": "",
		"team": ["pidgeot", "alakazam", "rhydon", "gyarados", "arcanine", "charizard"]},
]

const TYPE_NAMES := {
	"normal": "Normal", "fire": "Fuego", "water": "Agua", "electric": "Eléctrico", "grass": "Planta",
	"ice": "Hielo", "fighting": "Lucha", "poison": "Veneno", "ground": "Tierra", "flying": "Volador",
	"psychic": "Psíquico", "bug": "Bicho", "rock": "Roca", "ghost": "Fantasma", "dragon": "Dragón",
	"steel": "Acero", "dark": "Siniestro", "fairy": "Hada",
}


## Entrenador al azar: {"title", "name", "types", "leader": false}.
static func random(rng: RandomNumberGenerator) -> Dictionary:
	var cls: Dictionary = CLASSES[rng.randi_range(0, CLASSES.size() - 1)]
	var names := NAMES_M if cls.gender == 1 else NAMES_F
	return {"title": cls.title, "name": names[rng.randi_range(0, names.size() - 1)],
		"types": cls.types.duplicate(), "leader": false}


## Líder del piso `floor_number` (múltiplo de 10). `rematch` = ya se dio la vuelta a la lista.
static func leader_for(floor_number: int) -> Dictionary:
	var index := floor_number / 10 - 1
	var d: Dictionary = LEADERS[index % LEADERS.size()].duplicate(true)
	d["leader"] = true
	d["rematch"] = index >= LEADERS.size()
	return d


## "Cazabichos Pedro", "Líder de gimnasio Brock"...
static func full_name(t: Dictionary) -> String:
	return "%s %s" % [t.title, t.name]


static func types_text(types: Array) -> String:
	if types.is_empty():
		return "variado"
	return "/".join(types.map(func(t: String) -> String: return TYPE_NAMES.get(t, t)))

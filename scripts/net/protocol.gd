class_name Protocol
extends RefCounted
## Protocolo del modo VS: versión, huella de los datos del juego y mensajes.
##
## Un mensaje es un Dictionary con el tipo en "t" y sus campos; viaja como `var_to_bytes` (sin objetos, así que
## `bytes_to_var` no puede crear nada ejecutable). Lo usan el autoload `Net` (clientes) y tools/vs_server.gd (relay).

## Súbelo cuando cambie la forma de algún mensaje o la manera de simular una acción.
const VERSION := 1
const DEFAULT_PORT := 24680
## Tamaño máximo de un paquete (un resync con el estado completo cabe de sobra).
const MAX_PACKET := 64 * 1024
const NICK_MAX := 16

## Campos obligatorios de cada mensaje y su tipo. Un mensaje con otro tipo o sin estos campos se descarta.
const FIELDS := {
	# Saludo: el que se conecta lo manda; el otro lado (anfitrión o servidor) responde welcome o reject.
	"hello": {"v": TYPE_INT, "data": TYPE_STRING, "nick": TYPE_STRING},
	"welcome": {"v": TYPE_INT, "data": TYPE_STRING},
	"reject": {"code": TYPE_STRING},
	# Rival asignado: su apodo y el lado que te toca (0 = anfitrión, 1 = invitado).
	"match": {"nick": TYPE_STRING, "side": TYPE_INT},
	# El rival se fue (abandono, desconexión...).
	"gone": {"code": TYPE_STRING},
	# Salas (F4).
	"lobby_list": {},
	"room_create": {},
	"room_join": {},
	"room_leave": {},
	# Partida: el relay los reenvía al rival tal cual.
	"ready": {},
	"start": {},
	"deploy": {},
	"intent": {},
	"digest": {},
	"resync": {},
	"surrender": {},
	"rematch": {},
}

## Mensajes de la partida: van de un jugador al otro (el relay los reenvía sin mirarlos).
const GAME_TYPES := ["ready", "start", "deploy", "intent", "digest", "resync", "surrender", "rematch"]

## Carpetas cuyos datos cambian las reglas: si no coinciden en los dos PCs, la partida se desincronizaría.
const DATA_DIRS := ["res://data/pokemon/", "res://data/moves/", "res://data/items/"]
const DATA_FILES := ["res://data/abilities.json"]

static var _data_hash := ""


## Mensaje en bytes, listo para `put_packet`.
static func encode(msg: Dictionary) -> PackedByteArray:
	return var_to_bytes(msg)


## Mensaje a partir de un paquete; {} si no es válido (tamaño, forma, tipo desconocido o campos que faltan).
static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty() or bytes.size() > MAX_PACKET:
		return {}
	var msg: Variant = bytes_to_var(bytes)
	if typeof(msg) != TYPE_DICTIONARY or typeof(msg.get("t")) != TYPE_STRING or not FIELDS.has(msg.t):
		return {}
	var fields: Dictionary = FIELDS[msg.t]
	for key: String in fields:
		if typeof(msg.get(key)) != fields[key]:
			return {}
	return msg


## Apodo limpio: sin saltos de línea ni espacios de más y como mucho NICK_MAX letras.
static func clean_nick(nick: String) -> String:
	nick = " ".join(nick.strip_escapes().split(" ", false)).left(NICK_MAX)
	return nick if not nick.is_empty() else TranslationServer.translate("Entrenador")


## Huella de los datos del juego (Pokémon, ataques, objetos y habilidades). Se calcula con el contenido de los
## recursos, no con los archivos, para que coincida entre el editor y una build exportada (allí los .tres se
## convierten a binario). Se calcula una vez.
static func data_hash() -> String:
	if not _data_hash.is_empty():
		return _data_hash
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for dir: String in DATA_DIRS:
		var files: Array[String] = []
		for file in DirAccess.get_files_at(dir):
			file = file.trim_suffix(".remap")
			if file.ends_with(".tres"):
				files.append(file)
		files.sort()
		for file in files:
			ctx.update((file + "\n" + _resource_text(load(dir + file))).to_utf8_buffer())
	for path: String in DATA_FILES:
		ctx.update(FileAccess.get_file_as_bytes(path))
	_data_hash = ctx.finish().hex_encode().left(16)
	return _data_hash


## Propiedades guardadas de un recurso como texto (en orden fijo, sin la ruta ni el script).
static func _resource_text(res: Resource) -> String:
	var out := PackedStringArray()
	for prop in res.get_property_list():
		if prop.usage & PROPERTY_USAGE_STORAGE and not prop.name.begins_with("resource_") and prop.name != "script":
			out.append("%s=%s" % [prop.name, var_to_str(res.get(prop.name))])
	return "\n".join(out)


## Huella de una lista de valores (para comparar el estado de la partida en los dos PCs). Los floats deben
## llegar ya redondeados: el último bit puede variar entre sistemas.
static func digest(values: Array) -> int:
	return var_to_str(values).hash()


## Texto para el jugador de un código de rechazo o de desconexión.
static func reason_text(code: String) -> String:
	match code:
		"version":
			return TranslationServer.translate("El otro jugador tiene otra versión del juego.")
		"data":
			return TranslationServer.translate("Los datos del juego no coinciden con los del otro jugador.")
		"full":
			return TranslationServer.translate("La partida ya tiene dos jugadores.")
		"timeout":
			return TranslationServer.translate("El otro lado no respondió a tiempo.")
		"unreachable":
			return TranslationServer.translate("No se pudo conectar. Revisa la dirección y el puerto.")
		"left":
			return TranslationServer.translate("El rival se ha ido.")
		"lost":
			return TranslationServer.translate("Se perdió la conexión.")
	return TranslationServer.translate("Error de red.")

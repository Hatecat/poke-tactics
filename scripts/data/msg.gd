class_name Msg
extends RefCounted
## Mensaje que se guarda para mostrarlo más tarde (informes de la Torre y de la historia): la frase en español y
## sus datos, sin traducir. Se traduce al mostrarlo con `Msg.text`, así sale en el idioma del momento aunque se
## cambie entre medias. Forma: [frase, dato...]; un dato puede ser otro mensaje (Array), un texto de los datos
## (nombre de ataque, de objeto...: se traduce) o un número.


## Mensaje con huecos %s / %d rellenados con `args`.
static func make(text: String, args: Array = []) -> Array:
	return [text] + args


## Mensaje con plural: la forma la elige `n` al traducir.
static func plural(singular: String, plural_text: String, n: int, args: Array = []) -> Array:
	return [[singular, plural_text, n]] + args


## Texto del mensaje en el idioma actual. Un texto suelto (guardados antiguos) se devuelve tal cual.
static func text(msg: Variant) -> String:
	if msg is String:
		return msg
	if not msg is Array or msg.is_empty():
		return ""
	var head: Variant = msg[0]
	var args := []
	for a: Variant in msg.slice(1):
		args.append(text(a) if a is Array else TranslationServer.translate(a) if a is String and a != "" else a)
	var phrase: String = TranslationServer.translate_plural(head[0], head[1], int(head[2])) if head is Array \
		else TranslationServer.translate(head)
	return phrase % args if not args.is_empty() else phrase


## Varios mensajes, uno por línea.
static func lines(msgs: Array) -> String:
	return "\n".join(PackedStringArray(msgs.map(text)))

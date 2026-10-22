class_name MoveData
extends Resource
## Definición de un ataque: alcance, área y efectos. Se edita desde el inspector.

enum Category { PHYSICAL, SPECIAL, STATUS }
## SINGLE: solo la celda objetivo.
## CIRCLE: todas las celdas a distancia <= area_size del objetivo.
## CROSS: el objetivo + area_size celdas en cada dirección de la rejilla.
## LINE: area_size celdas en línea recta desde el atacante hacia el objetivo.
enum AreaShape { SINGLE, CIRCLE, CROSS, LINE }
enum Status { NONE, POISON, SLEEP, PARALYSIS, BURN }

@export var display_name := ""
@export var type := "normal"
@export var category := Category.PHYSICAL
@export var power := 0
@export_range(0, 100) var accuracy := 100

@export_group("Alcance")
@export var range_min := 1
@export var range_max := 1
@export var area_shape := AreaShape.SINGLE
@export var area_size := 0
@export var hits_allies := false

@export_group("Efectos")
@export var status := Status.NONE
@export_range(0, 100) var status_chance := 0
@export var knockback := 0
## Fracción del daño causado que recupera el atacante.
@export_range(0.0, 1.0) var drain := 0.0

@export_group("Presentación")
## Clave de animación (se busca como subcadena en el nombre de la animación del modelo).
@export var animation := "fight_b"

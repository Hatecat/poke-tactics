class_name MoveData
extends Resource
## Definición de un ataque: alcance, área y efectos. Se edita desde el inspector.
## Los ataques de data/moves/ se generan con tools/build_data.py.

enum Category { PHYSICAL, SPECIAL, STATUS }
## SINGLE: solo la celda objetivo.
## CIRCLE: todas las celdas a distancia <= area_size del objetivo.
## CROSS: el objetivo + area_size celdas en cada dirección de la rejilla.
## LINE: area_size celdas en línea recta desde el atacante hacia el objetivo.
enum AreaShape { SINGLE, CIRCLE, CROSS, LINE }
enum Status { NONE, POISON, SLEEP, PARALYSIS, BURN, FREEZE }

## Identificador estable (se usa para guardar los equipos).
@export var id := ""
@export var display_name := ""
@export_multiline var flavor := ""
@export var type := "normal"
@export var category := Category.PHYSICAL
@export var power := 0
@export_range(0, 100) var accuracy := 100

@export_group("Alcance")
@export var range_min := 1
@export var range_max := 1
@export var area_shape := AreaShape.SINGLE
@export var area_size := 0
## Sale disparado en línea recta: choca con el primer obstáculo o Pokémon del camino.
## (Los ataques LINE son rayos: atraviesan Pokémon pero no obstáculos.)
## Todos los ataques dañan también a los aliados que alcancen.
@export var projectile := false
## El ataque afecta al propio usuario (Danza Espada, Recuperación...).
@export var targets_self := false

@export_group("Efectos")
@export var status := Status.NONE
@export_range(0, 100) var status_chance := 0
@export var knockback := 0
## Fracción del daño causado que recupera el atacante.
@export_range(0.0, 1.0) var drain := 0.0
## Fracción de los PS máximos que recupera el usuario.
@export_range(0.0, 1.0) var heal := 0.0
## Fracción del daño causado que sufre el atacante.
@export_range(0.0, 1.0) var recoil := 0.0
## Daño fijo (Sísmico, Furia Dragón...). 0 = usar la fórmula normal.
@export var fixed_damage := 0
## El usuario se debilita al usarlo (Explosión).
@export var self_ko := false
## Cambios de stats al objetivo, p. ej. {"attack": -1}. Claves: attack, defense, sp_attack, sp_defense, speed.
@export var stat_changes := {}
@export_range(0, 100) var stat_chance := 100
## Cambios de stats al propio usuario (Danza Espada, A Bocajarro...).
@export var self_stat_changes := {}

@export_group("Turno")
## Usos por combate (los PP de los juegos divididos entre 5).
@export var pp := 5
## CT extra que cuesta usarlo (recarga de Hiperrayo, carga de Rayo Solar...).
@export var extra_ct := 0

@export_group("Presentación")
## Clave de animación (se busca como subcadena en el nombre de la animación del modelo).
@export var animation := "fight_b"

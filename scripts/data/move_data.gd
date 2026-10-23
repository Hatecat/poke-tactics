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
## No puede fallar (ignora precisión y evasión).
@export var always_hits := false
## Índice de crítico extra (1 = "alta probabilidad de crítico").
@export_range(0, 3) var crit_stage := 0
## Siempre es crítico (Llovizna Helada, Llave Corsé).
@export var always_crit := false
## Probabilidad de hacer retroceder: retrasa el próximo turno del objetivo.
@export_range(0, 100) var flinch_chance := 0
## Stat del atacante que usa en lugar de Ataque/At. Esp. (p. ej. "defense" en Prensa Metálica).
@export var attack_stat := ""

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
## Fracción de los PS máximos que paga el usuario (Tambor).
@export_range(0.0, 1.0) var hp_cost := 0.0
## Cambios de stats al objetivo, p. ej. {"attack": -1}. Claves: attack, defense, sp_attack,
## sp_defense, speed, accuracy, evasion y crit (índice de crítico, 0-3).
@export var stat_changes := {}
@export_range(0, 100) var stat_chance := 100
## Cambios de stats al propio usuario (Danza Espada, A Bocajarro...).
@export var self_stat_changes := {}

@export_group("Estados volátiles y campo")
## Estado volátil que provoca en el objetivo: confusion, leechseed, yawn, taunt, nightmare, curse.
@export var volatile := ""
@export_range(0, 100) var volatile_chance := 0
## Estado volátil sobre el propio usuario: protect, endure, substitute, ingrain, aquaring,
## destinybond, charge, magnetrise.
@export var self_volatile := ""
## Efecto de campo: zonas (reflect, lightscreen, auroraveil, safeguard, mist, tailwind), trampas
## (spikes, toxicspikes, stealthrock), globales (terrenos, trickroom, gravity) o de área (haze, perishsong).
@export var field_effect := ""
## Banderas para las habilidades: contact, punch, sound, powder, bite, pulse, wind, multihit, secondary.
@export var flags: PackedStringArray = []

@export_group("Clima")
## Clima que provoca (Weather.Kind; 0 = ninguno).
@export var sets_weather := 0
## Cómo le afecta el clima: "weather_ball", "storm", "blizzard", "solar", "solar_heal", "growth".
@export var weather_tag := ""

@export_group("Turno")
## Usos por combate (los PP de los juegos divididos entre 5).
@export var pp := 5
## CT extra que cuesta usarlo (recarga de Hiperrayo, carga de Rayo Solar...).
@export var extra_ct := 0

@export_group("Presentación")
## Clave de animación (se busca como subcadena en el nombre de la animación del modelo).
@export var animation := "fight_b"

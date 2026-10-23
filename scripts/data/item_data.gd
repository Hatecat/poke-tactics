class_name ItemData
extends Resource
## Objeto: baya (se consume), equipable o piedra evolutiva. Generado por tools/build_items.py;
## la lógica de cada `effect` está en scripts/battle/items.gd.

enum Category { BERRY, HELD, STONE }

@export var id := ""
@export var display_name := ""
@export_multiline var description := ""
@export var category := Category.HELD
@export var icon: Texture2D
## Clave del efecto (heal_frac, leftovers, choice, type_boost, evolution...).
@export var effect := ""
## Parámetros del efecto, p. ej. {"type": "fire", "boost": 1.2}.
@export var params := {}
## Potencia al lanzarlo con Lanzamiento.
@export var fling_power := 30
## 0 común, 1 poco común, 2 raro (probabilidad de aparecer como recompensa en la Torre).
@export_range(0, 2) var rarity := 0

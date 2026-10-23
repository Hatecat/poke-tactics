class_name PokemonData
extends Resource
## Especie de Pokémon: stats base, movilidad en el tablero y ataques.
## Los de data/pokemon/ se generan con tools/build_data.py.

@export var id := ""
@export var species_name := ""
@export var dex_number := 0
@export var types: PackedStringArray = ["normal"]
@export var model: PackedScene
## Altura en metros a la que se escala el modelo dentro del tablero.
@export var model_height := 0.9

## Proporción de machos (0-1); -1 = sin género.
@export var male_ratio := 0.5
## Habilidades posibles (ids de data/abilities.json); la última suele ser la oculta.
@export var abilities: PackedStringArray = []

@export_group("Stats base")
@export var base_hp := 50
@export var base_attack := 50
@export var base_defense := 50
@export var base_sp_attack := 50
@export var base_sp_defense := 50
@export var base_speed := 50

@export_group("Tablero")
## Casillas que ocupa. 1 = normal; 2 = bloque 2×2 (o 3 hexágonos); 3 = 3×3 (o 7 hexágonos).
@export_range(1, 3) var size := 1
## Ajuste a las casillas de movimiento (que salen de la velocidad base).
## Por ejemplo +1 para voladores o -1 para Pokémon muy pesados.
@export var move_modifier := 0
## Diferencia de altura que puede subir de un paso (bajar permite +1).
@export var jump := 1

@export_group("Ataques")
## Set por defecto (máx. 4).
@export var moves: Array[MoveData] = []
## Todos los ataques que puede aprender.
@export var learnset: Array[MoveData] = []

@export_group("Animaciones")
## Clip a usar para cada acción cuando el modelo los nombra distinto,
## p. ej. {"hit": "dizzy"}. Claves: idle, walk, fight_b, fight_d, hit, ko.
@export var anim_map := {}

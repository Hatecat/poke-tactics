class_name PokemonData
extends Resource
## Especie de Pokémon: stats base, movilidad en el tablero y set de ataques.

@export var species_name := ""
@export var dex_number := 0
@export var types: PackedStringArray = ["normal"]
@export var model: PackedScene
## Altura en metros a la que se escala el modelo dentro del tablero.
@export var model_height := 0.9

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
@export var moves: Array[MoveData] = []

class_name FieldState
extends RefCounted
## Efectos de campo activos: zonas (Reflejo, Pantalla de Luz...), trampas (Púas, Trampa Rocas),
## terreno, Espacio Raro, Gravedad y Viento Afín. Las duraciones se cuentan en turnos de cualquier
## Pokémon (una ronda = un turno de cada uno).

const ZONE_ROUNDS := 5
const GLOBAL_ROUNDS := 5
const TAILWIND_ROUNDS := 4
## Radio de las zonas alrededor de quien las crea.
const ZONE_RADIUS := 2
const MAX_SPIKES := 3

const NAMES := { # i18n
	"reflect": "Reflejo", "lightscreen": "Pantalla de Luz", "auroraveil": "Velo Aurora",
	"safeguard": "Velo Sagrado", "mist": "Neblina", "tailwind": "Viento Afín",
	"electricterrain": "Campo Eléctrico", "grassyterrain": "Campo de Hierba",
	"mistyterrain": "Campo de Niebla", "psychicterrain": "Campo Psíquico",
	"trickroom": "Espacio Raro", "gravity": "Gravedad",
}
const COLORS := {
	"reflect": Color(1.0, 0.75, 0.3, 0.22), "lightscreen": Color(0.6, 0.85, 1.0, 0.22),
	"auroraveil": Color(0.7, 1.0, 0.95, 0.25), "safeguard": Color(0.7, 0.55, 1.0, 0.2),
	"mist": Color(0.85, 0.9, 1.0, 0.25),
	"electricterrain": Color(1.0, 0.92, 0.3, 0.16), "grassyterrain": Color(0.4, 0.9, 0.35, 0.16),
	"mistyterrain": Color(1.0, 0.6, 0.85, 0.16), "psychicterrain": Color(0.75, 0.4, 1.0, 0.16),
}
const TERRAIN_TYPES := {"electricterrain": "electric", "grassyterrain": "grass", "psychicterrain": "psychic"}

## [{"kind", "team", "cells": {Vector2i: true}, "turns"}]
var zones: Array[Dictionary] = []
## celda -> {"team": equipo que la puso, "spikes": capas, "toxic": capas, "rocks": bool}
var traps := {}
var terrain := ""
var terrain_turns := 0
var trick_room := 0
var gravity := 0
var tailwind: Array[int] = [0, 0]


func zone_at(kind: String, team: int, cells: Array[Vector2i]) -> bool:
	for z in zones:
		if z.kind == kind and z.team == team:
			for c in cells:
				if z.cells.has(c):
					return true
	return false


## Avanza un turno. Devuelve los nombres de lo que terminó.
func tick() -> PackedStringArray:
	var ended := PackedStringArray()
	for z in zones.duplicate():
		z.turns -= 1
		if z.turns <= 0:
			zones.erase(z)
			ended.append(tr(NAMES[z.kind]))
	if terrain_turns > 0:
		terrain_turns -= 1
		if terrain_turns == 0:
			ended.append(tr(NAMES[terrain]))
			terrain = ""
	if trick_room > 0:
		trick_room -= 1
		if trick_room == 0:
			ended.append(tr(NAMES.trickroom))
	if gravity > 0:
		gravity -= 1
		if gravity == 0:
			ended.append(tr(NAMES.gravity))
	for team in 2:
		if tailwind[team] > 0:
			tailwind[team] -= 1
			if tailwind[team] == 0:
				ended.append(tr(NAMES.tailwind))
	return ended


## ¿Toca el suelo? (los voladores y levitadores no, salvo con Gravedad).
func grounded(u: Unit) -> bool:
	if gravity > 0:
		return true
	return not ("flying" in u.data.types or u.ability == "levitate" or u.volatiles.has("magnetrise") or Items.floats(u))


## Texto corto de lo que hay activo (para el panel de la batalla).
func summary(alive: int) -> String:
	var parts := PackedStringArray()
	if terrain:
		parts.append("%s (~%d)" % [tr(NAMES[terrain]), ceili(float(terrain_turns) / alive)])
	if trick_room:
		parts.append("%s (~%d)" % [tr(NAMES.trickroom), ceili(float(trick_room) / alive)])
	if gravity:
		parts.append("%s (~%d)" % [tr(NAMES.gravity), ceili(float(gravity) / alive)])
	return "\n".join(parts)

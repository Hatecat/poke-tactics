# poke-tactics

Prototipo de tactics por turnos con Pokémon (estilo *Pokémon Conquest* / *FF Tactics*) hecho en **Godot 4.7**.

## Ejecutar

```bash
~/Godot_v4.7.2-stable_linux.x86_64 --path ~/Documentos/poke-tactics          # jugar
~/Godot_v4.7.2-stable_linux.x86_64 -e --path ~/Documentos/poke-tactics       # abrir el editor
```

**Flujo:** Menú principal → *Editor de equipo* (hasta 6, se guarda solo) → *Jugar* (elige cuadrícula o hexágonos)
→ despliegue en tu zona azul → combate contra un rival aleatorio del mismo tamaño. *Tabla de tipos* muestra
las 18×18 efectividades. Al apuntar un ataque se ve la efectividad y el daño estimado sobre cada objetivo.

**Movimiento:** `2 + velocidad base / 45` casillas (2 a 6), más `move_modifier` de cada especie.

**Controles:** clic para seleccionar · clic derecho/Esc para cancelar · Q/E para rotar la cámara · rueda para el zoom ·
**R** para la revancha al terminar.

## Estructura

| Ruta | Qué es |
|---|---|
| `data/pokemon/*.tres` | Especies (`PokemonData`): stats base, movimiento, salto, modelo y ataques |
| `data/moves/*.tres` | Ataques (`MoveData`): tipo, potencia, alcance, forma del área y efectos |
| `scripts/grid/board_grid.gd` | Matemática de la rejilla (cuadrada y hex): vecinos, distancias, líneas |
| `scripts/battle/turn_manager.gd` | Turnos CT estilo FFT con velocidad comprimida |
| `scripts/battle/combat.gd` | Áreas de efecto, fórmula de daño y estados |
| `scripts/battle/battle.gd` | Controlador: despliegue, input, IA, UI y animaciones |
| `scripts/game.gd` | Autoload `Game`: roster, equipo guardado (`user://save.cfg`), rival, tablero |
| `scripts/ui/` | Menú principal, editor de equipo, tabla de tipos, vista 3D y kit de UI |
| `tools/convert_models.sh` | Convierte un modelo del repo 3d-pokemon (quita Draco) |

Ataques y Pokémon se editan desde el inspector de Godot (doble clic en el `.tres`).

## Balance de velocidad

La carga de CT es `10 * velocidad^0.4`: el Pokémon más rápido actúa unas 2,2 veces por cada turno del más lento,
y Scizor frente a Bulbasaur apenas 1,1 veces. Se ajusta con `SPEED_EXPONENT` en `turn_manager.gd`
(1.0 = lineal como en los juegos principales; más bajo = más igualado).

## Añadir un Pokémon

1. Copia el `.glb` ya convertido (sin Draco) a `assets/models/pokemon/<nombre>.glb`.
2. En Godot: duplica un `.tres` de `data/pokemon/` y cambia el modelo, los stats, los tipos y los ataques.
3. Listo: todo `.tres` de `data/pokemon/` aparece solo en el editor de equipo.

**Tamaño (`size`):** 1 = una casilla; 2 = bloque 2×2 en cuadrada o triángulo de 3 en hex; 3 = 3×3 o flor de 7 hexágonos.
El alcance de los ataques se mide desde la casilla más cercana de la huella, y un área que cubra varias de sus
casillas solo lo golpea una vez.

**Animaciones:** se buscan por subcadena (`idle`, `walk`, `fight_b`, `ko`…). La mayoría de los modelos del repo
(840 de 974) no trae animaciones; para esos hay versiones procedurales (respirar, saltito al caminar,
embestida al atacar, caída al debilitarse).

# poke-tactics

Prototipo de tactics por turnos con Pokémon (estilo *Pokémon Conquest* / *FF Tactics*) hecho en **Godot 4.7**.
Los 151 Pokémon de Kanto, con sus ataques aprendibles traducidos a reglas tácticas.

## Ejecutar

```bash
~/Godot_v4.7.2-stable_linux.x86_64 --path ~/Documentos/poke-tactics          # jugar
~/Godot_v4.7.2-stable_linux.x86_64 -e --path ~/Documentos/poke-tactics       # abrir el editor
tools/export_demo.sh                                                          # builds Windows + Linux
```

**Flujo:** Menú principal → *Editor de equipo* (hasta 6 Pokémon con 4 ataques cada uno, se guarda solo) →
*Jugar* (escenario guardado, o tablero + campo al azar) → despliegue en tu zona azul → combate contra un rival
aleatorio (Pokémon y ataques) del mismo tamaño. *Editor de escenarios* crea mapas para el futuro modo historia.
*Tabla de tipos* muestra las 18×18 efectividades.

**Controles:** clic para seleccionar · clic derecho/Esc para cancelar · Q/E rotar · rueda zoom ·
WASD/flechas o botón central para mover la cámara · **R** revancha al terminar.

## Estructura

| Ruta | Qué es |
|---|---|
| `data/pokemon/*.tres` | Especies (`PokemonData`): stats, tamaño, movimiento, set por defecto, learnset, `anim_map` |
| `data/moves/*.tres` | Ataques (`MoveData`): potencia, alcance, área y efectos |
| `data/maps/*.tres` | Escenarios del juego (`MapData`), creados con el editor |
| `scripts/grid/` | Rejilla (cuadrada/hex), biomas y su generador, `MapData` |
| `scripts/battle/` | Batalla: turnos CT, combate, unidades, tablero 3D, cámara |
| `scripts/data/` | Recursos de datos y `TeamMember` (especie + ataques elegidos) |
| `scripts/game.gd` | Autoload `Game`: roster, equipo guardado (`user://save.cfg`), rival, escenarios |
| `scripts/ui/` | Menú, editor de equipo, editor de escenarios, tabla de tipos, vista 3D, kit de UI |
| `tools/` | Generación de datos, importación de modelos, Blender y exportación |
| `art/` | Fuentes de arte (`.blend`); Godot las ignora (`.gdignore`) |

## Datos de Pokémon y ataques

Se generan desde Pokémon Showdown (stats, tipos, ataques, learnsets) y PokeAPI (nombres y descripciones en español):

```bash
tools/fetch_data.sh ~/datos-pokemon                                   # descarga las fuentes
python3 tools/import_models.py ~/Documentos/modelos-godot/regular ~/datos-pokemon   # N.glb -> nombre.glb
python3 tools/build_data.py ~/datos-pokemon                           # genera data/moves y data/pokemon
```

`build_data.py` traduce cada ataque a reglas tácticas:

| En los juegos | En el tablero |
|---|---|
| Contacto | Alcance 1 |
| Rayos (Rayo Hielo, Lanzallamas, Hiperrayo…) | Línea de 3-4 casillas |
| Bombas y bolas (Bomba Lodo, Bola Sombra…) | Alcance 2-4, círculo de 1 |
| A todos los adyacentes (Terremoto, Surf…) | Círculo alrededor del usuario (algunos dañan aliados) |
| Polvos (Somnífero…) | Alcance 1-2, círculo de 1 |
| Sonido de estado (Gruñido, Canto…) | Círculo de 2 alrededor del usuario |
| Recarga / carga en dos turnos | +50 / +30 CT (el siguiente turno llega más tarde) |
| Remolino, Rugido, Cola Dragón | Empuja 3 casillas |

**Línea de visión:** los proyectiles (bolas, chorros, disparos; 127 ataques) viajan en línea recta y chocan con
el primer obstáculo, pared de terreno (≥2 niveles más alta) o Pokémon del camino. Los rayos atraviesan Pokémon pero
se cortan en obstáculos. **Todos los ataques dañan también a los aliados** que alcancen.

También: estados (incluida congelación), subidas/bajadas de stats, curación, drenaje, retroceso, daño fijo,
Explosión. Los ataques con mecánicas que aún no existen (Protección, Sustituto, clima…) se omiten.
Tamaño: ≥1,6 m o ≥150 kg ocupan 2 casillas; ≥5 m, 3. Voladores y levitadores: +1 movimiento y salto 3.

Si retocas un `.tres` a mano, ten en cuenta que volver a ejecutar `build_data.py` lo sobrescribe.

## Campos

Pradera, Bosque, Montaña, Desierto, Lago, Nieve, Cueva y Gimnasio. Cada uno genera alturas, suelos y obstáculos
(árboles, rocas, cactus, columnas, cristales) al azar, garantizando un camino entre las dos zonas. Los obstáculos
bloquean el paso; los suelos aún no tienen efectos.

## Balance de velocidad

La carga de CT es `10 * velocidad^0.4`: el Pokémon más rápido actúa unas 2,2 veces por cada turno del más lento.
Movimiento: `2 + velocidad base / 45` casillas (2 a 6), más `move_modifier`. Se ajusta en `turn_manager.gd`.

## Animaciones

El juego reproduce las acciones `idle`, `walk`, `fight_b` (físico), `fight_d` (especial), `hit` y `ko`.
Busca el clip indicado en `anim_map` del `.tres` o, si no hay, uno cuyo nombre contenga la acción; si el modelo
no lo tiene, usa una animación procedural. Solo 19 de los 151 modelos traen clips.

Para animar uno en Blender (no hace falta tocar el rig, todos tienen esqueleto):

```bash
blender --background --python tools/blender/setup_animations.py -- charmander   # crea art/blender/charmander.blend
# abre el .blend, anima cada acción en el Action Editor (Dope Sheet → Action Editor) y guarda
blender --background art/blender/charmander.blend --python tools/blender/export_animations.py
```

El export sobrescribe `assets/models/pokemon/charmander.glb`; Godot lo reimporta solo. Las acciones que dejes
sin animar no se exportan, así que esas siguen usando la animación procedural: puedes ir de a poco.

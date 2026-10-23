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
*Partida rápida* (escenario guardado, o tablero + campo + clima, cada uno elegible o al azar) → despliegue en tu zona azul → combate contra un rival
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

## Clima

| Clima | Efectos |
|---|---|
| ☀ Sol | Fuego ×1,5 · Agua ×0,5 · Rayo Solar sin carga · Trueno/Vendaval 50 % · nadie se congela · Desarrollo doble |
| ☂ Lluvia | Agua ×1,5 · Fuego ×0,5 · Trueno/Vendaval no fallan · Rayo Solar a la mitad |
| ≋ Arena | 1/16 de daño por turno salvo Roca/Tierra/Acero · Def. Esp. de Roca ×1,5 |
| ❄ Granizo | 1/16 de daño por turno salvo Hielo · Defensa de Hielo ×1,5 · Ventisca no falla |

Meteorobola cambia de tipo y dobla su potencia; Fotosíntesis, Luz Lunar y Sol Matinal curan 2/3 con sol y 1/4 con
otros climas. Danza Lluvia, Día Soleado, Tormenta de Arena, Granizo y Paisaje Nevado cambian el clima durante
4 rondas; después vuelve el clima de fondo del combate (el de la partida rápida o el del escenario).
Las reglas están en `scripts/battle/weather.gd`.

**Precisión y evasión** también son stats mejorables (Ataque Arena, Doble Equipo, Reducción…), con el mismo
tope de ±6 y la misma duración que el resto.

**Críticos:** 1/24 de base; +1 índice (ataques de crítico alto) 1/8; +2 (Foco Energía) 1/2; +3, siempre.
Hacen ×1,5 e ignoran las bajadas de ataque y las subidas de defensa. **Retroceso:** el objetivo pierde
`FLINCH_DELAY` (30) de CT, así que su próximo turno llega más tarde.

**PP:** cada ataque tiene los PP de los juegos / 5 usos por combate (`PP_DIVISOR` en `build_data.py`); sin PP solo
queda Forcejeo. **Mejoras de stats:** tope ±6 y duran 3 turnos propios (`STAGE_TURNS` en `unit.gd`).

## Estados volátiles

Confusión (2-5 turnos; 1/3 de herirse y perder el turno), Drenadoras, Bostezo, Mofa (solo ataques de daño),
Pesadilla, Maldición, Canto Mortal, Protección/Detección (hasta su próximo turno; falla más si se repite),
Aguante, Sustituto (absorbe golpes y bloquea los de estado), Arraigo (cura 1/16 pero no puede moverse ni ser
empujado), Acua Aro, Mismo Destino, Carga y Levitón. Lógica en `scripts/battle/effects.gd`.

## Efectos de campo

| Tipo | Ataques | En el tablero |
|---|---|---|
| Zonas (radio 2 alrededor de quien lo usa, 5 rondas) | Reflejo, Pantalla de Luz, Velo Aurora, Velo Sagrado, Neblina | protegen a los aliados que estén dentro |
| Trampas en casillas | Púas (x3), Púas Tóxicas, Trampa Rocas | dañan/envenenan a los rivales que las pisen (los voladores esquivan las púas) |
| Globales (5 rondas) | Campos Eléctrico/Hierba/Niebla/Psíquico, Espacio Raro, Gravedad | solo afectan a quien toca el suelo; Espacio Raro invierte la velocidad |
| Equipo | Viento Afín | velocidad ×2 a todo el equipo (4 rondas) |
| Área | Niebla, Canto Mortal | resetea los stats / todos caen en 3 turnos |

## Habilidades

Cada Pokémon tiene las de su especie (se elige en el editor de equipo; los rivales al azar). 93 de las 114 tienen
efecto: potenciadores (Mar Llamas, Agallas, Experto, Adaptable, Francotirador…), inmunidades (Levitación,
Absorbe Agua/Fuego/Elec., Pararrayos, Insonorizar…), contacto (Elec. Estática, Punto Tóxico, Cuerpo Llama…),
clima (Nado Rápido, Clorofila, Cura Lluvia, Aclimatación…), Intimidación (rivales a 2 casillas, una vez cada uno),
Robustez, Muro Mágico, Rompemoldes, Ignorante, Indefenso, etc. Las que dependen de objetos, género o cambios
(Recogida, Gula, Gran Encanto, Rastro, Regeneración…) se muestran como «sin efecto en el tablero».
Lógica en `scripts/battle/abilities.gd`.

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

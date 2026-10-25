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
| ❄ Granizo | 1/16 de daño por turno salvo Hielo · Defensa de Hielo ×1,5 · Ventisca no falla · los Voladores (no Hielo) pierden 1 casilla de movimiento |

Meteorobola cambia de tipo y dobla su potencia; Fotosíntesis, Luz Lunar y Sol Matinal curan 2/3 con sol y 1/4 con
otros climas. Danza Lluvia, Día Soleado, Tormenta de Arena, Granizo y Paisaje Nevado cambian el clima durante
4 rondas; después vuelve el clima de fondo del combate (el de la partida rápida o el del escenario).
Las reglas están en `scripts/battle/weather.gd`.

**Precisión y evasión** también son stats mejorables (Ataque Arena, Doble Equipo, Reducción…), con el mismo
tope de ±6 y la misma duración que el resto.

**Críticos:** 1/24 de base; +1 índice (ataques de crítico alto) 1/8; +2 (Foco Energía) 1/2; +3, siempre.
Hacen ×1,5 e ignoran las bajadas de ataque y las subidas de defensa. **Retroceso:** el objetivo pierde
`FLINCH_DELAY` (30) de CT, así que su próximo turno llega más tarde.

**Multigolpe** (20 ataques): cada golpe es real, con su daño, su número y su posibilidad de crítico. Doble Patada o
Huesomerang dan siempre 2; Golpes Furia, Pin Misil, Semilla Ráfaga… de 2 a 5 (35/35/15/15 %; con Encadenado,
siempre 5); Triple Axel da 3 de potencia 20, 40 y 60. La precisión se tira una vez; Banda Focus y Robustez solo
aguantan el primero, Casco Dentado y las habilidades de contacto se activan en cada golpe y el ataque se corta si
el objetivo cae. La IA y la previsión cuentan el daño medio / el rango de golpes.

**PP:** cada ataque tiene los PP de los juegos / 5 usos por combate (`PP_DIVISOR` en `build_data.py`); sin PP solo
queda Forcejeo. **Mejoras de stats:** tope ±6 y duran 3 turnos propios (`STAGE_TURNS` en `unit.gd`).

**Ataques especiales** (`special` en MoveData): **Teletransporte** salta a cualquier casilla libre a 6 o menos,
ignorando obstáculos y desniveles (la IA lo usa para huir cuando está herida). **Transformación** (alcance 3)
copia al objetivo: modelo, tipos, stats salvo los PS, cambios de stats, habilidad y ataques (con la mitad de PP);
conserva su tamaño en el tablero y su nombre. La habilidad **Impostor** lo hace sola en su primer turno con el rival
más cercano. Si capturas un Ditto transformado, sigue siendo Ditto. **Salpicadura** no hace nada (Magikarp solo sabe eso hasta el nivel 15,
cuando aprende Placaje). Si un Pokémon no tiene ningún ataque a su nivel, aprende el primero de su lista.

## Estados volátiles

Confusión (2-5 turnos; 1/3 de herirse y perder el turno), Drenadoras, Bostezo, Mofa (solo ataques de daño),
Pesadilla, Maldición, Canto Mortal, Protección/Detección (hasta su próximo turno; falla más si se repite),
Aguante, Sustituto (absorbe golpes y bloquea los de estado), Arraigo (cura 1/16 pero no puede moverse ni ser
empujado), Acua Aro, Mismo Destino, Carga y Levitón. **Atrapar**: Constricción, Atadura, Tenaza y Acoso
inmovilizan 2 turnos al objetivo (1/8 de PS por turno) y también a quien lo sujeta; se suelta si se separan
(empujón, Teletransporte) o uno cae. Giro Fuego, Torbellino y Bucle Arena solo inmovilizan al objetivo. Los
Fantasma no pueden ser atrapados. Lógica en `scripts/battle/effects.gd`.

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

## El tablero como táctica

| | Efecto |
|---|---|
| Altura | ±10 % de daño por nivel de diferencia (tope +30 % / −20 %). Los ataques a distancia ganan +1 de alcance por cada 2 niveles por encima del objetivo; atacar 2+ niveles hacia arriba resta 10 % de precisión |
| Orientación | Al terminar su turno, el jugador elige hacia dónde mira (clic en una casilla; Enter/Esc lo deja igual). La IA mira al rival más cercano |
| Flanqueo | De lado: +10 % de daño y de precisión; por la espalda: +25 % |
| Agua | Moverse cuesta 2 salvo a tipo Agua, voladores y levitadores; el tipo Agua **nada al doble** y sin la penalización por peso (Lapras: 2 en tierra, 6 nadando); Fuego ×0,8 al atacar desde el agua |
| Afinidad | Atacar desde hierba (Planta), agua (Agua), arena/tierra (Tierra), roca/cueva (Roca) o nieve/hielo (Hielo): ×1,2 a ese tipo |
| Arena | Tierra/Roca/Acero son más difíciles de golpear (−15 % de precisión) |
| Hielo | Los empujones deslizan una casilla más |

Al pasar el ratón por una casilla se ve qué hace. Constantes en `scripts/battle/effects.gd`.

**Agua y tipos pesados:** Roca, Acero y Tierra no pueden entrar en el agua (ni moviéndose, ni desplegándose,
ni empujados), salvo que también sean Agua/Volador o floten (Levitación, Levitón).

## Dificultad y equipos

| | Rivales | IA |
|---|---|---|
| Fácil | nivel 45 | 35 % de las veces elige una acción aceptable al azar |
| Normal | nivel 50 | la mejor acción según daño, estados, campo, altura y flanqueo |
| Difícil | nivel 55 | además evita destinos donde varios rivales pueden castigarla y prioriza rematar |

Tus Pokémon son siempre nivel 50. Se pueden guardar hasta 6 equipos (pestañas en el editor) y elegir con cuál
jugar al empezar una partida rápida. Constantes en `game.gd` y al principio de `battle.gd`.

## Géneros

♂/♀/sin género según la proporción real de cada especie (se elige en el editor; los rivales al azar).
Atracción (50 % de no poder atacar cada turno, 5 turnos), Seducción, Gran Encanto y Rivalidad.

## Torre de Batallas

Draft de 4 Pokémon (en cada ronda, 1 de 6 básicos al azar) a nivel 5. Cada piso es un combate contra rivales
de nivel parecido al de tu equipo (evolucionados si les toca):

- **Salvajes** (2 de cada 3 pisos): se pueden capturar; un legendario cada 10 pisos desde el 25 (piso x5, o x4
  si el x5 es de entrenador), con el mismo tope de stats que los básicos (Mewtwo, desde el 35).
- **Entrenadores** (pisos múltiplos de 3): clase al azar con su tipo (Cazabichos, Nadador/a, Pescador,
  Ornitólogo, Pokémaníaco, Montañero, Karateka, Médium, Científico, Supernecio, Esquiadora, Domadragón…) y un
  nombre al azar. No se pueden capturar sus Pokémon; dan el doble de dinero y +50 % de experiencia.
- **Líderes** (cada 10 pisos): Brock, Misty, Teniente Surge, Erika, Koga, Sabrina, Blaine y Giovanni, luego el
  Alto Mando (Lorelei, Bruno, Agatha, Lance) y el Campeón Azul; después, revancha desde el principio. Llevan su
  equipo clásico (completado con su tipo), +2 niveles, el as +4 y objetos; combaten en el gimnasio. Dan el triple
  de dinero, un objeto raro y su medalla.

Clases, nombres y líderes en `scripts/data/trainers.gd`. Los básicos muy fuertes (Snorlax, Lapras, Scyther…) solo salen como rivales en pisos
altos (suma de stats base ≤ 400 + 10 × piso) y un entrenador no repite especie.

Al volver de cada piso, una ventana de **novedades** destaca dinero, medallas, capturas, objetos, evoluciones,
subidas de nivel y ataques nuevos.
Empiezas con 5 Poké Balls y ganas 1 por piso: lanzar una es tu acción del turno (alcance 4, captura mejor si el
rival está herido y dormido/congelado; al apuntar se ve el alcance). Captura: 0,6 × (1 − ⅔ × vida restante) ×
estado (×2 dormido/congelado, ×1,5 otro) × Ball (Super ×1,5, Ultra ×2; la Master Ball no falla), entre 5 % y 95 %
(los legendarios, ×0,25). Si acierta, el Pokémon se convierte en una
Poké Ball que se agita hasta 3 veces; si escapa, reaparece entre humo. Entre pisos el equipo se cura y gana experiencia (nivel del rival × 10
por cada derrotado o capturado), sube de nivel, aprende ataques (de sus listas por nivel) y evoluciona (las de
intercambio/amistad, a nivel 30; las de piedra, usando la piedra). Cada evolución se ve con una animación que se puede
*Cancelar* (con piedra, no se gasta); si se cancela, vuelve a intentarlo al subir de nivel o con *Evolucionar* en su ficha. Puedes cambiar miembros por capturados (máx. 6 en el equipo) y elegir
4 ataques de los aprendidos. La subida se guarda y se puede continuar; se guarda el récord de pisos.
Lógica en `scripts/tower_run.gd`, pantalla en `scripts/ui/tower.gd`.

## Objetos

89 objetos (`tools/build_items.py` → `data/items/`, sprites de PokeAPI en `assets/items/`), lógica en
`scripts/battle/items.gd` (pasivos) y `effects.gd` (los que se consumen o reaccionan):

- **Bayas** (se consumen): Aranja, Zidra, curativas de estado y Ziuela, Zanama (PP), las de PS bajos (+1 a un stat)
  y las 18 que reducen a la mitad un golpe supereficaz de su tipo.
- **Equipables**: Restos, Lodo Negro, Banda/Cinta Focus, Vidasfera, Cinta/Gafas/Pañuelo Elección (te atan al primer
  ataque), Cinta Experto, Cinta Fuerte, Gafas Especiales, los 18 potenciadores de tipo, Periscopio, Garra Rápida
  (+30 CT a veces), Roca del Rey, Campana Concha, Casco Dentado, Mineral Evolutivo, Chaleco Asalto, Refleluz,
  Polvo Brillo, Lupa, Raíz Grande, Hierbas Blanca/Mental, Toxisfera, Llamasfera, Globo Helio, Botas Gruesas,
  rocas de clima y Piedra Eterna.
- **Piedras** (Fuego, Agua, Trueno, Hoja, Lunar): en la Torre, las evoluciones por piedra necesitan la piedra.
- **Ataques**: Ladrón/Antojo, Desarme, Truco/Trapicheo, Picadura/Picoteo, Calcinación, Lanzamiento, Reciclaje.
- **Habilidades**: Recogida, Gula, Cosecha, Liviano, Nerviosismo, Viscosidad.

En Partida rápida se elige en el editor de equipo; en la Torre hay mochila (35 % de recibir un objeto por piso,
uno poco común o raro garantizado cada 5, Recogida al 20 %) y los salvajes a veces llevan bayas.

**Dinero y tienda (Torre)**: empiezas con 500 ₽ y cada piso da 150 + 25 × piso + 5 × nivel de los rivales. En la
gestión, el recuadro *Tienda* (junto al equipo) vende siempre Poké Balls (200 ₽), Super Balls (600 ₽) tras el
piso 20 y Ultra Balls (1200 ₽) tras el 40. Cada piso añade un lote al azar que se compra una vez: a veces Super
(40 %), Ultra (25 %) o Master Ball (5 %, 5000 ₽) si aún no se venden siempre, y 6 objetos (200/500/1200 ₽ según
rareza, piedras 1500 ₽).

## Velocidad de combate

En Opciones (menú principal) y en la Pausa (Esc): de 20 % a 200 % (200 % es la velocidad normal). Escala todo el
combate (animaciones, esperas, partículas) con `Engine.time_scale`; los menús y el movimiento manual de la cámara
van siempre a velocidad normal. Se guarda en `save.cfg`.

## Sonido

Autoload `Audio` (`scripts/audio.gd`): buses Música / Efectos / Ambiente, volúmenes en *Opciones* del menú.

| | Origen |
|---|---|
| Efectos (golpes por tipo, pasos por suelo, rayos, interfaz, fanfarrias) | Paquetes de [Kenney](https://kenney.nl) (CC0), seleccionados con `tools/import_sfx.py` |
| Música (menú, combate, cueva, gimnasio, editor) y ambientes (lluvia, viento, granizo) | Compuestos por código con `tools/make_audio.py` (numpy + ffmpeg) |
| Gritos | Sintetizados en `audio.gd`: uno propio por especie (grave si es grande), siempre el mismo |

Para cambiar la música: edita las llamadas a `song(...)` (tonalidad, escala, acordes, tempo, semilla) en
`make_audio.py` y vuelve a ejecutarlo.

## Balance de velocidad

La carga de CT es `10 * velocidad^0.4`: el Pokémon más rápido actúa unas 2,2 veces por cada turno del más lento.
Movimiento: `2 + velocidad base / 45` casillas (2 a 6), más `move_modifier`. Se ajusta en `turn_manager.gd`.

## Animaciones

El juego reproduce las acciones `idle`, `walk`, `fight_b` (físico), `fight_d` (especial), `hit` y `ko`.
Busca el clip indicado en `anim_map` del `.tres` o, si no hay, uno cuyo nombre contenga la acción; si el modelo
no lo tiene, usa una animación procedural. Los 151 modelos traen clips; a los que venían sin esqueleto en el
rip se lo pone `setup_animations.py` (ver más abajo).

Cada ataque indica además con qué parte del cuerpo se hace (`anim_variant` del `.tres`): el juego prueba
primero `fight_b_<variante>` y, si el modelo no lo tiene, el `fight_b` genérico (igual con `fight_d`). Así cada
Pokémon solo anima las variantes que le encajan; Charmander no necesita `wing` y sus ataques de alas usan `fight_b`.

| Acción | Variantes |
|---|---|
| `fight_b` (físico) | `bite`, `claw`, `punch`, `kick`, `tail` (cola o lianas), `wing`, `horn` (cuerno, pico, aguijón), `body` (placajes) |
| `fight_d` (especial/estado) | `breath` (sale de la boca), `sound`, `powder`, `mind` (psíquico/fantasma), `boost` (se potencia a sí mismo) |

Las asigna `anim_variant()` en `tools/build_data.py`. Para recalcularlas sin regenerar los ataques:
`python3 tools/assign_anim_variants.py` (`--dry-run` para ver el reparto; respeta las puestas a mano salvo con `--force`).

La variante dice qué tipo de ataque es, no cómo se anima: cada Pokémon anima su clip a su manera (el
`fight_d_mind` de Gengar lanza con las manos y el de Mightyena por la boca). Para casos concretos, el
`anim_map` del Pokémon admite excepciones, que se prueban antes que la variante:

```
anim_map = {
"lowkick": "fight_b_kick_low",
"lowsweep": "fight_b_kick_low",
"fight_d_mind": "fight_d_breath"
}
```

Por ataque (`lowkick`: Patada Baja usa un segundo clip de patada) o por variante (todo lo `mind` usa el clip
de boca). Orden de búsqueda: excepción del ataque → `fight_b_<variante>` → `fight_b` → procedural.
`build_data.py` conserva estas entradas al regenerar.

Para animar uno en Blender:

```bash
blender --background --python tools/blender/setup_animations.py -- charmander   # crea art/blender/charmander.blend
blender --background --python tools/blender/setup_animations.py -- charmander claw bite tail breath   # añade variantes
blender --background --python tools/blender/setup_animations.py -- blaziken kick kick_low   # segundo clip de patada
# esqueleto con los nombres de Charmander, bípedo (Charmeleon, Nidoking, Rhydon...) o cuadrúpedo
# (Arcanine, Rapidash, Venusaur, Nidorino, Slowpoke...): anima idle, walk y ataques solo
blender --background art/blender/charmeleon.blend --python tools/blender/animate_pokemon.py
# abre el .blend, anima cada acción en el Action Editor (Dope Sheet → Action Editor) y guarda
blender --background art/blender/charmander.blend --python tools/blender/export_animations.py
```

Las serpientes (Ekans, Arbok, Dratini, Dragonair, y también Caterpie y Weedle) no tienen patas y en el rip están de pie y rectas como un palo;
las anima otro script, que pone la postura (cola enroscada en el suelo y cuello alzado como una cobra) y la mueve
desde ahí (Ekans reposa enroscado en espiral; Caterpie y Weedle avanzan como orugas, estirando y encogiendo el
cuerpo). Como enroscadas abultan menos que su largo, `COILED_HEIGHT` en `tools/build_data.py` reduce su altura:

```bash
blender --background art/blender/ekans.blend --python tools/blender/animate_serpent.py
```

El resto de los que no tienen patas (Magikarp, Tentacool, Voltorb, Butterfree, Gyarados, Staryu...) usan un
animador genérico: el cuerpo se balancea y embiste desde los huesos raíz y cada apéndice (cola, antenas,
tentáculos, aletas, alas) ondula a lo largo de su cadena. Solo hace idle, walk, fight_b y fight_d; `TWEAKS`
ajusta la amplitud y el ritmo por especie: las mariposas flotan y baten las dos alas a la vez, Voltorb y Electrode
avanzan rodando, Paras y Parasect andan con las cuatro patas en diagonal y la concha de Cloyster va con el cuerpo:

```bash
blender --background art/blender/magikarp.blend --python tools/blender/animate_generic.py
```

Koffing y Weezing no traen esqueleto: `setup_animations.py` les pone uno (`AUTO_RIG`) con un hueso para el cuerpo
y otro para cada pieza suelta que sobresale (las nubes de gas, la cabeza pequeña de Weezing), y el animador
genérico los hace flotar y hincharse en el ataque especial. En el juego sueltan además gas tóxico todo el rato
(`GAS` en `unit.gd`, `Fx.toxic_gas`). Igual se montan Exeggcute (un hueso por huevo), Gastly (que en el juego suelta
gas morado oscuro) y Magneton.

Los demás sin esqueleto (Chansey, Snorlax, Lapras, Ponyta, Goldeen...) llevan uno de plantilla:
`tools/blender/rig_templates.py` da la posición de cada hueso en alturas del modelo, con los nombres de
Charmander, y `setup_animations.py` lo monta y pesa cada vértice por su distancia a los huesos (el tronco
cuenta como más cerca, para que las patas no se lleven la barriga). Después se animan con `animate_pokemon.py`
(bípedos y cuadrúpedos) o `animate_generic.py` (peces, cangrejos, Golbat, Shellder...). Para medir un modelo
nuevo, render ortográfico de frente, de lado y desde arriba con una rejilla de 0,1 alturas.

El export sobrescribe `assets/models/pokemon/charmander.glb`; Godot lo reimporta solo. Las acciones que dejes
sin animar no se exportan, así que esas siguen usando la animación procedural: puedes ir de a poco.

Ajustes que no se deducen del esqueleto:
- `PROPS` en `setup_animations.py`: accesorios sueltos que se cuelgan de un hueso al importar (las cucharas de
  Alakazam en sus manos, la cría de Kangaskhan en la bolsa).
- `TWEAKS` en `animate_pokemon.py`: postura por especie (cuánto bajan, se abren y se doblan los brazos, piernas
  más cerradas, pecho bajo y manos bajo los hombros en cuadrúpedos de patas cortas...). Las colas que atraviesan el suelo se levantan solas y las patas de cuadrúpedo que no lo tocan, se bajan.
- `STYLES` en `animate_pokemon.py`: forma de moverse distinta de la de su esqueleto. `fly` (Beedrill) vuela con
  las piernas colgando y aletea rápido los huesos de `wings`; las aves (Pidgey, Zapdos...) usan el mismo
  estilo con `flap` (fotogramas por batido y grados) para un aleteo lento y amplio; `lotus` (Abra) levita con las piernas cruzadas;
  `sit` (Persian) se sienta como un gato en el reposo. En el juego el modelo se apoya igualmente en el suelo
  (como las aves de los rips): se ve el vaivén pero no la altura de vuelo.
- Las llamas de los rips (`FireCore` / `FireSten`, Rapidash y Magmar) traen máscaras en gris: `Unit` las cambia
  en el juego por un material de fuego.

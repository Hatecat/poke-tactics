# poke-tactics

Prototipo de tactics por turnos con Pokémon (estilo *Pokémon Conquest* / *FF Tactics*) hecho en **Godot 4.7**.
Los 151 Pokémon de Kanto, con sus ataques aprendibles traducidos a reglas tácticas.

## Ejecutar

```bash
~/Godot_v4.7.2-stable_linux.x86_64 --path ~/Documentos/poke-tactics          # jugar
~/Godot_v4.7.2-stable_linux.x86_64 -e --path ~/Documentos/poke-tactics       # abrir el editor
tools/export_demo.sh                                                          # builds Windows + Linux
```

**Historia:** *Kanto: Huellas en la niebla*. Cristina, de Pueblo Lavanda, sale de viaje con Eevee y Pidgey
y un Gengar misterioso que reconoce a su madre. Escenas 3D con diálogos al estilo de *FF Tactics* entre
combates; ver [Modo historia](#modo-historia).

**Flujo:** Menú principal → *Editor de equipo* (hasta 6 Pokémon con 4 ataques cada uno, se guarda solo) →
*Partida rápida* (escenario guardado, o tablero + campo + clima, cada uno elegible o al azar) → despliegue en tu zona azul → combate contra un rival
aleatorio (Pokémon y ataques) del mismo tamaño. *Editor de escenarios* crea escenarios fijos.
*Tabla de tipos* muestra las 18×18 efectividades. *Combate VS* enfrenta a dos jugadores por Internet o por IP;
ver [Combate VS](#combate-vs-multijugador).

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
| `data/story/*.json` | Capítulos del modo historia: personajes, equipo inicial y pasos (escenas y combates) |
| `scripts/story/` | Modo historia: partida (`StoryRun`), escenas (`cutscene.gd`), cuadro de diálogo y figuras |
| `assets/portraits/` | Retratos de los personajes para los diálogos (`<id>.png`) |
| `locale/<tema>/` | Traducciones gettext por tema (`<tema>.pot` + `<idioma>.po`); guía para traducir en `locale/LEEME.md` |
| `scripts/net/` | Modo VS: red (`Net`, autoload), protocolo, inicio de partida (`VsMatch`) y servidor de salas (`VsRelay`) |
| `scripts/ui/` | Menú, editor de equipo, editor de escenarios, tabla de tipos, vista 3D, kit de UI (`UiKit`, `UiDialog`) |
| `tools/` | Generación de datos, importación de modelos, Blender y exportación |
| `art/` | Fuentes de arte (`.blend`); Godot las ignora (`.gdignore`) |

## Datos de Pokémon y ataques

Se generan desde Pokémon Showdown (stats, tipos, ataques, learnsets) y PokeAPI (nombres y descripciones en español):

```bash
tools/fetch_data.sh ~/datos-pokemon                                   # descarga las fuentes
python3 tools/import_models.py ~/Documentos/modelos-godot/regular ~/datos-pokemon   # N.glb -> nombre.glb
python3 tools/build_data.py ~/datos-pokemon                           # genera data/moves y data/pokemon
python3 tools/build_items.py ~/datos-pokemon                          # genera data/items
python3 tools/build_translations.py ~/datos-pokemon                   # actualiza las traducciones (locale/)
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

Pradera, Bosque, Montaña, Desierto, Lago, Nieve, Cueva, Gimnasio, Pantano, Ciudad, Laboratorio, Volcán, Playa,
Cementerio, Estudio, Biblioteca, Aeropuerto y Cueva submarina. Además, **Test**: la Pradera tal cual (mismo
generador, suelos, obstáculos, cielo, clima y música); no sale al elegir campo al azar ni en la Torre.
En combate y en el editor el mapa se ve a pantalla completa: el tablero queda encuadrado entero y rodeado de un
campo más oscuro de su propio bioma (bosque de pinos, dunas con cactus, calles con edificios, gradas del gimnasio…).
Cada uno genera alturas, suelos y obstáculos (árboles, rocas, cactus, columnas, cristales, edificios, farolas,
máquinas, incubadoras, fumarolas, sombrillas, lápidas, estanterías, focos, cámaras, aviones, corales) al azar, garantizando un camino entre
las dos zonas para todos: también para los que no pueden entrar al agua (Roca, Acero, Tierra) y para los de talla
grande (hasta 3×3, como Onix). Los ríos se cruzan por vados o puentes de madera. Los obstáculos bloquean el paso.
La **lava** solo la pisan los de tipo Fuego y los que vuelan, y potencia los ataques de Fuego desde ella.

El **Gimnasio** tiene un estilo por tipo (18) y uno neutral: colores del suelo, líneas y columnas, y rasgos como
piscinas (Agua, Veneno), fosos de lava (Fuego), jardín con árboles (Planta, Bicho), placas de hielo, arena o roca, y
cristales o árboles secos en lugar de columnas. Cada estilo con columnas tiene su propia forma: mármol estriado
(neutral), pilar liso (Normal), poste de dojo con cuerdas (Lucha), columna con alas (Volador), pararrayos con
bobinas encendidas (Eléctrico), anillos de oro y cuernos (Dragón), obsidiana con vetas rojas (Siniestro), acero
remachado (Acero), basalto con brasas (Fuego), mármol con olas (Agua) y anillos tóxicos (Veneno). Los cristales
toman el color del tipo (Hielo, Psíquico, Hada), los árboles secos de Fantasma llevan un fuego fatuo, las placas de
hielo son azules y agrietadas, y en Planta y Bicho la arena es de césped segado con jardines de hierba alta a los lados. En la Torre usa el tipo del líder o entrenador; en Partida rápida
sale al azar, y en el editor de escenarios se elige.
La arena es un estadio: Poké Ball pintada en el centro, tarimas escalonadas del líder y del retador, luz LED y
barandilla en el borde, gradas con público que salta, muros con estandartes, focos en las esquinas, la medalla
sobre el sitio del líder con dos estatuas de piedra del Pokémon emblema del tipo, la puerta de entrada y adornos
del tipo (braseros, fuentes, bobinas, sacos de boxeo, orbes, engranajes...). Las gradas del lado de la cámara se
ocultan para no tapar (`scripts/battle/gym_dressing.gd`).

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

## Modo historia

*Historia* en el menú empieza (o continúa) el capítulo. Está hecho el **Capítulo 1** completo:
la mañana en Pueblo Lavanda, la discusión con su padre, el ataque de los rufianes en la Ruta 8 (combate en el
que Gengar llega como aliado), la reacción de Gengar ante la madre, la revelación del padre esa noche, la
videollamada con su hermano y la salida por la Ruta 12 (combate contra Pokémon salvajes en la niebla). El
progreso se guarda en cada paso.

- **Escenas:** el lugar en 3D con sus participantes (los Pokémon con su modelo; las personas, con una figura
  provisional de colores). Abajo, el cuadro de diálogo con el retrato de quien habla; clic, Enter o Espacio
  pasan la línea, y *Saltar escena* (o Esc) la salta entera. Lo que Cristina percibe de Gengar sale en cursiva
  morada: Gengar no habla, transmite sentimientos.
- **Combates:** el equipo de Cristina sube de nivel con la experiencia (como en la Torre) y aprende ataques;
  si ya conoce cuatro, la escena siguiente pregunta cuál olvidar (o no aprender el nuevo).
  Un combate puede tener eventos a mitad (diálogos y aliados que juega la IA). Si pierdes, se reintenta.
- **Retratos:** `assets/portraits/<id>.png` (cristina, papa, mama, hermano, rufian, rufiana, eevee, pidgey, gengar). Si
  no hay, se dibuja uno provisional con la inicial y el color del personaje.
- **Escribir capítulos:** cada capítulo es un JSON en `data/story/` (`capitulo1.json`). La lista de órdenes del
  guion (decir, siente, narrar, mover, mirar, emocion, anim, aparecer, irse, camara, esperar, fundido, musica...)
  está al principio de `scripts/story/cutscene.gd`; los eventos de combate, en `_story_events` de `battle.gd`.
  Un lugar con la misma `semilla` genera el mismo tablero en la escena y en el combate.

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

## Combate VS (multijugador)

Uno contra uno entre dos PCs, con tu equipo del editor. Menú principal → **Combate VS**: escribe tu apodo, elige
equipo (de 1 a 6 Pokémon; en VS todos luchan a **nivel 50**, sin experiencia, evoluciones ni Poké Balls) y
conéctate de una de dos formas:

- **Por Internet** (recomendado): escribe la dirección del servidor de salas (`dirección` o `dirección:puerto`;
  se guarda) y *Conectar*. Nadie tiene que abrir puertos. En el vestíbulo puedes:
  - *Partida rápida*: entras en la primera sala pública que espera rival o se abre una nueva.
  - *Crear una sala* con nombre; si marcas *Privada* no sale en la lista y se entra con su **código** de 5
    letras (se ve mientras esperas: pásaselo a tu rival).
  - *Entrar con un código*, o pulsar *Entrar* en la lista de salas públicas (nombre, anfitrión y ping; se
    actualiza sola).
- **IP directa**: uno pulsa *Alojar* (puerto 24680 por defecto; muestra sus IP de la red local) y el otro escribe
  esa IP y pulsa *Unirse*. En la misma red local funciona tal cual; por Internet, el anfitrión tiene que abrir
  (redirigir) ese puerto **UDP** en su router.

**Sala:** se ve al rival y su ping. El anfitrión (quien creó la sala) elige tablero (cuadrado o hexagonal) y
escenario (o al azar); cuando los dos pulsan **¡Listo!** empieza el combate, con el mismo mapa, clima y orden de
turnos en los dos PCs. Cada uno coloca a su equipo en su zona azul y se juega por turnos de CT como siempre: cuando
le toca al rival, ves lo que hace.

- **Reloj:** 60 s por turno (se ve arriba, en rojo y con aviso sonoro los últimos 10 s). Si se acaba, tu Pokémon
  espera; **3 turnos seguidos** sin jugar = derrota. La pausa (Esc) no para el combate; desde ella puedes
  *Rendirte*.
- **Cortes de conexión:** por servidor, el juego reconecta solo y al que se cae se le espera 60 s (los dos ven el
  aviso); si no vuelve, el otro gana por abandono. Por IP directa no hay reconexión: un corte termina la
  partida como abandono.
- **Final:** victoria, derrota, empate, abandono o rendición, con *Revancha* (mismos equipos y tablero, mapa
  nuevo) y *Salir*. Tu **marcador** (victorias · derrotas · empates, en total y contra cada rival) se guarda en
  este PC y se ve en la pantalla VS, en la sala y al terminar.
- Los dos tienen que tener **la misma versión** del juego y **los mismos datos** (Pokémon, ataques, objetos): si no,
  la conexión se rechaza con un mensaje claro. Si las dos partidas dejaran de coincidir (se comprueba una huella
  del estado tras cada acción), el combate termina sin resultado y lo dice.

Cómo funciona: cada PC simula el combate entero con la misma semilla y solo viajan las acciones (`apply_intent`
en `battle.gd`), con su huella. El anfitrión valida los equipos; el servidor solo reenvía y pone límites. Un
cliente modificado podría hacer trampas: para un juego entre amigos se acepta. Detalle en `scripts/net/`.

### Montar el servidor de salas

El servidor es el mismo proyecto sin gráficos (`scripts/net/vs_relay.gd`). Usa **UDP 24680** (o el puerto que
le pases); necesita una máquina con IP pública (un VPS Linux pequeño basta: no simula combates, solo reenvía).

```bash
# Probarlo desde el proyecto (en tu PC: los jugadores ponen 127.0.0.1 o tu IP)
~/Godot_v4.7.2-stable_linux.x86_64 --headless --path . --script tools/vs_server.gd -- 24680

# Build para el VPS (preset "Linux Server": arranca directamente en el servidor)
~/Godot_v4.7.2-stable_linux.x86_64 --headless --path . --export-release "Linux Server" \
    ../poke-tactics-builds/server/poke-tactics-server.x86_64
scp ../poke-tactics-builds/server/poke-tactics-server.x86_64 usuario@mi-vps:/opt/poke-tactics/
ssh usuario@mi-vps '/opt/poke-tactics/poke-tactics-server.x86_64 --headless -- 24680'   # prueba a mano
```

Argumentos tras `--`: el puerto y, opcional, `--quiet` (sin registro de conexiones y salas). La build y el juego
tienen que salir **del mismo commit**: si no, el servidor rechaza a los jugadores por versión o datos.

Como servicio (systemd), en `/etc/systemd/system/poke-tactics-vs.service`:

```ini
[Unit]
Description=Poké Tactics: servidor de salas VS
After=network-online.target
Wants=network-online.target

[Service]
User=poketactics
Environment=POKE_TACTICS_NO_SAVE=1
ExecStart=/opt/poke-tactics/poke-tactics-server.x86_64 --headless -- 24680
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
sudo useradd --system --create-home poketactics
sudo chmod +x /opt/poke-tactics/poke-tactics-server.x86_64
sudo systemctl daemon-reload && sudo systemctl enable --now poke-tactics-vs
sudo ufw allow 24680/udp          # y abre el mismo puerto UDP en el cortafuegos del proveedor del VPS
journalctl -u poke-tactics-vs -f  # registro: quién entra, salas, partidas, cortes
```

Límites (en `vs_relay.gd`): 256 jugadores, 128 salas, 60 mensajes por segundo por jugador, saludo en 8 s.

**Pruebas del modo VS** (todas con `POKE_TACTICS_NO_SAVE=1`): `tools/vs_smoke.sh` (red: saludo, rechazos,
servidor, salas, reconexión e inundación), `tools/vs_match.sh partidas semilla puerto` (partidas enteras entre dos
procesos con la IA; `VS_RELAY=1` para ir por el servidor, quinto argumento `abandona`/`rinde`/`mal`/`corta`) y
`tools/vs_test.gd` (repetir partidas grabadas acción por acción da el mismo estado).

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

## Interfaz

Estilo moderno con toques cyberpunk: fondo índigo con bandas, rejilla en perspectiva y líneas de barrido;
paneles con esquinas cortadas y borde neón; títulos con efecto glitch; acentos en dorado (acción principal),
cian y magenta. Todo sale de `scripts/ui/ui_kit.gd` (`UiKit`): colores, radios, espaciados y tamaños como
constantes, un único `Theme` con variantes (`PrimaryButton`, `GhostButton`, `DangerButton`, `Card`,
`CardButton`, `MenuItem`, `DialogPanel`, `Title`...) y piezas comunes (`dialog`, `screen_header`, `menu_item`,
`type_chip`, `category_chip`, `move_button`, `hp_bar`, `brackets`, `background`). Los diálogos modales son
`UiDialog` (`scripts/ui/ui_dialog.gd`): velo, título, ✕, Escape para cerrar y animación de apertura.
Para una pantalla nueva, usa estas piezas en vez de crear estilos sueltos.

## Calidad gráfica

En Opciones (y en Pausa) se elige **Alta**, **Media** o **Baja**. Alta lo enseña todo; Media quita la luz rebotada
y suaviza algo menos las sombras; Baja quita también la sombra de contacto, usa FXAA y sombras más simples (unas
tres veces más fluido en una gráfica integrada). El juego usa la tarjeta gráfica dedicada si la hay; el nombre de
la que está en uso sale al pasar el ratón por el desplegable.

## Idiomas

Español (el original) e inglés, en *Opciones → Idioma* (por defecto, el del sistema). Las traducciones son
archivos gettext en `locale/<tema>/<idioma>.po`, con el texto en español como clave (msgid), una carpeta por tema
(`ataques`, `objetos`, `habilidades`, `interfaz`, `combate`, `historia`) para poder traducir varios temas a
la vez. El juego carga todos los `.po` al arrancar y ofrece cada idioma que tenga alguno. Guía para quien
traduzca: `locale/LEEME.md`.

- Ataques, objetos y habilidades: `python3 tools/build_translations.py <dir_datos>` rehace las plantillas `.pot`
  y fusiona los `.po` (conserva lo traducido, rellena lo nuevo con PokeAPI; `--nuevo fr` crea un idioma). Los
  textos propios del juego van en su lista `MANUAL`. Vuelve a ejecutarlo después de `build_data.py` o `build_items.py`.
- Textos del código y de la historia: `python3 tools/extract_texts.py` busca los `tr("...")`,
  `tr_n(...)`, `TranslationServer.translate("...")`, las constantes marcadas con el comentario `# i18n` y los
  textos de los capítulos (`data/story/*.json`: diálogos, narración, nombres, lugares, rótulos), rehace
  las plantillas y fusiona los `.po` (lo nuevo queda vacío; `--faltan en` lista lo que falta). Ejecútalo después de
  añadir o cambiar textos.
- Todo el juego está en inglés: menús, editores, Torre, tabla de tipos, el combate entero y el modo historia
  (diálogos y rótulos del capítulo 1). Al añadir un capítulo o escena, vuelve a ejecutar `extract_texts.py`.

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

Los modelos salen con más color que sus texturas (los rips se veían desteñidos con la luz normal) y Gastly es
una esfera negra envuelta en un halo de gas morado que palpita, transparente en el centro y denso en el borde.
Las casillas resaltadas (movimiento, alcance, área, orientación) son más intensas y llevan un borde claro. Las de
movimiento son azules, y verdes sobre el agua y los suelos azules (hielo, líneas del laboratorio...), donde el azul
no se vería.

El juego reproduce las acciones `idle`, `walk`, `fight_b` (físico), `fight_d` (especial), `hit` y `ko`, y en
reposo el clip de su estado: `status_freeze`, `status_sleep`, `status_paralysis`, `status_confusion` o
`status_burn` / `status_poison` (en ese orden de prioridad). Cambia solo al recibir o curarse el estado
(`Unit.idle_key`); además, como en los juegos, cada estado se ve sobre el modelo mientras dure: congelado queda encerrado en un
bloque de hielo facetado y translúcido (`Fx.ice_block`); quemado, se tiñe de rojo, que palpita, y le brotan
lenguas de fuego del cuerpo (`Fx.burning`), con una llamarada
cada vez que se resiente; dormido suelta zetas que suben de la cabeza (`Fx.sleeping`); envenenado, se tiñe
de morado y le salen burbujas moradas que suben y revientan (`Fx.poisoned`); paralizado, a ratos parpadea en amarillo y le saltan
rayos en zigzag alrededor del cuerpo (`Fx.paralyzed`), y confuso, estrellas y pajaritos que le dan vueltas sobre la cabeza (`Fx.dizzy`, aparte del resto, porque
se puede estar confuso y además quemado). Todos se ven en el visor de animaciones
del editor de equipo.

Las Poké Balls se animan como en los juegos (`scripts/battle/ball_fx.gd`). Al empezar cualquier combate, cada
Pokémon sale de su bola: llega en arco desde fuera del tablero, se abre en el aire con un destello y el Pokémon se
materializa como una silueta blanca que crece y toma color (primero los rivales y luego los tuyos; los salvajes de
la Torre ya están ahí). Al capturar en la Torre, la bola vuela en arco, se abre, el Pokémon entra como energía roja,
la bola cae dando botes y se sacude hasta tres veces con el botón parpadeando; si lo atrapa, hace clic y saltan
estrellitas, y si se escapa, la bola se abre de golpe y el Pokémon vuelve a salir. En el visor de animaciones,
*Captura* y *Salida* las reproducen sobre el Pokémon.

Los terrenos se generan con geografía (`scripts/grid/biome.gd`): relieve de ruido fractal suavizado (sin picos
sueltos), y luego el suelo según altura y pendiente, y los obstáculos donde tendrían sentido. Pradera: lomas, un
sendero entre los dos bandos, una charca (siempre de al menos 8 casillas) y bosquecillos. Bosque: arboleda con claros, un arroyo y hojarasca bajo la
espesura (pinos en lo alto). Montaña: macizo central con valles verdes, roca y cumbres nevadas, pedregal al pie de
los cortados. Desierto: dunas alineadas por el viento, mesetas de arenisca, un oasis con palmeras (tronco anillado y curvo,
hojas con foliolos que cuelgan, cocos) y matorrales de cactus de tres tipos (columnar con brazos, barril con
flores y nopal con tunas). Lago: cuenca
central con playa de arena. Nieve: ventisqueros con sombras azuladas, estanque de hielo agrietado, neveros sobre la roca y pinares nevados. Cueva: crestas de roca,
charcas, estalagmitas y cristales. Pantano: terreno bajo con pozas, lodazales, juncales, nenúfares, sauces, árboles
secos, luciérnagas y bruma verdosa. Ciudad: calles de dos carriles con línea discontinua, manzanas de edificios de
1 a 3 plantas, farolas y un parque con fuente. Laboratorio: paneles con líneas guía luminosas, plataforma central
elevada, bancos de consolas con pantallas y pilotos, e incubadoras de cristal con líquido que brilla. Volcán: crestas
de basalto, río y pozas de lava (costra agrietada que se desliza sobre roca fundida que late y alumbra) con dos pasos
de roca o puentes de madera chamuscada, ceniza, fumarolas humeantes, troncos calcinados, brasas que suben y calima. Playa: el mar en un costado con
orilla irregular, muelle de madera, sombrillas, palmeras, conchas y dunas con hierba tierra adentro. Cementerio:
noche con neblina, hierba oscura, caminos de tierra, hileras de lápidas (losa o cruz), árboles secos, faroles y
fuegos fatuos. Estudio: plató a oscuras con escenario elevado de madera, cinta amarilla alrededor, focos con viseras que lo
apuntan y lo alumbran con un cono de luz visible, y cámaras con piloto rojo que lo enfocan. Biblioteca: tarima, alfombras granates en los pasillos, estanterías corridas de dos caras con libros de todos los tamaños (escaleras, globos y pilas encima), mesas de lectura con lámpara de banquero encendida, columnas junto a la alfombra, luz cálida con polvo en el aire y, fuera del tablero, más salas de estanterías en hileras. Aeropuerto: pista de dos carriles con línea central,
calle de rodaje, plataforma con aviones aparcados (ocupan 3×3), terminal acristalada con cubierta en voladizo y torre de control, y farolas. Cueva submarina: caverna
inundada en azul con islotes de roca y arena, corales que se mecen, algas, cristales azules al pie de las paredes, cáusticas (la red de luz del oleaje) que ondulan sobre el fondo y burbujas que suben. El río del bosque tiene dos cruces de 3 casillas (vado de tierra o
puente con barandilla), y al final de la generación se abre, si hace falta, un paso sin agua y uno de 3 casillas
de ancho (quitando obstáculos y suavizando cuestas) entre los dos bandos. El terreno está vivo (`scripts/battle/terrain_fx.gd`): árboles, palmeras,
hierba y juncos se mecen con el viento (más con lluvia o tormenta de arena, menos con sol); la hierba crece en zonas de
hierba alta y claros de césped corto, y se aparta alrededor de cada Pokémon para no taparlo; las copas, los pinos y
los troncos tienen textura procedural (racimos de hojas, agujas y corteza con grietas); el agua tiene oleaje,
reflejos y espuma en la orilla; con lluvia el suelo, las rocas y los árboles se ven mojados (más oscuros y
brillantes), salen charcos y las gotas hacen ondas en el agua; con tormenta de arena hay bruma,
nubes de polvo que cruzan, ráfagas de arena y polvo que se levanta de las crestas de las dunas; con granizo caen bolitas de hielo
azuladas que rebotan, se acumulan en el suelo y salpican el agua, con ventisca a ras de suelo; los cristales (drusas talladas con refracción y vetas) laten e iluminan el suelo de su color, la cueva tiene
suelo de piedra agrietada con piedras sueltas y sombras suaves; las rocas tienen formas y tamaños distintos
(redondeadas, talladas, lajas y agujas); el sol gira con la cámara al rotar el mapa, así que la luz y las
sombras caen siempre desde el mismo lado de la pantalla, y cada bioma tiene su ambiente (hojas que caen, polen, arena
que corre, copos, motas que brillan).

Los estados, el daño recibido y el debilitado de los 151 salen de `tools/blender/animate_status.py`, que parte del
`idle` de cada especie (así sirve para cualquier esqueleto) y le suma el movimiento, como en los juegos: al recibir
daño retrocede echando la cabeza atrás, se encoge y se recupera con un pequeño rebote; dormido se
encorva con la cabeza caída y respira lento; paralizado va a tirones con calambres; envenenado se balancea
encorvado con escalofríos; quemado se encoge por el ardor, con punzadas de dolor y sacudidas; confuso da vueltas mareado; congelado se queda rígido con algún temblor; debilitado
se queja, cae de lado (de bruces si es más ancho que alto, como las aves) y queda tendido. Las serpientes se
duermen y caen con su propio animador (`animate_serpent.py`, bajando el cuello al suelo); Mewtwo y Dragonite usan
sus clips de los juegos para dormir, aturdido y debilitado (`anim_map`), y Bulbasaur su `ko`.

```bash
blender --background art/blender/pikachu.blend --python tools/blender/animate_status.py            # las que falten
blender --background art/blender/pikachu.blend --python tools/blender/animate_status.py -- ko --force  # rehacer una
blender --background --python tools/blender/animate_status.py -- --import mewtwo  # .blend de un rip con clips propios
```
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

El cuerpo de los rips de serpiente solo tiene anillos cada mucho trecho y cada vértice va con un solo hueso: al
enroscarse se veían esquinas. `smooth_serpent_weights.py` añade anillos al tubo del cuerpo y reparte los pesos
entre los huesos vecinos (la cabeza, las mandíbulas y la capucha de Arbok no se tocan); hecho en Ekans, Arbok y
Dratini. Después hay que volver a animar con `--force` (las acciones de estado también) y exportar:

```bash
blender --background art/blender/ekans.blend --python tools/blender/smooth_serpent_weights.py
```

El cuerpo del rip de Ekans es más delgado que el del artwork: `thicken_serpent.py` aleja cada vértice del centro
de su anillo (`--factor`, 1,35 en Ekans) y vuelve a 1 justo debajo de la cabeza para que el cuello empalme. Los
huesos y las acciones no cambian; después, solo exportar:

```bash
blender --background art/blender/ekans.blend --python tools/blender/thicken_serpent.py -- --factor 1.35
```

Las cadenas largas de algunos rips (la cola de Raichu, la liana de Victreebel) traen los huesos con los ejes
girados: los giros de los animadores solo las retorcían y quedaban como un palo recto. `sway_chain.py` prueba
qué eje de cada hueso las dobla de verdad y suma a todas las acciones una curva fija y una onda que baja hasta la
punta (`CHAINS` por especie). Va después del animador y de `animate_status.py`, y antes de exportar:

Antes, `smooth_chain.py` les añade anillos (la cola de Raichu tenía cinco en todo su largo y se doblaba en codos)
y reparte los pesos a lo largo de la cadena, sin tocar la punta (el rayo, la hoja). A la cola de Raichu le pone
además un material liso oscuro (`TailDark`, color en `FLAT_COLORS` de `unit.gd`):

```bash
blender --background art/blender/raichu.blend --python tools/blender/smooth_chain.py
blender --background art/blender/raichu.blend --python tools/blender/sway_chain.py
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
Charmander, y `setup_animations.py` lo monta y pesa cada vértice por su distancia a los huesos: el tronco
(Hips, Spine, Head, Belly...) se mueve rígido y brazos, patas y colas solo se llevan lo que sobresale, para que
no arrastren la cara ni la barriga. Después se animan con `animate_pokemon.py` (bípedos y cuadrúpedos) o
`animate_generic.py` (peces, cangrejos, Golbat, Shellder...). Si se retoca una plantilla, `--reweight` recoloca
los huesos del .blend y rehace los pesos sin tocar las acciones (luego hay que volver a animar con `--force`):

```bash
blender --background --python tools/blender/setup_animations.py -- chansey --reweight
```

Para medir un modelo nuevo, render ortográfico de frente, de lado y desde arriba con una rejilla de 0,1 alturas.

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
  en el juego por un material de fuego. Las llamas de Moltres (`fire_*`) pasan a un material sin luz ni metal.
- `hold` en los `TWEAKS` de `animate_generic.py`: giros fijos de huesos, también espejados por lado (`DROP` baja
  el hueso, `FWD` lo adelanta): los brazos de Geodude doblados con los puños cerrados.
- `flap_follow` en `animate_generic.py`: retraso y amplitud de la punta del ala (Moltres bate despacio y ondula).
- `KO_STYLE` en `animate_status.py`: debilitados que no caen de lado: los lodos se derriten, Diglett y Dugtrio
  se hunden en su agujero, Dewgong se tumba sobre la barriga y Kingler se desploma a medias.
- **Color:** las texturas de los rips salen desteñidas con la luz del juego y el sol del tablero quemaba los
  colores claros (Charizard amarillo). `python3 tools/tune_textures.py [especies]` escribe una versión ajustada
  de cada textura en `assets/models/pokemon/tuned/` (los originales no se tocan) y `Unit` la usa si existe;
  `TUNE` corrige especies sueltas frente a sus colores oficiales. Después, `godot --headless --path . --import`.
  Los modelos de color liso sin textura (Haunter) toman su color de `FLAT_COLORS` en `unit.gd`, y las piezas con
  metálico alto pierden el brillo metálico salvo en los de tipo Acero (salían grisáceas).
- **Apoyo en el suelo:** `Unit.fit_model` apoya el modelo con el primer fotograma del reposo, y lo que las
  animaciones bajan o suben después (aleteos, vaivenes, posturas de estado) lo hundía en la casilla o lo dejaba en
  el aire. `tools/bake_ground.gd` mide el punto más bajo de la malla ~60 veces por segundo en cada clip y guarda en
  `data/pokemon_ground.json` cuánto subir o bajar cada fotograma; `Unit` lo aplica con su nodo `_lift`. Los
  voladores y levitadores (`FLYERS`, con su holgura) flotan a una altura fija, se posan dormidos o congelados y
  bajan al debilitarse; Diglett y Dugtrio (`IN_GROUND`) pueden meterse en su agujero. En el reposo, al andar y en
  los estados el punto más bajo va siempre pegado al suelo; en ataques y golpes se respetan los saltos. En agua
  (al menos media huella) los de tipo Agua se hunden un 30 % de su altura y el resto de terrestres un 10 % (lo
  mismo en lava); el anillo del equipo baja a la superficie (`Unit.set_surface`, desde `battle.gd` `_place`).
  **Tras cambiar animaciones o modelos, vuelve a hacer el bake** y compruébalo:

```bash
godot --headless --path . --script tools/bake_ground.gd [-- especie1,especie2]   # ~10 min las 151
godot --headless --path . --script tools/check_ground.gd                          # sale con 1 si algo se hunde o flota >2 %
POKE_TACTICS_NO_SAVE=1 OUT=carpeta/ godot --path . --resolution 1600x900 --script tools/ground_biomes.gd  # 18 biomas
```

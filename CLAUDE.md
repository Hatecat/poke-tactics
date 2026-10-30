# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Poké Tactics — instrucciones para Claude Code

**Clave del proyecto: `poketactics` (o `poketactis`).** Cuando el usuario escriba cualquiera de las dos, retoma este proyecto: lee este
archivo y el README, resume en pocas líneas en qué estado está y pregunta con qué quiere seguir.

El usuario habla español y escribe frases cortas ("muéstrame...", "mejóralo"). Responde en español. Espera ver
los cambios probados en una partida real, con capturas o video, antes de darlos por buenos.

## Qué es

Juego táctico por turnos con Pokémon (los 151 originales) en Godot 4.7.2, todo en GDScript. Tablero 3D cuadrado
o hexagonal, modos Partida rápida y Torre de Batallas, editor de equipo, editor de escenarios y tabla de tipos.
Ver README.md para las reglas y la estructura de carpetas.

## Comandos

En este equipo Godot es el binario `~/Godot_v4.7.2-stable_linux.x86_64` (`tools/export_demo.sh` lo toma de `$GODOT`).

```bash
G=~/Godot_v4.7.2-stable_linux.x86_64
$G --path .                                   # jugar
$G -e --path .                                # editor
$G --headless --path . --import               # registrar clases nuevas (class_name)
POKE_TACTICS_NO_SAVE=1 $G --path . --script <prueba>.gd   # partida de prueba (ver "Probar en partida")
$G --headless --path . --script tools/check_ground.gd [-- especie1,especie2]   # apoyo en el suelo; sale con 1 si falla
python3 tools/extract_texts.py                # actualizar locale/*.pot tras añadir textos
tools/export_demo.sh                          # builds Windows + Linux en ../poke-tactics-builds
```

No hay tests unitarios: la comprobación es una partida real con capturas (y `check_ground.gd` para modelos).
Los datos (`data/pokemon`, `data/moves`, `data/items`) los generan `tools/build_data.py` / `build_items.py` desde
Pokémon Showdown y PokeAPI (ver README): retocar un `.tres` a mano se pierde al regenerar.

## Arquitectura

- **Autoloads:** `Game` (scripts/game.gd) guarda todo el estado entre escenas: roster, equipos, `player_team` /
  `enemy_team`, `mode` (`"quick"`, `"tower"`, `"story"`), `biome`, `weather`, `map`, `rng`, opciones, y
  `story` (`StoryRun`) / `tower` (`TowerRun`). Las escenas se cambian con `change_scene_to_file` y leen de `Game`.
  `Audio` lleva música y efectos.
- **Escenas** (scenes/*.tscn): casi vacías; cada una tiene un script que monta todo por código (menú, editor de
  equipo, editor de mapas, torre, historia, tabla de tipos, batalla).
- **Batalla:** `battle.gd` es el controlador (estados `State`, input, IA, UI, final según el modo). Delega en
  módulos `RefCounted` sin nodos: `TurnManager` (CT estilo FFT), `Combat` (reglas puras: celdas apuntables, área,
  daño), `Effects` (estados volátiles, habilidades; recibe la batalla en `Effects.new(self)`), `FieldState`
  (zonas, trampas, terreno), `Weather`, `Items`, `Abilities`. Lo visual va aparte: `BoardView` (tablero 3D,
  campo de adorno, batching), `Unit` (cada Pokémon), `CameraRig`, `Fx`/`BallFx`/`WeatherFx`/`TerrainFx`,
  `GymDressing`.
- **Rejilla:** `BoardGrid` es lógica pura (vecinos, distancias, líneas, posición en el mundo) para cuadrada y hex,
  siempre con celdas `Vector2i(columna, fila)`. `Biome` define biomas, suelos, obstáculos y el generador;
  `MapData` es el escenario guardado (`data/maps/*.tres` o `user://`).
- **Datos:** recursos `PokemonData`, `MoveData`, `ItemData` en scripts/data/; `TeamMember` = especie + ataques
  elegidos. Mensajes guardados para mostrar más tarde con `Msg`.

## Estado (octubre 2026)

Hechos: 18 biomas (incluido `TEST`, copia de la Pradera fuera del azar) con generador propio y Gimnasio por tipo,
terreno vivo con shaders, clima visual, estados alterados con efecto, Poké Balls (salida y captura en la Torre),
mapa a pantalla completa con campo de adorno, calidad gráfica, idiomas (es/en) y el capítulo 1 del modo historia
(termina en "Continuará... Capítulo 2 · Ciudad Fucsia"; biblia narrativa en
~/Documentos/Historia_Kanto_Futuro_Version_1 1.docx). Detalle de cada parte en el README.

## Trampas y reglas del código

- **Enums de `Biome`** (`Kind`, suelos, `Prop`): los valores nuevos van siempre al final, o se rompen los mapas
  guardados. Para quitar un obstáculo usa `Biome._clear_prop` (el avión ocupa 3×3: `PLANE` en el ancla y
  `PLANE_PART` en el resto). El aspecto se toma de `Biome.look(kind)`, no de `grid.biome` (Test → Pradera).
- **Generador:** garantiza paso sin agua (`_ensure_dry_path`) y para talla 3 (`_ensure_wide_path`). Para
  comprobarlo en muchos mapas, genera con `Biome.generate` en un script `--headless` y recorre la huella como
  `battle.gd` `_fits`. La lava solo la pisan Fuego y voladores (`effects.lava_blocked`).
- **Rendimiento:** en combate `BoardView.batching` agrupa en MultiMesh por zonas (`CHUNK`) las piezas con meta
  `"batch"`; sus shaders leen `INSTANCE_CUSTOM` con `instanced = true`. Pieza nueva repetida por casilla → márcala
  igual. El editor no agrupa el tablero (sí el campo de adorno). Los obstáculos se funden en `BoardView._bake`
  (quedan sueltas las piezas con viento, brillo, transparencia o hijos). Las primitivas de
  `_cyl`/`_sphere`/`_capsule` se comparten: no las modifiques después de crearlas.
  Los ~6 s de "carga" al empezar un combate son la intro de las Poké Balls (`_send_out_intro`); la carga real es
  de 0,4-1,2 s. `light_projector` sale negro con texturas hechas por código (por eso las cáusticas son una capa
  aditiva, `TerrainFx.CAUSTIC_SHADER`).
- **Campo de adorno** (`BoardView._build_scenery`, `SCENERY_*`): fuera de la rejilla, sin colisión; se oscurece
  con la distancia (`_scenery_dim`). La cámara encuadra con `BoardView.board_box()` + `CameraRig.frame`.
  Lab y Estudio siguen un plano (`_scenery_layout`); la Librería, `_library_scenery`. En los biomas naturales
  (`RELIEF_KINDS`) `_build_relief` pone relieve (dunas, lomas, laderas) llano junto al borde, orillas y senderos,
  con pendiente máxima `RELIEF_SLOPE` para no tapar casillas; los adornos se asientan con `_relief_at`.
- **Objetos detallados:** `_bevel_box`, `_wing_mesh`, `_screen_material` (en `_screen_mats`, no en `_mats`). El
  avión es `AirlinerMesh` (airliner_mesh.gd; `PlaneMesh` ya es una clase de Godot): fuselaje de una pieza, perfiles
  de ala y motores torneados, ventanillas por shader. El público del gimnasio (`GymDressing._person_mesh`) es de
  piezas redondeadas, pieza por color de vértice, cara y pelo pintados por `CROWD_SHADER`, mirando a la arena.
- **GPU:** en el flatpak hace falta la extensión `org.freedesktop.Platform.GL.nvidia-*` de la misma versión que el
  driver; si no, corre en la Intel (compruébalo con `RenderingServer.get_video_adapter_name()`).
- **Modelos de Pokémon:** texturas ajustadas en `assets/models/pokemon/tuned/` (`tools/tune_textures.py`);
  `Unit._vivid_materials` / `_fix_palette_materials` / `FLAT_COLORS` / `KO_STYLE` en unit.gd. Tras cambiar un
  animador, vuelve a pasar `animate_status.py --force` (las animaciones de estado salen del idle) y, en Raichu y
  Victreebel, `sway_chain.py` después. Tras tocar animaciones o modelos, rehaz `tools/bake_ground.gd`
  (→ `data/pokemon_ground.json`, aplicado por `Unit._lift`; voladores en `bake_ground.FLYERS`) y pasa
  `tools/check_ground.gd` (y `tools/ground_biomes.gd` para verlo en los 18 biomas). Para revisar los 151 de un
  vistazo: un script que crea un `Unit` por clip (idle, walk, fight_b, fight_d, hit, ko) y hace `seek` + `pause`.
- **Modo historia:** `StoryRun` (en `Game.story`, sección "story" del guardado) recorre los pasos de
  data/story/capituloN.json: "titulo" y "escena" en story.tscn (`cutscene.gd`), "combate" en battle.tscn con
  `Game.mode = "story"`. Retratos en assets/portraits/<id>.png; `Unit.ally_ai` es el aliado de la IA. Los ataques
  que no caben van a `StoryRun.pending_moves` y la escena siguiente pregunta cuál olvidar (`DialogueBox.choose`).
- **Idiomas:** gettext en `locale/<tema>/`; ataques/objetos/habilidades con `tools/build_translations.py`, el
  resto con `tools/extract_texts.py`. Los capítulos se escriben en español y `DialogueBox.say` aplica `tr`.

## Cómo trabajar

- Godot: en el equipo original es el flatpak `org.godotengine.Godot` (4.7.2). En otro equipo puede ser el
  binario oficial; confirma cuál hay antes de usarlo.
- Tras crear un script nuevo con `class_name`, ejecuta `godot --headless --path . --import` para registrar la clase.
- `--check-only` no resuelve los autoloads (`Game`, `Audio`): da errores falsos en battle.gd. Para validar, mejor
  ejecuta una partida.
- **Probar en partida:** usa un script `extends SceneTree` fuera del proyecto (pásalo con `--script`). El script
  rellena `Game.player_team` y `Game.enemy_team` y pone `Game.map = null`, `Game.mode = "quick"` y elige
  `Game.biome`, `Game.weather` y `Game.rng.seed`. Después hace
  `change_scene_to_file("res://scenes/battle.tscn")`, espera `while b.state != b.State.DEPLOY` y guarda las
  capturas con `root.get_texture().get_image().save_png(...)`.
- **Video:** añade `--write-movie salida.avi --fixed-fps 30` y conviértelo a mp4 con ffmpeg.
- **No crear ni tocar el guardado del usuario** (`user://save.cfg`) en las pruebas: lanza Godot con la variable
  de entorno `POKE_TACTICS_NO_SAVE=1` y `Game.save()` no escribe nada. En un script `--script`, no uses
  `StoryRun` u otras clases que lean `Game` al compilar: cárgalas con `load()` y espera un frame (el roster aún no
  está cargado en `_initialize`).
- **Exportar:** `tools/export_demo.sh`, o
  `godot --headless --path . --export-release "Windows Desktop" <ruta>.exe` (y `"Linux"` para `.x86_64`).
  Hacen falta las plantillas de exportación de 4.7.2, que se descargan de las releases de Godot en GitHub.
- Estilo: código y comentarios en español, `##` para documentar funciones, todo procedural (sin escenas para
  efectos). Imita el código de alrededor.
- Actualiza el README cuando añadas algo visible para el jugador.
- **Textos traducibles:** escribe el texto en español dentro de `tr("...")` (en funciones `static`,
  `TranslationServer.translate("...")`); las constantes con textos, con `# i18n` al final de su primera línea.
  Luego `python3 tools/extract_texts.py` y traduce lo nuevo en `locale/<tema>/en.po`. Los nombres de datos
  (`mv.display_name`, `Combat.TYPE_NAMES[t]`, `Biome.NAMES[k]`...) se traducen al mostrarlos: `tr(mv.display_name)`.
  No compares textos mostrados para decidir lógica (usa ids o listas). Las frases montadas necesitan `tr()` antes de rellenar: `tr("¡{a} usó {b}!").format({"a": ..., "b": tr(mv.display_name)})`
  (huecos con nombre, para que cada idioma ordene la frase; `tr_n()` para plurales). Nada de pegar trozos con
  género o artículos. Los textos que se guardan para mostrarlos después (informes de la Torre y de la historia)
  van como mensajes `Msg.make("frase en español", [datos])` y se muestran con `Msg.text` / `Msg.lines`, así salen
  en el idioma del momento.

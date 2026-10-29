# Poké Tactics — instrucciones para Claude Code

**Clave del proyecto: `poketactics` (o `poketactis`).** Cuando el usuario escriba cualquiera de las dos, retoma este proyecto: lee este
archivo y el README, resume en pocas líneas en qué estado está y pregunta con qué quiere seguir.

El usuario habla español y escribe frases cortas ("muéstrame...", "mejóralo"). Responde en español. Espera ver
los cambios probados en una partida real, con capturas o video, antes de darlos por buenos.

## Qué es

Juego táctico por turnos con Pokémon (los 151 originales) en Godot 4.7.2, todo en GDScript. Tablero 3D cuadrado
o hexagonal, modos Partida rápida y Torre de Batallas, editor de equipo, editor de escenarios y tabla de tipos.
Ver README.md para las reglas y la estructura de carpetas.

## Hecho hasta ahora (octubre 2026)

- **Estados alterados** con efecto visual (scripts/battle/fx.gd, unit.gd `_set_look`): bloque de hielo, llamas,
  Zzz, burbujas + tinte morado (veneno), rayos en zigzag + parpadeo amarillo (parálisis), estrellas y pájaros
  girando (confusión).
- **Poké Ball** (scripts/battle/ball_fx.gd): salida de cada Pokémon al empezar el combate y captura en la Torre
  (abrir, absorber, sacudidas, clic o escape). Botones *Captura* y *Salida* en el visor de animaciones.
- **Terrenos** (scripts/grid/biome.gd): generador con geografía para cada bioma (ríos, lago con playa, macizo
  nevado, dunas, mesetas, oasis, cueva con estalagmitas). Obstáculos nuevos `STALAGMITE` y `PALM` (al final del
  enum `Prop`, para no romper mapas guardados).
- **Pantano y Ciudad** (biomas `SWAMP`, `CITY`), suelos `BRIDGE`, `MUD`, `ROAD` y obstáculos `DEAD_TREE`, `BUILDING`,
  `LAMP`, todos al final de sus enums. El generador garantiza paso sin agua (`_ensure_dry_path`) y para talla 3
  (`_ensure_wide_path`); el río del bosque tiene vados o puentes (`_fords`). Para comprobarlo en muchos mapas,
  genera con `Biome.generate` en un script `--headless` y recorre la huella como `battle.gd` `_fits`.
- **Laboratorio, Volcán y Playa** (`LAB`, `VOLCANO`, `BEACH`), suelo `LAVA` (solo Fuego y voladores:
  `effects.lava_blocked`; shader `TerrainFx.LAVA_SHADER`) y obstáculos `PARASOL`, `MACHINE`, `TANK`, `VENT`.
  **Gimnasio por tipo:** `Biome.GYM_STYLES` / `gym_style()`, guardado en `BoardGrid.gym_type` y `MapData.gym_type`;
  battle.gd lo toma del líder (`trainer.types[0]`) o al azar.
  El estadio alrededor (gradas, muros, medalla, estatuas, adornos por tipo) está en `scripts/battle/gym_dressing.gd`,
  fuera de las casillas; `Unit.fit_model` escala las estatuas.
- **Cementerio, Estudio, Librería, Aeropuerto y Cueva submarina** (`CEMETERY`, `STUDIO`, `LIBRARY`, `AIRPORT`,
  `UNDERWATER`), suelo `WOOD` y obstáculos `GRAVE`, `SHELF`, `SPOTLIGHT`, `CAMERA`, `CORAL` y el avión: `PLANE` en
  la casilla ancla (lo dibuja entero) y `PLANE_PART` en el resto de su huella 3×3. Para quitar obstáculos usa
  `Biome._clear_prop`, que quita el avión completo.
- **Terreno vivo** (scripts/battle/terrain_fx.gd + board_view.gd): shaders de viento (árboles, hierba, juncos),
  agua con oleaje y espuma, laterales con capas, detalles del suelo y partículas de ambiente por bioma.
- **Rendimiento:** en combate `BoardView.batching` agrupa en MultiMesh (por zonas de `CHUNK` casillas) las caras
  de arriba, laterales y detalles marcados con meta `"batch"`; los shaders leen lo de cada pieza de
  `INSTANCE_CUSTOM` con `instanced = true`. Pieza nueva repetida por casilla → márcala igual. El editor no agrupa.
  La hierba tiene una sola cara por hoja (material de dos caras, `TerrainFx._two_sided`).
  Los obstáculos se funden al construirse (`BoardView._bake`): sus piezas opacas de color liso pasan a una malla
  con color por vértice por acabado; las de viento, brillo o transparencia, y las que tienen hijos, quedan sueltas
  (la Librería pasó de ~20.000 llamadas de dibujo a ~500). Las primitivas de `_cyl`/`_sphere`/`_capsule` se
  comparten: no las modifiques después de crearlas.
  La "carga" de ~6 s al empezar un combate es casi toda la intro de las Poké Balls (`_send_out_intro`, ~5,5 s);
  la carga real es de 0,4-1,2 s. Los proyectores de luz (`light_projector`) salían negros con texturas hechas por
  código: las cáusticas de la cueva submarina son una capa aditiva por casilla (`TerrainFx.CAUSTIC_SHADER`).
- **Calidad gráfica** (`Game.graphics_quality`, Opciones y Pausa): `Game.apply_graphics` (MSAA/FXAA, atlas y filtro de
  sombras) + `CameraRig.apply_quality` (SSIL, SSAO, cascadas, PCSS). Alta = como siempre. El juego usa la GPU
  dedicada solo (Vulkan elige la discreta); en el flatpak hace falta la extensión `org.freedesktop.Platform.GL.nvidia-*`
  de la misma versión que el driver (si no, corre en la Intel: compruébalo con `RenderingServer.get_video_adapter_name()`).
- **Pokémon:** `Unit._vivid_materials` usa la textura ajustada de `assets/models/pokemon/tuned/` (de
  `tools/tune_textures.py`, por píxel y con `TUNE` por especie) o, si no hay, satura la original; `_fix_palette_materials`
  toma el color del nombre de la pieza en los modelos de paleta (Gastly) y su gas usa `HALO_SHADER` (halo fresnel).
  Revisión de los 151 (octubre 2026): serpientes suavizadas (`smooth_serpent_weights.py`, Ekans/Arbok/Dratini),
  brazos de Geodude/Graveler/Hitmonlee/Hitmonchan, Ekans más grueso (`thicken_serpent.py`), cola de Raichu y liana de Victreebel (`smooth_chain.py` una vez en el .blend; `sway_chain.py` tras animate_status), `FLAT_COLORS`
  para colores lisos (Haunter), metálico solo en tipo Acero, cola de Slowpoke y debilitados (`KO_STYLE`). Para revisarlos todos de un
  vistazo: un script que crea un `Unit` por clip (idle, walk, fight_b, fight_d, hit, ko) y hace `seek` + `pause`.
  El preview del editor/visor (`pokemon_preview.gd` `_fit_width`) reduce el modelo si no cabe a lo ancho.
  Tras cambiar un animador, vuelve a pasar también `animate_status.py` con `--force` (las de estado salen del idle).
- **Clima** (weather_fx.gd + board_view.gd): la lluvia moja el suelo, forma charcos y hace ondas en el agua; la
  tormenta de arena va en capas y levanta polvo de las dunas; el granizo cae en bolitas de hielo que rebotan y se
  acumulan. La fuerza del viento depende del clima (`WIND` en battle.gd).

- **Modo historia** (scripts/story/, data/story/capitulo1.json): `StoryRun` (en `Game.story`, guardado en la
  sección "story") recorre los pasos del capítulo: "titulo" y "escena" en scenes/story.tscn (`cutscene.gd`, guion
  en JSON), "combate" en battle.tscn con `Game.mode = "story"`. `DialogueBox` es el cuadro estilo FFT (retratos en
  assets/portraits/<id>.png), `StoryFigure` la persona provisional y `Unit.ally_ai` el aliado de la IA (Gengar).
  Biblia narrativa: ~/Documentos/Historia_Kanto_Futuro_Version_1 1.docx. Hecho el capítulo 1 completo
  (termina en "Continuará... Capítulo 2 · Ciudad Fucsia"). Los ataques que no caben se guardan en
  `StoryRun.pending_moves` y la escena siguiente pregunta cuál olvidar (`DialogueBox.choose`).

- **Idiomas** (hecho, español e inglés): `Game.language` / `apply_language()`, selector en Opciones; gettext en
  `locale/<tema>/<idioma>.po` + `<tema>.pot` (ataques/objetos/habilidades con `tools/build_translations.py`; los textos del código
  y de data/story/*.json con `tools/extract_texts.py`), cargados en `Game._load_translations()`. La clave es el texto en español.
  Los textos de los capítulos se escriben en español en el JSON y se traducen al mostrarlos (`DialogueBox.say` aplica `tr`).

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

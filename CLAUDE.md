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
- **Terreno vivo** (scripts/battle/terrain_fx.gd + board_view.gd): shaders de viento (árboles, hierba, juncos),
  agua con oleaje y espuma, laterales con capas, detalles del suelo y partículas de ambiente por bioma.
- **Clima** (weather_fx.gd + board_view.gd): la lluvia moja el suelo, forma charcos y hace ondas en el agua; la
  tormenta de arena va en capas y levanta polvo de las dunas; el granizo cae en bolitas de hielo que rebotan y se
  acumulan. La fuerza del viento depende del clima (`WIND` en battle.gd).

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
- **No crear ni tocar el guardado del usuario** (`user://save.cfg`) en las pruebas.
- **Exportar:** `tools/export_demo.sh`, o
  `godot --headless --path . --export-release "Windows Desktop" <ruta>.exe` (y `"Linux"` para `.x86_64`).
  Hacen falta las plantillas de exportación de 4.7.2, que se descargan de las releases de Godot en GitHub.
- Estilo: código y comentarios en español, `##` para documentar funciones, todo procedural (sin escenas para
  efectos). Imita el código de alrededor.
- Actualiza el README cuando añadas algo visible para el jugador.

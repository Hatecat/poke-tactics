extends Node
## Autoload "Game": roster disponible, equipos del jugador (guardados en disco),
## equipo rival y opciones de la próxima batalla.

const MAX_TEAM := 6
const MAX_TEAMS := 6
enum Difficulty { EASY, NORMAL, HARD }
const DIFFICULTY_NAMES := ["Fácil", "Normal", "Difícil"] # i18n
## Nivel de los rivales en cada dificultad (los tuyos siempre son 50).
const DIFFICULTY_LEVELS := [45, 50, 55]
const DIFFICULTY_DESC := [ # i18n
	"Rivales a nivel 45; a veces eligen mal.",
	"Rivales a nivel 50.",
	"Rivales a nivel 55; evitan exponerse y rematan a los débiles.",
]


## Un equipo guardado: nombre y hasta 6 Pokémon.
class TeamSlot:
	var name := ""
	var members: Array[TeamMember] = []
const SAVE_PATH := "user://save.cfg"
const POKEMON_DIR := "res://data/pokemon/"
## Escenarios del juego (se guardan aquí al ejecutar desde el editor de Godot, para
## que entren en el repo y en las builds) y escenarios del jugador.
const GAME_MAPS_DIR := "res://data/maps/"
const USER_MAPS_DIR := "user://maps/"

var roster: Array[PokemonData] = []
var teams: Array[TeamSlot] = []
var current_team := 0
var difficulty := Difficulty.NORMAL
## Modo de la batalla en curso: "quick" (Partida rápida), "tower" (Torre de Batallas) o "story" (Historia).
var mode := "quick"
## Partida del modo historia (null = no empezada).
var story: StoryRun
## Partida de la Torre en curso (null = ninguna) y récord de pisos.
var tower: TowerRun
var tower_best := 0
## Volúmenes de 0 a 1 (los aplica el autoload Audio).
var volumes := {"master": 0.8, "music": 0.6, "sfx": 0.8}
## Velocidad de los combates en %: 200 es la velocidad normal del juego; se puede bajar hasta 20.
const BATTLE_SPEED_MIN := 20
const BATTLE_SPEED_MAX := 200
var battle_speed := BATTLE_SPEED_MAX
## Calidad gráfica. Alta: todo (luz rebotada SSIL, sombra de contacto SSAO, MSAA, sombras suaves en 4
## cascadas). Media: sin SSIL y sombras algo menos suaves. Baja: además sin SSAO, FXAA en vez de MSAA y
## sombras más simples, para gráficas integradas.
enum Quality { LOW, MEDIUM, HIGH }
const QUALITY_NAMES := ["Baja", "Media", "Alta"] # i18n
var graphics_quality := Quality.HIGH
## Idiomas. El español es el original: los textos del juego son las claves (msgid) de las traducciones,
## locale/<tema>/<idioma>.po. Un idioma está disponible si hay algún .po suyo; aquí solo su nombre en ese idioma.
## language = "" usa el del sistema si está traducido (si no, inglés).
const LOCALE_DIR := "res://locale/"
const LANGUAGE_NAMES := {"es": "Español", "en": "English", "fr": "Français", "de": "Deutsch", "it": "Italiano",
	"pt": "Português", "pt_BR": "Português (Brasil)", "ja": "日本語", "ko": "한국어", "zh_CN": "简体中文", "zh_TW": "繁體中文"}
var languages: PackedStringArray = ["es"]
var language := ""
## Equipo con el que se juega (el seleccionado).
var player_team: Array[TeamMember]:
	get:
		return teams[current_team].members
	set(value):
		teams[current_team].members = value
var enemy_team: Array[TeamMember] = []
var topology := BoardGrid.Topology.SQUARE
var biome := Biome.Kind.MEADOW
## Clima de la partida rápida (-1 = aleatorio según el campo).
var weather := -1
## Escenario fijo para la próxima batalla (null = generar uno aleatorio).
var map: MapData
## Escenario abierto en el editor (se conserva al ir a probarlo y volver).
var editor_map: MapData
## La batalla actual es una prueba lanzada desde el editor de escenarios.
var testing_map := false
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	_load_roster()
	# Antes de leer el guardado, para que los equipos que se crean al empezar ya salgan en el idioma del sistema.
	_load_translations()
	_load_save()
	apply_language()
	apply_graphics()


func _load_roster() -> void:
	for file in DirAccess.get_files_at(POKEMON_DIR):
		# En builds exportados los recursos aparecen como ".tres.remap".
		file = file.trim_suffix(".remap")
		if file.ends_with(".tres"):
			roster.append(load(POKEMON_DIR + file))
	roster.sort_custom(func(a: PokemonData, b: PokemonData) -> bool: return a.dex_number < b.dex_number)


## Busca por id ("mrmime") o por nombre ("Mr. Mime").
func find_species(key: String) -> PokemonData:
	for p in roster:
		if p.id == key or p.species_name == key:
			return p
	return null


func add_team(team_name := "") -> int:
	if teams.size() >= MAX_TEAMS:
		return -1
	var slot := TeamSlot.new()
	slot.name = team_name if team_name else tr("Equipo %d") % (teams.size() + 1)
	teams.append(slot)
	save()
	return teams.size() - 1


func remove_team(index: int) -> void:
	if teams.size() <= 1:
		return
	teams.remove_at(index)
	current_team = clampi(current_team, 0, teams.size() - 1)
	save()


func select_team(index: int) -> void:
	current_team = clampi(index, 0, teams.size() - 1)
	save()


func add_to_team(p: PokemonData) -> bool:
	if player_team.size() >= MAX_TEAM:
		return false
	player_team.append(TeamMember.create(p))
	save()
	return true


func remove_from_team(index: int) -> void:
	player_team.remove_at(index)
	save()


## Rival aleatorio (especies y ataques) del mismo tamaño que el equipo del jugador.
func roll_enemy_team() -> void:
	enemy_team.clear()
	for i in maxi(player_team.size(), 1):
		enemy_team.append(TeamMember.random(roster[rng.randi_range(0, roster.size() - 1)], rng))


## Rutas de todos los escenarios guardados (del juego y del jugador).
func list_maps() -> PackedStringArray:
	var paths := PackedStringArray()
	for dir in [GAME_MAPS_DIR, USER_MAPS_DIR]:
		if not DirAccess.dir_exists_absolute(dir):
			continue
		for file in DirAccess.get_files_at(dir):
			file = file.trim_suffix(".remap")
			if file.ends_with(".tres"):
				paths.append(dir + file)
	return paths


func save_map(data: MapData) -> String:
	var dir := GAME_MAPS_DIR if OS.has_feature("editor") else USER_MAPS_DIR
	DirAccess.make_dir_recursive_absolute(dir)
	var slug := data.map_name.to_lower().strip_edges().replace(" ", "_").validate_filename()
	var path := dir + (slug if slug else "escenario") + ".tres"
	data.take_over_path(path)
	return path if ResourceSaver.save(data, path) == OK else ""


## Escala de tiempo del motor durante los combates (200 % = 1,0).
func battle_time_scale() -> float:
	return float(battle_speed) / BATTLE_SPEED_MAX


## Aplica la calidad gráfica a la ventana y al entorno de la escena actual (si tiene WorldEnvironment y Sun).
func apply_graphics() -> void:
	if not is_inside_tree():
		return
	var q := graphics_quality
	var vp := get_tree().root
	vp.msaa_3d = Viewport.MSAA_DISABLED if q == Quality.LOW else Viewport.MSAA_2X
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if q == Quality.LOW else Viewport.SCREEN_SPACE_AA_DISABLED
	RenderingServer.directional_shadow_atlas_set_size(2048 if q == Quality.LOW else 4096, true)
	RenderingServer.directional_soft_shadow_filter_set_quality([RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM][q])
	var scene := get_tree().current_scene
	if scene:
		CameraRig.apply_quality(scene)


## Carga todos los .po de locale/ (una carpeta por tema: ataques, objetos, interfaz...).
func _load_translations() -> void:
	for theme in DirAccess.get_directories_at(LOCALE_DIR):
		for file in DirAccess.get_files_at(LOCALE_DIR + theme):
			if not file.ends_with(".po"):
				continue
			var tr_res: Translation = load(LOCALE_DIR + theme + "/" + file)
			if tr_res:
				TranslationServer.add_translation(tr_res)
				if tr_res.locale not in languages:
					languages.append(tr_res.locale)


func apply_language() -> void:
	var code := language
	if code == "" or code not in languages:
		code = OS.get_locale()
		if code not in languages:
			code = OS.get_locale_language()
		if code not in languages:
			code = "en" if "en" in languages else "es"
	TranslationServer.set_locale(code)


## Desplegable de idioma (para Opciones). Al cambiarlo se vuelve a abrir la pantalla para rehacer sus textos.
func language_picker() -> OptionButton:
	var pick := OptionButton.new()
	pick.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var codes := languages
	for code in codes:
		pick.add_item(LANGUAGE_NAMES.get(code, TranslationServer.get_locale_name(code)))
	pick.select(maxi(codes.find(TranslationServer.get_locale()), 0))
	pick.item_selected.connect(func(i: int) -> void:
		language = codes[i]
		apply_language()
		save()
		get_tree().reload_current_scene.call_deferred())
	return pick


## Desplegable de calidad gráfica (para Opciones y Pausa): la cambia y la aplica al momento.
func quality_picker() -> OptionButton:
	var pick := OptionButton.new()
	for i in QUALITY_NAMES.size():
		pick.add_item(tr(QUALITY_NAMES[i]), i)
	pick.select(graphics_quality)
	pick.tooltip_text = tr("Baja o Media van más fluidas en gráficas integradas.\nGráfica en uso: %s") % RenderingServer.get_video_adapter_name()
	pick.item_selected.connect(func(i: int) -> void:
		graphics_quality = i as Quality
		apply_graphics())
	return pick


## Deslizador de velocidad de combate (para Opciones y Pausa). `on_change` se llama con el nuevo valor.
func speed_slider(on_change := Callable()) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var slider := HSlider.new()
	slider.min_value = BATTLE_SPEED_MIN
	slider.max_value = BATTLE_SPEED_MAX
	slider.step = 10
	slider.value = battle_speed
	slider.custom_minimum_size = Vector2(260, 26)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pct := Label.new()
	pct.text = "%d%%" % battle_speed
	pct.custom_minimum_size.x = 56
	slider.value_changed.connect(func(v: float) -> void:
		battle_speed = int(v)
		pct.text = "%d%%" % battle_speed
		if on_change.is_valid():
			on_change.call(battle_speed))
	row.add_child(slider)
	row.add_child(pct)
	return row


func save() -> void:
	# Las pruebas automáticas lo ponen para no tocar el guardado del jugador.
	if OS.has_environment("POKE_TACTICS_NO_SAVE"):
		return
	var cfg := ConfigFile.new()
	cfg.set_value("teams", "list", teams.map(func(t: TeamSlot) -> Dictionary:
		return {"name": t.name, "members": t.members.map(func(m: TeamMember) -> Dictionary: return m.to_dict())}))
	cfg.set_value("teams", "current", current_team)
	cfg.set_value("options", "difficulty", difficulty)
	cfg.set_value("options", "volumes", volumes)
	cfg.set_value("options", "battle_speed", battle_speed)
	cfg.set_value("options", "graphics_quality", graphics_quality)
	cfg.set_value("options", "language", language)
	cfg.set_value("tower", "run", tower.to_dict() if tower and not tower.finished else {})
	cfg.set_value("tower", "best", tower_best)
	cfg.set_value("story", "run", story.to_dict() if story else {})
	cfg.set_value("options", "topology", topology)
	cfg.set_value("options", "biome", biome)
	cfg.set_value("options", "weather", weather)
	cfg.save(SAVE_PATH)


func _load_save() -> void:
	var cfg := ConfigFile.new()
	var loaded := cfg.load(SAVE_PATH) == OK
	if loaded:
		for t: Dictionary in cfg.get_value("teams", "list", []):
			var slot := TeamSlot.new()
			slot.name = t.get("name", tr("Equipo %d") % (teams.size() + 1))
			for d: Dictionary in t.get("members", []):
				var m := TeamMember.from_dict(d, find_species)
				if m and slot.members.size() < MAX_TEAM:
					slot.members.append(m)
			if teams.size() < MAX_TEAMS:
				teams.append(slot)
		if teams.is_empty():
			# Formatos antiguos: un solo equipo (con ataques, o solo nombres de especie).
			var slot := TeamSlot.new()
			slot.name = tr("Equipo %d") % 1
			for d: Dictionary in cfg.get_value("team", "members", []):
				var m := TeamMember.from_dict(d, find_species)
				if m and slot.members.size() < MAX_TEAM:
					slot.members.append(m)
			for species_name: String in cfg.get_value("team", "species", []):
				var p := find_species(species_name)
				if p and slot.members.size() < MAX_TEAM:
					slot.members.append(TeamMember.create(p))
			teams.append(slot)
		current_team = clampi(cfg.get_value("teams", "current", 0), 0, teams.size() - 1)
		difficulty = cfg.get_value("options", "difficulty", Difficulty.NORMAL)
		volumes.merge(cfg.get_value("options", "volumes", {}), true)
		battle_speed = clampi(cfg.get_value("options", "battle_speed", BATTLE_SPEED_MAX), BATTLE_SPEED_MIN, BATTLE_SPEED_MAX)
		graphics_quality = clampi(cfg.get_value("options", "graphics_quality", Quality.HIGH), Quality.LOW, Quality.HIGH) as Quality
		language = cfg.get_value("options", "language", "")
		tower_best = cfg.get_value("tower", "best", 0)
		var run: Dictionary = cfg.get_value("tower", "run", {})
		if not run.is_empty():
			tower = TowerRun.from_dict(run)
		var story_run: Dictionary = cfg.get_value("story", "run", {})
		if not story_run.is_empty():
			story = StoryRun.from_dict(story_run)
	if teams.is_empty():
		var slot := TeamSlot.new()
		slot.name = tr("Equipo %d") % 1
		teams.append(slot)
	if loaded:
		topology = cfg.get_value("options", "topology", BoardGrid.Topology.SQUARE)
		biome = cfg.get_value("options", "biome", Biome.Kind.MEADOW)
		weather = cfg.get_value("options", "weather", -1)
	# Primera vez que se abre el juego: un equipo inicial.
	if not loaded and player_team.is_empty():
		for id in ["bulbasaur", "charmander", "squirtle"]:
			var p := find_species(id)
			if p:
				player_team.append(TeamMember.create(p))

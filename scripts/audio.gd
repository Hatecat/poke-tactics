extends Node
## Autoload "Audio": música (con fundido), ambientes de clima, efectos de sonido y gritos.
## Los efectos son de Kenney (CC0); la música y los ambientes los genera tools/make_audio.py;
## los gritos se sintetizan aquí (uno propio por especie, siempre el mismo).

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
const AMBIENCE_DIR := "res://assets/audio/ambience/"
const BUSES := ["Music", "Sfx", "Ambience"]
const POOL_SIZE := 14
const MUSIC_FADE := 1.2
const CRY_RATE := 22050

## Sonido de impacto según el tipo del ataque.
const TYPE_HITS := {
	"normal": "hit_punch", "fighting": "hit_heavy", "rock": "hit_rock", "ground": "hit_rock",
	"steel": "hit_metal", "ice": "hit_glass", "electric": "hit_zap", "fire": "hit_fire",
	"water": "hit_slime", "poison": "hit_slime", "grass": "hit_wood", "bug": "hit_soft",
	"psychic": "hit_psychic", "ghost": "hit_shadow", "dark": "hit_shadow", "dragon": "launch_beam",
	"fairy": "hit_bell", "flying": "hit_wind",
}
## Pasos según el suelo.
const TILE_STEPS := {
	Biome.Tile.GRASS: "step_grass", Biome.Tile.DIRT: "step_soft", Biome.Tile.SAND: "step_soft",
	Biome.Tile.SNOW: "step_snow", Biome.Tile.ICE: "step_snow", Biome.Tile.WATER: "step_water",
	Biome.Tile.MUD: "step_water", Biome.Tile.BRIDGE: "step_stone", Biome.Tile.ROAD: "step_stone",
	Biome.Tile.FLOOR: "step_stone", Biome.Tile.WOOD: "step_stone",
}

var _sfx := {} # nombre -> [AudioStream]
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _music: Array[AudioStreamPlayer] = []
var _music_on := 0
var _music_name := ""
var _ambience: AudioStreamPlayer
var _ambience_name := ""
var _cries := {} # id de especie -> AudioStreamWAV
var _last_hover := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus in BUSES:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")
	_load_sfx()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "Sfx"
		add_child(p)
		_pool.append(p)
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.bus = "Music"
		m.volume_db = -80.0
		add_child(m)
		_music.append(m)
	_ambience = AudioStreamPlayer.new()
	_ambience.bus = "Ambience"
	add_child(_ambience)
	apply_volumes()
	get_tree().node_added.connect(_on_node_added)


# --- Volumen -------------------------------------------------------------------------

## Aplica Game.volumes ({"master", "music", "sfx"} de 0 a 1).
func apply_volumes() -> void:
	var v: Dictionary = Game.volumes
	_set_bus("Master", v.get("master", 0.8))
	_set_bus("Music", v.get("music", 0.6))
	_set_bus("Sfx", v.get("sfx", 0.8))
	_set_bus("Ambience", v.get("sfx", 0.8) * 0.8)


func _set_bus(bus: String, linear: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(i, linear <= 0.001)


# --- Efectos ---------------------------------------------------------------------------

func _load_sfx() -> void:
	for file in DirAccess.get_files_at(SFX_DIR):
		# En builds exportados aparecen como ".ogg.import" o ".ogg.remap".
		file = file.trim_suffix(".import").trim_suffix(".remap")
		if not file.ends_with(".ogg"):
			continue
		var name := file.get_basename()
		name = name.substr(0, name.rfind("_"))
		if not _sfx.has(name):
			_sfx[name] = []
		_sfx[name].append(load(SFX_DIR + file))


## Reproduce un efecto (una variante al azar, con algo de variación de tono).
func sfx(name: String, volume_db := 0.0, pitch := 1.0, jitter := 0.06) -> void:
	var list: Array = _sfx.get(name, [])
	if list.is_empty():
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = list[randi() % list.size()]
	p.volume_db = volume_db
	p.pitch_scale = pitch * randf_range(1.0 - jitter, 1.0 + jitter)
	p.play()


func hit(type: String, crit := false) -> void:
	sfx(TYPE_HITS.get(type, "hit_punch"), 0.0 if not crit else 2.0)
	if crit:
		sfx("hit_heavy", -2.0, 0.85)


func step(tile: int) -> void:
	sfx(TILE_STEPS.get(tile, "step_stone"), -8.0, 1.0, 0.12)


# --- Música y ambiente ----------------------------------------------------------------

## Cambia de pista con fundido cruzado ("" = silencio). No reinicia si ya suena.
func music(name: String) -> void:
	if name == _music_name:
		return
	_music_name = name
	var old := _music[_music_on]
	_music_on = 1 - _music_on
	var new := _music[_music_on]
	var tw := create_tween().set_parallel()
	tw.tween_property(old, "volume_db", -80.0, MUSIC_FADE)
	tw.chain().tween_callback(old.stop)
	if name:
		var stream: AudioStreamOggVorbis = load(MUSIC_DIR + name + ".ogg")
		stream.loop = true
		new.stream = stream
		new.volume_db = -40.0
		new.play()
		create_tween().tween_property(new, "volume_db", 0.0, MUSIC_FADE)


func ambience(name: String) -> void:
	if name == _ambience_name:
		return
	_ambience_name = name
	if name == "":
		create_tween().tween_property(_ambience, "volume_db", -60.0, 0.8).finished.connect(_ambience.stop)
		return
	var stream: AudioStreamOggVorbis = load(AMBIENCE_DIR + name + ".ogg")
	stream.loop = true
	_ambience.stream = stream
	_ambience.volume_db = -30.0
	_ambience.play()
	create_tween().tween_property(_ambience, "volume_db", -4.0, 1.0)


## Pista para el combate según el campo.
func battle_music(biome: int) -> String:
	match Biome.look(biome):
		Biome.Kind.CAVE, Biome.Kind.UNDERWATER, Biome.Kind.CEMETERY: return "cave"
		Biome.Kind.GYM: return "gym"
		Biome.Kind.MEADOW, Biome.Kind.LAKE, Biome.Kind.BEACH: return "battle_heroic"
	return "battle"


func weather_ambience(kind: int) -> String:
	match kind:
		Weather.Kind.RAIN: return "rain"
		Weather.Kind.SAND: return "wind"
		Weather.Kind.HAIL: return "hail"
	return ""


# --- Gritos -----------------------------------------------------------------------------

## Grito sintetizado de la especie: grave si es grande, agudo si es pequeño. `pitch` < 1 = abatido.
func cry(data: PokemonData, pitch := 1.0, volume_db := -4.0) -> void:
	if data == null:
		return
	if not _cries.has(data.id):
		_cries[data.id] = _make_cry(data)
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = _cries[data.id]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


func _make_cry(data: PokemonData) -> AudioStreamWAV:
	var r := RandomNumberGenerator.new()
	r.seed = hash(data.id)
	var base := clampf(780.0 / sqrt(maxf(data.model_height, 0.4)), 260.0, 1300.0)
	var parts := r.randi_range(2, 3)
	var samples := PackedFloat32Array()
	for part in parts:
		var dur := r.randf_range(0.09, 0.22) * (1.0 + 0.3 * (data.size - 1))
		var n := int(dur * CRY_RATE)
		var f_start := base * r.randf_range(0.8, 1.4)
		var f_end := base * r.randf_range(0.6, 1.5)
		var vib_rate := r.randf_range(14.0, 34.0)
		var vib_depth := r.randf_range(0.02, 0.08)
		var harsh := r.randf_range(0.2, 0.75) # mezcla cuadrada/sierra: más áspero en los grandes
		var phase := 0.0
		for i in n:
			var t := float(i) / n
			var f := lerpf(f_start, f_end, t) * (1.0 + vib_depth * sin(TAU * vib_rate * i / CRY_RATE))
			phase = fmod(phase + f / CRY_RATE, 1.0)
			var sq := 1.0 if phase < 0.5 else -1.0
			var saw := phase * 2.0 - 1.0
			var env := minf(1.0, t * 12.0) * pow(1.0 - t, 0.6)
			samples.append((sq * (1.0 - harsh) + saw * harsh) * env * 0.5)
		for i in int(0.02 * CRY_RATE):
			samples.append(0.0)
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = CRY_RATE
	wav.data = bytes
	return wav


# --- Interfaz: clic y hover automáticos en todos los botones ------------------------------

func _on_node_added(node: Node) -> void:
	# Un botón puede salir y volver a entrar en el árbol: se conecta solo la primera vez.
	if node is BaseButton and not node.has_meta("silent") and not node.has_meta("audio_hooked"):
		node.set_meta("audio_hooked", true)
		node.pressed.connect(func() -> void: sfx("ui_click", -6.0))
		node.mouse_entered.connect(_hover)


func _hover() -> void:
	# Evita una ráfaga de ticks al pasar el ratón por una lista de botones.
	var now := Time.get_ticks_msec()
	if now - _last_hover > 60:
		_last_hover = now
		sfx("ui_hover", -16.0, 1.0, 0.02)

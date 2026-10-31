class_name GymDressing
extends Node3D
## Lo que rodea la arena de un gimnasio, fuera de las casillas (no cambia el juego): el emblema de Poké Ball
## en el centro de la cancha, el suelo pulido del edificio con la arena como tarima, luz LED en el zócalo y
## barandilla, gradas con público que salta, muros con estandartes, focos en las esquinas, la medalla sobre
## el sitio del líder con dos estatuas de piedra del Pokémon emblema del tipo, la puerta de entrada y la
## decoración propia del tipo (braseros, fuentes, bobinas...). Lo alto del lado que mira a la cámara se
## oculta para no tapar el tablero.

const FLOOR_Y := -0.25  # = -BoardView.BASE_THICKNESS: la arena queda como una tarima sobre el suelo
const STAND_GAP := 2.4  # del borde de la arena al primer escalón de las gradas
const TIER_DEPTH := 0.9
const TIER_RISE := 0.45
const TIERS := 3
const WALL_HEIGHT := 4.4
const DOOR_WIDTH := 3.0
const STATUE_HEIGHT := 1.4
## Pokémon de las estatuas de cada gimnasio.
const STATUES := {
	"": "rhydon", "normal": "snorlax", "fire": "arcanine", "water": "gyarados", "electric": "raichu",
	"grass": "venusaur", "ice": "articuno", "fighting": "machamp", "poison": "muk", "ground": "nidoking",
	"flying": "pidgeot", "psychic": "alakazam", "bug": "scyther", "rock": "golem", "ghost": "gengar",
	"dragon": "dragonite", "dark": "persian", "steel": "magneton", "fairy": "clefable",
}
const CROWD_COLORS := [Color(0.85, 0.25, 0.22), Color(0.22, 0.45, 0.85), Color(0.95, 0.8, 0.25),
	Color(0.3, 0.7, 0.35), Color(0.9, 0.9, 0.9), Color(0.55, 0.3, 0.7), Color(0.95, 0.55, 0.2), Color(0.2, 0.2, 0.25)]
const SKIN := [Color(0.96, 0.8, 0.66), Color(0.84, 0.64, 0.48), Color(0.6, 0.42, 0.3), Color(0.98, 0.86, 0.74)]
## Público: una malla de persona sentada (piernas, torso, brazos, cabeza y pelo) con el tipo de pieza en el
## color de cada vértice (r) y, en los brazos, el lado (g). Por instancia (INSTANCE_CUSTOM): colores de ropa,
## piel y pelo, el ánimo (tranquilo, aplaude, levanta los brazos) y la fase, para que no se muevan a la vez.
const CROWD_SHADER := """
shader_type spatial;
const vec3 SHIRTS[10] = vec3[10](vec3(0.85, 0.25, 0.22), vec3(0.22, 0.45, 0.85), vec3(0.95, 0.8, 0.25),
	vec3(0.3, 0.68, 0.35), vec3(0.92, 0.92, 0.9), vec3(0.55, 0.3, 0.7), vec3(0.95, 0.55, 0.2),
	vec3(0.22, 0.23, 0.28), vec3(0.4, 0.75, 0.85), vec3(0.85, 0.45, 0.6));
const vec3 PANTS[5] = vec3[5](vec3(0.2, 0.25, 0.4), vec3(0.15, 0.15, 0.17), vec3(0.45, 0.38, 0.3),
	vec3(0.3, 0.35, 0.45), vec3(0.55, 0.52, 0.48));
const vec3 SKIN[5] = vec3[5](vec3(0.96, 0.8, 0.66), vec3(0.84, 0.64, 0.48), vec3(0.6, 0.42, 0.3),
	vec3(0.98, 0.86, 0.74), vec3(0.45, 0.3, 0.22));
const vec3 HAIR[5] = vec3[5](vec3(0.1, 0.08, 0.07), vec3(0.35, 0.22, 0.12), vec3(0.85, 0.7, 0.4),
	vec3(0.6, 0.25, 0.12), vec3(0.75, 0.75, 0.75));
varying vec3 tint;
varying vec3 rest;  // posición sin animar, para dibujar la cara y el pelo sobre la cabeza
varying vec3 hair;
varying float hair_style;
varying float head;

vec3 turn_x(vec3 v, vec3 pivot, float a) {
	vec3 d = v - pivot;
	return pivot + vec3(d.x, d.y * cos(a) - d.z * sin(a), d.y * sin(a) + d.z * cos(a));
}

void vertex() {
	vec4 k = INSTANCE_CUSTOM;
	float part = floor(COLOR.r * 8.0 + 0.5);
	rest = VERTEX;
	head = step(5.5, part) * step(part, 6.5);
	float phase = k.w * 6.2831;
	// Ánimo por rachas: cada grupo se anima y se calma a su ritmo
	float wave = smoothstep(0.2, 0.9, sin(TIME * 0.35 + k.w * 9.0) * 0.5 + 0.5);
	float mood = k.z;  // 0 tranquilo, 0,5 aplaude, 1 levanta los brazos
	if (COLOR.g > 0.1) {
		float side = COLOR.g > 0.75 ? 1.0 : -1.0;
		vec3 shoulder = vec3(0.17 * side, 0.6, 0.0);
		// a > 0 sube el brazo por delante (la cara mira a -z); con el giro al revés los brazos en alto se iban
		// hacia atrás, por detrás de la cabeza
		float a = -0.15 - 0.05 * sin(TIME * 1.3 + phase);  // en reposo, sobre las rodillas
		if (mood > 0.75) {
			a = mix(a, 2.35 + 0.2 * sin(TIME * 7.0 + phase), wave);  // brazos arriba, algo adelantados, agitándolos
		} else if (mood > 0.25) {
			a = mix(a, 0.75, wave);  // brazos al frente
			VERTEX.x -= side * wave * (0.04 + 0.04 * sin(TIME * 12.0 + phase)) * smoothstep(0.45, 0.2, VERTEX.y);
		}
		VERTEX = turn_x(VERTEX, shoulder, a);
	}
	if (part < 3.5 || part > 5.5) {  // torso, cabeza y brazos se inclinan hacia la arena al animarse
		VERTEX = turn_x(VERTEX, vec3(0.0, 0.25, 0.0), -0.12 * wave * step(0.25, mood));
	}
	VERTEX.y += max(0.0, sin(TIME * 6.0 + phase)) * 0.035 * wave * step(0.75, mood);
	int ks = int(k.x * 10.0) % 10;
	int kp = int(k.y * 5.0) % 5;
	int kh = int(k.x * 37.0) % 5;
	int kk = int(k.y * 23.0) % 5;
	hair = HAIR[kh];
	hair_style = fract(k.x * 13.0);
	bool short_sleeves = fract(k.y * 7.0) > 0.5;
	if (part < 0.5) tint = SHIRTS[ks];
	else if (part < 1.5 || part > 5.5) tint = SKIN[kk];
	else if (part < 2.5) tint = HAIR[kh];
	else if (part < 3.5) tint = SHIRTS[ks] * 0.88;
	else if (part < 4.5) tint = PANTS[kp];
	else tint = vec3(0.12, 0.12, 0.13);
	if (part > 6.5 && !short_sleeves) tint = SHIRTS[ks] * 0.88;  // antebrazo: manga larga o piel
}

void fragment() {
	vec3 col = tint;
	if (head > 0.5) {
		// Coordenadas sobre la cabeza como esfera unidad (la cara mira a -z)
		vec3 n = (rest - vec3(0.0, 0.775, 0.0)) / vec3(0.08, 0.095, 0.085);
		// Pelo: corto, largo (baja por la nuca) o casi calvo, con la línea de la frente
		float back = hair_style < 0.4 ? -0.35 : (hair_style < 0.8 ? -0.95 : 0.25);
		float front = hair_style < 0.8 ? 0.4 : 0.7;
		float line = mix(back, front, smoothstep(0.2, -0.5, n.z));
		col = mix(col, hair, step(line, n.y));
		// Cara sencilla: dos ojos y una sonrisa
		float face = step(n.z, -0.55);
		float eye = min(length(vec2(abs(n.x) - 0.36, (n.y - 0.08) * 0.8)), 1.0);
		col = mix(col, vec3(0.06, 0.05, 0.05), face * step(eye, 0.11));
		float smile = abs(n.y - (-0.38 + 0.6 * n.x * n.x));
		col = mix(col, vec3(0.45, 0.15, 0.13), face * step(smile, 0.05) * step(abs(n.x), 0.26));
	}
	ALBEDO = pow(col, vec3(2.2));
	ROUGHNESS = 0.85;
}
"""

var _style: Dictionary
var _type: String
var _min := Vector2.ZERO  # extremos de la arena en el plano (x, z)
var _max := Vector2.ZERO
var _hideable: Array = []  # [nodo, normal hacia fuera]: se oculta cuando queda entre la cámara y la arena
var _mats := {}
var _rng := RandomNumberGenerator.new()


func setup(grid: BoardGrid) -> void:
	_type = grid.gym_type
	_style = Biome.gym_style(_type)
	_rng.seed = hash(_type) + 17
	_min = Vector2(INF, INF)
	_max = Vector2(-INF, -INF)
	for c in grid.all_cells():
		var w := grid.to_world(c)
		_min = _min.min(Vector2(w.x, w.z))
		_max = _max.max(Vector2(w.x, w.z))
	_min -= Vector2(0.5, 0.5)
	_max += Vector2(0.5, 0.5)
	_emblem()
	_hall()
	# Lados: -z es el del líder (equipo rival), +z el del retador, con la puerta.
	var center := (_min + _max) * 0.5
	var half := (_max - _min) * 0.5
	_side(Vector3(center.x, FLOOR_Y, _min.y), Vector3.BACK * -1.0, half.x, "leader")
	_side(Vector3(center.x, FLOOR_Y, _max.y), Vector3.BACK, half.x, "entrance")
	_side(Vector3(_min.x, FLOOR_Y, center.y), Vector3.LEFT, half.y, "")
	_side(Vector3(_max.x, FLOOR_Y, center.y), Vector3.RIGHT, half.y, "")
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_corner(Vector3(center.x + sx * half.x, FLOOR_Y, center.y + sz * half.y), Vector3(sx, 0, sz).normalized())


## Oculta lo alto de los lados que quedan entre la cámara y la arena.
func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var back := cam.global_transform.basis.z
	back = Vector3(back.x, 0, back.z).normalized()
	for entry: Array in _hideable:
		entry[0].visible = (entry[1] as Vector3).dot(back) < 0.3


# --- Cancha ------------------------------------------------------------------------

## Poké Ball pintada en el centro: aro del color de las líneas y botón blanco con su borde.
func _emblem() -> void:
	var line: Color = _style.line
	var c := (_min + _max) * 0.5
	var y := 0.004  # justo sobre el suelo (las zonas y resaltados van más arriba)
	for part in [[_ring_mesh(2.35, 2.6), line], [_ring_mesh(0.55, 0.8), line], [_disc_mesh(0.55), Color(0.96, 0.95, 0.92)]]:
		var mi := _mesh(self, part[0], Vector3(c.x, y, c.y), part[1])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Suelo pulido del edificio, zócalo de luz LED alrededor de la arena y barandilla baja.
func _hall() -> void:
	var c := (_min + _max) * 0.5
	var reach := STAND_GAP + TIERS * TIER_DEPTH + 0.6
	var size := _max - _min + Vector2.ONE * reach * 2.0
	var floor_mi := _mesh(self, _box(Vector3(size.x, 0.3, size.y)), Vector3(c.x, FLOOR_Y - 0.15, c.y), Color.WHITE)
	var polished := StandardMaterial3D.new()
	polished.albedo_color = (_style.floor as Color).darkened(0.45)
	polished.roughness = 0.25
	floor_mi.material_override = polished
	var led := _glow_mat(_style.line, 2.0)
	var rail := _mat(Color(0.82, 0.83, 0.86), 0.3, 0.8)
	var ext := _max - _min
	for horizontal in [true, false]:
		for s in [-1.0, 1.0]:
			var length: float = ext.x if horizontal else ext.y
			var pos := Vector3(c.x, FLOOR_Y + 0.04, c.y)
			var out := Vector3(0, 0, s) if horizontal else Vector3(s, 0, 0)
			pos += out * ((ext.y if horizontal else ext.x) * 0.5 + 0.04)
			var dims := Vector3(length + 0.16, 0.08, 0.08) if horizontal else Vector3(0.08, 0.08, length + 0.16)
			var strip := _mesh(self, _box(dims), pos, Color.WHITE)
			strip.material_override = led
			strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# Barandilla: postes cada metro y pasamanos, algo separada de la arena
			var rail_pos := pos + out * 0.55 + Vector3.UP * 0.36
			var bar_dims := Vector3(length + 1.1, 0.05, 0.05) if horizontal else Vector3(0.05, 0.05, length + 1.1)
			_mesh(self, _box(bar_dims), rail_pos, Color.WHITE).material_override = rail
			var along := Vector3(1, 0, 0) if horizontal else Vector3(0, 0, 1)
			for i in int(length) + 2:
				var p := rail_pos + along * (float(i) - (length + 1.0) * 0.5) + Vector3.DOWN * 0.18
				_mesh(self, _cyl(0.025, 0.025, 0.36, 6), p, Color.WHITE).material_override = rail


# --- Edificio ------------------------------------------------------------------------

## Un lado del edificio, construido en un marco local: x a lo largo del lado, z hacia fuera.
## `role`: "leader" (medalla y estatuas), "entrance" (puerta y alfombra) o "".
func _side(origin: Vector3, out: Vector3, half_len: float, role: String) -> void:
	var side := Node3D.new()
	add_child(side)
	side.position = origin
	side.basis = Basis(Vector3.UP.cross(out), Vector3.UP, out)
	_hideable.append([side, out])
	var length := half_len + STAND_GAP  # mitad de la longitud de las gradas
	var gap := DOOR_WIDTH * 0.5 if role == "entrance" else 0.0
	var seat := (_style.side as Color).darkened(0.25)
	# Gradas: escalones corridos (partidos por la puerta en la entrada)
	for i in TIERS:
		var z := STAND_GAP + TIER_DEPTH * (i + 0.5)
		var h := TIER_RISE * (i + 1)
		for seg in ([[-length, -gap], [gap, length]] if gap > 0.0 else [[-length, length]]):
			var w: float = seg[1] - seg[0]
			_mesh(side, _box(Vector3(w, h, TIER_DEPTH)), Vector3((seg[0] + seg[1]) * 0.5, h * 0.5, z), seat.lightened(0.06 * (i % 2)))
			# Borde de cada escalón con el color del gimnasio
			_mesh(side, _box(Vector3(w, 0.04, 0.06)), Vector3((seg[0] + seg[1]) * 0.5, h + 0.02, z - TIER_DEPTH * 0.5 + 0.03), _style.line)
	_crowd(side, length, gap)
	# Muro del fondo con remate, estandartes y, según el lado, la medalla o la puerta
	var wall_z := STAND_GAP + TIERS * TIER_DEPTH + 0.15
	var wall_len := (length + TIERS * TIER_DEPTH + 0.45) * 2.0
	var wall_col := (_style.side as Color).darkened(0.1)
	_mesh(side, _box(Vector3(wall_len, WALL_HEIGHT, 0.3)), Vector3(0, WALL_HEIGHT * 0.5, wall_z), wall_col)
	var trim := _mesh(side, _box(Vector3(wall_len, 0.12, 0.34)), Vector3(0, WALL_HEIGHT - 0.3, wall_z), Color.WHITE)
	trim.material_override = _glow_mat(_style.line, 0.6)
	var face := wall_z - 0.17
	var step := 3.4
	var count := int(length * 2.0 / step)
	for i in count:
		var x := (float(i) - (count - 1) * 0.5) * step
		if role == "leader" and absf(x) < 1.8:
			continue  # sitio de la medalla
		_banner(side, Vector3(x, WALL_HEIGHT - 1.55, face))
	match role:
		"leader":
			_medal(side, Vector3(0, WALL_HEIGHT - 1.5, face))
			for sx in [-1.0, 1.0]:
				_statue(side, Vector3(sx * 4.2, 0, 1.15))
		"entrance":
			_mesh(side, _box(Vector3(DOOR_WIDTH - 0.4, 2.6, 0.06)), Vector3(0, 1.3, face), Color(0.08, 0.08, 0.1))
			_mesh(side, _box(Vector3(DOOR_WIDTH, 0.2, 0.12)), Vector3(0, 2.7, face), _style.line)
			var carpet := _mesh(side, _box(Vector3(1.6, 0.02, wall_z - 0.3)), Vector3(0, 0.01, (wall_z + 0.3) * 0.5), (_style.line as Color).darkened(0.35))
			carpet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Decoración del tipo a lo largo del pasillo entre la arena y las gradas
	var spots := [-half_len + 1.2, half_len - 1.2]
	if role == "":
		spots.append(0.0)
	for x: float in spots:
		var d := _decor()
		d.position = Vector3(x, 0, 1.25)
		d.rotation.y = PI  # de cara a la arena
		side.add_child(d)


## Público en las gradas: asientos con respaldo (algunos vacíos), pasillos con escaleras cada pocos asientos y
## personas sentadas de cara a la arena, de distinta talla y complexión, todas en una MultiMesh (una llamada).
## Delante, un panel de luz con los colores del gimnasio.
func _crowd(side: Node3D, length: float, gap: float) -> void:
	var spots: Array[Vector3] = []
	var seats: Array[Vector3] = []
	var aisle_every := 9
	for i in TIERS:
		var x := -length + 0.3
		var n := 0
		while x < length - 0.3:
			if absf(x) > gap + 0.2:
				var p := Vector3(x, TIER_RISE * (i + 1), STAND_GAP + TIER_DEPTH * (i + 0.62))
				if n % aisle_every == aisle_every - 1:
					if i < TIERS - 1:  # escalones del pasillo, a media altura entre gradas
						_mesh(side, _box(Vector3(0.4, TIER_RISE * 0.5, TIER_DEPTH * 0.5)),
							Vector3(x, TIER_RISE * (i + 1.25), STAND_GAP + TIER_DEPTH * (i + 1.25)), (_style.side as Color).darkened(0.35))
				else:
					seats.append(p)
					if _rng.randf() > 0.18:
						spots.append(p + Vector3(_rng.randf_range(-0.03, 0.03), 0.06, 0.0))
			x += 0.46
			n += 1
	# Asientos: una malla de banqueta con respaldo
	var seat_mesh := _seat_mesh()
	var seat_mm := MultiMesh.new()
	seat_mm.transform_format = MultiMesh.TRANSFORM_3D
	seat_mm.mesh = seat_mesh
	seat_mm.instance_count = seats.size()
	for i in seats.size():
		seat_mm.set_instance_transform(i, Transform3D(Basis(), seats[i]))
	var seat_mmi := MultiMeshInstance3D.new()
	seat_mmi.multimesh = seat_mm
	seat_mmi.material_override = _mat((_style.line as Color).darkened(0.25), 0.45)
	side.add_child(seat_mmi)
	# Personas
	var shader := Shader.new()
	shader.code = CROWD_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _person_mesh()
	mm.instance_count = spots.size()
	for i in spots.size():
		var tall := _rng.randf_range(0.9, 1.1)
		var wide := _rng.randf_range(0.9, 1.15)
		# Cada uno mira hacia el centro de la arena (algo por delante de su lado), con un ligero desvío
		var turn := clampf(atan2(spots[i].x, spots[i].z + 5.0), -0.7, 0.7) + _rng.randf_range(-0.06, 0.06)
		var basis := Basis(Vector3.UP, turn).scaled(Vector3(wide, tall, wide))
		mm.set_instance_transform(i, Transform3D(basis, spots[i]))
		var mood: float = [0.0, 0.0, 0.5, 0.5, 1.0][_rng.randi() % 5]
		mm.set_instance_custom_data(i, Color(_rng.randf(), _rng.randf(), mood, _rng.randf()))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	side.add_child(mmi)
	# Panel de luz al pie de las gradas: franjas del color del gimnasio sobre fondo oscuro
	var panel_z := STAND_GAP - 0.1
	for seg in ([[-length, -gap], [gap, length]] if gap > 0.0 else [[-length, length]]):
		var w: float = seg[1] - seg[0]
		var mid: float = (seg[0] + seg[1]) * 0.5
		_mesh(side, _box(Vector3(w, 0.42, 0.08)), Vector3(mid, 0.21, panel_z), Color(0.06, 0.06, 0.08))
		var count := int(w / 1.6)
		for k in count:
			var bx := mid + (float(k) - (count - 1) * 0.5) * 1.6
			var strip := _mesh(side, _box(Vector3(1.3, 0.26, 0.02)), Vector3(bx, 0.21, panel_z - 0.05), Color.WHITE)
			strip.material_override = _glow_mat((_style.line as Color) if k % 2 == 0 else (_style.floor as Color).lightened(0.3), 1.1)
			strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Persona sentada de cara a -z (hacia la arena) para la MultiMesh del público, hecha de piezas redondeadas
## continuas (tronco con cintura y hombros, brazo y antebrazo, muslo y pierna, zapatos, cuello y cabeza). El
## color de cada vértice dice qué pieza es (r: 0 camiseta, 1 piel, 3 mangas, 4 pantalón, 5 zapatos, 6 cabeza,
## 7 antebrazo) y, en los brazos, el lado (g). La cara y el pelo los pinta el shader sobre la cabeza.
func _person_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := [0]
	# Tubo por una línea de puntos con su radio (0 cierra la punta, redondeada); `flat` aplasta la sección
	var tube := func(pts: Array, radii: Array, kind: int, arm := 0.0, seg := 8, flat := 1.0) -> void:
		var col := Color(kind / 8.0, arm, 0.0)
		var base: int = count[0]
		for i in pts.size():
			var tan: Vector3 = (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
			var u := Vector3.RIGHT if absf(tan.x) < 0.9 else Vector3.UP
			u = (u - tan * u.dot(tan)).normalized()
			var v := tan.cross(u)
			for j in seg:
				var a := TAU * j / seg
				st.set_color(col)
				st.add_vertex(pts[i] + (u * cos(a) + v * sin(a) * flat) * float(radii[i]))
		for i in pts.size() - 1:
			for j in seg:
				var a := base + i * seg + j
				var b := base + i * seg + (j + 1) % seg
				st.add_index(a)
				st.add_index(a + seg)
				st.add_index(b)
				st.add_index(b)
				st.add_index(a + seg)
				st.add_index(b + seg)
		count[0] += pts.size() * seg
	# Elipsoide como tubo vertical
	var blob := func(c: Vector3, r: Vector3, kind: int, arm := 0.0, seg := 8) -> void:
		var pts: Array = []
		var radii: Array = []
		for i in 7:
			var t := PI * i / 6.0
			pts.append(c + Vector3(0, -cos(t) * r.y, 0))
			radii.append(sin(t) * r.x)
		tube.call(pts, radii, kind, arm, seg, r.z / r.x)
	# Tronco: cadera, cintura, pecho y hombros redondeados
	var body_y := [0.2, 0.24, 0.34, 0.46, 0.56, 0.61, 0.645]
	var body_r := [0.0, 0.115, 0.105, 0.125, 0.14, 0.12, 0.0]
	var body: Array = []
	for y in body_y:
		body.append(Vector3(0, y, 0.02 + (0.6 - y) * 0.06))
	tube.call(body, body_r, 0, 0.0, 10, 0.68)
	tube.call([Vector3(0, 0.6, 0.02), Vector3(0, 0.66, 0.015), Vector3(0, 0.7, 0.01)], [0.042, 0.04, 0.04], 1)  # cuello
	blob.call(Vector3(0, 0.775, 0), Vector3(0.08, 0.095, 0.085), 6, 0.0, 10)
	for side in [-1.0, 1.0]:
		var arm := 1.0 if side > 0 else 0.5
		# Brazo: del hombro al codo, y el antebrazo hacia las rodillas, con la mano
		var sh := Vector3(0.155 * side, 0.57, 0.01)
		var elbow := Vector3(0.175 * side, 0.4, -0.03)
		var wrist := Vector3(0.14 * side, 0.32, -0.18)
		tube.call([sh + Vector3(0, 0.035, 0), sh, sh.lerp(elbow, 0.5), elbow], [0.0, 0.05, 0.043, 0.038], 3, arm)
		tube.call([elbow, elbow.lerp(wrist, 0.5), wrist], [0.038, 0.034, 0.028], 7, arm)
		blob.call(wrist + Vector3(0, -0.005, -0.03), Vector3(0.028, 0.032, 0.04), 1, arm, 6)
		# Pierna sentada: muslo hacia delante, pierna hasta el escalón y zapato
		var hip := Vector3(0.068 * side, 0.24, 0.0)
		var knee := Vector3(0.075 * side, 0.25, -0.27)
		var ankle := Vector3(0.075 * side, 0.0, -0.3)
		tube.call([hip + Vector3(0, 0, 0.04), hip, hip.lerp(knee, 0.5), knee, knee + Vector3(0, 0, -0.04)], [0.0, 0.065, 0.06, 0.05, 0.0], 4)
		tube.call([knee, knee.lerp(ankle, 0.5), ankle], [0.048, 0.042, 0.034], 4)
		blob.call(Vector3(0.075 * side, -0.025, -0.33), Vector3(0.042, 0.03, 0.075), 5, 0.0, 6)
	st.generate_normals()
	return st.commit()


## Asiento de grada: banqueta con respaldo.
func _seat_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in [[Vector3(0.38, 0.06, 0.32), Vector3(0, 0.14, -0.02)], [Vector3(0.38, 0.34, 0.05), Vector3(0, 0.3, 0.15)],
			[Vector3(0.06, 0.12, 0.06), Vector3(0, 0.06, 0.0)]]:
		st.append_from(_box(b[0]), 0, Transform3D(Basis(), b[1]))
	return st.commit()


## Estandarte colgado del muro: tela del color de las líneas con un círculo y una franja.
func _banner(parent: Node3D, pos: Vector3) -> void:
	var line: Color = _style.line
	_mesh(parent, _box(Vector3(0.95, 0.06, 0.08)), pos + Vector3(0, 1.0, -0.02), Color(0.75, 0.62, 0.3))  # varilla
	_mesh(parent, _box(Vector3(0.8, 1.9, 0.03)), pos, line)
	_mesh(parent, _box(Vector3(0.8, 0.14, 0.035)), pos + Vector3(0, -0.6, 0), (_style.floor as Color))
	var disc := _mesh(parent, _cyl(0.24, 0.24, 0.02, 16), pos + Vector3(0, 0.25, -0.025), _style.floor)
	disc.rotation.x = PI / 2


## Medalla del gimnasio sobre el sitio del líder: aro dorado, fondo del color del tipo y gema brillante.
func _medal(parent: Node3D, pos: Vector3) -> void:
	var gold := _mat(Color(0.95, 0.75, 0.3), 0.25, 1.0)
	for part in [[0.95, 0.06, gold], [0.75, 0.08, _mat(_style.line)], [0.32, 0.1, _glow_mat((_style.line as Color).lightened(0.3), 1.5)]]:
		var mi := _mesh(parent, _cyl(part[0], part[0], part[1], 6 if part[0] < 0.4 else 24), pos + Vector3(0, 0, -part[1] * 0.5), Color.WHITE)
		mi.rotation.x = PI / 2
		mi.material_override = part[2]
	var light := OmniLight3D.new()
	light.light_color = _style.line
	light.light_energy = 1.2
	light.omni_range = 3.0
	light.position = pos + Vector3(0, 0, -0.8)
	parent.add_child(light)


## Estatua de piedra del Pokémon emblema del tipo sobre un pedestal con placa dorada.
func _statue(parent: Node3D, pos: Vector3) -> void:
	var stone := (_style.pillar as Color).lerp(Color(0.6, 0.6, 0.6), 0.5)
	_mesh(parent, _box(Vector3(0.95, 0.7, 0.95)), pos + Vector3(0, 0.35, 0), stone.darkened(0.2))
	_mesh(parent, _box(Vector3(1.05, 0.1, 1.05)), pos + Vector3(0, 0.75, 0), stone.darkened(0.1))
	_mesh(parent, _box(Vector3(0.5, 0.22, 0.03)), pos + Vector3(0, 0.38, -0.49), Color(0.95, 0.75, 0.3))
	var data := load("res://data/pokemon/%s.tres" % STATUES.get(_type, "rhydon")) as PokemonData
	if data == null or data.model == null:
		return
	var model: Node3D = data.model.instantiate()
	var holder := Node3D.new()
	holder.position = pos + Vector3(0, 0.8, 0)
	holder.rotation.y = PI  # mira a la arena
	parent.add_child(holder)
	holder.add_child(model)
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		var anim: AnimationPlayer = players[0]
		var key: String = data.anim_map.get("idle", "idle")
		for clip in anim.get_animation_list():
			if clip.ends_with(key) or key in clip:
				anim.play(clip)
				anim.advance(0.0)
				anim.pause()  # congelada en la pose de reposo
				break
	Unit.fit_model(model, STATUE_HEIGHT)
	var mat := _mat(stone, 0.85)
	for m: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		m.material_override = mat


## Esquina: base y torre de focos que iluminan la arena.
func _corner(pos: Vector3, out: Vector3) -> void:
	var node := Node3D.new()
	add_child(node)
	node.position = pos + out * (STAND_GAP + TIERS * TIER_DEPTH * 0.7) * 1.2
	_hideable.append([node, out])
	var metal := _mat(Color(0.35, 0.36, 0.4), 0.4, 0.7)
	_mesh(node, _box(Vector3(1.2, 0.4, 1.2)), Vector3(0, 0.2, 0), (_style.side as Color).darkened(0.3))
	_mesh(node, _cyl(0.1, 0.14, 5.2, 8), Vector3(0, 2.8, 0), Color.WHITE).material_override = metal
	var head := Node3D.new()
	head.position = Vector3(0, 5.4, 0)
	node.add_child(head)
	head.look_at_from_position(node.position + head.position, Vector3.ZERO, Vector3.UP)
	head.position = Vector3(0, 5.4, 0)
	_mesh(head, _box(Vector3(1.1, 0.6, 0.3)), Vector3.ZERO, Color.WHITE).material_override = metal
	var lamp := _mesh(head, _box(Vector3(0.95, 0.45, 0.04)), Vector3(0, 0, -0.17), Color.WHITE)
	lamp.material_override = _glow_mat(Color(1.0, 0.97, 0.88), 3.0)
	var spot := SpotLight3D.new()
	spot.light_color = Color(1.0, 0.97, 0.9)
	spot.light_energy = 1.6
	spot.spot_range = 30.0
	spot.spot_angle = 28.0
	spot.position = Vector3(0, 0, -0.3)
	head.add_child(spot)


# --- Decoración por tipo ---------------------------------------------------------------

## Adorno del tipo del gimnasio, con el origen en el suelo.
func _decor() -> Node3D:
	var n := Node3D.new()
	match _type:
		"fire": _brazier(n, Color(1.0, 0.5, 0.15), _mat(Color(0.2, 0.18, 0.18), 0.5, 0.6))
		"dragon": _brazier(n, Color(0.45, 0.55, 1.0), _mat(Color(0.95, 0.75, 0.3), 0.25, 1.0))
		"dark": _torch(n, Color(0.95, 0.15, 0.2))
		"ghost": _candelabra(n)
		"water": _fountain(n)
		"poison": _barrel(n)
		"electric": _tesla(n)
		"grass": _planter(n, true)
		"bug": _bug_plant(n)
		"ice": _ice_spikes(n)
		"fighting": _punching_bag(n)
		"ground": _sand_bones(n)
		"rock": _menhir(n)
		"flying": _windmill(n)
		"psychic": _orb(n)
		"steel": _gears(n)
		"fairy": _ribbon(n)
		_: _planter(n, false)
	return n


func _brazier(n: Node3D, flame: Color, metal: Material) -> void:
	for i in 3:
		var a := TAU * i / 3.0
		var leg := _mesh(n, _cyl(0.025, 0.035, 0.75, 6), Vector3(cos(a) * 0.17, 0.36, sin(a) * 0.17), Color.WHITE)
		leg.rotation = Vector3(sin(a) * 0.25, 0, -cos(a) * 0.25)
		leg.material_override = metal
	_mesh(n, _cyl(0.32, 0.16, 0.2, 14), Vector3(0, 0.8, 0), Color.WHITE).material_override = metal
	_mesh(n, _cyl(0.27, 0.27, 0.02, 14), Vector3(0, 0.89, 0), flame.darkened(0.5)).material_override = _glow_mat(flame, 1.5)
	_flame(n, Vector3(0, 0.92, 0), flame, 1.5)


func _torch(n: Node3D, flame: Color) -> void:
	var iron := _mat(Color(0.15, 0.13, 0.16), 0.5, 0.6)
	_mesh(n, _cyl(0.04, 0.06, 1.3, 6), Vector3(0, 0.65, 0), Color.WHITE).material_override = iron
	_mesh(n, _cyl(0.14, 0.06, 0.16, 8), Vector3(0, 1.36, 0), Color.WHITE).material_override = iron
	_flame(n, Vector3(0, 1.44, 0), flame, 1.0)


func _candelabra(n: Node3D) -> void:
	var brass := _mat(Color(0.55, 0.45, 0.3), 0.35, 0.9)
	_mesh(n, _cyl(0.04, 0.16, 0.1, 10), Vector3(0, 0.05, 0), Color.WHITE).material_override = brass
	_mesh(n, _cyl(0.025, 0.025, 1.0, 6), Vector3(0, 0.55, 0), Color.WHITE).material_override = brass
	_mesh(n, _box(Vector3(0.6, 0.03, 0.03)), Vector3(0, 0.95, 0), Color.WHITE).material_override = brass
	for x in [-0.3, 0.0, 0.3]:
		var y := 1.0 + (0.12 if x == 0.0 else 0.0)
		_mesh(n, _cyl(0.03, 0.03, 0.18, 6), Vector3(x, y + 0.04, 0), Color(0.92, 0.9, 0.85))
		_flame(n, Vector3(x, y + 0.15, 0), Color(0.65, 0.4, 1.0), 0.45, x == 0.0)


func _fountain(n: Node3D) -> void:
	var stone := Color(0.85, 0.88, 0.92)
	_mesh(n, _cyl(0.5, 0.55, 0.3, 18), Vector3(0, 0.15, 0), stone)
	var water := _mesh(n, _cyl(0.44, 0.44, 0.02, 18), Vector3(0, 0.28, 0), Color.WHITE)
	water.material_override = _glow_mat(Color(0.3, 0.65, 0.95), 0.4)
	_mesh(n, _cyl(0.06, 0.09, 0.6, 8), Vector3(0, 0.55, 0), stone)
	_mesh(n, _cyl(0.2, 0.08, 0.08, 12), Vector3(0, 0.86, 0), stone)
	var spray := _particles(n, Vector3(0, 0.9, 0), Color(0.75, 0.9, 1.0, 0.8), 30, 0.05, 0.9)
	spray.initial_velocity_min = 0.9
	spray.initial_velocity_max = 1.2
	spray.spread = 25.0
	spray.gravity = Vector3(0, -4.0, 0)


func _barrel(n: Node3D) -> void:
	_mesh(n, _cyl(0.28, 0.25, 0.75, 14), Vector3(0, 0.375, 0), Color(0.35, 0.3, 0.38))
	for y in [0.15, 0.6]:
		_mesh(n, _cyl(0.29, 0.29, 0.05, 14), Vector3(0, y, 0), Color(0.2, 0.2, 0.22))
	_mesh(n, _cyl(0.25, 0.25, 0.02, 14), Vector3(0, 0.75, 0), Color.WHITE).material_override = _glow_mat(Color(0.7, 0.3, 0.9), 1.2)
	_particles(n, Vector3(0, 0.78, 0), Color(0.75, 0.4, 0.95, 0.9), 8, 0.15, 0.25)


func _tesla(n: Node3D) -> void:
	var metal := _mat(Color(0.6, 0.62, 0.66), 0.3, 0.9)
	_mesh(n, _cyl(0.22, 0.26, 0.15, 10), Vector3(0, 0.075, 0), Color(0.2, 0.2, 0.22))
	for i in 4:
		_mesh(n, _cyl(0.11 - i * 0.015, 0.12 - i * 0.015, 0.22, 10), Vector3(0, 0.26 + i * 0.22, 0), Color(0.75, 0.45, 0.2) if i % 2 else Color(0.85, 0.55, 0.25)).material_override = metal if i % 2 else null
	var torus := TorusMesh.new()
	torus.inner_radius = 0.12
	torus.outer_radius = 0.22
	_mesh(n, torus, Vector3(0, 1.15, 0), Color.WHITE).material_override = metal
	var core := _mesh(n, _sphere(0.08), Vector3(0, 1.15, 0), Color.WHITE)
	core.material_override = _glow_mat(Color(1.0, 0.9, 0.3), 3.0)
	var sparks := _particles(n, Vector3(0, 1.15, 0), Color(1.0, 0.95, 0.5), 14, 0.25, 0.15)
	sparks.initial_velocity_min = 0.6
	sparks.initial_velocity_max = 1.2
	sparks.spread = 180.0
	sparks.gravity = Vector3.ZERO
	var light := _light(n, Vector3(0, 1.15, 0), Color(1.0, 0.9, 0.4), 1.0)
	var tw := light.create_tween().set_loops()
	tw.tween_property(light, "light_energy", 0.2, 0.05)
	tw.tween_property(light, "light_energy", 1.4, 0.07)
	tw.tween_interval(0.4)


func _planter(n: Node3D, flowers: bool) -> void:
	var pot := Color(0.62, 0.4, 0.28) if flowers else Color(0.85, 0.85, 0.82)
	_mesh(n, _cyl(0.28, 0.22, 0.4, 12), Vector3(0, 0.2, 0), pot)
	_mesh(n, _cyl(0.25, 0.25, 0.03, 12), Vector3(0, 0.39, 0), Color(0.3, 0.22, 0.15))
	var leaf := Color(0.25, 0.5, 0.25)
	for i in 5:
		var a := TAU * i / 5.0
		_mesh(n, _sphere(0.17), Vector3(cos(a) * 0.13, 0.55 + 0.05 * (i % 2), sin(a) * 0.13), leaf.lightened(0.05 * (i % 3)))
	_mesh(n, _sphere(0.2), Vector3(0, 0.72, 0), leaf)
	if flowers:
		var petals := [Color(0.95, 0.4, 0.5), Color(0.98, 0.85, 0.3), Color(0.95, 0.95, 0.95)]
		for i in 7:
			var a := TAU * i / 7.0 + 0.4
			_mesh(n, _sphere(0.06), Vector3(cos(a) * 0.22, 0.62 + 0.12 * (i % 3), sin(a) * 0.22), petals[i % 3])


func _bug_plant(n: Node3D) -> void:
	_mesh(n, _cyl(0.22, 0.28, 0.35, 10), Vector3(0, 0.175, 0), Color(0.42, 0.3, 0.2))
	for i in 5:
		var a := TAU * i / 5.0
		var leaf := _mesh(n, _sphere(0.3), Vector3(cos(a) * 0.25, 0.5 + 0.1 * (i % 2), sin(a) * 0.25), Color(0.4, 0.6, 0.2).lightened(0.05 * (i % 3)))
		leaf.scale = Vector3(1.0, 0.25, 0.55)
		leaf.rotation = Vector3(0, -a, 0.5)
	var cocoon := _mesh(n, CapsuleMesh.new(), Vector3(0, 0.75, 0), Color(0.85, 0.78, 0.45))
	cocoon.scale = Vector3(0.22, 0.32, 0.22)
	var bugs := _particles(n, Vector3(0, 0.9, 0), Color(0.75, 1.0, 0.4), 6, 0.45, 0.05)
	bugs.gravity = Vector3.ZERO
	bugs.lifetime = 2.5


func _ice_spikes(n: Node3D) -> void:
	_mesh(n, _sphere(0.4), Vector3(0, 0.02, 0), Color(0.95, 0.97, 1.0)).scale = Vector3(1.0, 0.25, 1.0)
	var ice := _mat(Color(0.7, 0.88, 1.0), 0.1, 0.0)
	ice.metallic_specular = 0.9
	for i in 5:
		var a := TAU * i / 5.0 + 0.3
		var tall := 0.9 if i == 0 else 0.4 + 0.1 * (i % 3)
		var shard := _mesh(n, _cyl(0.0, 0.1 if i == 0 else 0.06, tall, 6), Vector3(0, tall * 0.5, 0) if i == 0 else Vector3(cos(a) * 0.18, tall * 0.45, sin(a) * 0.18), Color.WHITE)
		if i > 0:
			shard.rotation = Vector3(sin(a) * 0.4, 0, -cos(a) * 0.4)
		shard.material_override = ice


func _punching_bag(n: Node3D) -> void:
	var wood := Color(0.45, 0.3, 0.2)
	for x in [-0.35, 0.35]:
		_mesh(n, _box(Vector3(0.07, 1.45, 0.07)), Vector3(x, 0.725, 0), wood)
	_mesh(n, _box(Vector3(0.82, 0.07, 0.07)), Vector3(0, 1.45, 0), wood)
	var pivot := Node3D.new()
	pivot.position = Vector3(0, 1.42, 0)
	n.add_child(pivot)
	_mesh(pivot, _cyl(0.01, 0.01, 0.25, 4), Vector3(0, -0.12, 0), Color(0.6, 0.6, 0.62))
	_mesh(pivot, _capsule(0.17, 0.7), Vector3(0, -0.6, 0), Color(0.75, 0.15, 0.12))
	var tw := pivot.create_tween().set_loops()
	tw.tween_property(pivot, "rotation:x", 0.12, 0.9).set_trans(Tween.TRANS_SINE)
	tw.tween_property(pivot, "rotation:x", -0.12, 0.9).set_trans(Tween.TRANS_SINE)


func _sand_bones(n: Node3D) -> void:
	_mesh(n, _sphere(0.45), Vector3.ZERO, Color(0.8, 0.65, 0.42)).scale = Vector3(1.0, 0.45, 1.0)
	_mesh(n, TerrainFx.rock_mesh(1), Vector3(0.2, 0.15, -0.1), Color(0.55, 0.45, 0.35)).scale = Vector3.ONE * 0.32
	var bone := Node3D.new()
	bone.position = Vector3(-0.1, 0.22, 0.12)
	bone.rotation = Vector3(0, 0.6, PI / 2 - 0.2)
	n.add_child(bone)
	var white := Color(0.94, 0.92, 0.85)
	_mesh(bone, _cyl(0.035, 0.035, 0.42, 6), Vector3.ZERO, white)
	for y in [-0.22, 0.22]:
		for x in [-0.04, 0.04]:
			_mesh(bone, _sphere(0.055), Vector3(x, y, 0), white)


func _menhir(n: Node3D) -> void:
	var stone := Color(0.55, 0.5, 0.45)
	_mesh(n, TerrainFx.rock_mesh(3), Vector3(0, 0.55, 0), stone).scale = Vector3(0.45, 0.75, 0.4)
	# Fósil de amonites apoyado al pie
	var fossil := Node3D.new()
	fossil.position = Vector3(0.3, 0.2, -0.15)
	fossil.rotation = Vector3(PI / 2, 0.3, 0)
	n.add_child(fossil)
	for i in 3:
		var t := TorusMesh.new()
		t.inner_radius = 0.03 + i * 0.05
		t.outer_radius = 0.07 + i * 0.05
		_mesh(fossil, t, Vector3.ZERO, Color(0.78, 0.68, 0.5).darkened(0.08 * i))


func _windmill(n: Node3D) -> void:
	var white := Color(0.92, 0.94, 0.97)
	_mesh(n, _cyl(0.05, 0.08, 1.4, 8), Vector3(0, 0.7, 0), white)
	_mesh(n, _box(Vector3(0.14, 0.14, 0.25)), Vector3(0, 1.42, 0), white)
	var rotor := Node3D.new()
	rotor.position = Vector3(0, 1.42, -0.15)
	n.add_child(rotor)
	for i in 3:
		var blade := Node3D.new()
		blade.rotation.z = TAU * i / 3.0
		rotor.add_child(blade)
		_mesh(blade, _box(Vector3(0.07, 0.48, 0.02)), Vector3(0, 0.26, 0), _style.line)
	var tw := rotor.create_tween().set_loops()
	tw.tween_property(rotor, "rotation:z", TAU, 2.5).from(0.0)


func _orb(n: Node3D) -> void:
	var base := Color(0.85, 0.75, 0.85)
	_mesh(n, _cyl(0.12, 0.22, 0.65, 8), Vector3(0, 0.325, 0), base)
	_mesh(n, _cyl(0.2, 0.12, 0.08, 8), Vector3(0, 0.69, 0), base)
	var orb := _mesh(n, _sphere(0.17), Vector3(0, 1.0, 0), Color.WHITE)
	orb.material_override = _glow_mat(Color(1.0, 0.45, 0.8), 2.0)
	var light := _light(orb, Vector3.ZERO, Color(1.0, 0.5, 0.85), 0.9)
	light.omni_range = 2.0
	var tw := orb.create_tween().set_loops()
	tw.tween_property(orb, "position:y", 1.12, 1.2).set_trans(Tween.TRANS_SINE)
	tw.tween_property(orb, "position:y", 0.95, 1.2).set_trans(Tween.TRANS_SINE)


func _gears(n: Node3D) -> void:
	var steel := _mat(Color(0.7, 0.72, 0.76), 0.3, 0.9)
	_mesh(n, _box(Vector3(0.7, 0.2, 0.3)), Vector3(0, 0.1, 0), Color(0.3, 0.32, 0.36))
	for g in [[Vector3(-0.15, 0.55, 0), 0.3, 1.0], [Vector3(0.24, 0.85, 0.02), 0.2, -1.5]]:
		var gear := Node3D.new()
		gear.position = g[0]
		n.add_child(gear)
		var r: float = g[1]
		var disc := _mesh(gear, _cyl(r, r, 0.08, 16), Vector3.ZERO, Color.WHITE)
		disc.rotation.x = PI / 2
		disc.material_override = steel
		var teeth := int(r * 30)
		for i in teeth:
			var a := TAU * i / teeth
			var tooth := _mesh(gear, _box(Vector3(0.07, 0.08, 0.08)), Vector3(cos(a), sin(a), 0) * (r + 0.03), Color.WHITE)
			tooth.rotation.z = a
			tooth.material_override = steel
		_mesh(gear, _cyl(r * 0.3, r * 0.3, 0.1, 10), Vector3.ZERO, Color(0.3, 0.32, 0.36)).rotation.x = PI / 2
		var tw := gear.create_tween().set_loops()
		tw.tween_property(gear, "rotation:z", TAU * signf(g[2]), absf(g[2]) * 4.0).from(0.0)


func _ribbon(n: Node3D) -> void:
	var pink := Color(0.98, 0.6, 0.78)
	_mesh(n, _cyl(0.035, 0.05, 1.25, 8), Vector3(0, 0.625, 0), Color(0.98, 0.92, 0.95))
	_mesh(n, _sphere(0.1), Vector3(0, 1.3, 0), Color.WHITE).material_override = _glow_mat(Color(1.0, 0.8, 0.9), 1.5)
	for s in [-1.0, 1.0]:
		var loop := _mesh(n, _sphere(0.12), Vector3(s * 0.13, 1.08, 0), pink)
		loop.scale = Vector3(1.0, 0.6, 0.35)
	_mesh(n, _sphere(0.05), Vector3(0, 1.08, 0), pink.darkened(0.15))
	var stars := _particles(n, Vector3(0, 1.0, 0), Color(1.0, 0.85, 0.95), 10, 0.4, 0.1)
	stars.gravity = Vector3(0, 0.15, 0)
	stars.lifetime = 2.0


# --- Ayudas ------------------------------------------------------------------------------

## Llama de partículas aditivas con una luz que parpadea.
func _flame(parent: Node3D, pos: Vector3, color: Color, size: float, light := true) -> void:
	var p := _particles(parent, pos, color, 16, 0.06 * size, 0.0)
	p.lifetime = 0.55
	p.initial_velocity_min = 0.25 * size
	p.initial_velocity_max = 0.5 * size
	p.gravity = Vector3(0, 1.2 * size, 0)
	p.spread = 10.0
	(p.mesh as QuadMesh).size = Vector2.ONE * 0.22 * size
	var ramp := Gradient.new()
	ramp.set_color(0, Color(color.lightened(0.6), 0.9))
	ramp.add_point(0.35, Color(color, 0.8))
	ramp.set_color(ramp.get_point_count() - 1, Color(color.darkened(0.3), 0.0))
	p.color_ramp = ramp
	if light:
		var l := _light(parent, pos + Vector3.UP * 0.2, color, 0.8)
		var tw := l.create_tween().set_loops()
		tw.tween_property(l, "light_energy", 1.05, 0.12)
		tw.tween_property(l, "light_energy", 0.65, 0.17)


## Partículas brillantes que suben (o flotan) desde `pos` en una esfera de radio `radius`.
func _particles(parent: Node3D, pos: Vector3, color: Color, amount: int, radius: float, rise: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.position = pos
	p.amount = amount
	p.lifetime = 1.2
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = maxf(radius, 0.01)
	p.direction = Vector3.UP
	p.spread = 15.0
	p.gravity = Vector3(0, rise, 0)
	p.initial_velocity_min = rise * 0.5
	p.initial_velocity_max = rise
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0.2))
	p.scale_amount_curve = curve
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.08
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = WeatherFx._soft_texture(false)
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	quad.material = mat
	p.mesh = quad
	p.color = color
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.emitting = true
	return p


func _light(parent: Node3D, pos: Vector3, color: Color, energy: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = 2.2
	l.position = pos
	parent.add_child(l)
	return l


func _mesh(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = _mat(color)
	parent.add_child(mi)
	return mi


func _mat(color: Color, roughness := 0.8, metallic := 0.0) -> StandardMaterial3D:
	var key := "%s_%.2f_%.2f" % [color.to_html(), roughness, metallic]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = roughness
		m.metallic = metallic
		_mats[key] = m
	return _mats[key]


func _glow_mat(color: Color, energy: float) -> StandardMaterial3D:
	var key := "glow_%s_%.2f" % [color.to_html(), energy]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = energy
		_mats[key] = m
	return _mats[key]


func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


func _cyl(top_r: float, bottom_r: float, h: float, segments := 10) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top_r
	m.bottom_radius = bottom_r
	m.height = h
	m.radial_segments = segments
	m.rings = 1
	return m


func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 12
	m.rings = 6
	return m


func _capsule(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	return m


## Corona plana (aro) en el suelo, de radio interior `r0` a exterior `r1`.
func _ring_mesh(r0: float, r1: float, segs := 48) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var p := [Vector3(cos(a0), 0, sin(a0)), Vector3(cos(a1), 0, sin(a1))]
		for v in [p[0] * r0, p[0] * r1, p[1] * r1, p[0] * r0, p[1] * r1, p[1] * r0]:
			st.add_vertex(v)
	return st.commit()


func _disc_mesh(r: float, segs := 32) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		for v in [Vector3.ZERO, Vector3(cos(a0), 0, sin(a0)) * r, Vector3(cos(a1), 0, sin(a1)) * r]:
			st.add_vertex(v)
	return st.commit()

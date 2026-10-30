class_name AirlinerMesh
## Avión de pasajeros de superficies suaves para el aeropuerto: fuselaje de una pieza (secciones elípticas con
## morro afilado y cola que sube hacia la deriva) con ventanillas, cabina, puertas y franja pintadas por shader;
## alas, estabilizadores y deriva con perfil aerodinámico (borde de ataque redondeado), en flecha y
## estrechándose, con winglets curvos; motores torneados con labio de toma de aire y tobera. Mira hacia +z,
## con el suelo en y = 0. Superficies: 0 fuselaje (shader), 1 pintura, 2 metal, 3 negro (tomas y ruedas).

const FUSELAGE_SHADER := """
shader_type spatial;
uniform vec4 livery : source_color = vec4(0.85, 0.2, 0.2, 1.0);
uniform float shade = 1.0;  // fuera del tablero se oscurece como el resto del adorno
varying vec3 lp;
void vertex() {
	lp = VERTEX;
}
float box(vec2 p, vec2 c, vec2 h, float r) {
	vec2 d = abs(p - c) - h + r;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}
void fragment() {
	vec3 col = vec3(0.95, 0.96, 0.98);
	float side = step(0.18, abs(lp.x));
	// Panza gris claro y franja de la aerolínea a lo largo, bajo las ventanillas
	col = mix(col, vec3(0.78, 0.8, 0.83), smoothstep(0.47, 0.43, lp.y));
	col = mix(col, livery.rgb, side * step(abs(lp.y - 0.585), 0.018) * step(-1.0, lp.z) * step(lp.z, 1.15));
	// Ventanillas: fila de óvalos oscuros a los dos lados
	float k = (lp.z + 0.8) / 0.11;
	float win = box(vec2(fract(k) - 0.5, (lp.y - 0.67) / 0.11), vec2(0.0), vec2(0.18, 0.2), 0.17);
	float in_row = step(0.0, k) * step(k, 15.0) * side;
	col = mix(col, vec3(0.1, 0.13, 0.18), in_row * smoothstep(0.02, -0.02, win));
	// Puertas: contorno fino delante y detrás
	for (int i = 0; i < 2; i++) {
		float dz = i == 0 ? 0.98 : -0.9;
		float door = abs(box(vec2(lp.z, lp.y), vec2(dz, 0.62), vec2(0.05, 0.11), 0.02));
		col = mix(col, vec3(0.55, 0.57, 0.6), side * smoothstep(0.006, 0.0, door));
	}
	// Cabina: cristales oscuros en el morro, con montantes
	float cz = lp.z - 1.24;
	float cy = lp.y - (0.735 - cz * 0.3);
	float cab = step(abs(cz), 0.06) * step(abs(cy), 0.028) * step(0.025, abs(lp.x));
	col = mix(col, vec3(0.08, 0.1, 0.14), cab * step(0.006, abs(fract(lp.x / 0.08) - 0.5) * 0.08));
	ALBEDO = col * shade;
	ROUGHNESS = 0.3;
	SPECULAR = 0.6;
}
"""

const Y0 := 0.62  # altura del eje del fuselaje
const RING := 28  # vértices por sección del fuselaje


## Malla del avión con la franja y la deriva de color `livery` (cacheada por quien llama).
static func build(livery: Color) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	_add(mesh, _fuselage())
	var paint := SurfaceTool.new()
	paint.begin(Mesh.PRIMITIVE_TRIANGLES)
	var metal := SurfaceTool.new()
	metal.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dark := SurfaceTool.new()
	dark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var white := Color(0.94, 0.95, 0.97)
	for side in [-1.0, 1.0]:
		# Ala: raíz bajo el fuselaje, punta en flecha hacia atrás y algo más alta, y winglet curvo hacia arriba
		var wing: Array = []
		for t in _steps(10):
			var span := 0.15 + 1.3 * t
			var chord := lerpf(0.78, 0.24, t)
			var lead := 0.42 - 0.62 * t  # borde de ataque
			wing.append(_airfoil(Vector3(span * side, Y0 - 0.17 + 0.09 * t, lead), chord, 0.12, Vector3.RIGHT * side))
		for k in 4:
			var a := (k + 1) / 4.0 * PI * 0.45
			var r := 0.14
			var base := Vector3((1.45 + sin(a) * r * 0.6) * side, Y0 - 0.08 + (1.0 - cos(a)) * r + sin(a) * 0.06, -0.2 - k * 0.03)
			wing.append(_airfoil(base, lerpf(0.22, 0.12, k / 3.0), 0.1, Vector3.RIGHT * side))
		_loft(paint, wing, white, side < 0)
		# Estabilizador horizontal
		var stab: Array = []
		for t in _steps(6):
			stab.append(_airfoil(Vector3((0.08 + 0.55 * t) * side, Y0 + 0.13 + 0.04 * t, -1.18 - 0.28 * t), lerpf(0.36, 0.14, t), 0.1, Vector3.RIGHT * side))
		_loft(paint, stab, white, side < 0)
		# Motor torneado bajo el ala, con pilón
		var center := Vector3(0.6 * side, Y0 - 0.3, 0.32)
		_lathe(metal, center, [[0.28, 0.105], [0.26, 0.128], [0.2, 0.136], [0.0, 0.135], [-0.14, 0.12], [-0.22, 0.09], [-0.26, 0.07]], Color(0.72, 0.74, 0.78))
		_lathe(dark, center, [[0.27, 0.0], [0.27, 0.1]], Color(0.07, 0.07, 0.08))  # toma de aire
		_lathe(dark, center, [[-0.25, 0.068], [-0.34, 0.0]], Color(0.25, 0.25, 0.27))  # cono de escape
		var pylon: Array = []
		for t in _steps(3):
			pylon.append(_airfoil(center + Vector3(0, 0.1 + 0.08 * t, 0.02 - 0.06 * t), 0.4, 0.14, Vector3.UP))
		_loft(paint, pylon, white.darkened(0.06), side > 0)
	# Deriva en flecha con el color de la aerolínea
	var fin: Array = []
	for t in _steps(8):
		fin.append(_airfoil(Vector3(0, Y0 + 0.15 + 0.62 * t, -1.08 - 0.42 * t), lerpf(0.62, 0.24, t), 0.1, Vector3.UP))
	_loft(paint, fin, livery, false)
	# Tren de aterrizaje: patas finas y ruedas dobles (toros)
	for at in [Vector3(0, 0, 0.92), Vector3(-0.2, 0, 0.0), Vector3(0.2, 0, 0.0)]:
		_lathe(metal, at + Vector3(0, 0.07, 0), [[0.0, 0.018], [Y0 - 0.33, 0.018]], Color(0.62, 0.64, 0.68), Vector3.UP)
		for wx in [-0.045, 0.045]:
			_lathe(dark, at + Vector3(wx, 0.07, 0), [[-0.022, 0.0], [-0.022, 0.06], [-0.016, 0.07], [0.016, 0.07], [0.022, 0.06], [0.022, 0.0]], Color(0.07, 0.07, 0.08), Vector3.RIGHT)
	for st: SurfaceTool in [paint, metal, dark]:
		st.index()
		st.generate_normals()
		_add(mesh, st)
	return mesh


static func materials(livery: Color, shade := 1.0) -> Array[Material]:
	var fus := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = FUSELAGE_SHADER
	fus.shader = shader
	fus.set_shader_parameter("livery", livery)
	fus.set_shader_parameter("shade", shade)
	var paint := StandardMaterial3D.new()
	paint.vertex_color_use_as_albedo = true
	paint.vertex_color_is_srgb = true
	paint.roughness = 0.32
	var metal := StandardMaterial3D.new()
	metal.vertex_color_use_as_albedo = true
	metal.vertex_color_is_srgb = true
	metal.roughness = 0.28
	metal.metallic = 0.7
	var dark := StandardMaterial3D.new()
	dark.vertex_color_use_as_albedo = true
	dark.vertex_color_is_srgb = true
	dark.roughness = 0.8
	for m: StandardMaterial3D in [paint, metal, dark]:
		m.albedo_color = Color(shade, shade, shade)
	return [fus, paint, metal, dark]


static func _add(mesh: ArrayMesh, st: SurfaceTool) -> void:
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays())


static func _steps(n: int) -> Array[float]:
	var out: Array[float] = []
	for i in n + 1:
		out.append(float(i) / n)
	return out


## Fuselaje: secciones casi circulares (algo achatadas por la panza) a lo largo de z. Radio y altura del eje
## siguen curvas continuas: morro elíptico, tramo recto y cono de cola que se estrecha y sube hacia la deriva.
static func _fuselage() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var zs: Array[float] = []
	for i in 15:  # morro, con más secciones junto a la punta
		zs.append(1.5 - 0.55 * pow(i / 15.0, 1.6))
	for i in 12:
		zs.append(lerpf(0.95, -0.75, i / 12.0))
	for i in 17:  # cola
		zs.append(-0.75 - 0.89 * sin(i / 16.0 * PI * 0.5))
	for z in zs:
		var r := 0.3
		var yc := 0.0
		if z > 0.95:
			var t := (z - 0.95) / 0.55
			r = 0.3 * sqrt(maxf(1.0 - pow(t, 2.4), 0.0))
			yc = -0.06 * t * t
		elif z < -0.75:
			var t := (-0.75 - z) / 0.89
			r = 0.3 * pow(maxf(1.0 - pow(t, 1.7), 0.0), 0.75)
			yc = 0.18 * pow(t, 1.4)
		for j in RING + 1:
			var ang := TAU * j / RING
			var y := cos(ang) * r * (0.94 if cos(ang) < 0.0 else 1.0)
			st.set_uv(Vector2(j / float(RING), z))
			st.add_vertex(Vector3(sin(ang) * r, Y0 + yc + y, z))
	for i in zs.size() - 1:
		for j in RING:
			var a := i * (RING + 1) + j
			var b := a + RING + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(a + 1)
			st.add_index(a + 1)
			st.add_index(b)
			st.add_index(b + 1)
	st.generate_normals()
	return st


## Sección de perfil aerodinámico simétrico (NACA 00xx) de cuerda `chord` hacia -z desde `lead`, con el grosor
## perpendicular a la envergadura `span_dir` y a la cuerda.
static func _airfoil(lead: Vector3, chord: float, thick: float, span_dir: Vector3) -> PackedVector3Array:
	var up := span_dir.cross(Vector3.BACK).normalized()
	if up.length() < 0.5:
		up = Vector3.UP
	if span_dir.abs() == Vector3.UP:
		up = Vector3.RIGHT
	var pts := PackedVector3Array()
	var n := 10
	for i in range(n, -1, -1):  # extradós, del borde de salida al de ataque
		pts.append(_foil_point(lead, chord, thick, up, i / float(n), 1.0))
	for i in range(1, n + 1):  # intradós, de vuelta
		pts.append(_foil_point(lead, chord, thick, up, i / float(n), -1.0))
	return pts


static func _foil_point(lead: Vector3, chord: float, thick: float, up: Vector3, u: float, sgn: float) -> Vector3:
	var x := (1.0 - cos(u * PI)) * 0.5  # más puntos junto a los bordes
	var y := 5.0 * thick * (0.2969 * sqrt(x) - 0.126 * x - 0.3516 * x * x + 0.2843 * x * x * x - 0.1036 * x * x * x * x)
	return lead + Vector3(0, 0, -x * chord) + up * y * chord * sgn


## Superficie que pasa por las secciones (anillos cerrados del mismo tamaño), con tapas en los extremos.
static func _loft(st: SurfaceTool, sections: Array, color: Color, flip: bool) -> void:
	var base := 0
	var verts: Array[Vector3] = []
	for sec: PackedVector3Array in sections:
		for p in sec:
			verts.append(p)
	var m: int = (sections[0] as PackedVector3Array).size()
	var tris: Array[int] = []
	for i in sections.size() - 1:
		for j in m:
			var a := i * m + j
			var b := i * m + (j + 1) % m
			var c := a + m
			var d := b + m
			tris.append_array([a, c, b, b, c, d])
	for cap in [0, sections.size() - 1]:  # tapas: abanico desde el primer punto
		for j in range(1, m - 1):
			var t := [cap * m, cap * m + j, cap * m + j + 1]
			tris.append_array(t if cap > 0 else [t[0], t[2], t[1]])
	for k in range(0, tris.size(), 3):
		var order := [0, 2, 1] if flip else [0, 1, 2]
		for o in order:
			st.set_color(color)
			st.add_vertex(verts[tris[k + o]])


## Pieza torneada alrededor del eje `axis` (z por defecto) que pasa por `center`: perfil de [posición en el eje,
## radio].
static func _lathe(st: SurfaceTool, center: Vector3, profile: Array, color: Color, axis := Vector3.BACK) -> void:
	var seg := 20
	var u := Vector3.UP if axis != Vector3.UP else Vector3.RIGHT
	var v := axis.cross(u)
	for i in profile.size() - 1:
		var a: Array = profile[i]
		var b: Array = profile[i + 1]
		for j in seg:
			var t0 := TAU * j / seg
			var t1 := TAU * (j + 1) / seg
			var p := func(row: Array, t: float) -> Vector3:
				return center + axis * float(row[0]) + (u * cos(t) + v * sin(t)) * float(row[1])
			var q := [p.call(a, t0), p.call(a, t1), p.call(b, t0), p.call(b, t1)]
			for idx in [0, 2, 1, 1, 2, 3]:
				st.set_color(color)
				st.add_vertex(q[idx])

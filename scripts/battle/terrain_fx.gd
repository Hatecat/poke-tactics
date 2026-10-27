class_name TerrainFx
extends RefCounted
## Materiales y mallas vivas del terreno: vegetación que se mece con el viento, agua con oleaje,
## laterales con capas de suelo y roca, detalles del suelo (hierba, flores, juncos, piedras...) y
## partículas de ambiente de cada bioma. Lo usa BoardView.

## Vegetación: la parte alta se desplaza con el viento (ráfagas lentas + temblor de hojas). `base_y` y
## `height` (por instancia) dicen dónde empieza a doblarse y cuánto mide.
const FOLIAGE_SHADER := "
shader_type spatial;
uniform vec4 albedo : source_color = vec4(1.0);
uniform bool vertex_color = false;
uniform float sway = 1.0;
uniform float flutter = 0.0;
uniform float wind = 1.0;
uniform vec2 wind_dir = vec2(1.0, 0.3);  // como el viento de la tormenta de arena
uniform float glow = 0.0;
uniform float pulse = 0.0;
uniform float roughness = 0.85;
uniform float wet = 0.0;
uniform float push = 0.0;  // 1 en la hierba: se aparta y se aplasta alrededor de los Pokémon
uniform vec4 pushers[12];  // xyz = pies de cada Pokémon, w = radio (0 = libre)
uniform int pattern = 0;  // textura procedural: 0 lisa, 1 copa de hojas, 2 agujas de pino, 3 corteza, 4 corteza con musgo
instance uniform float base_y = 0.0;
instance uniform float height = 1.0;
varying vec3 rest_pos;  // posición en el mundo sin viento: la textura no resbala al mecerse

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x),
			mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x),
			mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// Distancia al centro de la hoja más cercana (celdas de Voronoi): 0 en el centro, ~1 en los huecos.
float leaves(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float d = 8.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			for (int z = -1; z <= 1; z++) {
				vec3 o = vec3(float(x), float(y), float(z));
				vec3 h = vec3(hash13(i + o), hash13(i + o + 17.1), hash13(i + o + 41.7));
				d = min(d, length(o + h - f));
			}
		}
	}
	return d;
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	rest_pos = wp;
	float k = clamp((wp.y - base_y) / height, 0.0, 1.4);
	k *= k;
	float ph = dot(MODEL_MATRIX[3].xz, vec2(0.37, 0.29));
	float gust = 0.55 + 0.45 * sin(TIME * 0.45 + wp.x * 0.13 + wp.z * 0.07);
	float s = (sin(TIME * 1.7 + ph) * 0.6 + sin(TIME * 3.1 + ph * 1.7) * 0.25 + 0.5) * gust;
	vec2 off = normalize(wind_dir) * s * sway * wind * k * 0.12;
	off += vec2(sin(TIME * 8.0 + wp.y * 11.0 + wp.x * 7.0), cos(TIME * 7.0 + wp.z * 9.0 + wp.y * 5.0))
		* flutter * min(wind, 2.0) * k * 0.015;
	wp.xz += off;
	wp.y -= length(off) * 0.35 * k;
	if (push > 0.0) {
		for (int i = 0; i < 12; i++) {
			vec4 u = pushers[i];
			vec2 d = wp.xz - u.xz;
			float dist = length(d);
			if (u.w <= 0.0 || dist > u.w || abs(base_y - u.y) > 0.2) {
				continue;
			}
			float f = push * (1.0 - smoothstep(u.w * 0.35, u.w, dist));
			vec2 dir = dist > 0.001 ? d / dist : vec2(1.0, 0.0);
			wp.xz += dir * f * k * height * 0.9;
			wp.y = max(base_y + 0.01, wp.y - f * k * height * 0.75);
		}
	}
	VERTEX = (inverse(MODEL_MATRIX) * vec4(wp, 1.0)).xyz;
}

void fragment() {
	vec3 c = albedo.rgb;
	if (vertex_color) {
		c *= pow(COLOR.rgb, vec3(2.2));  // color de vértice en sRGB
	}
	if (pattern > 0) {
		vec3 q = rest_pos - NODE_POSITION_WORLD;
		vec3 qn = normalize(q + vec3(0.0, 0.0001, 0.0));
		vec2 dir = normalize(q.xz + vec2(0.0001));
		float up = clamp((rest_pos.y - base_y) / height, 0.0, 1.0);
		float rim = 1.0 - abs(dot(NORMAL, VIEW));  // 1 en la silueta
		float bump = 0.0;  // relieve (en metros) para sombrear las hojas o las grietas
		if (pattern <= 2) {
			float shade;
			float edge;  // lo que se recorta en la silueta: solo formas grandes, sin puntitos
			if (pattern == 1) {
				// Copa: racimos de hojas con bordes en sombra, hojitas finas, manchas grandes, la parte de
				// abajo de cada bola en su propia sombra y la de abajo de la copa en penumbra.
				shade = smoothstep(0.15, 0.8, leaves(rest_pos * 10.0));
				float fine = vnoise(rest_pos * 38.0);
				float tuft = vnoise(rest_pos * 3.5);
				c *= mix(1.2, 0.6, shade) * mix(0.88, 1.1, fine) * mix(0.82, 1.12, tuft) * mix(0.72, 1.08, up);
				c *= mix(0.62, 1.0, smoothstep(-0.9, 0.5, qn.y));
				c = mix(c, c * vec3(1.15, 1.12, 0.78), (1.0 - shade) * up * 0.55);  // puntas al sol, más amarillas
				bump = (1.0 - shade) * 0.03 + fine * 0.006;
				edge = shade;
			} else {
				// Pino: vetas de agujas que caen desde el eje, mechones oscuros y el borde de cada piso, que
				// cuelga, más claro; la parte alta del piso queda bajo el de arriba.
				float streak = vnoise(vec3(dir * 16.0, q.y * 4.0 + vnoise(rest_pos * 5.0) * 2.0));
				float needles = vnoise(vec3(dir * 14.0, q.y * 16.0));
				float clumps = smoothstep(0.1, 0.85, leaves(rest_pos * 12.0));
				shade = clumps * 0.45 + streak * 0.35 + needles * 0.2;
				shade = mix(clumps, shade, smoothstep(0.03, 0.12, length(q.xz)));  // sin rayado en la punta, donde se juntan las vetas
				c *= mix(1.3, 0.55, shade) * mix(0.75, 1.05, up);
				c *= mix(1.12, 0.78, smoothstep(-0.6, 0.6, qn.y));
				bump = (1.0 - shade) * 0.025;
				edge = clumps;
			}
			// Bordes de hoja: en la silueta se recortan los huecos entre racimos (sin bolas lisas).
			if (edge > mix(1.5, 0.5, smoothstep(0.6, 0.97, rim))) {
				discard;
			}
			BACKLIGHT = c * 0.4;  // el sol atraviesa las hojas
		} else {
			// Corteza: grietas verticales irregulares, veta fina, nudos y la base más oscura; con
			// `pattern` 4 sale musgo en la parte baja.
			float n = vnoise(vec3(dir * 3.0, rest_pos.y * 2.2)) * 0.7 + vnoise(vec3(dir * 7.0, rest_pos.y * 5.0)) * 0.3;
			float crack = smoothstep(0.02, 0.18, abs(n - 0.5));
			float grain = vnoise(rest_pos * vec3(30.0, 6.0, 30.0));
			float knot = smoothstep(0.08, 0.16, leaves(vec3(dir * 2.5, rest_pos.y * 4.0)));
			c *= mix(0.5, 1.08, crack) * mix(0.88, 1.1, grain) * mix(0.55, 1.0, knot) * mix(0.7, 1.0, smoothstep(0.0, 0.25, up));
			if (pattern == 4) {
				float moss = smoothstep(0.45, 0.7, vnoise(rest_pos * 9.0) + (0.35 - up) * 1.5) * crack;
				c = mix(c, vec3(0.2, 0.34, 0.12) * mix(0.8, 1.15, grain), moss);
			}
			bump = crack * 0.012 + (1.0 - knot) * 0.008;
		}
		// Relieve sin UV (Mikkelsen): inclina la normal según cómo cambia `bump` en pantalla.
		vec3 dpdx = dFdx(VERTEX);
		vec3 dpdy = dFdy(VERTEX);
		vec3 r1 = cross(dpdy, NORMAL);
		vec3 r2 = cross(NORMAL, dpdx);
		float det = dot(dpdx, r1);
		vec3 grad = sign(det) * (dFdx(bump) * r1 + dFdy(bump) * r2);
		NORMAL = normalize(abs(det) * NORMAL - grad);
	}
	ALBEDO = c * (1.0 - 0.2 * wet);  // mojado: más oscuro y algo más brillante
	ROUGHNESS = mix(roughness, 0.55, wet);
	EMISSION = c * glow * (1.0 + pulse * sin(TIME * 2.2 + NODE_POSITION_WORLD.x * 1.3 + NODE_POSITION_WORLD.z));
}
"

## Agua: olas que recorren todo el tablero (en coordenadas del mundo, así las casillas encajan), reflejos
## que brillan y espuma en las orillas (`shore`: lados con tierra, por instancia: este, sur, oeste, norte).
const WATER_SHADER := "
shader_type spatial;
uniform vec4 deep : source_color = vec4(0.12, 0.36, 0.7, 1.0);
uniform vec4 shallow : source_color = vec4(0.3, 0.62, 0.88, 1.0);
uniform float wind = 1.0;
uniform float waves = 1.0;
uniform float rain = 0.0;
instance uniform vec4 shore = vec4(0.0);
varying vec3 wpos;

// Ondas de las gotas de lluvia: anillos que se abren y se apagan, uno por celdilla, cada uno a su ritmo.
float ripples(vec2 p, float t) {
	float s = 0.0;
	vec2 cell = floor(p * 3.0);
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			vec2 c = cell + vec2(float(x), float(y));
			vec2 h = fract(sin(vec2(dot(c, vec2(127.1, 311.7)), dot(c, vec2(269.5, 183.3)))) * 43758.5453);
			float ph = fract(t * 0.9 + h.x);
			float d = length(p - (c + h) / 3.0);
			s += (1.0 - ph) * smoothstep(0.022, 0.0, abs(d - ph * 0.28));
		}
	}
	return s;
}

float wave(vec2 p, float t) {
	return sin(p.x * 1.3 + t * 1.4) * 0.5 + sin(p.y * 1.7 - t * 1.1 + p.x * 0.4) * 0.35
		+ sin((p.x + p.y) * 2.9 + t * 2.3) * 0.15;
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float a = 0.03 * clamp(wind, 0.4, 2.5) * waves;
	float h = wave(wp.xz, TIME) * a;
	float e = 0.05;
	float hx = wave(wp.xz + vec2(e, 0.0), TIME) * a;
	float hz = wave(wp.xz + vec2(0.0, e), TIME) * a;
	VERTEX.y += h;
	NORMAL = normalize(vec3(h - hx, e, h - hz));
	wpos = wp;
}

void fragment() {
	float r = sin(wpos.x * 5.0 + TIME * 1.5) * sin(wpos.z * 4.3 - TIME * 1.2);
	vec3 col = mix(deep.rgb, shallow.rgb, 0.45 + 0.25 * r);
	float sp = pow(max(0.0, sin(wpos.x * 9.7 + sin(wpos.z * 2.3) * 3.0 + TIME * 2.0) * sin(wpos.z * 8.3 + sin(wpos.x * 1.9) * 3.0 - TIME * 1.7)), 40.0);
	vec4 edge = vec4(UV.x, UV.y, 1.0 - UV.x, 1.0 - UV.y);
	vec4 near = shore * (1.0 - smoothstep(0.0, 0.16 + 0.04 * sin(TIME * 2.0 + wpos.x * 3.0 + wpos.z * 2.0), 1.0 - edge));
	float foam = max(max(near.x, near.y), max(near.z, near.w));
	float drops = rain * min(ripples(wpos.xz, TIME), 1.0);
	ALBEDO = mix(col + sp * 0.7 + drops * 0.45, vec3(0.92, 0.97, 1.0), foam * 0.75);
	ROUGHNESS = mix(0.06, 0.6, foam);
	SPECULAR = 0.8;
}
"

## Laterales de las casillas: arriba el color del suelo (tierra, arena, nieve...), abajo la roca madre,
## con vetas horizontales por cada nivel de altura. `top_y` (por instancia) es lo alto de la casilla.
const SIDE_SHADER := "
shader_type spatial;
uniform vec4 top_color : source_color;
uniform vec4 bottom_color : source_color;
uniform float band = 0.3;
uniform float wet = 0.0;
instance uniform float top_y = 0.0;
varying float wy;

void vertex() {
	wy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	float t = smoothstep(band * 0.6, band * 1.4, top_y - wy);
	vec3 c = mix(top_color.rgb, bottom_color.rgb, t);
	float strata = smoothstep(0.0, 0.025, abs(fract(wy / 0.35 + 0.5) - 0.5));
	ALBEDO = c * mix(0.82, 1.0, strata) * (1.0 - 0.25 * wet);
	ROUGHNESS = mix(0.95, 0.4, wet);
}
"

## Suelo de piedra (cueva y roca): losas irregulares con juntas oscuras y gravilla, cada losa de un tono,
## grano fino y relieve sin UV. Solo en la cara de arriba; `albedo` es el color de la casilla.
const STONE_SHADER := "
shader_type spatial;
uniform vec4 albedo : source_color = vec4(1.0);
uniform float wet = 0.0;
varying vec3 wpos;
varying vec3 wnormal;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x),
			mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x),
			mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec3 c = albedo.rgb;
	float gap = 1.0;
	if (wnormal.y > 0.5) {
		// Voronoi en el plano: distancia a la losa más cercana (f1) y a la segunda (f2).
		vec2 p = wpos.xz * 2.6 + vec2(vnoise(wpos * 2.0), vnoise(wpos * 2.0 + 7.0)) * 0.5;
		vec2 ip = floor(p);
		vec2 fp = fract(p);
		float f1 = 8.0;
		float f2 = 8.0;
		vec2 id = vec2(0.0);
		for (int x = -1; x <= 1; x++) {
			for (int y = -1; y <= 1; y++) {
				vec2 o = vec2(float(x), float(y));
				vec2 cell = ip + o;
				vec2 h = vec2(hash13(vec3(cell, 1.0)), hash13(vec3(cell, 5.0)));
				float d = length(o + h - fp);
				if (d < f1) {
					f2 = f1;
					f1 = d;
					id = cell;
				} else if (d < f2) {
					f2 = d;
				}
			}
		}
		// Grietas de grosor desigual: unas casi cerradas, otras abiertas.
		float width = mix(0.01, 0.06, vnoise(vec3(wpos.xz * 3.0, 4.0)));
		gap = smoothstep(0.0, width, f2 - f1);
		float tone = hash13(vec3(id, 9.0));
		float grain = vnoise(vec3(wpos.xz * 30.0, 0.0));
		float rough = abs(vnoise(vec3(wpos.xz * 9.0, 1.0)) * 2.0 - 1.0);  // superficie áspera, con aristas
		float big = vnoise(vec3(wpos.xz * 1.2, 3.0));
		float gravel = step(0.72, hash13(vec3(floor(wpos.xz * 55.0), 2.0)));
		c *= mix(0.88, 1.1, tone) * mix(0.93, 1.05, grain) * mix(0.86, 1.08, big) * mix(1.04, 0.94, rough);
		c *= mix(1.03, 0.92, f1 * f1);  // cada piedra abombada: el borde algo más oscuro
		c *= mix(0.74 + gravel * 0.2, 1.0, gap);  // grietas suaves con gravilla clara
		float bump = gap * (0.006 + (1.0 - f1 * f1) * 0.015) + rough * 0.003 + grain * 0.002;
		vec3 dpdx = dFdx(VERTEX);
		vec3 dpdy = dFdy(VERTEX);
		vec3 r1 = cross(dpdy, NORMAL);
		vec3 r2 = cross(NORMAL, dpdx);
		float det = dot(dpdx, r1);
		vec3 grad = sign(det) * (dFdx(bump) * r1 + dFdy(bump) * r2);
		NORMAL = normalize(abs(det) * NORMAL - grad);
	}
	ALBEDO = c * (1.0 - 0.25 * wet);
	ROUGHNESS = mix(0.93, mix(0.25, 0.5, gap), wet);  // mojado brilla, más en las juntas encharcadas
}
"

## Cristal: caras planas talladas, lo de detrás desviado y teñido (refracción), velos y vetas por dentro,
## bordes que brillan y un latido de luz como el resto de lo que brilla.
const CRYSTAL_SHADER := "
shader_type spatial;
render_mode depth_draw_always;
uniform vec4 tint : source_color = vec4(0.65, 0.45, 0.95, 1.0);
uniform float glow = 0.8;
uniform float pulse = 0.35;
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
varying vec3 wpos;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x),
			mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x),
			mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));  // la malla trae normales suaves
	if (dot(n, NORMAL) < 0.0) {
		n = -n;
	}
	NORMAL = n;
	float fres = pow(1.0 - clamp(dot(n, VIEW), 0.0, 1.0), 3.0);
	vec3 behind = textureLod(screen, SCREEN_UV - n.xy * 0.05, 2.0).rgb;
	float cloud = vnoise(wpos * vec3(14.0, 4.0, 14.0));
	float vein = smoothstep(0.05, 0.0, abs(vnoise(wpos * 7.0) - 0.5));  // vetas internas
	float beat = 1.0 + pulse * sin(TIME * 2.2 + NODE_POSITION_WORLD.x * 1.3 + NODE_POSITION_WORLD.z);
	vec3 deep = tint.rgb * tint.rgb;  // por dentro, más saturado
	ALBEDO = mix(deep * 0.2, tint.rgb * 0.5, fres);
	EMISSION = behind * tint.rgb * 0.85 + deep * glow * beat * (0.2 + 0.55 * cloud)
		+ tint.rgb * (vein * 0.5 + fres * 0.9);
	ROUGHNESS = 0.05;
	SPECULAR = 0.9;
	ALPHA = 1.0;  // va en la pasada transparente, que es la que ve lo de detrás
}
"

static var _shaders := {}
static var _meshes := {}


static func shader(code: String) -> Shader:
	if not _shaders.has(code):
		var s := Shader.new()
		s.code = code
		_shaders[code] = s
	return _shaders[code]


static func foliage_material(color: Color, sway: float, flutter := 0.0, vcol := false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader(FOLIAGE_SHADER)
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("sway", sway)
	m.set_shader_parameter("flutter", flutter)
	m.set_shader_parameter("vertex_color", vcol)
	return m


static func stone_material(color: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader(STONE_SHADER)
	m.set_shader_parameter("albedo", color)
	return m


static func crystal_material(color: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader(CRYSTAL_SHADER)
	m.set_shader_parameter("tint", color)
	return m


static func water_material(deep: Color, shallow: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader(WATER_SHADER)
	m.set_shader_parameter("deep", deep)
	m.set_shader_parameter("shallow", shallow)
	return m


static func side_material(top: Color, bottom: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader(SIDE_SHADER)
	m.set_shader_parameter("top_color", top)
	m.set_shader_parameter("bottom_color", bottom)
	return m


# --- Detalles del suelo -------------------------------------------------------
# Mallas pequeñas con color por vértice, varias variantes de cada una (se reparten por casilla).

const VARIANTS := 4
## Variantes de roca: `v % 4` elige el estilo (redondeada, tallada, laja, aguja) y `v / 4` la forma concreta.
const ROCK_VARIANTS := 8


## Malla de detalles `kind` ("grass", "flowers", "reeds", "pebbles", "stones", "shrub", "mushrooms", "mound",
## "lily", "fern") en su variante `v`, para una casilla de 1×1 centrada en el origen.
static func decor_mesh(kind: String, v: int, tint: Color) -> Mesh:
	var key := "%s_%d_%s" % [kind, v, tint.to_html()]
	if _meshes.has(key):
		return _meshes[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind) + v * 7919
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	match kind:
		"grass":
			# Césped corto y tupido: matas pequeñas por toda la casilla.
			for i in rng.randi_range(12, 15):
				var p := _spot(rng, 0.47)
				for b in rng.randi_range(11, 15):
					var a := rng.randf() * TAU
					_curved_blade(st, p + Vector3(cos(a), 0, sin(a)) * 0.015, Vector3(cos(a), 0, sin(a)),
						rng.randf_range(0.06, 0.13), rng.randf_range(0.02, 0.028), rng.randf_range(0.025, 0.06), 2,
						_grass_tone(rng, tint))
		"tallgrass":
			# Hierba alta: matas densas de hojas largas que se doblan, algunas con espiga.
			for i in rng.randi_range(16, 19):
				var p := _spot(rng, 0.48)
				var clump_h := rng.randf_range(0.3, 0.46)
				for b in rng.randi_range(18, 24):
					var a := rng.randf() * TAU
					var dir := Vector3(cos(a), 0, sin(a))
					_curved_blade(st, p + dir * 0.02, dir, clump_h * rng.randf_range(0.65, 1.0),
						rng.randf_range(0.03, 0.045), rng.randf_range(0.05, 0.14), 3, _grass_tone(rng, tint))
				if rng.randf() < 0.15:
					var h := clump_h * 1.1
					var lean := Vector3(rng.randf_range(-0.03, 0.03), 0, rng.randf_range(-0.03, 0.03))
					_blade(st, p, lean, h, 0.006, tint.darkened(0.1).lerp(Color(0.8, 0.75, 0.45), 0.4))
					_blossom(st, p + lean + Vector3.UP * h, 0.018, Color(0.82, 0.74, 0.46), 1.6)
		"fern":
			for i in rng.randi_range(3, 5):
				var p := _spot(rng, 0.4)
				for b in rng.randi_range(6, 10):
					var a := rng.randf() * TAU
					var lean := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.02, 0.12)
					_blade(st, p, lean, rng.randf_range(0.6, 1.0) * 0.22, 0.035,
						tint.darkened(rng.randf_range(0.0, 0.25)).lerp(Color(0.75, 0.8, 0.35), rng.randf() * 0.2))
		"flowers":
			var petals := [Color(1, 0.92, 0.3), Color(1, 1, 1), Color(0.95, 0.45, 0.6), Color(0.65, 0.5, 0.95), Color(1, 0.55, 0.25)]
			for i in rng.randi_range(3, 6):
				var p := _spot(rng, 0.4)
				var h := rng.randf_range(0.1, 0.17)
				_blade(st, p, Vector3(rng.randf_range(-0.02, 0.02), 0, 0.01), h, 0.012, tint)
				_blossom(st, p + Vector3.UP * h, 0.035, petals[rng.randi_range(0, petals.size() - 1)])
			for i in 2:
				var p := _spot(rng, 0.4)
				for b in 5:
					var a := rng.randf() * TAU
					_blade(st, p, Vector3(cos(a), 0, sin(a)) * 0.05, rng.randf_range(0.07, 0.12), 0.018, tint.darkened(0.15))
		"reeds":
			for i in rng.randi_range(2, 4):
				var p := _spot(rng, 0.42)
				for b in rng.randi_range(3, 6):
					var a := rng.randf() * TAU
					var h := rng.randf_range(0.3, 0.5)
					var lean := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.01, 0.05)
					_blade(st, p, lean, h, 0.02, tint.darkened(rng.randf_range(0.0, 0.2)))
					if b % 2 == 0:
						_box(st, p + lean * 0.9 + Vector3.UP * h * 0.85, Vector3(0.025, 0.08, 0.025), Color(0.45, 0.28, 0.15))
		"lily":
			for i in rng.randi_range(1, 3):
				var p := _spot(rng, 0.3) + Vector3.UP * 0.005
				_disc(st, p, rng.randf_range(0.08, 0.13), tint)
				if rng.randf() < 0.4:
					_blossom(st, p + Vector3.UP * 0.02, 0.03, Color(1.0, 0.75, 0.85))
		"pebbles":
			for i in rng.randi_range(2, 5):
				var p := _spot(rng, 0.42)
				var s := rng.randf_range(0.03, 0.07)
				_box(st, p + Vector3.UP * s * 0.3, Vector3(s * 1.4, s * 0.7, s), tint.darkened(rng.randf_range(0.0, 0.3)), rng.randf() * PI)
		"stones":
			# Piedras sueltas de varios tamaños, medio hundidas en el suelo.
			for i in rng.randi_range(4, 7):
				var p := _spot(rng, 0.4)
				var r := rng.randf_range(0.05, 0.13)
				_stone(st, rng, p, r, tint.lightened(rng.randf_range(0.0, 0.25)), rng.randf_range(0.35, 0.9))
		"shrub":
			var p := _spot(rng, 0.25)
			for b in 12:
				var a := TAU * b / 12.0 + rng.randf() * 0.4
				_blade(st, p, Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.08, 0.16), rng.randf_range(0.12, 0.22), 0.015,
					tint.darkened(rng.randf_range(0.0, 0.3)))
		"mushrooms":
			for i in rng.randi_range(2, 4):
				var p := _spot(rng, 0.38)
				var h := rng.randf_range(0.05, 0.1)
				_box(st, p + Vector3.UP * h * 0.5, Vector3(0.02, h, 0.02), Color(0.85, 0.82, 0.75))
				_blossom(st, p + Vector3.UP * h, rng.randf_range(0.035, 0.055), tint)
		"hailstones":
			for i in rng.randi_range(6, 12):
				_blossom(st, _spot(rng, 0.44) + Vector3.UP * 0.01, rng.randf_range(0.018, 0.03), tint.darkened(rng.randf_range(0.0, 0.15)))
		"mound":
			for i in rng.randi_range(1, 2):
				var p := _spot(rng, 0.3)
				_blossom(st, p, rng.randf_range(0.1, 0.16), tint, 0.35)
	if kind not in ["grass", "tallgrass"]:  # la hierba lleva sus propias normales (luz suave, sin facetas)
		st.generate_normals()
	var mesh := st.commit()
	_meshes[key] = mesh
	return mesh


static func _spot(rng: RandomNumberGenerator, r: float) -> Vector3:
	return Vector3(rng.randf_range(-r, r), 0, rng.randf_range(-r, r))


## Hoja o tallo: triángulo de base `w` que sube `h` inclinándose hacia `lean`; más oscuro abajo.
static func _blade(st: SurfaceTool, p: Vector3, lean: Vector3, h: float, w: float, color: Color) -> void:
	var side := Vector3(-lean.z, 0, lean.x).normalized() if lean.length() > 0.001 else Vector3.RIGHT
	var tip := p + lean + Vector3.UP * h
	for face in [[p - side * w, p + side * w], [p + side * w, p - side * w]]:
		st.set_color(color.darkened(0.35))
		st.add_vertex(face[0])
		st.set_color(color.darkened(0.35))
		st.add_vertex(face[1])
		st.set_color(color.lightened(0.15))
		st.add_vertex(tip)


## Hoja de hierba curva: sube `h` en `segs` tramos, se estrecha hacia la punta y se dobla hacia `dir`
## (`bend` = cuánto se aleja la punta). Base oscura, punta clara; normales hacia arriba para que el
## césped se ilumine como una masa suave y no como triángulos sueltos.
static func _curved_blade(st: SurfaceTool, p: Vector3, dir: Vector3, h: float, w: float, bend: float, segs: int,
		color: Color) -> void:
	var side := Vector3(-dir.z, 0, dir.x)
	var normal := (Vector3.UP + dir * 0.35).normalized()
	var pts: Array[Vector3] = []
	var cols: Array[Color] = []
	for i in segs + 1:
		var t := float(i) / segs
		pts.append(p + dir * bend * t * t + Vector3.UP * h * (t - 0.25 * t * t * bend / maxf(h, 0.01)))
		cols.append(color.darkened(0.5 * (1.0 - t)).lerp(color.lightened(0.08), t * t))
	for i in segs:
		var w0 := w * (1.0 - float(i) / segs)
		var w1 := w * (1.0 - float(i + 1) / segs)
		var a0 := pts[i] - side * w0
		var b0 := pts[i] + side * w0
		var a1 := pts[i + 1] - side * w1
		var b1 := pts[i + 1] + side * w1
		var tris := [[a0, b0, b1, 0, 0, 1], [a0, b1, a1, 0, 1, 1]] if i < segs - 1 else [[a0, b0, a1, 0, 0, 1]]
		for tri: Array in tris:
			for order in [[0, 1, 2], [0, 2, 1]]:  # dos caras
				for j: int in order:
					st.set_normal(normal)
					st.set_color(cols[i + tri[3 + j]])
					st.add_vertex(tri[j])


## Tono de una hoja: el del suelo, algo más oscuro, más amarillo o más fresco según la hoja.
static func _grass_tone(rng: RandomNumberGenerator, tint: Color) -> Color:
	var c := tint.darkened(rng.randf_range(0.05, 0.3))
	var r := rng.randf()
	if r < 0.12:
		return c.lerp(Color(0.74, 0.72, 0.36), 0.35)  # hoja seca
	if r < 0.4:
		return c.lerp(Color(0.32, 0.72, 0.22), 0.35)  # brote nuevo
	return c


## Piedra suelta: contorno de 5 a 8 puntas a distancias distintas, cima desplazada y algo de aristas;
## `flat` la aplasta (laja) o la deja alta (canto).
static func _stone(st: SurfaceTool, rng: RandomNumberGenerator, c: Vector3, r: float, color: Color, flat: float) -> void:
	var n := rng.randi_range(5, 8)
	var top := c + Vector3(rng.randf_range(-0.3, 0.3) * r, r * flat, rng.randf_range(-0.3, 0.3) * r)
	var bottom := c - Vector3.UP * r * 0.2
	var ring: Array[Vector3] = []
	var a0 := rng.randf() * TAU
	for i in n:
		var a := a0 + TAU * (i + rng.randf_range(-0.25, 0.25)) / n
		ring.append(c + Vector3(cos(a), rng.randf_range(0.0, 0.35) * flat, sin(a)) * r * rng.randf_range(0.65, 1.2))
	for i in n:
		var p0 := ring[i]
		var p1 := ring[(i + 1) % n]
		var shade := rng.randf_range(0.0, 0.12)  # cada cara de un tono: aristas marcadas
		for tri in [[top, p1, p0], [bottom, p0, p1]]:
			for v: Vector3 in tri:
				st.set_color(color.darkened(shade) if v != bottom else color.darkened(0.35))
				st.add_vertex(v)


## Bola facetada pequeña (flor, sombrerillo de seta, montoncito de nieve). `flat` aplasta en vertical.
static func _blossom(st: SurfaceTool, c: Vector3, r: float, color: Color, flat := 0.7) -> void:
	var top := c + Vector3.UP * r * flat
	var bottom := c - Vector3.UP * r * flat * 0.3
	var n := 6
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var p0 := c + Vector3(cos(a0), 0, sin(a0)) * r
		var p1 := c + Vector3(cos(a1), 0, sin(a1)) * r
		for tri in [[top, p1, p0], [bottom, p0, p1]]:
			for v: Vector3 in tri:
				st.set_color(color if v != bottom else color.darkened(0.3))
				st.add_vertex(v)


static func _disc(st: SurfaceTool, c: Vector3, r: float, color: Color) -> void:
	var n := 8
	for i in n:
		if i == 0:
			continue  # la muesca de la hoja de nenúfar
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		for v in [c, c + Vector3(cos(a1), 0, sin(a1)) * r, c + Vector3(cos(a0), 0, sin(a0)) * r]:
			st.set_color(color)
			st.add_vertex(v)


static func _box(st: SurfaceTool, c: Vector3, size: Vector3, color: Color, rot := 0.0) -> void:
	var b := Basis(Vector3.UP, rot)
	var h := size * 0.5
	var faces := [
		[Vector3(-1, 1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1), Vector3(-1, 1, 1)],
		[Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)],
		[Vector3(1, -1, -1), Vector3(-1, -1, -1), Vector3(-1, 1, -1), Vector3(1, 1, -1)],
		[Vector3(1, -1, 1), Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1)],
		[Vector3(-1, -1, -1), Vector3(-1, -1, 1), Vector3(-1, 1, 1), Vector3(-1, 1, -1)],
	]
	for f: Array in faces:
		var q: Array[Vector3] = []
		for v: Vector3 in f:
			q.append(c + b * (v * h))
		var shade := color if f[0].y > 0 and f[1].y > 0 else color.darkened(0.15)
		for i: int in [0, 2, 1, 0, 3, 2]:
			st.set_color(shade)
			st.add_vertex(q[i])


# --- Obstáculos ----------------------------------------------------------------

## Roca irregular: esfera de pocos polígonos deformada con ruido (estable por variante).
static func rock_mesh(v: int) -> Mesh:
	var key := "rock_%d" % v
	if _meshes.has(key):
		return _meshes[key]
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 9
	sphere.rings = 5
	var arrays := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var style := v % 4
	var noise := FastNoiseLite.new()
	noise.seed = 31 + v * 17
	noise.frequency = 1.6
	var rng := RandomNumberGenerator.new()
	rng.seed = 977 + v * 131
	# Cortes planos (caras de roca partida): un plano por corte; lo que sobresale queda aplastado contra él.
	var cuts: Array[Plane] = []
	for i in [2, 5, 3, 4][style] + rng.randi_range(0, 2):
		var n := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.4, 1.0), rng.randf_range(-1, 1)).normalized()
		cuts.append(Plane(n, rng.randf_range(0.26, 0.42)))
	var bumpy: float = [0.35, 0.2, 0.25, 0.3][style]
	var stretch: Vector3 = [Vector3(1, 0.85, 1), Vector3(1, 1, 0.9), Vector3(1.2, 0.45, 1), Vector3(0.6, 1.5, 0.6)][style]
	var lean := Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.12, 0.12)) if style == 3 else Vector3.ZERO
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in idx:
		var p := verts[i]
		p *= 1.0 + noise.get_noise_3dv(p * 2.0) * bumpy
		for cut in cuts:
			var over := cut.distance_to(p)
			if over > 0.0:
				p -= cut.normal * over
		p *= stretch
		p += lean * (p.y + 0.5)  # la aguja se inclina un poco
		if p.y < -0.15:
			p.y = -0.15 + (p.y + 0.15) * 0.3  # base aplanada, asentada en el suelo
		st.add_vertex(p)
	st.generate_normals()  # sin índices: caras planas, aspecto de roca tallada
	var mesh := st.commit()
	_meshes[key] = mesh
	return mesh


## Charco: mancha plana de borde irregular (con UV para el material del agua), estable por variante.
static func puddle_mesh(v: int) -> Mesh:
	var key := "puddle_%d" % v
	if _meshes.has(key):
		return _meshes[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 977 + v * 31
	var center := Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.12, 0.12))
	var r := rng.randf_range(0.2, 0.3)
	var pts: Array[Vector3] = []
	var n := 12
	for i in n:
		var a := TAU * i / n
		var k := rng.randf_range(0.7, 1.15) * (1.3 if i % 6 < 2 else 1.0)
		pts.append(center + Vector3(cos(a), 0, sin(a)) * r * k)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		for p: Vector3 in [center, pts[i], pts[(i + 1) % n]]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(p.x + 0.5, p.z + 0.5))
			st.add_vertex(p)
	var mesh := st.commit()
	_meshes[key] = mesh
	return mesh


# --- Ambiente ---------------------------------------------------------------------

## Partículas de ambiente del bioma sobre un tablero de `size` (ancho, fondo) centrado en `center`:
## hojas que caen en el bosque, polen en la pradera, arena que corre por el desierto, copos sueltos
## en la nieve, motas que brillan en la cueva. null si el bioma no tiene.
static func ambient(kind: Biome.Kind, center: Vector3, size: Vector2) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.position = center
	var quad := QuadMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = mat
	p.mesh = quad
	var ext := Vector3(size.x * 0.5, 0.0, size.y * 0.5)
	match kind:
		Biome.Kind.FOREST:
			p.amount = 40
			p.lifetime = 7.0
			ext.y = 0.4
			p.position.y += 2.6
			quad.size = Vector2(0.09, 0.06)
			p.direction = Vector3(0.6, -1, 0.4)
			p.spread = 25.0
			p.initial_velocity_min = 0.25
			p.initial_velocity_max = 0.5
			p.gravity = Vector3(0.15, -0.12, 0.1)
			p.angular_velocity_min = -180.0
			p.angular_velocity_max = 180.0
			p.angle_max = 360.0
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
			p.particle_flag_rotate_y = true
			p.color_initial_ramp = _ramp([Color(0.45, 0.62, 0.22), Color(0.85, 0.6, 0.2), Color(0.7, 0.35, 0.15)])
		Biome.Kind.MEADOW, Biome.Kind.LAKE:
			p.amount = 30
			p.lifetime = 6.0
			ext.y = 0.8
			p.position.y += 1.2
			quad.size = Vector2(0.04, 0.04)
			p.direction = Vector3(0.8, 0.2, 0.6)
			p.spread = 40.0
			p.initial_velocity_min = 0.15
			p.initial_velocity_max = 0.35
			p.gravity = Vector3(0, 0.02, 0)
			p.color = Color(1.0, 0.97, 0.75, 0.85)
		Biome.Kind.DESERT:
			p.amount = 70
			p.lifetime = 2.5
			ext.y = 0.15
			p.position.y += 0.5
			quad.size = Vector2(0.22, 0.03)
			p.direction = Vector3(1, 0, 0.3)
			p.spread = 8.0
			p.initial_velocity_min = 1.6
			p.initial_velocity_max = 2.6
			p.gravity = Vector3.ZERO
			p.color = Color(0.95, 0.85, 0.6, 0.45)
		Biome.Kind.SNOW, Biome.Kind.MOUNTAIN:
			p.amount = 45 if kind == Biome.Kind.SNOW else 25
			p.lifetime = 6.0
			ext.y = 0.5
			p.position.y += 3.0
			quad.size = Vector2(0.05, 0.05)
			p.direction = Vector3(0.5, -1, 0.3)
			p.spread = 20.0
			p.initial_velocity_min = 0.3
			p.initial_velocity_max = 0.6
			p.gravity = Vector3(0.1, -0.1, 0)
			p.color = Color(1, 1, 1, 0.9)
		Biome.Kind.CAVE:
			p.amount = 35
			p.lifetime = 5.0
			ext.y = 0.8
			p.position.y += 1.0
			quad.size = Vector2(0.05, 0.05)
			p.direction = Vector3.UP
			p.spread = 60.0
			p.initial_velocity_min = 0.05
			p.initial_velocity_max = 0.15
			p.gravity = Vector3.ZERO
			p.color = Color(0.75, 0.6, 1.0, 0.9)
			mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_:
			p.free()
			return null
	p.emission_box_extents = ext
	p.preprocess = p.lifetime
	p.color_ramp = _fade_ramp()
	return p


static func _ramp(colors: Array) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray(colors)
	return g


## Aparecen y se desvanecen suavemente.
static func _fade_ramp() -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.15, 0.8, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	return g

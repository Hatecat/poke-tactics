"""Anima un Pokémon bípedo o cuadrúpedo pose a pose: idle, walk, fight_b, fight_d y las variantes
de ataque que usa su learnset. Bípedos: claw, bite, punch, kick, tail, body, breath, sound, boost.
Cuadrúpedos (se detectan solos: las patas delanteras llegan al suelo): las mismas más horn, mind y
powder; claw es un zarpazo con la pata delantera, punch un pisotón y kick una coz.

Uso (desde la carpeta del proyecto, después de setup_animations.py):
    blender --background art/blender/charmeleon.blend --python tools/blender/animate_pokemon.py
    blender --background art/blender/charmeleon.blend --python tools/blender/animate_pokemon.py -- fight_b_claw idle
    blender --background art/blender/charmeleon.blend --python tools/blender/animate_pokemon.py -- --force
Sin acciones, crea todas las que necesita. Solo sobrescribe acciones quietas (las que deja
setup_animations.py); con --force rehace también las que ya tienen movimiento.
Después: tools/blender/export_animations.py.

Necesita un esqueleto con la convención de los rips de Charmander: Hips (o Waist) y LThigh/LFoot (o
LLeg/LFoot) y sus R. Lo demás es opcional: Head (sin ella el cuerpo es la cabeza, como Jigglypuff o
Mankey), LArm/LHand (sin brazos, como Oddish), Spine1/Spine2 (o un solo Spine), Neck (o Neck1/Neck2),
Jaw (o LowerJaw), ForeArm/Leg (sin ellos la pata es de un hueso, como Raticate), Toe, la cola (Tail1..N; TailB01..
como Rapidash; o varias colas LTailA1.., RTailB1.. que salen de Hips, como Vulpix) y su punta
(TailA..). Sin cola no se crea fight_b_tail. En los cuadrúpedos Arm/ForeArm/Hand son las patas
delanteras. Los nombres se normalizan: "059 RArm" y "RArm_15" cuentan como RArm, y los de 3ds Max
("Bip001 L Calf") se traducen (LLeg).
El tamaño, hacia dónde mira y cuánto hay que bajar los brazos se miden en el propio esqueleto.
"""
import math
import re
import sys
from pathlib import Path

import bpy
from mathutils import Quaternion, Vector

PROJECT = Path(__file__).resolve().parents[2]
REQUIRED = ["Hips"] + [s + b for s in "LR" for b in ("Thigh", "Foot")]
# Altura cabeza-dedos de Charmander, con la que se escribieron las distancias de abajo.
REF_HEIGHT = 0.379


# ---------- esqueleto ----------
arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
PB = arm.pose.bones


# Huesos de 3ds Max (Exeggutor): "Bip001 L Calf" -> "LLeg". Sus Spine, Spine1... van un número por delante.
BIPED = {"Pelvis": "Hips", "Spine": "Spine1", "Spine1": "Spine2", "Spine2": "Spine3", "Calf": "Leg",
         "Toe0": "Toe", "Clavicle": "Shoulder", "UpperArm": "Arm", "Forearm": "ForeArm"}


def _canon(name):
    """Nombre sin el número de nodo de algunos rips: "059 RArm" y "RArm_15" -> "RArm"."""
    name = re.sub(r"_\d+$", "", re.sub(r"^\d+ ", "", name))
    m = re.fullmatch(r"Bip\d+ (?:([LR]) )?(\w+)", name)
    if m:
        name = (m.group(1) or "") + BIPED.get(m.group(2), m.group(2))
    return name


# B: huesos por nombre normalizado. Si falta un hueso, hace sus veces el equivalente de otros rips:
# un solo Spine (Raticate), Waist (Squirtle), LowerJaw (Psyduck, Kangaskhan), piernas de un hueso (Vileplume).
ALIASES = {"Spine1": "Spine", "Hips": "Waist", "Jaw": "LowerJaw", "LThigh": "LLeg", "RThigh": "RLeg"}
B = {_canon(b.name): b for b in arm.data.bones}
for _want, _have in ALIASES.items():
    if _want not in B and _have in B:
        B[_want] = B.pop(_have)
CANON = {b.name: n for n, b in B.items()}
missing = [n for n in REQUIRED if n not in B]
if missing:
    raise SystemExit(f"El esqueleto no sigue la convención de Charmander; faltan: {', '.join(missing)}")
HAS_ARMS = all(s + b in B for s in "LR" for b in ("Arm", "Hand"))
# Sin cabeza aparte (Jigglypuff, Mankey, Graveler) el cuerpo hace de cabeza. CANON sigue diciendo
# Hips, así que los giros de cabeza de las poses no se aplican: el cuerpo ya se mueve como cadera.
HEAD_IS_BODY = "Head" not in B
if HEAD_IS_BODY:
    B["Head"] = B["Hips"]


def _name(bone):
    return CANON[bone.name] if bone else None


def _chain(prefix):
    names = [n for n in B if re.fullmatch(prefix + r"\d+", n)]
    return sorted(names, key=lambda n: int(re.sub(r"\D", "", n[len(prefix):])))


def _descends(name, ancestor):
    b = B[name].parent
    while b:
        if _name(b) == ancestor:
            return True
        b = b.parent
    return False


# Colas: cadenas Tail1.., TailB01.. o LTailA1.. que salen de Hips (las de Rapidash que salen del cuello
# son la crin). TAIL es la principal y TAILS todas (Vulpix tiene seis).
TAILS = []
for _n in sorted(B):
    _m = re.fullmatch(r"([LR]?Tail[A-Z]?)0*1", _n)
    if _m and _name(B[_n].parent) == "Hips":
        TAILS.append(_chain(_m.group(1)))
TAILS.sort(key=lambda c: (not re.fullmatch(r"Tail\d+", c[0]), c[0]))
TAIL = TAILS[0] if TAILS else []
_tail_bones = {n for c in TAILS for n in c}
# Punta de la cola (la llama de Charmander): solo cadenas que cuelgan de la cola.
FLAME = [n for n in _chain("TailA") if TAIL and _descends(n, TAIL[0])]
# Llamas sueltas (crin y cola de Rapidash): cualquier otra cadena Tail<letra><n>.
FLICKER = [n for n in B if re.fullmatch(r"[LR]?Tail[A-Z]\d+", n) and n not in _tail_bones and n not in FLAME]
ROOTS = [n for n, b in B.items() if b.parent is None]

HAS_NECK = "Neck" in B


def _snap(v):
    """El eje principal (±X, ±Y, ±Z) más parecido a `v`: los rips están alineados con los ejes."""
    i = max(range(3), key=lambda k: abs(v[k]))
    axis = Vector((0, 0, 0))
    axis[i] = 1 if v[i] > 0 else -1
    return axis


def _pos(name):
    return B[name].head_local


# Cuadrúpedo: las manos (patas delanteras) llegan casi al suelo. La vertical sale de las patas, que en
# cualquier cuerpo apuntan hacia abajo (de la cadera a los pies; los brazos en cruz de un bípedo se
# anulan entre sí). Con la cadera no basta: en Rattata los pies quedan más atrás que abajo.
_hip_up = _snap(-sum((_pos(s + end) - _pos(s + top) for s in "LR"
                      for top, end in (("Thigh", "Foot"),) + ((("Arm", "Hand"),) if HAS_ARMS else ())), Vector()))
_feet_h = min(_pos(n).dot(_hip_up) for n in ("LToe", "RToe", "LFoot", "RFoot") if n in B)
# Las manos, a ras de suelo: ni altas ni muy por debajo de los pies (en Persian quedan a -0,67 caderas,
# porque los pies se miden en los dedos). Muy por debajo es que los brazos apuntan hacia delante y
# tuercen la vertical (los cañones de Blastoise, a -35): entonces es un bípedo.
_hands = (_pos("LHand").dot(_hip_up) - _feet_h) / (_pos("Hips").dot(_hip_up) - _feet_h) if HAS_ARMS else 9
QUAD = -1.5 < _hands < 0.3

# Ejes en el espacio de la armadura, medidos en el esqueleto (cada rip trae los suyos: Charmander
# tiene +Z arriba y mira a -Y; Nidoking, -Y arriba y mira a -Z). Arriba: de los pies a la cabeza.
# Delante: de talón a dedos o, sin dedos, de la cabeza a la mandíbula. En los cuadrúpedos la cabeza
# puede estar más adelantada que alta: arriba es de los pies a la cadera y delante, hacia la cabeza.
if QUAD:
    UP = _hip_up
    _fwd = _pos("Head") - _pos("Hips")
else:
    UP = _snap(_pos("Head") - (_pos("LFoot") + _pos("RFoot")) / 2)
    # Dedos: LToe o, si hay varios (LToeA, LToeB... como Pinsir), su punto medio. Con los dos pies:
    # en Alakazam los dedos se abren hacia fuera y los de un solo pie apuntarían de lado.
    _toes = {s: [n for n in B if re.fullmatch(s + r"Toe[A-Z]?\d*", n)] for s in "LR"}
    if not all(_toes.values()) and "Jaw" not in B:
        raise SystemExit("Bípedo sin dedos (LToe) ni mandíbula (Jaw): no se puede saber hacia dónde mira.")
    _fwd = sum((sum((_pos(n) for n in t), Vector()) / len(t) - _pos(s + "Foot") for s, t in _toes.items()),
               Vector()) if all(_toes.values()) else (_pos("Jaw") - _pos("Head"))
FWD = _snap(_fwd - UP * _fwd.dot(UP))
LEFT = UP.cross(FWD)
BACK = -FWD
# Giros: PITCH inclina hacia delante (+), YAW gira hacia la izquierda del Pokémon visto desde arriba,
# ROLL ladea. Son los ejes X, Z, Y de Charmander.
PITCH, YAW, ROLL = LEFT, UP, BACK
# Algunos rips tienen L y R cambiados respecto a la izquierda real: entonces los brazos se espejan.
SIDE = 1 if (_pos("LThigh") - _pos("RThigh")).dot(LEFT) > 0 else -1
_ground = min(_pos(n).dot(UP) for n in ("LToe", "RToe", "LFoot", "RFoot", "LHand", "RHand") if n in B)
# Bípedos: distancias escritas para la altura de Charmander. Cuadrúpedos: en alturas de cadera.
# Sin cabeza aparte se mide hasta el centro del cuerpo, que queda a media altura.
SCALE = (_pos("Hips").dot(UP) - _ground) if QUAD else \
    (_pos("Head").dot(UP) - _ground) * (1.6 if HEAD_IS_BODY else 1) / REF_HEIGHT


_VERTS = []


def _mesh_verts():
    """(hueso con más peso, posición en el espacio de la armadura) de cada vértice de la malla."""
    if not _VERTS:
        to_arm = arm.matrix_world.inverted()
        for o in (o for o in bpy.data.objects if o.type == "MESH" and o.find_armature() == arm):
            groups = {g.index: g.name for g in o.vertex_groups}
            m = to_arm @ o.matrix_world
            _VERTS.extend((groups.get(max(v.groups, key=lambda g: g.weight).group), m @ v.co)
                          for v in o.data.vertices if v.groups)
    return _VERTS


def _tail_lift(chain):
    """Grados que hay que levantar la cola para que no atraviese el suelo (la de Wartortle cuelga 0,86
    por debajo de los pies en el propio modelo). 0 si ya queda por encima."""
    root = B[chain[0]]
    tail = {root.name} | {b.name for b in root.children_recursive}
    tail_v = [co for g, co in _mesh_verts() if g in tail]
    body_v = [co for g, co in _mesh_verts() if g not in tail]
    if not tail_v or not body_v:
        return 0.0
    ground = min(v.dot(UP) for v in body_v)
    head = root.head_local

    def lowest(deg):
        q = Quaternion(PITCH, math.radians(deg))
        return min((head + q @ (v - head)).dot(UP) for v in tail_v[::max(1, len(tail_v) // 400)])
    # Rozar el suelo es normal (Charizard, Rhydon); solo se corrige si la atraviesa de verdad.
    if lowest(0) >= ground - 0.05 * SCALE * REF_HEIGHT:
        return 0.0
    sign = 1 if lowest(10) > lowest(0) else -1
    for deg in range(2, 92, 2):
        if lowest(sign * deg) >= ground:
            return float(sign * deg)
    return 90.0 * sign


# Ajustes por especie (el nombre del .blend), sobre lo que la herramienta deduce del esqueleto:
#   arm_drop / arm2_drop: grados que bajan los brazos (y el segundo par) desde la horizontal (45 y 20);
#   arm_fwd: grados que se adelantan los brazos (25); elbow: flexión extra de los codos;
#   legs_in: grados que se cierran las piernas.
_STRONG_ARMS = {"arm_drop": 70, "arm_fwd": 8, "elbow": 20}  # brazos largos: colgando junto al cuerpo
TWEAKS = {
    "machop": _STRONG_ARMS,
    "machoke": _STRONG_ARMS,
    "machamp": dict(_STRONG_ARMS, arm2_drop=40),
    "golem": {"arm_drop": 62, "elbow": 45, "legs_in": 10},  # brazos largos: doblados, para que no parezcan patas
    # Patas delanteras cortas y adelantadas: con el pecho más bajo, las manos van bajo los hombros.
    "nidoranf": {"chest": 10, "front_back": 0.18},
    # Brazos que en el modelo ya apuntan adelante: la mano quedaba delante del pecho y parecía otra cabeza.
    "sandshrew": {"arm_out": 32, "arm_drop": 35, "arm_fwd": 0, "elbow": -10},
}.get(Path(bpy.data.filepath).stem, {})

# Estilos por especie, que cambian todas las acciones:
#   fly: insecto que vuela (Beedrill): flota, las patas cuelgan y aletea rápido (las alas en "wings");
#   lotus: levita con las piernas cruzadas (Abra); sit: el idle es sentado, como un gato (Persian).
STYLES = {
    "beedrill": {"style": "fly", "wings": ["LFeelerA", "LFeelerB", "RFeelerA", "RFeelerB"]},
    "abra": {"style": "lotus"},
    "persian": {"style": "sit"},
}
STYLE = STYLES.get(Path(bpy.data.filepath).stem, {})

# Giros de base sumados a todas las poses: colas que atraviesan el suelo y piernas que se cierran.
# Los que flotan no tocan el suelo: el abdomen de Beedrill puede colgar.
BASE_ROTS = {} if STYLE.get("style") in ("fly", "lotus") else \
    {c[0]: [(PITCH, lift)] for c in TAILS if (lift := _tail_lift(c))}
for _s, _k in (("L", 1), ("R", -1)):
    if TWEAKS.get("legs_in"):
        _a = TWEAKS["legs_in"] * _k * SIDE
        BASE_ROTS[_s + "Thigh"] = [(ROLL, _a)]
        BASE_ROTS[_s + "Foot"] = [(ROLL, -_a)]


def _arm_drop(side):
    """side: "L", "R" o con el sufijo del par ("L2")."""
    hand, upper = (side[0] + "Hand" + side[1:], side[0] + "Arm" + side[1:])
    d = _pos(hand) - _pos(upper)
    down = -d.dot(UP)
    return math.degrees(math.atan2(down, (d + UP * down).length))


# Pares de brazos: "" el principal y "2" el segundo de Machamp (LArm2...), que baja menos para
# no solaparse. Pose base: tantos grados por debajo de la horizontal y 25° hacia delante (en pose
# en T se bajan del todo; si el modelo ya los trae bajados, solo lo que falte).
ARM_PAIRS = {"": TWEAKS.get("arm_drop", 45.0)} if HAS_ARMS else {}
# Solo si cuelgan del lomo del propio Pokémon: los LArm2 de la cría de Kangaskhan cuelgan de SpineB.
if all(n in B for n in ("LArm2", "LForeArm2", "LHand2", "RArm2", "RForeArm2", "RHand2")) \
        and any(_descends("LArm2", n) for n in ("Spine1", "Spine2", "Spine3")):
    ARM_PAIRS["2"] = TWEAKS.get("arm2_drop", 20.0)
ARM_LOWER = {s + k: max(0.0, drop - _arm_drop(s + k)) for k, drop in ARM_PAIRS.items() for s in "LR"}


def _arm_ahead(side):
    """Brazo que ya apunta hacia delante, no en cruz (los cañones de Blastoise): no se baja ni se
    adelanta, que con esos giros se levantaría o se retorcería."""
    d = (_pos(side[0] + "Hand" + side[1:]) - _pos(side[0] + "Arm" + side[1:])).normalized()
    return not QUAD and d.dot(FWD) > 0.95


ARM_AHEAD = {s + k: _arm_ahead(s + k) for k in ARM_PAIRS for s in "LR"}
for _side, _ahead in ARM_AHEAD.items():
    if _ahead:
        ARM_LOWER[_side] = 0.0


def _elbow_axis(side):
    """Eje sobre el que se dobla el codo hacia delante: perpendicular al antebrazo y a FWD. Con el
    brazo colgando es PITCH; con el brazo en cruz (Machop) PITCH lo retorcería sobre sí mismo."""
    d = (_pos(side[0] + "Hand" + side[1:]) - _pos(side[0] + "ForeArm" + side[1:])).normalized()
    axis = d.cross(FWD)
    return axis.normalized() if axis.length > 0.3 else -PITCH


ELBOW = {s + k: _elbow_axis(s + k) for k in ARM_PAIRS for s in "LR"}


def lquat(name, rots):
    inv = B[name].matrix_local.to_3x3().inverted()
    q = Quaternion()
    for axis, deg in rots:
        q = q @ Quaternion((inv @ Vector(axis)).normalized(), math.radians(deg))
    return q


# ---------- piezas de pose (ángulos en grados; distancias como en Charmander) ----------
def arm_(side, fwd=0, up=0, inward=0, bend=0, pair=""):
    s = (1 if side == "L" else -1) * SIDE
    return {
        side + "Arm" + pair: [(YAW, -s * (inward - TWEAKS.get("arm_out", 0))), (PITCH, -fwd), (ROLL, -s * up),
                              (PITCH, 0 if ARM_AHEAD[side + pair] else -TWEAKS.get("arm_fwd", 25)),
                              (ROLL, ARM_LOWER[side + pair] * s)],
        side + "ForeArm" + pair: [(ELBOW[side + pair],
                                   bend if ARM_AHEAD[side + pair] else 25 + TWEAKS.get("elbow", 0) + bend)],
    }


def arms(fwd=0, up=0, inward=0, bend=0, **r):
    """Los brazos (todos los pares hacen lo mismo); r_fwd, r_up... cambian solo los derechos."""
    d = {}
    for pair in ARM_PAIRS:
        d.update(arm_("L", fwd, up, inward, bend, pair))
        d.update(arm_("R", r.get("r_fwd", fwd), r.get("r_up", up), r.get("r_inward", inward), r.get("r_bend", bend),
                      pair))
    return d


def leg(side, fwd=0, knee=0, foot=None):
    """fwd: muslo hacia delante; knee: flexión; foot: si es None, el pie queda plano."""
    if foot is None:
        foot = fwd - knee
    return {side + "Thigh": [(PITCH, -fwd)], side + "Leg": [(PITCH, knee)], side + "Foot": [(PITCH, foot)]}


def crouch(a):
    d = leg("L", a, 2 * a)
    d.update(leg("R", a, 2 * a))
    return d


def spine(lean=0, yaw=0, side=0, lean2=None):
    """lean: inclinación del pecho hacia delante; el total visible es 1,5 × lean."""
    return {"Spine1": [(PITCH, lean), (YAW, yaw), (ROLL, side)],
            "Spine2": [(PITCH, lean * 0.5 if lean2 is None else lean2), (YAW, yaw * 0.6)]}


def head(pitch=0, yaw=0, roll=0, neck=None, jaw=0, lean=0):
    """pitch: hacia dónde mira (+ abajo); `lean` (la del torso) se compensa para no mirar al suelo."""
    n = (pitch * 0.4 if neck is None else neck) if HAS_NECK else 0
    return {"Neck": [(PITCH, n), (YAW, yaw * 0.4)],
            "Head": [(PITCH, pitch - 1.5 * lean - n), (YAW, yaw), (ROLL, roll)], "Jaw": [(PITCH, jaw)]}


def hips(yaw=0, roll=0):
    return {"Hips": [(YAW, yaw), (ROLL, roll)]}


def tail(yaw=0, pitch=0, delay=0.0, flame=0):
    """yaw/pitch: giro total de la punta (+ pitch = arriba), repartido entre los huesos (en cada cola)."""
    d = {}
    for chain in TAILS:
        w = [0.4 + 0.6 * (i + 1) / len(chain) for i in range(len(chain))]
        total = sum(w)
        for i, n in enumerate(chain):
            k = (i + 1) / len(chain)
            d[n] = [(YAW, yaw * w[i] / total * (1 - delay * (1 - k))), (PITCH, pitch * w[i] / total)]
    for n in FLAME:
        d[n] = [(YAW, yaw * 0.08), (PITCH, pitch * 0.08 + flame / 3)]
    return d


def tail_wave(t, amp, pitch_amp, step, freq=1):
    """Ondulación con retraso hacia la punta (idle y walk); con varias colas, cada una desfasada."""
    d = {}
    for c, chain in enumerate(TAILS):
        for i, n in enumerate(chain):
            k = (i + 1) / len(chain)
            off = 0.9 * c
            d[n] = [(YAW, amp * (0.4 + 0.6 * k) / len(chain) * 2.2 * math.sin(t - step * i + off)),
                    (PITCH, pitch_amp / len(chain) * 1.6 * math.cos(2 * t - step * i + off))]
    for j, n in enumerate(FLAME):
        k = len(TAIL) + j
        d[n] = [(YAW, amp * 0.18 * math.sin(t - step * k) + 2 * math.sin(3 * t - 0.7 * k)),
                (PITCH, pitch_amp * 0.3 * math.sin(2 * t - 0.6 * k))]
    return d


def pose(*parts, root=(0, 0, 0)):
    d = {"root": root}
    for p in parts:
        d.update(p)
    return d


def BASE():
    return pose(arms(), crouch(4), root=(0, 0, -0.002))


# ---------- ciclos (idle, walk): una pose por fotograma ----------
def idle_pose(t):
    s = math.sin
    return pose(
        arms(fwd=2.5 * s(t + 0.8), up=1.5 * s(t), bend=2.5 * s(t + 1.4), r_fwd=2.5 * s(t + 1.3)),
        {"Spine1": [(PITCH, -1.2 * s(t)), (ROLL, 0.8 * s(t + 0.7))], "Spine2": [(PITCH, -1.6 * s(t - 0.3))]},
        {"LShoulder": [(ROLL, -2.0 * s(t - 0.2))], "RShoulder": [(ROLL, 2.0 * s(t - 0.2))]},
        {"Neck": [(YAW, 1.5 * s(t + 1.2)), (PITCH, 1.0 * s(t - 0.6))],
         "Head": [(YAW, 3.5 * s(t + 1.0) + s(2 * t + 0.4)), (PITCH, 1.2 * s(2 * t + 0.5) + s(t - 0.9)),
                  (ROLL, 1.2 * s(t + 2.0))],
         "Jaw": [(PITCH, 1.0 - s(t - 0.4))]},
        tail_wave(t, amp=14, pitch_amp=4, step=0.45))


def walk_pose(t):
    s, c = math.sin, math.cos
    p = {}
    for side, ph in (("L", t), ("R", t + math.pi)):
        ph %= 2 * math.pi
        thigh = 22 * c(ph)  # adelante en el contacto
        swing = max(0.0, -s(ph))
        knee = 6 + 38 * swing ** 1.2
        heel = 18 * max(0.0, (ph / math.pi - 0.6) / 0.4) ** 2 if ph < math.pi else 0.0
        strike = -10 * max(0.0, c(ph)) ** 6
        p.update(leg(side, thigh, knee, foot=thigh - knee + heel + strike + 8 * swing))
        p[side + "Toe"] = [(PITCH, -heel * 0.9)]
    # Brazos al revés que las piernas: con la izquierda delante (t = 0), el brazo izquierdo atrás.
    p.update(arms(fwd=-15 * c(t), bend=10 - 6 * c(t - 0.6), r_fwd=15 * c(t), r_bend=10 + 6 * c(t - 0.6)))
    p["Hips"] = [(YAW, -6 * c(t)), (ROLL, -4 * s(t))]
    p["Spine1"] = [(PITCH, 5), (YAW, 4 * c(t)), (ROLL, 2 * s(t))]
    p["Spine2"] = [(PITCH, 1.5 * c(2 * t - 0.6)), (YAW, 2 * c(t - 0.3))]
    p["Neck"] = [(PITCH, -3 - c(2 * t - 0.9)), (YAW, -2 * c(t - 0.3))]
    p["Head"] = [(PITCH, -1.5 * c(2 * t - 1.2)), (YAW, -3 * c(t - 0.5)), (ROLL, -1.5 * s(t - 0.5))]
    p.update(tail_wave(t, amp=20, pitch_amp=3, step=0.5))
    return pose(p, root=(0.006 * s(t), 0, -0.005 * c(2 * t)))


def cycle(fn, frames):
    return [(f, fn(2 * math.pi * (f - 1) / (frames - 1))) for f in range(1, frames + 1)]


# ---------- ataques: [(fotograma, pose)] ----------
ACTIONS = {
    "idle": lambda: cycle(idle_pose, 24),
    "walk": lambda: cycle(walk_pose, 24),
    "fight_b": lambda: [  # físico genérico: retrocede y embiste con el torso y los brazos
        (1, BASE()),
        (8, pose(arms(fwd=-10, up=10, bend=30), crouch(14), spine(-8), head(-6, lean=-8), tail(pitch=20),
                 root=(0, 0.012, -0.008))),
        (12, pose(arms(fwd=55, bend=-10), crouch(8), spine(14), head(6, lean=14), tail(pitch=-4),
                  root=(0, -0.04, -0.004))),
        (16, pose(arms(fwd=48), crouch(9), spine(12), head(5, lean=12), tail(pitch=-2), root=(0, -0.036, -0.005))),
        (26, BASE()),
    ],
    "fight_b_claw": lambda: [  # zarpazo con la derecha de arriba abajo cruzando el cuerpo
        (1, BASE()),
        (8, pose(arms(r_up=80, r_fwd=10, r_bend=40, fwd=10), crouch(10), spine(-5, yaw=-18), hips(yaw=-8),
                 head(-4, yaw=-6, lean=-5), tail(yaw=25, pitch=10), root=(0, 0.01, -0.006))),
        (12, pose(arms(r_up=-15, r_fwd=70, r_inward=45, fwd=-10), crouch(8), spine(12, yaw=22), hips(yaw=10),
                  head(6, yaw=8, lean=12), tail(yaw=-35, delay=0.6), root=(0, -0.03, -0.005))),
        (15, pose(arms(r_up=-25, r_fwd=60, r_inward=55, r_bend=10, fwd=-10), crouch(9), spine(11, yaw=26),
                  hips(yaw=12), head(5, yaw=10, lean=11), tail(yaw=-25), root=(0, -0.028, -0.006))),
        (26, BASE()),
    ],
    "fight_b_bite": lambda: [  # cabeza atrás con la boca abierta y mordisco hacia delante
        (1, BASE()),
        (7, pose(arms(fwd=-5, up=5, bend=20), crouch(12), spine(-6), head(-18, lean=-6, jaw=28), tail(pitch=18),
                 root=(0, 0.012, -0.007))),
        (11, pose(arms(fwd=35, bend=30), crouch(8), spine(14), head(10, lean=14, jaw=0), tail(pitch=-4),
                  root=(0, -0.038, -0.005))),
        (13, pose(arms(fwd=35, bend=30), crouch(8), spine(14), head(9, yaw=7, lean=14, jaw=2),
                  tail(pitch=-3, yaw=6), root=(0, -0.036, -0.005))),
        (15, pose(arms(fwd=35, bend=30), crouch(8), spine(14), head(9, yaw=-7, lean=14, jaw=2),
                  tail(pitch=-3, yaw=-6), root=(0, -0.036, -0.005))),
        (24, BASE()),
    ],
    "fight_b_punch": lambda: [  # puñetazo recto con la derecha
        (1, BASE()),
        (7, pose(arms(r_fwd=-35, r_bend=70, fwd=30, bend=50), crouch(12), spine(-4, yaw=-20), hips(yaw=-8),
                 head(-2, yaw=12, lean=-4), tail(yaw=18, pitch=8), root=(0, 0.01, -0.007))),
        (10, pose(arms(r_fwd=85, r_inward=10, r_bend=-20, fwd=-20, bend=60), crouch(8), spine(12, yaw=22),
                  hips(yaw=9), head(4, yaw=-10, lean=12), tail(yaw=-28, delay=0.5), root=(0, -0.035, -0.005))),
        (14, pose(arms(r_fwd=80, r_inward=10, r_bend=-15, fwd=-20, bend=60), crouch(9), spine(10, yaw=20),
                  hips(yaw=8), head(4, yaw=-9, lean=10), tail(yaw=-20), root=(0, -0.032, -0.005))),
        (24, BASE()),
    ],
    "fight_b_kick": lambda: [  # patada frontal con la derecha
        (1, BASE()),
        (8, pose(arms(up=25, fwd=10, bend=30), leg("L", 6, 14), leg("R", 55, 80), spine(-4, side=-6),
                 hips(roll=-6), head(-2, lean=-4), tail(pitch=14), root=(0.01, 0.006, -0.004))),
        (12, pose(arms(up=35, fwd=-15, bend=20), leg("L", 4, 10), leg("R", 70, 0, foot=-20), spine(-12, side=-6),
                  hips(roll=-6), head(4, lean=-12), tail(pitch=28), root=(0.01, -0.012, -0.003))),
        (16, pose(arms(up=30, fwd=-10, bend=20), leg("L", 4, 10), leg("R", 62, 5, foot=-15), spine(-10, side=-6),
                  hips(roll=-6), head(3, lean=-10), tail(pitch=24), root=(0.01, -0.01, -0.003))),
        (21, pose(arms(up=15, bend=20), leg("L", 6, 14), leg("R", 30, 50), spine(-4, side=-3), hips(roll=-3),
                  head(0, lean=-4), tail(pitch=10), root=(0.005, 0.0, -0.005))),
        (28, BASE()),
    ],
    "fight_b_tail": lambda: [  # gira el cuerpo y barre con la cola como un látigo
        (1, BASE()),
        (9, pose(arms(up=15, bend=30), crouch(12), spine(4, yaw=30), hips(yaw=35), head(0, yaw=-30, lean=4),
                 tail(yaw=-40, pitch=14), root=(0, 0, -0.007))),
        (14, pose(arms(up=25, bend=20), crouch(10), spine(4, yaw=-35), hips(yaw=-50), head(2, yaw=35, lean=4),
                  tail(yaw=-80, pitch=6, delay=0.7), root=(0, -0.01, -0.006))),
        (18, pose(arms(up=20, bend=20), crouch(10), spine(4, yaw=-30), hips(yaw=-45), head(2, yaw=30, lean=4),
                  tail(yaw=-55, pitch=4), root=(0, -0.01, -0.006))),
        (30, BASE()),
    ],
    "fight_b_body": lambda: [  # placaje: se agacha y embiste de cabeza
        (1, BASE()),
        (8, pose(arms(fwd=-30, up=15, bend=20), crouch(22), spine(12), head(4, lean=12), tail(pitch=22),
                 root=(0, 0.015, -0.014))),
        (12, pose(arms(fwd=-40, up=20, bend=10), crouch(6), spine(22), head(14, lean=22), tail(pitch=-4, delay=0.5),
                  root=(0, -0.065, -0.004))),
        (15, pose(arms(fwd=-35, up=18, bend=15), crouch(14), spine(18), head(10, lean=18), tail(pitch=-2),
                  root=(0, -0.058, -0.01))),
        (24, BASE()),
    ],
    "fight_d": lambda: [  # especial genérico: concentra energía y la lanza con los brazos
        (1, BASE()),
        (10, pose(arms(fwd=10, up=20, bend=70), crouch(10), spine(-6), head(-8, lean=-6, jaw=4),
                  tail(pitch=24, flame=15), root=(0, 0.008, -0.006))),
        (15, pose(arms(fwd=70, up=5, bend=-10), crouch(8), spine(8), head(2, lean=8, jaw=12), tail(pitch=-2),
                  root=(0, -0.015, -0.005))),
        (20, pose(arms(fwd=65, up=5, bend=-5), crouch(8), spine(7), head(2, lean=7, jaw=10), tail(pitch=0),
                  root=(0, -0.014, -0.005))),
        (30, BASE()),
    ],
    "fight_d_breath": lambda: [  # inspira y escupe hacia delante, sosteniendo la llamarada
        (1, BASE()),
        (10, pose(arms(up=20, fwd=-5, bend=30), crouch(6), spine(-10, lean2=-6), head(-24, lean=-10, jaw=6),
                  tail(pitch=26, flame=18), root=(0, 0.01, 0.002))),
        (16, pose(arms(fwd=25, up=5, bend=40), crouch(10), spine(8), head(-2, lean=8, jaw=30), tail(pitch=-2),
                  root=(0, -0.012, -0.006))),
        (22, pose(arms(fwd=25, up=5, bend=40), crouch(10), spine(8), head(-2, yaw=6, lean=8, jaw=32), tail(pitch=0),
                  root=(0, -0.012, -0.006))),
        (28, pose(arms(fwd=25, up=5, bend=40), crouch(10), spine(8), head(-2, yaw=-6, lean=8, jaw=30),
                  tail(pitch=0), root=(0, -0.012, -0.006))),
        (36, BASE()),
    ],
    "fight_d_sound": lambda: [  # rugido
        (1, BASE()),
        (8, pose(arms(fwd=15, bend=40), crouch(12), spine(6), head(10, lean=6, jaw=4), tail(pitch=-2),
                 root=(0, 0, -0.007))),
        (13, pose(arms(up=35, fwd=-10, bend=20), crouch(8), spine(-8, lean2=-5), head(-20, lean=-8, jaw=32),
                  tail(pitch=30, flame=15), root=(0, 0.004, -0.004))),
        (17, pose(arms(up=33, fwd=-10, bend=20), crouch(8), spine(-8, lean2=-5), head(-19, yaw=5, lean=-8, jaw=30),
                  tail(pitch=30, yaw=6), root=(0, 0.004, -0.004))),
        (21, pose(arms(up=35, fwd=-10, bend=20), crouch(8), spine(-8, lean2=-5), head(-19, yaw=-5, lean=-8, jaw=32),
                  tail(pitch=30, yaw=-6), root=(0, 0.004, -0.004))),
        (26, pose(arms(up=30, fwd=-8, bend=20), crouch(8), spine(-6, lean2=-4), head(-14, lean=-6, jaw=24),
                  tail(pitch=22), root=(0, 0.003, -0.004))),
        (32, BASE()),
    ],
    "fight_d_boost": lambda: [  # se recoge y se yergue sacando pecho (Danza Espada, Corpulencia...)
        (1, BASE()),
        (8, pose(arms(fwd=25, inward=20, bend=70), crouch(16), spine(12), head(16, lean=12), tail(pitch=-2),
                 root=(0, 0, -0.011))),
        (16, pose(arms(up=40, fwd=-10, bend=75), crouch(2), spine(-6, lean2=-4), head(-14, lean=-6, jaw=10),
                  tail(pitch=36, flame=20), root=(0, 0, 0.004))),
        (20, pose(arms(up=42, fwd=-10, bend=78), crouch(2), spine(-6, lean2=-4), head(-14, roll=4, lean=-6, jaw=8),
                  tail(pitch=36, yaw=8, flame=24), root=(0, 0, 0.004))),
        (24, pose(arms(up=40, fwd=-10, bend=75), crouch(2), spine(-6, lean2=-4), head(-14, roll=-4, lean=-6, jaw=8),
                  tail(pitch=36, yaw=-8, flame=20), root=(0, 0, 0.004))),
        (32, BASE()),
    ],
}


# ---------- cuadrúpedos ----------
# Patas delanteras: Arm-ForeArm-Hand; traseras: Thigh-Leg-Foot (con Toe, si lo hay, colgando de Foot).
# Cada pata se resuelve con IK de dos huesos en el plano lateral: la pose dice dónde va el extremo
# (Hand o Foot) y el tercer hueso conserva su orientación, así que los apoyos no resbalan aunque el
# cuerpo se mueva. Distancias en alturas de cadera (SCALE); root = (izquierda, atrás, arriba).
QUAD_LEGS = {leg: tuple(n for n in chain if n in B) for leg, chain in {
    "LF": ("LArm", "LForeArm", "LHand"), "RF": ("RArm", "RForeArm", "RHand"),
    "LH": ("LThigh", "LLeg", "LFoot"), "RH": ("RThigh", "RLeg", "RFoot")}.items()}
NECK = [n for n in ("Neck", "Neck1", "Neck2") if n in B]



def _leg_gap(leg):
    """Altura sobre el suelo de lo más bajo de la pata (en alturas de cadera). Las manos de Nidoran♀
    quedan 3 cm en el aire en el propio modelo; la IK las baja."""
    end = B[QUAD_LEGS[leg][-1]]
    names = {end.name} | {b.name for b in end.children_recursive}
    low = [co.dot(UP) for g, co in _mesh_verts() if g in names]
    return (min(low) - _ground_mesh) / SCALE if low else 0.0


if QUAD:
    _ground_mesh = min(co.dot(UP) for _, co in _mesh_verts())
    LEG_GAP = {leg: _leg_gap(leg) for leg in QUAD_LEGS}
    LEG_GAP = {leg: g if g > 0.02 else 0.0 for leg, g in LEG_GAP.items()}


def _2d(v):
    return Vector((v.dot(FWD), v.dot(UP)))


def _rot2(v, deg):
    """Gira un vector del plano (delante, arriba) como lo haría un giro de `deg` sobre PITCH."""
    a = math.radians(deg)
    return Vector((v.x * math.cos(a) + v.y * math.sin(a), -v.x * math.sin(a) + v.y * math.cos(a)))


def _ang(v):
    return math.degrees(math.atan2(v.y, v.x))


def _pitch_of(p, name):
    return sum(deg for axis, deg in p.get(name, []) if axis is PITCH)


def _ancestors(name):
    chain, b = [], B[name].parent
    while b:
        chain.append(_name(b))
        b = b.parent
    return chain[::-1]


def _fk(p, chain):
    """Transformación (giro acumulado, traslación) en el plano lateral tras los huesos de `chain`."""
    root = p.get("root", (0, 0, 0))
    angle, offset = 0.0, Vector((-root[1], root[2])) * SCALE
    for n in chain:
        h, phi = _2d(_pos(n)), _pitch_of(p, n)
        offset = _rot2(h - _rot2(h, phi), angle) + offset
        angle += phi
    return angle, offset


def _leg_ik(p, leg, fwd=0.0, up=0.0, tip=0.0):
    """Giros para que el extremo de la pata quede en su sitio de reposo desplazado (fwd, up).
    `tip`: giro extra del extremo (+ dedos abajo). Con un solo hueso (Raticate) solo apunta hacia allí."""
    chain = QUAD_LEGS[leg]
    top, end = chain[0], chain[-1]
    parent_angle, offset = _fk(p, _ancestors(top))
    t0, e0 = _2d(_pos(top)), _2d(_pos(end))
    t = _rot2(t0, parent_angle) + offset
    target = e0 + Vector((fwd, up - LEG_GAP[leg])) * SCALE
    d = target - t
    if len(chain) == 2:
        d1 = -(_ang(d) - _ang(e0 - t0))
        return {top: [(PITCH, d1 - parent_angle)], end: [(PITCH, -d1 + tip)]}
    mid = chain[1]
    m0 = _2d(_pos(mid))
    l1, l2 = (m0 - t0).length, (e0 - m0).length
    dist = min(max(d.length, abs(l1 - l2) + 1e-4), (l1 + l2) * 0.999)
    base = _ang(d)
    alpha = math.degrees(math.acos(max(-1.0, min(1.0, (l1 * l1 + dist * dist - l2 * l2) / (2 * l1 * dist)))))
    bend = (m0 - t0).x * (e0 - m0).y - (m0 - t0).y * (e0 - m0).x
    best = None
    for sign in (1, -1):
        u = base + sign * alpha
        m = t + Vector((math.cos(math.radians(u)), math.sin(math.radians(u)))) * l1
        e = t + d.normalized() * dist
        if best is None or ((m - t).x * (e - m).y - (m - t).y * (e - m).x) * bend > 0:
            best = (u, _ang(e - m))
    u, lo = best
    # El giro sobre PITCH va al revés que el ángulo del plano (de delante hacia arriba).
    d1 = -(u - _ang(m0 - t0))
    d2 = -(lo - _ang(e0 - m0))
    return {top: [(PITCH, d1 - parent_angle)], mid: [(PITCH, d2 - d1)], end: [(PITCH, -d2 + tip)]}


def qpose(*parts, root=(0, 0, 0), feet=None):
    """Pose de cuadrúpedo: las piezas y, al final, las cuatro patas por IK. feet = {"RF": (fwd, up, tip)}."""
    p = pose(*parts, root=root)
    p["_q"] = ({k: list(v) for k, v in p.items() if k != "root"}, root, feet or {})
    if TWEAKS.get("chest"):
        p["Spine1"] = [(PITCH, TWEAKS["chest"])] + p.get("Spine1", [])
    if TWEAKS.get("front_back"):
        feet = dict(feet or {})
        for leg in ("LF", "RF"):
            f = (tuple(feet.get(leg, ())) + (0, 0, 0))[:3]
            feet[leg] = (f[0] - TWEAKS["front_back"], f[1], f[2])
    for leg in QUAD_LEGS:
        for name, rots in _leg_ik(p, leg, *(feet or {}).get(leg, ())).items():
            p[name] = p.get(name, []) + rots
    return p


def qspine(pitch=0, pitch2=None, hips=0, hips_yaw=0):
    """pitch: + baja el pecho (gira sobre la cadera); hips: + sube la grupa. Sin ladeos: un lomo
    ladeado sube las patas de un lado y hunde las del otro, y la IK (lateral) no lo corrige."""
    return {"Spine1": [(PITCH, pitch)],
            "Spine2": [(PITCH, pitch * 0.5 if pitch2 is None else pitch2)],
            "Hips": [(PITCH, hips), (YAW, hips_yaw)]}


def _blend(qa, qb, k):
    """Pose intermedia entre dos qpose (factor k): interpola los ángulos y vuelve a resolver la IK."""
    (pa, ra, fa), (pb, rb, fb) = qa, qb
    parts = {}
    for bone in set(pa) | set(pb):
        axes = []
        for axis, _ in pa.get(bone, []) + pb.get(bone, []):
            if not any(a is axis for a in axes):
                axes.append(axis)
        parts[bone] = [(axis, (1 - k) * sum(d for a, d in pa.get(bone, []) if a is axis)
                        + k * sum(d for a, d in pb.get(bone, []) if a is axis)) for axis in axes]
    root = tuple((1 - k) * x + k * y for x, y in zip(ra, rb))
    feet = {}
    for leg in set(fa) | set(fb):
        a, b = (tuple(fa.get(leg, ())) + (0, 0, 0))[:3], (tuple(fb.get(leg, ())) + (0, 0, 0))[:3]
        feet[leg] = tuple((1 - k) * x + k * y for x, y in zip(a, b))
    return qpose(parts, root=root, feet=feet)


def densify(keys):
    """Una clave por fotograma: entre poses clave Blender interpolaría los giros y las patas apoyadas
    se hundirían o resbalarían; así la IK se cumple en todos los fotogramas."""
    out = []
    for (fa, a), (fb, b) in zip(keys, keys[1:]):
        for f in range(fa, fb):
            k = (f - fa) / (fb - fa)
            out.append((f, a if f == fa else _blend(a["_q"], b["_q"], k * k * (3 - 2 * k))))
    return out + [keys[-1]]


def qhead(pitch=0, yaw=0, roll=0, jaw=0, spine=0):
    """pitch: + mira abajo (se compensa la inclinación del lomo `spine`); repartido con el cuello."""
    total = pitch - 1.5 * spine
    share = 0.35 if NECK else 0
    d = {n: [(PITCH, total * share / len(NECK)), (YAW, yaw * 0.4 / len(NECK))] for n in NECK}
    d["Head"] = [(PITCH, total * (1 - share)), (YAW, yaw * (0.6 if NECK else 1)), (ROLL, roll)]
    d["Jaw"] = [(PITCH, jaw)]
    return d


def flicker(t, amp=6):
    """Llamas y crines (Rapidash): cada hueso oscila con su propia fase."""
    return {n: [(YAW, amp * math.sin(2 * t + 1.3 * i)), (PITCH, amp * 0.7 * math.sin(3 * t + 0.9 * i))]
            for i, n in enumerate(FLICKER)}


def QBASE():
    return qpose(root=(0, 0, -0.02))


def quad_idle_pose(t):
    s = math.sin
    return qpose(
        qspine(pitch=1.0 * s(t + 0.5), pitch2=-1.2 * s(t)),
        qhead(pitch=1.5 * s(2 * t + 0.5) + s(t - 0.9), yaw=5 * s(t + 1.0) + s(2 * t + 0.4), roll=1.5 * s(t + 2.0),
              jaw=1.0 - s(t - 0.4)),
        tail_wave(t, amp=12, pitch_amp=3, step=0.45), flicker(t),
        root=(0, 0.004 * s(t + 0.3), -0.02 + 0.012 * s(t)))


def quad_sit_pose(t):
    """Sentado como un gato: la grupa en el suelo, el pecho alto sobre las patas delanteras estiradas."""
    s = math.sin
    return qpose(
        qspine(pitch=-42 + 1.0 * s(t + 0.5), pitch2=-10, hips=-62),
        qhead(pitch=45 + 1.5 * s(2 * t + 0.5), yaw=6 * s(t + 1.0), roll=1.5 * s(t + 2.0), jaw=1.0 - s(t - 0.4)),
        tail(yaw=70 + 8 * s(t), pitch=65), flicker(t),
        root=(0, 0.04, -0.33 + 0.008 * s(t)), feet={"LH": (0.14, 0, 0), "RH": (0.14, 0, 0)})


# Paso lateral (el de casi todos los cuadrúpedos al andar): trasera izq., delantera izq., trasera der.,
# delantera der., cada una un cuarto de ciclo después. 65 % del ciclo apoyada.
QUAD_PHASE = {"LH": 0.0, "LF": 0.25, "RH": 0.5, "RF": 0.75}
DUTY, STRIDE, LIFT = 0.65, 0.22, 0.14


def _tip_max(leg):
    """Giro de punta abajo al levantar la pata: 30° salvo que los dedos bajen más de lo que sube la pata
    y atraviesen el suelo (los pies largos de los Nidoran)."""
    end = B[QUAD_LEGS[leg][-1]]
    names = {end.name} | {b.name for b in end.children_recursive}
    head = _2d(end.head_local)
    pts = [_2d(co) - head for g, co in _mesh_verts() if g in names]
    if not pts:
        return 30
    low = min(v.y for v in pts)
    for deg in range(30, 0, -2):
        if low - min(_rot2(v, deg).y for v in pts) <= 0.8 * LIFT * SCALE:
            return deg
    return 0


TIP_MAX = {leg: _tip_max(leg) for leg in QUAD_LEGS} if QUAD else {}


def _step(ph, leg):
    """(fwd, up, tip) del extremo de una pata en la fase ph (0..1) del ciclo."""
    if ph < DUTY:
        return (STRIDE * (1 - 2 * ph / DUTY), 0.0, 0.0)
    q = (ph - DUTY) / (1 - DUTY)
    ease = q * q * (3 - 2 * q)
    return (-STRIDE + 2 * STRIDE * ease, LIFT * math.sin(math.pi * q), TIP_MAX[leg] * math.sin(math.pi * q))


def quad_walk_pose(t):
    s, c = math.sin, math.cos
    cyc = t / (2 * math.pi)
    feet = {leg: _step((cyc + ph) % 1.0, leg) for leg, ph in QUAD_PHASE.items()}
    return qpose(
        qspine(pitch=1.0 * c(2 * t), hips_yaw=2 * s(t)),
        qhead(pitch=2 * c(2 * t - 0.8), yaw=-3 * c(t - 0.5), roll=-1.5 * s(t - 0.5)),
        tail_wave(t, amp=16, pitch_amp=3, step=0.5), flicker(t, amp=9),
        root=(0.008 * s(t), 0, -0.03 + 0.012 * c(2 * t)), feet=feet)


QUAD_ACTIONS = {
    "idle": lambda: cycle(quad_idle_pose, 24),
    "walk": lambda: cycle(quad_walk_pose, 24),
    "fight_b": lambda: [  # físico genérico: se agacha hacia atrás y embiste con el pecho
        (1, QBASE()),
        (8, qpose(qspine(-4), qhead(-6, spine=-4), tail(pitch=18), root=(0, 0.08, -0.09))),
        (12, qpose(qspine(8), qhead(8, spine=8, jaw=6), tail(pitch=-4), root=(0, -0.2, -0.03),
                   feet={"LF": (0.12, 0), "RF": (0.12, 0)})),
        (16, qpose(qspine(7), qhead(7, spine=7, jaw=4), tail(pitch=-2), root=(0, -0.18, -0.035),
                   feet={"LF": (0.12, 0), "RF": (0.12, 0)})),
        (26, QBASE()),
    ],
    "fight_b_bite": lambda: [  # echa la cabeza atrás con la boca abierta y muerde hacia delante
        (1, QBASE()),
        (7, qpose(qspine(-2), qhead(-22, spine=-2, jaw=30), tail(pitch=16), root=(0, 0.07, -0.06))),
        (11, qpose(qspine(8), qhead(12, spine=8, jaw=0), tail(pitch=-4), root=(0, -0.2, -0.04),
                   feet={"LF": (0.1, 0), "RF": (0.1, 0)})),
        (13, qpose(qspine(8), qhead(11, yaw=10, spine=8, jaw=3), tail(pitch=-3, yaw=8), root=(0, -0.19, -0.04),
                   feet={"LF": (0.1, 0), "RF": (0.1, 0)})),
        (15, qpose(qspine(8), qhead(11, yaw=-10, spine=8, jaw=3), tail(pitch=-3, yaw=-8), root=(0, -0.19, -0.04),
                   feet={"LF": (0.1, 0), "RF": (0.1, 0)})),
        (24, QBASE()),
    ],
    "fight_b_body": lambda: [  # placaje: se encoge y carga con todo el cuerpo, cabeza gacha
        (1, QBASE()),
        (8, qpose(qspine(3), qhead(10, spine=3), tail(pitch=20), root=(0, 0.12, -0.14))),
        (12, qpose(qspine(10), qhead(22, spine=10), tail(pitch=-6, delay=0.5), root=(0, -0.32, -0.04),
                   feet={"LF": (0.25, 0), "RF": (0.18, 0), "LH": (0.06, 0), "RH": (0.06, 0)})),
        (15, qpose(qspine(8), qhead(18, spine=8), tail(pitch=-2), root=(0, -0.3, -0.06),
                   feet={"LF": (0.25, 0), "RF": (0.18, 0), "LH": (0.06, 0), "RH": (0.06, 0)})),
        (24, QBASE()),
    ],
    "fight_b_horn": lambda: [  # baja la cabeza apuntando con el cuerno y cornea hacia delante y arriba
        (1, QBASE()),
        (8, qpose(qspine(6), qhead(30, spine=6), tail(pitch=14), root=(0, 0.08, -0.12))),
        (12, qpose(qspine(4), qhead(-8, spine=4), tail(pitch=-6, delay=0.5), root=(0, -0.24, -0.02),
                   feet={"LF": (0.15, 0), "RF": (0.15, 0)})),
        (16, qpose(qspine(3), qhead(-4, spine=3), tail(pitch=-2), root=(0, -0.22, -0.03),
                   feet={"LF": (0.15, 0), "RF": (0.15, 0)})),
        (26, QBASE()),
    ],
    "fight_b_claw": lambda: [  # se apoya atrás, alza la pata delantera derecha y da un zarpazo
        (1, QBASE()),
        (8, qpose(qspine(-8), qhead(-6, yaw=-6, spine=-8), tail(yaw=20, pitch=12),
                  root=(0.03, 0.06, -0.04), feet={"RF": (0.25, 0.5, -30)})),
        (12, qpose(qspine(8), qhead(10, yaw=8, spine=8), tail(yaw=-25, delay=0.6),
                   root=(-0.01, -0.12, -0.05), feet={"RF": (0.42, 0.04, 25)})),
        (15, qpose(qspine(7), qhead(8, yaw=8, spine=7), tail(yaw=-18), root=(-0.01, -0.11, -0.05),
                   feet={"RF": (0.38, 0.0, 15)})),
        (22, qpose(qspine(2), qhead(2, spine=2), tail(yaw=-5), root=(0, -0.03, -0.03), feet={"RF": (0.12, 0.12, 10)})),
        (26, QBASE()),
    ],
    "fight_b_punch": lambda: [  # pisotón: se alza sobre las patas traseras y cae con las delanteras
        (1, QBASE()),
        (8, qpose(qspine(-6), qhead(4, spine=-6), tail(pitch=10), root=(0, 0.05, -0.05))),
        (13, qpose(qspine(-18), qhead(-4, spine=-18, jaw=10), tail(pitch=-10), root=(0, 0.06, 0.0),
                   feet={"LF": (0.15, 0.55, -20), "RF": (0.2, 0.6, -20), "LH": (-0.04, 0), "RH": (-0.04, 0)})),
        (17, qpose(qspine(6), qhead(10, spine=6), tail(pitch=16, delay=0.5), root=(0, -0.08, -0.1),
                   feet={"LF": (0.18, 0), "RF": (0.22, 0)})),
        (20, qpose(qspine(5), qhead(9, spine=5), tail(pitch=8), root=(0, -0.07, -0.08),
                   feet={"LF": (0.18, 0), "RF": (0.22, 0)})),
        (28, QBASE()),
    ],
    "fight_b_kick": lambda: [  # coz: carga el peso delante y patea hacia atrás con las traseras
        (1, QBASE()),
        (8, qpose(qspine(4), qhead(6, spine=4), tail(pitch=10), root=(0, -0.04, -0.08),
                  feet={"LH": (0.1, 0.12, 20), "RH": (0.1, 0.12, 20)})),
        (12, qpose(qspine(10, hips=12), qhead(-6, spine=10), tail(pitch=30, delay=0.5), root=(0, -0.1, -0.02),
                   feet={"LH": (-0.6, 0.45, -20), "RH": (-0.55, 0.4, -20)})),
        (16, qpose(qspine(9, hips=10), qhead(-4, spine=9), tail(pitch=24), root=(0, -0.1, -0.03),
                   feet={"LH": (-0.55, 0.4, -15), "RH": (-0.5, 0.36, -15)})),
        (21, qpose(qspine(3, hips=2), qhead(2, spine=3), tail(pitch=8), root=(0, -0.04, -0.04),
                   feet={"LH": (-0.1, 0.12, 15), "RH": (-0.08, 0.1, 15)})),
        (28, QBASE()),
    ],
    "fight_b_tail": lambda: [  # gira la grupa y barre con la cola
        (1, QBASE()),
        (9, qpose(qspine(2, hips_yaw=6), qhead(0, yaw=-25, spine=2), tail(yaw=-45, pitch=12),
                  root=(-0.02, 0, -0.05))),
        (14, qpose(qspine(2, hips_yaw=-8), qhead(2, yaw=30, spine=2), tail(yaw=85, pitch=6, delay=0.7),
                   root=(0.02, 0, -0.05))),
        (18, qpose(qspine(2, hips_yaw=-7), qhead(2, yaw=26, spine=2), tail(yaw=60, pitch=4),
                   root=(0.02, 0, -0.05))),
        (30, QBASE()),
    ],
    "fight_d": lambda: [  # especial genérico: se afianza, concentra con la cabeza alta y lanza hacia delante
        (1, QBASE()),
        (10, qpose(qspine(-2), qhead(-18, spine=-2, jaw=4), tail(pitch=22, flame=15), root=(0, 0.05, -0.07),
                   feet={"LF": (0.06, 0), "RF": (-0.04, 0)})),
        (15, qpose(qspine(5), qhead(6, spine=5, jaw=16), tail(pitch=-2), root=(0, -0.08, -0.04),
                   feet={"LF": (0.06, 0), "RF": (-0.04, 0)})),
        (20, qpose(qspine(4), qhead(5, spine=4, jaw=12), tail(pitch=0), root=(0, -0.07, -0.04),
                   feet={"LF": (0.06, 0), "RF": (-0.04, 0)})),
        (30, QBASE()),
    ],
    "fight_d_breath": lambda: [  # inspira alzando la cabeza y escupe hacia delante barriendo un poco
        (1, QBASE()),
        (10, qpose(qspine(-3), qhead(-30, spine=-3, jaw=6), tail(pitch=24, flame=18), root=(0, 0.06, -0.03))),
        (16, qpose(qspine(4), qhead(4, spine=4, jaw=32), tail(pitch=-2), root=(0, -0.08, -0.06))),
        (22, qpose(qspine(4), qhead(4, yaw=9, spine=4, jaw=34), tail(pitch=0, yaw=-6), root=(0, -0.08, -0.06))),
        (28, qpose(qspine(4), qhead(4, yaw=-9, spine=4, jaw=32), tail(pitch=0, yaw=6), root=(0, -0.08, -0.06))),
        (36, QBASE()),
    ],
    "fight_d_sound": lambda: [  # rugido con la cabeza alta
        (1, QBASE()),
        (8, qpose(qspine(5), qhead(12, spine=5, jaw=4), tail(pitch=-2), root=(0, 0.02, -0.06))),
        (13, qpose(qspine(-3), qhead(-32, spine=-3, jaw=34), tail(pitch=28, flame=15), root=(0, 0.03, -0.03))),
        (17, qpose(qspine(-3), qhead(-31, yaw=7, spine=-3, jaw=32), tail(pitch=28, yaw=6), root=(0, 0.03, -0.03))),
        (21, qpose(qspine(-3), qhead(-31, yaw=-7, spine=-3, jaw=34), tail(pitch=28, yaw=-6), root=(0, 0.03, -0.03))),
        (26, qpose(qspine(-2), qhead(-24, spine=-2, jaw=24), tail(pitch=20), root=(0, 0.02, -0.03))),
        (32, QBASE()),
    ],
    "fight_d_boost": lambda: [  # se recoge, pisa fuerte y se yergue con la cola en alto
        (1, QBASE()),
        (8, qpose(qspine(4), qhead(14, spine=4), tail(pitch=-4), root=(0, 0.03, -0.12),
                  feet={"RF": (0.05, 0.25, 10)})),
        (12, qpose(qspine(4), qhead(12, spine=4), tail(pitch=-2), root=(0, 0.03, -0.13))),
        (17, qpose(qspine(-4), qhead(-24, spine=-4, jaw=10), tail(pitch=34, flame=20), root=(0, 0.03, -0.02))),
        (21, qpose(qspine(-4), qhead(-24, roll=6, spine=-4, jaw=8), tail(pitch=34, yaw=8, flame=24),
                   root=(0, 0.03, -0.02))),
        (25, qpose(qspine(-4), qhead(-24, roll=-6, spine=-4, jaw=8), tail(pitch=34, yaw=-8, flame=20),
                   root=(0, 0.03, -0.02))),
        (32, QBASE()),
    ],
    "fight_d_mind": lambda: [  # se concentra: ladea la cabeza, se queda quieto y libera el poder
        (1, QBASE()),
        (10, qpose(qspine(2), qhead(10, roll=14, spine=2), tail(pitch=6), root=(0, 0.01, -0.04))),
        (16, qpose(qspine(2), qhead(12, roll=16, yaw=3, spine=2), tail(pitch=8), root=(0, 0.01, -0.045))),
        (20, qpose(qspine(-2), qhead(-18, roll=-4, spine=-2, jaw=8), tail(pitch=20), root=(0, 0.02, -0.03))),
        (24, qpose(qspine(-2), qhead(-15, roll=-2, spine=-2, jaw=6), tail(pitch=18), root=(0, 0.02, -0.03))),
        (34, QBASE()),
    ],
    "fight_d_powder": lambda: [  # se sacude a sacudidas cortas para soltar polvos (bulbo, flor)
        (1, QBASE()),
        (7, qpose(qspine(4), qhead(12, spine=4), root=(0, 0, -0.1))),
        (10, qpose(qspine(-3), qhead(-8, yaw=8, spine=-3), tail(yaw=12), root=(0, 0, -0.02))),
        (12, qpose(qspine(3), qhead(4, yaw=-6, spine=3), tail(yaw=-10), root=(0, 0, -0.09))),
        (14, qpose(qspine(-3), qhead(-8, yaw=8, spine=-3), tail(yaw=10), root=(0, 0, -0.02))),
        (16, qpose(qspine(3), qhead(4, yaw=-6, spine=3), tail(yaw=-8), root=(0, 0, -0.09))),
        (18, qpose(qspine(-3), qhead(-8, yaw=6, spine=-3), tail(yaw=6), root=(0, 0, -0.02))),
        (21, qpose(qspine(-2), qhead(-4, spine=-2), root=(0, 0, -0.04))),
        (30, QBASE()),
    ],
}
if QUAD:
    ACTIONS = QUAD_ACTIONS


# ---------- qué acciones necesita ----------
def learnset_actions(name):
    """fight_<x>_<variante> de los ataques de data/pokemon/<name>.tres que estas poses saben hacer."""
    tres = PROJECT / "data/pokemon" / f"{name}.tres"
    if not tres.exists():
        return set()
    found = set()
    for mid in set(re.findall(r'path="res://data/moves/([^"]+)\.tres"', tres.read_text(encoding="utf-8"))):
        text = (PROJECT / "data/moves" / f"{mid}.tres").read_text(encoding="utf-8")
        anim = re.search(r'^animation = "([^"]*)"', text, re.MULTILINE)
        variant = re.search(r'^anim_variant = "([^"]*)"', text, re.MULTILINE)
        if anim and variant and (TAIL or variant.group(1) != "tail"):
            found.add(f"{anim.group(1)}_{variant.group(1)}")
    found &= set(ACTIONS)
    return found


def has_motion(action):
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for fc in bag.fcurves:
                    vals = [k.co[1] for k in fc.keyframe_points]
                    if vals and max(vals) - min(vals) > 1e-4:
                        return True
    return False


HOVER = 0.06  # altura de vuelo, en alturas de Charmander como el resto de distancias


def _float_legs(frame):
    """Piernas de los que flotan: colgando (fly) o cruzadas (lotus)."""
    sw = math.sin(frame * 0.4)
    if STYLE["style"] == "fly":
        return {**leg("L", 18 + 4 * sw, 40 + 6 * sw), **leg("R", 14 - 4 * sw, 36 - 6 * sw)}
    d = {}
    for side, k in (("L", SIDE), ("R", -SIDE)):
        # Muslo hacia delante y afuera; la espinilla gira en horizontal hacia el centro (sobre el eje que,
        # con el muslo adelantado, ya es el vertical) y se cruza delante con la otra.
        d[side + "Thigh"] = [(YAW, 45 * k), (PITCH, -80)]
        d[side + "Leg"] = [(ROLL, 105 * k), (PITCH, 10)]
        d[side + "Foot"] = [(PITCH, 70)]
    return d


def styled(name, keys):
    """Aplica el estilo de la especie a las poses clave de una acción."""
    kind = STYLE.get("style")
    if kind in ("fly", "lotus"):
        out = []
        for i, (frame, p) in enumerate(keys):
            p = dict(p)
            p.update(_float_legs(frame))
            # Flota a HOVER, con un vaivén lento; al debilitarse va cayendo al suelo.
            k = 1 - i / max(1, len(keys) - 1) if name == "ko" else 1
            bob = 0.012 * math.sin(2 * math.pi * (frame - 1) / 24)
            root = p.get("root", (0, 0, 0))
            p["root"] = (root[0], root[1], root[2] + (HOVER + bob) * k)
            if name == "walk":  # vuela inclinado hacia delante
                p["Hips"] = [(PITCH, 12)] + p.get("Hips", [])
            if kind == "lotus":  # la cola cuelga en vez de quedar tiesa hacia atrás
                for n, rots in tail(pitch=-35).items():
                    p[n] = rots + p.get(n, [])
            out.append((frame, p))
        return out
    if kind == "sit" and name == "idle":
        return cycle(quad_sit_pose, 48)
    return keys


def flap(act):
    """Aleteo rápido de insecto (un batido cada 3 fotogramas) en toda la acción, encima de las claves."""
    wings = [w for w in STYLE.get("wings", []) if w in B]
    if not wings:
        return
    by_canon = {CANON.get(pb.name): pb for pb in PB}
    for frame in range(int(act.frame_start), int(act.frame_end) + 1):
        a = 38 * math.sin(2 * math.pi * frame / 3)
        for w in wings:
            pb = by_canon[w]
            k = SIDE if w.startswith("L") else -SIDE
            pb.rotation_quaternion = lquat(w, [(ROLL, -a * k)])
            pb.keyframe_insert("rotation_quaternion", frame=frame, group=pb.name)


def build(name, keys):
    keys = styled(name, keys)
    if QUAD and name not in ("idle", "walk"):
        keys = densify(keys)
    old = bpy.data.actions.get(name)
    if old:
        bpy.data.actions.remove(old)
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    act.use_frame_range = True
    act.frame_start, act.frame_end = keys[0][0], keys[-1][0]
    act.use_cyclic = name in ("idle", "walk")
    arm.animation_data.action = act
    for frame, p in keys:
        root = p.get("root", (0, 0, 0))
        offset = (LEFT * root[0] + BACK * root[1] + UP * root[2]) * SCALE
        for pb in PB:
            name = CANON.get(pb.name, "")  # "" = un duplicado al normalizar: se queda en reposo
            pb.rotation_mode = "QUATERNION"
            rots = p.get(name) if name else None
            if name in BASE_ROTS:
                rots = BASE_ROTS[name] + (rots or [])
            pb.rotation_quaternion = lquat(name, rots) if rots else Quaternion()
            pb.location = B[name].matrix_local.to_3x3().inverted() @ offset if name in ROOTS else Vector()
            pb.keyframe_insert("location", frame=frame, group=pb.name)
            pb.keyframe_insert("rotation_quaternion", frame=frame, group=pb.name)
    flap(act)


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    force = "--force" in args
    wanted = [a for a in args if not a.startswith("--")]
    unknown = [a for a in wanted if a not in ACTIONS]
    if unknown:
        raise SystemExit(f"Acciones desconocidas: {', '.join(unknown)}. Válidas: {', '.join(ACTIONS)}")
    name = Path(bpy.data.filepath).stem
    if not wanted:
        wanted = [a for a in ACTIONS if not a.startswith("fight_") or a in ("fight_b", "fight_d")
                  or a in learnset_actions(name)]
    arm.animation_data_create()
    # Por nombre: si es una de las que se rehacen, el objeto Action se borra.
    previous = arm.animation_data.action.name if arm.animation_data.action else "idle"
    made, kept = [], []
    for action_name in wanted:
        existing = bpy.data.actions.get(action_name)
        if existing and has_motion(existing) and not force:
            kept.append(action_name)
            continue
        build(action_name, ACTIONS[action_name]())
        made.append(action_name)
    arm.animation_data.action = bpy.data.actions.get(previous) or bpy.data.actions.get("idle")
    for pb in PB:
        pb.rotation_quaternion = Quaternion()
        pb.location = Vector()
    bpy.ops.wm.save_mainfile()
    body = "cuadrúpedo" if QUAD else "bípedo, sin brazos" if not HAS_ARMS else \
        f"bípedo, brazos bajados L {ARM_LOWER['L']:.0f}° R {ARM_LOWER['R']:.0f}°" + (", brazos hacia delante" if ARM_AHEAD["L"] else "")
    body += ", el cuerpo es la cabeza" if HEAD_IS_BODY else ""
    print(f"Arriba {tuple(UP)}, delante {tuple(FWD)}, L{'=' if SIDE > 0 else ' espejado'}. Escala {SCALE:.2f}, {body}, "
          f"{len(TAILS)} cola(s), la principal de {len(TAIL)} huesos (+{len(FLAME)} de punta, {len(FLICKER)} de llamas)")
    print("Animadas:", ", ".join(made) or "ninguna")
    if kept:
        print("Ya tenían movimiento (no se tocan; usa --force para rehacerlas):", ", ".join(kept))


main()

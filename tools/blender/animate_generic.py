"""Anima Pokémon sin patas que no son serpientes (Caterpie, Magikarp, Tentacool, Voltorb...).

    blender --background art/blender/magikarp.blend --python tools/blender/animate_generic.py [-- acciones] [--force]

No hace falta que el esqueleto siga la convención de Charmander: el cuerpo entero se mueve desde los huesos
raíz (vaivén, salto, embestida) y cada apéndice (cola, antenas, tentáculos, aletas, alas, brazos...) oscila
con un retraso a lo largo de su cadena, así que ondula. Los apéndices tumbados aletean arriba y abajo; los
que apuntan arriba o abajo se mecen adelante y atrás. Delante es -Y del mundo (hacia donde mira el juego).
Igual que animate_pokemon.py, no rehace las acciones que ya tienen movimiento salvo con --force.
"""
import math
import re
import sys
from pathlib import Path

import bpy
from mathutils import Quaternion, Vector

PROJECT = Path(__file__).resolve().parents[2]
NAME = Path(bpy.data.filepath).stem

arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
PB = arm.pose.bones
BONES = arm.data.bones


def _canon(name):
    return re.sub(r"_\d+$", "", re.sub(r"^\d+ ", "", name))


def _snap(v):
    i = max(range(3), key=lambda k: abs(v[k]))
    axis = Vector((0, 0, 0))
    axis[i] = 1 if v[i] > 0 else -1
    return axis


_to_arm = arm.matrix_world.inverted().to_3x3()
UP = _snap(_to_arm @ Vector((0, 0, 1)))
FWD = _snap(_to_arm @ Vector((0, -1, 0)))
LEFT = UP.cross(FWD)
PITCH = LEFT  # inclina adelante (+)

# Huesos que solo marcan el final de una cadena o vienen del rip sin deformar nada.
_SKIP = re.compile(r"End.*|_rootJoint|mesh\d*|pm\d+.*|Origin")
ROOTS = [b for b in BONES if b.parent is None]
# Ajustes por especie: amp (grados del vaivén de apéndices), freq (vaivenes por ciclo de reposo), hover
# (flota: insectos voladores), float (flota subiendo y bajando mucho, sin saltar al avanzar), puff (se hincha
# en el ataque especial: escala del cuerpo), wings (cadenas de alas: aletean las dos a la vez, arriba y abajo;
# "flap" = (grados, grados de alas alzadas, retraso de las de detrás en ciclos, aleteos por ciclo de reposo);
# "flap_follow" = (retraso por hueso hacia la punta en ciclos, amplitud de los huesos de la punta), por defecto
# (0.06, 0.35)),
# shell (huesos que van con el cuerpo, como la concha de Cloyster), roll (al avanzar rueda, como Voltorb),
# legs (patas de araña abiertas a los lados, como Paras: al andar barren adelante y atrás en diagonal),
# crab (anda de lado: se gira 90° y las patas solo suben y bajan, deprisa), hold (huesos con un giro fijo
# en todas las poses: regex -> grados sobre el eje de cabeceo, o lista de (eje, grados) con eje "PITCH",
# "DROP" (baja el hueso hacia el suelo) o "FWD" (lo lleva hacia delante); DROP y FWD van espejados por lado).
TWEAKS = {
    "butterfree": {"hover": True, "freq": 4, "wings": r"[LR]Feeler[AB]\d*", "flap": (32, 10, 0.04, 6)},
    # La polilla bate más lento y amplio, con las alas de detrás muy retrasadas: un batido en ocho.
    "venomoth": {"hover": True, "freq": 3, "wings": r"[LR]Feeler[AB]\d*", "flap": (40, 20, 0.15, 4)},
    "magikarp": {"amp": 16, "freq": 2},
    "tentacool": {"amp": 14},
    "tentacruel": {"amp": 12},
    "cloyster": {"shell": r"[LR]Feeler[AB]"},
    "paras": {"legs": True, "amp": 5},
    # Las pinzas colgaban por debajo de las patas y el juego lo apoyaba en ellas: van levantadas hacia delante.
    "parasect": {"legs": True, "amp": 5, "hold": {r"[LR]ForeArm": -70}},
    # Brazos en cruz del rip (más del doble de anchos que la roca): bajados, con el codo doblado adelante y
    # los dedos cerrados en puño, como en el artwork.
    "geodude": {"hold": {r"[LR]Arm": [("DROP", 12), ("FWD", 12)], r"[LR]ForeArm": [("FWD", 50), ("DROP", -35)],
                         r"[LR]Finger[B-E]\d": [("FWD", 60)],
                         r"[LR]FingerA\d": [("FWD", 35), ("DROP", 30)]}},
    "voltorb": {"roll": True},
    "electrode": {"roll": True},
    # Bolas de gas con esqueleto automático (setup_animations.auto_rig): flotan y se hinchan.
    "koffing": {"float": True, "puff": 1.3, "amp": 9},
    "weezing": {"float": True, "puff": 1.25, "amp": 9},
    "gastly": {"float": True, "puff": 1.15, "amp": 6},
    "magneton": {"float": True, "amp": 8},
    "exeggcute": {"amp": 8},
    # Esqueletos de plantilla (rig_templates.py).
    "golbat": {"hover": True, "amp": 28, "freq": 3},
    "goldeen": {"amp": 16, "freq": 2},
    "seaking": {"amp": 16, "freq": 2},
    "horsea": {"float": True, "amp": 12},
    "seadra": {"float": True, "amp": 12},
    "lapras": {"amp": 8},
    "shellder": {"amp": 7},  # la concha abre poco: más estira la cara de dentro
    "kabuto": {"amp": 12},
    # Cangrejos: andan de lado (crab) sobre sus patas, con las pinzas casi quietas.
    "krabby": {"amp": 6, "legs": True, "crab": True},
    "kingler": {"amp": 6, "legs": True, "crab": True},
    # Rips con esqueletos propios (Bone001..., L_UpperArm...): sin la convención de Charmander.
    "zubat": {"hover": True, "amp": 24, "freq": 3},
    # Moltres bate despacio y amplio (un batido por segundo) y la punta del ala llega tarde: ondula como un ave.
    "moltres": {"hover": True, "freq": 2, "wings": r"[LR]_(UpperArm|Forearm|Hand|Wing_ex)", "flap": (36, 10, 0.0, 2),
                "flap_follow": (0.11, 0.6)},
    "onix": {"amp": 7},
    "ditto": {"amp": 6},
    "grimer": {"amp": 7},
    "muk": {"amp": 7},
    "wigglytuff": {"amp": 8},
    "haunter": {"float": True, "amp": 10},
    "magnemite": {"float": True, "amp": 4},
}.get(NAME, {})
AMP = TWEAKS.get("amp", 10)
FREQ = TWEAKS.get("freq", 1)
HOVER = TWEAKS.get("hover", False)
FLOAT = TWEAKS.get("float", False)
PUFF = TWEAKS.get("puff", 1.0)
ROLL_WALK = TWEAKS.get("roll", False)
CRAB = TWEAKS.get("crab", False)
# Una vuelta por casilla: el juego tarda STEP_TIME (0,22 s) en cada una y el clip de andar dura 21 fotogramas
# (0,875 s a 24 fps), así que lleva 4 vueltas. Al llegar a la casilla queda de cara y volver al reposo no se nota.
ROLL_TURNS, ROLL_FRAMES = 4, 21

# Cuerpo: raíces y columna; lo que deforma pero no es cuerpo es un apéndice.
_BODY = re.compile(r"Hips|Waist|Spine\d*|Neck\d*|Head\d*|Origin|_rootJoint|pm\d+.*|mesh\d*"
                   + ("|" + TWEAKS["shell"] if "shell" in TWEAKS else ""))
BODY = [b for b in BONES if _BODY.fullmatch(_canon(b.name))]
APPENDAGES = [b for b in BONES if b not in BODY and not _SKIP.fullmatch(_canon(b.name))]
# Patas: el muslo barre y levanta; lo que cuelga de él (rodilla, pie) va rígido.
LEGS = [b for b in APPENDAGES if TWEAKS.get("legs") and re.fullmatch(r"[LR](Thigh2?|Leg1)", _canon(b.name))]
APPENDAGES = [b for b in APPENDAGES if not any(b.parent == l or b.parent in l.children_recursive for l in LEGS)]
WINGS = [b for b in APPENDAGES if "wings" in TWEAKS and re.fullmatch(TWEAKS["wings"], _canon(b.name))]


def _depth(bone):
    """Posición en su cadena de apéndice: 0 en el hueso que sale del cuerpo."""
    d = 0
    while bone.parent and bone.parent in APPENDAGES:
        bone, d = bone.parent, d + 1
    return d


DEPTH = {b.name: _depth(b) for b in APPENDAGES}
_lo = min((arm.matrix_world @ v.co).z for o in bpy.context.scene.objects if o.type == "MESH" for v in o.data.vertices)
_hi = max((arm.matrix_world @ v.co).z for o in bpy.context.scene.objects if o.type == "MESH" for v in o.data.vertices)
HEIGHT = max(_hi - _lo, 1e-3) / arm.matrix_world.to_scale().z


def _swing_axis(bone):
    """Eje de oscilación en el espacio de la armadura: aleteo si el hueso va tumbado, vaivén si va de pie."""
    d = (bone.tail_local - bone.head_local).normalized()
    side = d.cross(UP)
    return side.normalized() if side.length > 0.35 else LEFT


AXIS = {b.name: _swing_axis(b) for b in APPENDAGES}
# Las patas giran sobre la vertical (barrido) y sobre el eje de delante (levantar): signo según el lado.
for _b in LEGS:
    del AXIS[_b.name]
# Las alas giran sobre el eje de delante (arriba y abajo), espejadas: el signo según el lado del cuerpo.
for _b in WINGS:
    AXIS[_b.name] = FWD if _b.head_local.dot(LEFT) > 0 else -FWD
_verts = [arm.matrix_world.inverted() @ (o.matrix_world @ v.co)
          for o in bpy.context.scene.objects if o.type == "MESH" for v in o.data.vertices]
# Centro de la caja del cuerpo (espacio de la armadura): sobre él gira al rodar.
CENTER = Vector([(min(v[i] for v in _verts) + max(v[i] for v in _verts)) / 2 for i in range(3)])



def lquat_arm(axis, deg):
    return Quaternion(axis, math.radians(deg))


def lquat(bone, axis, deg):
    inv = bone.matrix_local.to_3x3().inverted()
    return Quaternion((inv @ axis).normalized(), math.radians(deg))


# ---------- poses: dict con root=(adelante, arriba) en alturas, pitch del cuerpo y fase/amp de apéndices ----------
def _hold(bone, spec):
    if isinstance(spec, (int, float)):
        return lquat(bone, PITCH, spec)
    out = LEFT if bone.head_local.dot(LEFT) >= 0 else -LEFT  # hacia dónde sale el hueso del cuerpo
    axes = {"PITCH": PITCH, "DROP": out.cross(-UP).normalized(), "FWD": out.cross(FWD).normalized()}
    q = Quaternion()
    for ax, deg in spec:
        q = Quaternion(axes[ax], math.radians(deg)) @ q
    rest = bone.matrix_local.to_quaternion()
    return rest.inverted() @ q @ rest


HOLD = {b.name: _hold(b, spec) for b in BONES for rx, spec in TWEAKS.get("hold", {}).items()
        if re.fullmatch(rx, _canon(b.name))}


def P(fwd=0.0, up=0.0, pitch=0.0, yaw=0.0, amp=None, phase=0.0, spread=0.0, scale=1.0, wing=None, gait=None):
    """wing: fase del aleteo (ciclos); si no se da, aletea al ritmo de los fotogramas (lo pone apply_pose).
    gait: fase del paso de las patas (ciclos); sin él, quietas."""
    return {"root": (fwd, up), "pitch": pitch, "yaw": yaw, "amp": AMP if amp is None else amp,
            "phase": phase, "spread": spread, "scale": scale, "wing": wing, "gait": gait}


def cycle(fn, frames):
    return [(f + 1, fn(f / frames)) for f in range(0, frames + 1, 2)]


def idle_pose(t):
    s = math.sin(2 * math.pi * t)
    hover = 0.03 * s if HOVER else 0.05 * s if FLOAT else 0.0
    return P(up=0.012 * s + hover, pitch=1.5 * s, phase=FREQ * t)


def walk_pose(t):
    if ROLL_WALK:  # una vuelta entera por ciclo, sin saltar
        return P(pitch=360 * ROLL_TURNS * t, amp=AMP * 0.5, phase=2 * FREQ * t)
    if CRAB:  # de lado: el costado derecho por delante, con pasitos rápidos
        return P(yaw=90, up=0.01 * abs(math.sin(8 * math.pi * t)), phase=2 * FREQ * t, gait=4 * t)
    if LEGS:  # anda sobre las patas: el cuerpo apenas se mece
        return P(up=0.01 * abs(math.sin(4 * math.pi * t)), pitch=2 * math.sin(4 * math.pi * t), phase=2 * FREQ * t,
                 gait=t)
    hop = math.sin(2 * math.pi * t) * 0.6 if FLOAT else abs(math.sin(2 * math.pi * t))
    return P(fwd=0.0, up=(0.02 if HOVER or FLOAT else 0.05) * hop, pitch=6 + 3 * math.sin(4 * math.pi * t),
             amp=AMP * 1.4, phase=2 * FREQ * t)


def _held(start, end, **kw):
    """Poses con los apéndices vibrando entre start y end (para sostener un ataque)."""
    return [(f, P(phase=f / 6, **kw)) for f in range(start, end + 1, 2)]


ACTIONS = {
    "idle": lambda: cycle(idle_pose, 48),
    # Rodando, una clave por fotograma: entre dos claves gira 69° y con más saltaría por el camino corto.
    "walk": lambda: [(f + 1, walk_pose(f / ROLL_FRAMES)) for f in range(ROLL_FRAMES + 1)] if ROLL_WALK
    else cycle(walk_pose, 24),
    "fight_b": lambda: [  # se echa atrás y embiste
        (1, P()),
        (8, P(fwd=-0.06, up=0.02, pitch=-14, amp=AMP * 0.6, phase=0.25)),
        (12, P(fwd=0.16, up=0.0, pitch=18, amp=AMP * 1.6, phase=0.6)),
        (16, P(fwd=0.13, pitch=12, amp=AMP, phase=0.8)),
        (26, P()),
    ],
    "fight_d": lambda: [  # se recoge, se hincha y lanza el ataque, vibrando
        (1, P()),
        (9, P(up=-0.03, pitch=8, amp=AMP * 0.5, spread=-12, phase=0.2, scale=1 - (PUFF - 1) * 0.3)),
        (14, P(up=0.05, pitch=-10, spread=18, phase=0.5, scale=PUFF)),
        *_held(16, 26, up=0.05, pitch=-10, spread=18, amp=AMP * 0.6, scale=PUFF),
        (32, P()),
    ],
}


def apply_pose(frame, p):
    fwd, up = p["root"]
    offset = (FWD * fwd + UP * up) * HEIGHT
    if p["wing"] is None and WINGS:  # el reposo dura 48 fotogramas: "flap"[3] batidos en ese tiempo
        p = dict(p, wing=(frame - 1) * TWEAKS["flap"][3] / 48)
    turn = lquat_arm(PITCH, p["pitch"])
    # Gira sobre el centro del cuerpo y no sobre la cabeza del hueso raíz (rodar, cabecear).
    pivot = CENTER - turn @ CENTER if ROLL_WALK else Vector()
    for pb in PB:
        bone = pb.bone
        pb.rotation_mode = "QUATERNION"
        q = Quaternion()
        loc = Vector()
        scale = Vector((1, 1, 1))
        if bone in ROOTS:
            head = bone.head_local
            roll = turn @ head - head if ROLL_WALK else Vector()
            loc = bone.matrix_local.to_3x3().inverted() @ (offset + pivot + roll)
            q = lquat(bone, UP, p["yaw"]) @ lquat(bone, PITCH, p["pitch"])
            scale = Vector((1, 1, 1)) * p["scale"]
        elif bone in LEGS:
            q = Quaternion()
            if p["gait"] is not None:
                side = 1 if bone.head_local.dot(LEFT) > 0 else -1
                # En diagonal: la delantera izquierda con la trasera derecha, y al revés.
                off = 0.0 if (side > 0) == _canon(bone.name).endswith("Thigh") else 0.5
                ph = 2 * math.pi * (p["gait"] + off)
                q = lquat(bone, UP, -side * (0 if CRAB else 28) * math.cos(ph)) @ \
                    lquat(bone, FWD, side * (30 if CRAB else 24) * max(0.0, -math.sin(ph)))
        elif bone in WINGS:
            amp, lift, lag, beats = TWEAKS["flap"]
            follow, tip = TWEAKS.get("flap_follow", (0.06, 0.35))
            d = DEPTH[bone.name]
            back = lag if re.search(r"B\d*$", _canon(bone.name)) else 0.0
            ph = p["wing"] - back - follow * d
            a = amp * math.sin(2 * math.pi * ph) * (1 if d == 0 else tip) + (lift if d == 0 else 0)
            q = lquat(bone, AXIS[bone.name], a)
        elif bone.name in AXIS:
            d = DEPTH[bone.name]
            # La onda baja por la cadena: cada hueso va un poco por detrás del anterior.
            a = p["amp"] * math.sin(2 * math.pi * (p["phase"] - 0.12 * d)) + p["spread"] * (1 if d == 0 else 0.3)
            q = lquat(bone, AXIS[bone.name], a)
        if bone.name in HOLD:
            q = HOLD[bone.name] @ q
        pb.rotation_quaternion = q
        pb.location = loc
        pb.scale = scale
        pb.keyframe_insert("location", frame=frame, group=pb.name)
        pb.keyframe_insert("rotation_quaternion", frame=frame, group=pb.name)
        if PUFF != 1.0:
            pb.keyframe_insert("scale", frame=frame, group=pb.name)


def has_motion(action):
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for fc in bag.fcurves:
                    vals = [k.co[1] for k in fc.keyframe_points]
                    if vals and max(vals) - min(vals) > 1e-4:
                        return True
    return False


def _between(a, b, k):
    """Pose intermedia entre dos P (factor k); la fase del aleteo sigue saliendo del fotograma."""
    out = dict(a)
    for key in ("pitch", "yaw", "amp", "phase", "spread", "scale"):
        out[key] = a[key] + (b[key] - a[key]) * k
    out["root"] = tuple(x + (y - x) * k for x, y in zip(a["root"], b["root"]))
    return out


def densify(keys, step=2):
    """Con alas, una clave cada `step` fotogramas: entre claves lejanas el aleteo saltaría de fase."""
    out = []
    for (fa, a), (fb, b) in zip(keys, keys[1:]):
        for f in range(fa, fb, step):
            k = (f - fa) / (fb - fa)
            out.append((f, _between(a, b, k * k * (3 - 2 * k))))
    return out + [keys[-1]]


def build(name, keys):
    if WINGS and name not in ("idle", "walk"):
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
        apply_pose(frame, p)


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    force = "--force" in args
    wanted = [a for a in args if not a.startswith("--")] or list(ACTIONS)
    unknown = [a for a in wanted if a not in ACTIONS]
    if unknown:
        raise SystemExit(f"Acciones desconocidas: {', '.join(unknown)}. Válidas: {', '.join(ACTIONS)}")
    arm.animation_data_create()
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
        pb.scale = Vector((1, 1, 1))
    bpy.ops.wm.save_mainfile()
    print(f"Arriba {tuple(UP)}, delante {tuple(FWD)}. Raíces: {', '.join(_canon(b.name) for b in ROOTS)}; "
          f"{len(APPENDAGES)} huesos de apéndices")
    print("Animadas:", ", ".join(made) or "ninguna")
    if kept:
        print("Ya tenían movimiento (no se tocan; usa --force para rehacerlas):", ", ".join(kept))


main()

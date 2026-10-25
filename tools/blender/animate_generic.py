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
# Cuerpo: raíces y columna; lo que deforma pero no es cuerpo es un apéndice.
_BODY = re.compile(r"Hips|Waist|Spine\d*|Neck\d*|Head\d*|Origin|_rootJoint|pm\d+.*|mesh\d*")
BODY = [b for b in BONES if _BODY.fullmatch(_canon(b.name))]
APPENDAGES = [b for b in BONES if b not in BODY and not _SKIP.fullmatch(_canon(b.name))]


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

# Ajustes por especie: amp (grados del vaivén de apéndices), freq (vaivenes por ciclo de reposo), hover
# (flota y aletea rápido: insectos voladores), bob (sube y baja el cuerpo, en alturas).
TWEAKS = {
    "butterfree": {"hover": True, "amp": 28, "freq": 4},
    "venomoth": {"hover": True, "amp": 28, "freq": 4},
    "magikarp": {"amp": 16, "freq": 2},
    "tentacool": {"amp": 14},
    "tentacruel": {"amp": 12},
}.get(NAME, {})
AMP = TWEAKS.get("amp", 10)
FREQ = TWEAKS.get("freq", 1)
HOVER = TWEAKS.get("hover", False)


def lquat(bone, axis, deg):
    inv = bone.matrix_local.to_3x3().inverted()
    return Quaternion((inv @ axis).normalized(), math.radians(deg))


# ---------- poses: dict con root=(adelante, arriba) en alturas, pitch del cuerpo y fase/amp de apéndices ----------
def P(fwd=0.0, up=0.0, pitch=0.0, yaw=0.0, amp=None, phase=0.0, spread=0.0):
    return {"root": (fwd, up), "pitch": pitch, "yaw": yaw, "amp": AMP if amp is None else amp,
            "phase": phase, "spread": spread}


def cycle(fn, frames):
    return [(f + 1, fn(f / frames)) for f in range(0, frames + 1, 2)]


def idle_pose(t):
    s = math.sin(2 * math.pi * t)
    hover = 0.03 * math.sin(2 * math.pi * t) if HOVER else 0.0
    return P(up=0.012 * s + hover, pitch=1.5 * s, phase=FREQ * t)


def walk_pose(t):
    hop = abs(math.sin(2 * math.pi * t))
    return P(fwd=0.0, up=(0.02 if HOVER else 0.05) * hop, pitch=6 + 3 * math.sin(4 * math.pi * t),
             amp=AMP * 1.4, phase=2 * FREQ * t)


def _held(start, end, **kw):
    """Poses con los apéndices vibrando entre start y end (para sostener un ataque)."""
    return [(f, P(phase=f / 6, **kw)) for f in range(start, end + 1, 2)]


ACTIONS = {
    "idle": lambda: cycle(idle_pose, 48),
    "walk": lambda: cycle(walk_pose, 24),
    "fight_b": lambda: [  # se echa atrás y embiste
        (1, P()),
        (8, P(fwd=-0.06, up=0.02, pitch=-14, amp=AMP * 0.6, phase=0.25)),
        (12, P(fwd=0.16, up=0.0, pitch=18, amp=AMP * 1.6, phase=0.6)),
        (16, P(fwd=0.13, pitch=12, amp=AMP, phase=0.8)),
        (26, P()),
    ],
    "fight_d": lambda: [  # se recoge, se hincha y lanza el ataque, vibrando
        (1, P()),
        (9, P(up=-0.03, pitch=8, amp=AMP * 0.5, spread=-12, phase=0.2)),
        (14, P(up=0.05, pitch=-10, spread=18, phase=0.5)),
        *_held(16, 26, up=0.05, pitch=-10, spread=18, amp=AMP * 0.6),
        (32, P()),
    ],
}


def apply_pose(frame, p):
    fwd, up = p["root"]
    offset = (FWD * fwd + UP * up) * HEIGHT
    for pb in PB:
        bone = pb.bone
        pb.rotation_mode = "QUATERNION"
        q = Quaternion()
        loc = Vector()
        if bone in ROOTS:
            loc = bone.matrix_local.to_3x3().inverted() @ offset
            q = lquat(bone, PITCH, p["pitch"])
        elif bone.name in AXIS:
            d = DEPTH[bone.name]
            # La onda baja por la cadena: cada hueso va un poco por detrás del anterior.
            a = p["amp"] * math.sin(2 * math.pi * (p["phase"] - 0.12 * d)) + p["spread"] * (1 if d == 0 else 0.3)
            q = lquat(bone, AXIS[bone.name], a)
        pb.rotation_quaternion = q
        pb.location = loc
        pb.keyframe_insert("location", frame=frame, group=pb.name)
        pb.keyframe_insert("rotation_quaternion", frame=frame, group=pb.name)


def has_motion(action):
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for fc in bag.fcurves:
                    vals = [k.co[1] for k in fc.keyframe_points]
                    if vals and max(vals) - min(vals) > 1e-4:
                        return True
    return False


def build(name, keys):
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
    bpy.ops.wm.save_mainfile()
    print(f"Arriba {tuple(UP)}, delante {tuple(FWD)}. Raíces: {', '.join(_canon(b.name) for b in ROOTS)}; "
          f"{len(APPENDAGES)} huesos de apéndices")
    print("Animadas:", ", ".join(made) or "ninguna")
    if kept:
        print("Ya tenían movimiento (no se tocan; usa --force para rehacerlas):", ", ".join(kept))


main()

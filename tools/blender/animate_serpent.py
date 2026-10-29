"""Anima Pokémon sin patas con cuerpo de serpiente (Ekans, Arbok, Dratini, Dragonair).

    blender --background art/blender/ekans.blend --python tools/blender/animate_serpent.py [-- acciones] [--force]

El esqueleto son dos cadenas que salen del mismo punto: una hacia la cabeza (Spine1, Spine2... Neck, Head) y
otra hacia la cola (Tail1, Tail2...). En el reposo de estos rips la serpiente está de pie y recta como un palo,
así que la postura la pone la animación: tumba el cuerpo, enrosca la cola en el suelo y alza el cuello como
una cobra. Su altura en el juego es la de la cobra: ver COILED_HEIGHT en tools/build_data.py. Igual que animate_pokemon.py, no rehace las acciones que ya tienen movimiento salvo con
--force, y solo crea las variantes de ataque que usa la especie (las demás caen en fight_b / fight_d).
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


def _canon(name):
    """Nombre sin el número de nodo de algunos rips: "059 Tail1" y "Tail1_15" -> "Tail1"."""
    return re.sub(r"_\d+$", "", re.sub(r"^\d+ ", "", name))


B = {_canon(b.name): b for b in arm.data.bones}
CANON = {b.name: n for n, b in B.items()}


def _chain(start, pattern):
    """Desde `start`, baja por el hijo cuyo nombre cumple `pattern` mientras lo haya."""
    out = []
    bone = B.get(start)
    while bone:
        out.append(_canon(bone.name))
        bone = next((c for c in bone.children if re.fullmatch(pattern, _canon(c.name))), None)
    return out


# Delante: Spine1... (y Neck) hasta Head. Detrás: Tail1... En Ekans y Dratini la cola cuelga de Hips.
FRONT = _chain("Spine1", r"Spine\d+|Neck\d*|Head")
TAIL = _chain("Tail1", r"Tail\d+")
if not FRONT or FRONT[-1] != "Head" or len(TAIL) < 3:
    raise SystemExit("El esqueleto no es de serpiente: hace falta Spine1... Head y Tail1, Tail2, Tail3...")
JAW = next((n for n in ("LowerJaw", "Jaw", "LowerBeak") if n in B), None)
UPPER_JAW = "UpperJaw" if "UpperJaw" in B else None
ROOTS = [n for n, b in B.items() if b.parent is None]


def _pos(name):
    return B[name].head_local


def _snap(v):
    i = max(range(3), key=lambda k: abs(v[k]))
    axis = Vector((0, 0, 0))
    axis[i] = 1 if v[i] > 0 else -1
    return axis


# Ejes en el espacio de la armadura: arriba, el Z del mundo, y delante, el -Y del mundo (hacia donde
# mira el juego), que es hacia donde miran estos rips (los glTF importados pueden venir girados).
_to_arm = arm.matrix_world.inverted().to_3x3()
UP = _snap(_to_arm @ Vector((0, 0, 1)))
FWD = _snap(_to_arm @ Vector((0, -1, 0)))
LEFT = UP.cross(FWD)
BACK = -FWD
# PITCH inclina hacia delante (+) un hueso que apunta arriba; ROLL lo ladea.
PITCH, ROLL = LEFT, FWD
# En el reposo estos rips están de pie y rectos como un palo: la cabeza arriba y la cola hacia el suelo.
if (_pos("Head") - _pos(FRONT[0])).dot(UP) <= 0 or (_pos(TAIL[-1]) - _pos(TAIL[0])).dot(UP) >= 0:
    raise SystemExit("El reposo no es una serpiente de pie (cabeza arriba, cola abajo): este modo no le sirve.")
# Al tumbar la cadena con PITCH 90°, lo que en el reposo era BACK pasa a ser la vertical: girar alrededor de
# BACK es serpentear por el suelo.
GROUND_YAW = BACK
LENGTH = sum((B[n].head_local - B[n].parent.head_local).length for n in FRONT[1:] + TAIL[1:]
             if B[n].parent) or 1.0

# Cadena de la cabeza: el primer hueso se tumba hacia delante, los siguientes siguen por el suelo y RAISE
# vuelve a alzar el cuello hasta la vertical (cobra). NECK es lo que queda de pie hasta la cabeza.
_F = FRONT[:-1]
_lie = max(1, len(_F) // 3)
_nraise = max(1, min(3, len(_F) - _lie - 1))
LIE = _F[1:_lie]
RAISE = _F[_lie:_lie + _nraise]
NECK = _F[_lie + _nraise:]
# Cola: el primer hueso se tumba hacia atrás y el resto se enrosca de lado.
COIL = TAIL[1:]


def _seg(name):
    """Largo del hueso a lo largo del cuerpo: de su cabeza a la del siguiente de la cadena (el eje del hueso del
    rip no va a lo largo del cuerpo); la punta, como el anterior."""
    i = TAIL.index(name)
    if i + 1 < len(TAIL):
        return (_pos(TAIL[i + 1]) - _pos(name)).length
    return (_pos(name) - _pos(TAIL[i - 1])).length


# Parte de la vuelta que toma cada hueso de la cola: según su largo, para que la curva sea redonda (curvatura
# constante). Con el mismo ángulo en todos, los huesos cortos de la punta la cerraban en un cuadradito.
_coil_len = sum(_seg(n) for n in COIL) or 1.0
COIL_SHARE = {n: _seg(n) / _coil_len for n in COIL}


def lquat(name, rots):
    inv = B[name].matrix_local.to_3x3().inverted()
    q = Quaternion()
    for axis, deg in rots:
        q = q @ Quaternion((inv @ Vector(axis)).normalized(), math.radians(deg))
    return q


# ---------- poses (ángulos en grados; distancias en fracciones del largo del cuerpo) ----------
def body(lift=1.0, lean=0.0, sway=0.0, head=0.0, jaw=0.0, coil=230.0, wave=0.0, phase=0.0, tail_whip=0.0,
         root=(0, 0), hump=0.0, spiral=0.0, look=0.0, ripple=0.0, ripple_phase=0.0, tip=0.0):
    """Postura completa. lift: 1 = cuello vertical, menos = inclinado adelante, más = echado atrás;
    lean: grados que se inclina adelante la parte erguida; sway: grados que se ladea; head: cabeceo;
    coil: grados que se enrosca la cola; wave/phase: serpenteo por el suelo (grados por hueso, fase 0-1);
    tail_whip: grados extra en la cola, más en la punta; hump: joroba que recorre el cuerpo de la cola a la
    cabeza (grados por hueso, oruga); spiral: grados que sube cada hueso de la cola (enroscada en espiral);
    look: grados que gira la cabeza a su izquierda (mira alrededor; el cuello la acompaña un poco);
    ripple/ripple_phase: vaivén que sube por el cuello con retraso, como un látigo lento (grados, fase 0-1);
    tip: grados que se curva la punta de la cola (los últimos huesos)."""
    p = {_F[0]: [(PITCH, 90)], TAIL[0]: [(PITCH, 90)]}
    ground = LIE + COIL
    for i, n in enumerate(ground):
        s = i / max(1, len(ground) - 1)
        a = wave * math.sin(2 * math.pi * (phase - 1.2 * s))
        if n in COIL:
            k = COIL.index(n) / max(1, len(COIL) - 1)
            a += coil * COIL_SHARE[n] + tail_whip * (0.3 + k) / len(COIL)
        p[n] = [(GROUND_YAW, a)]
        if hump:
            p[n].append((PITCH, hump * math.sin(2 * math.pi * (phase + 1.0 * s))))
        if spiral and n in COIL:
            p[n].append((PITCH, -spiral * COIL_SHARE[n] * len(COIL)))
        if tip and n in COIL[-3:]:
            p[n][0] = (GROUND_YAW, p[n][0][1] + tip / 3)
    for n in RAISE:
        p[n] = [(PITCH, -90 * lift / len(RAISE))]
    for j, n in enumerate(NECK):
        r = ripple * math.sin(2 * math.pi * (ripple_phase - 0.12 * j))
        p[n] = [(PITCH, lean / max(1, len(NECK))), (ROLL, (sway + r) / max(1, len(NECK))),
                (UP, look * 0.35 / max(1, len(NECK)))]
    # La cabeza compensa la inclinación para seguir mirando al frente, más el cabeceo; y la mayor parte del giro.
    head_r = ripple * math.sin(2 * math.pi * (ripple_phase - 0.12 * len(NECK)))
    p["Head"] = [(PITCH, 90 * (lift - 1) - lean * 0.6 + head), (ROLL, -(sway + head_r) * 0.5), (UP, look * 0.65)]
    if JAW:
        p[JAW] = [(PITCH, jaw)]
    if UPPER_JAW:
        p[UPPER_JAW] = [(PITCH, -jaw * 0.4)]
    p["root"] = root
    return p


# Ajustes por especie. coiled: en reposo, enroscada en espiral con la cabeza baja (Ekans); crawl: oruga que
# avanza encogiendo y estirando el cuerpo en vez de serpentear (Caterpie, Weedle).
TWEAKS = {
    "ekans": {"coiled": True},
    "caterpie": {"crawl": True},
    "weedle": {"crawl": True},
}.get(NAME, {})
# Ekans: una vuelta y poco, que con su largo da un rollo redondo sin que el cuerpo se atraviese.
REST = dict(lift=0.75, lean=-10, coil=400, spiral=5) if TWEAKS.get("coiled") else {}


def BASE():
    return body(**REST)


def cycle(fn, frames):
    return [(f + 1, fn(f / frames)) for f in range(0, frames + 1, 2)]


def idle_pose(t):
    """Cuatro segundos: respira dos veces, se mece con el vaivén subiendo por el cuello, mira a un lado y al otro
    (y se queda un momento mirando) y la punta de la cola se curva despacio."""
    s = math.sin(4 * math.pi * t)
    look = 18 * math.sin(2 * math.pi * t) + 5 * math.sin(6 * math.pi * t)
    return body(**{**REST, "lift": REST.get("lift", 1.0) + 0.05 * s},
                sway=6 * math.sin(2 * math.pi * t + 0.8), head=-3 * s - 2 * math.sin(6 * math.pi * t + 1),
                wave=3, phase=t, look=look, ripple=6, ripple_phase=2 * t, tip=25 * math.sin(2 * math.pi * t - 1.0))


def walk_pose(t):
    if TWEAKS.get("crawl"):
        # Estira el frente y lo vuelve a recoger mientras una joroba sube de la cola a la cabeza.
        s = math.sin(2 * math.pi * t)
        return body(lift=1.0 - 0.2 * s, lean=12 + 18 * s, head=-14 * s, coil=150, hump=35, phase=t,
                    sway=3 * math.sin(2 * math.pi * t + 0.5), root=(0.05 * s, 0.02 * max(0.0, -s)))
    # Serpentea: el cuerpo se estira (poca vuelta en la cola) y una onda grande lo recorre hacia atrás; la cabeza
    # se mantiene al frente girando contra la onda del cuello.
    w = math.sin(2 * math.pi * t)
    return body(lean=10, sway=3 * w, wave=24, phase=t, coil=50, look=-10 * math.sin(2 * math.pi * t - 0.4),
                ripple=4, ripple_phase=t, head=-2 * math.sin(4 * math.pi * t))


def strike(bite):
    """Se echa atrás con el cuello en S y se lanza adelante; con mordisco abre la boca."""
    return [
        (1, BASE()),
        (8, body(lift=1.25, lean=-12, head=8, jaw=22 if bite else 6, coil=250, root=(-0.05, 0))),
        (12, body(lift=0.6, lean=24, head=10, jaw=32 if bite else 4, coil=200, root=(0.07, 0))),
        (15, body(lift=0.65, lean=20, head=6, jaw=0, coil=205, root=(0.06, 0))),
        (26, BASE()),
    ]


def special(jaw_open, lean=14, shake=0.0):
    """Se echa atrás tomando aire y lanza hacia delante con la boca abierta, sosteniendo el ataque."""
    keys = [
        (1, BASE()),
        (9, body(lift=1.2, lean=-14, head=-6, jaw=jaw_open * 0.3, root=(-0.03, 0))),
        (14, body(lift=0.9, lean=lean, head=-4, jaw=jaw_open, root=(0.03, 0))),
    ]
    for f in range(17, 27, 3):
        keys.append((f, body(lift=0.9, lean=lean, head=-4, jaw=jaw_open * (0.85 + 0.15 * (f % 2)),
                             sway=shake * (1 if f % 2 else -1), root=(0.03, 0))))
    keys.append((32, BASE()))
    return keys


ACTIONS = {
    "idle": lambda: cycle(idle_pose, 96),
    "walk": lambda: cycle(walk_pose, 24),
    "fight_b": lambda: strike(bite=False),
    "fight_b_body": lambda: strike(bite=False),
    "fight_b_bite": lambda: strike(bite=True),
    "fight_b_tail": lambda: [  # gira el cuerpo y barre con la cola como un látigo
        (1, BASE()),
        (8, body(sway=-8, tail_whip=-70, root=(-0.02, 0))),
        (13, body(sway=10, tail_whip=120, coil=150, root=(0.03, 0))),
        (17, body(sway=6, tail_whip=60, root=(0.02, 0))),
        (28, BASE()),
    ],
    "fight_d": lambda: special(jaw_open=12),
    "fight_d_breath": lambda: special(jaw_open=32),
    "fight_d_sound": lambda: special(jaw_open=40, lean=-6, shake=4),  # se yergue y sisea con la boca muy abierta
    "fight_d_boost": lambda: [  # se enrosca más, se alza y se mece
        (1, BASE()),
        (8, body(lift=0.8, lean=10, coil=300, root=(-0.02, 0))),
        (16, body(lift=1.15, lean=-8, sway=8, coil=300, head=-6)),
        (24, body(lift=1.15, lean=-8, sway=-8, coil=300, head=-6)),
        (34, BASE()),
    ],
    # Los demás estados los hace animate_status.py desde el idle; estos dos necesitan bajar el cuello al suelo.
    "status_sleep": lambda: cycle(sleep_pose, 72),
    "ko": lambda: [  # se yergue con un quejido y el cuello se desploma hacia delante hasta el suelo
        (1, BASE()),
        (6, body(**{**REST, "lift": 1.15, "lean": -10, "head": -15, "jaw": 20})),
        (18, body(**{**REST, "lift": 0.05, "lean": 10, "head": 12, "jaw": 12})),
        (22, body(**{**REST, "lift": 0.14, "lean": 6, "head": 8, "jaw": 10})),
        (26, body(**{**REST, "lift": 0.0, "lean": 4, "head": 6, "jaw": 8, "coil": REST.get("coil", 230) * 0.8})),
        (37, body(**{**REST, "lift": 0.0, "lean": 4, "head": 6, "jaw": 8, "coil": REST.get("coil", 230) * 0.8})),
    ],
}


def sleep_pose(t):
    """Enroscado con la cabeza apoyada casi en el suelo y respirando despacio."""
    b = math.sin(2 * math.pi * 2 * t)
    return body(**{**REST, "lift": 0.22 + 0.03 * b, "lean": 0, "head": 14 - 2 * b,
                   "coil": REST.get("coil", 230) + 60, "sway": 2 * math.sin(2 * math.pi * t)})


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
        if anim and variant:
            found.add(f"{anim.group(1)}_{variant.group(1)}")
    return found & set(ACTIONS)


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
    act.use_cyclic = name in ("idle", "walk") or name.startswith("status_")
    arm.animation_data.action = act
    for frame, p in keys:
        fwd, up = p.get("root", (0, 0))
        offset = (FWD * fwd + UP * up) * LENGTH
        for pb in PB:
            name_ = CANON.get(pb.name, "")
            pb.rotation_mode = "QUATERNION"
            rots = p.get(name_)
            pb.rotation_quaternion = lquat(name_, rots) if rots else Quaternion()
            pb.location = B[name_].matrix_local.to_3x3().inverted() @ offset if name_ in ROOTS else Vector()
            pb.keyframe_insert("location", frame=frame, group=pb.name)
            pb.keyframe_insert("rotation_quaternion", frame=frame, group=pb.name)


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    force = "--force" in args
    wanted = [a for a in args if not a.startswith("--")]
    unknown = [a for a in wanted if a not in ACTIONS]
    if unknown:
        raise SystemExit(f"Acciones desconocidas: {', '.join(unknown)}. Válidas: {', '.join(ACTIONS)}")
    if not wanted:
        wanted = [a for a in ACTIONS if not a.startswith("fight_") or a in ("fight_b", "fight_d")
                  or a in learnset_actions(NAME)]
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
    print(f"Arriba {tuple(UP)}, delante {tuple(FWD)}. Cuerpo: {len(FRONT)} huesos hasta la cabeza, "
          f"{len(TAIL)} de cola; mandíbula: {JAW or 'no'}")
    print("Animadas:", ", ".join(made) or "ninguna")
    if kept:
        print("Ya tenían movimiento (no se tocan; usa --force para rehacerlas):", ", ".join(kept))


main()

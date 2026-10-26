"""Anima los estados alterados y el debilitado de cualquier Pokémon, sea cual sea su esqueleto.

    blender --background art/blender/pikachu.blend --python tools/blender/animate_status.py [-- acciones] [--force]
    blender --background --python tools/blender/animate_status.py -- --import mewtwo   # crea el .blend sin tocar sus clips

Cada acción sale del reposo (idle) de la propia especie, que ya está hecho a la medida de su esqueleto (bípedo,
cuadrúpedo, serpiente, genérico o los clips de los juegos de Mewtwo y Dragonite): se muestrea a otro ritmo y se le
suma un movimiento del cuerpo entero desde los huesos raíz (girando sobre el suelo, no sobre la cadera) y, si hay
hueso Head, de la cabeza. Como en los juegos:

| Acción | Qué hace |
|---|---|
| status_sleep | se encorva con la cabeza caída y ladeada y respira lento (el reposo, a un tercio de velocidad) |
| status_paralysis | el reposo va a tirones y cada poco le dan calambres: sacudidas rápidas y se encoge |
| status_poison | encorvado y mareado: se balancea pesado, respira hondo y de vez en cuando le da un escalofrío |
| status_confusion | da vueltas sobre sí mismo como mareado (el cuerpo describe un círculo) y la cabeza va a su aire |
| status_burn | encogido por el ardor: le dan punzadas de dolor y se sacude como para apagarse (el juego le pone las llamas y el tinte rojo) |
| status_freeze | rígido en la primera pose del reposo, con un temblor cada poco (el juego le pone el hielo encima) |
| hit | encaja el golpe: retrocede echando la cabeza atrás, se encoge y se recupera con un pequeño rebote |
| ko | se echa atrás con un quejido, cae de lado (de bruces si es más ancho que alto), rebota y queda tendido |

Los que flotan (aves, fantasmas) bajan al suelo al dormirse y al caer. No rehace las acciones que ya tienen
movimiento salvo con --force; las que el .tres asigna en su anim_map (el ko de Mewtwo) no se crean.
Después: tools/blender/export_animations.py.
"""
import math
import re
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector

PROJECT = Path(__file__).resolve().parents[2]
# Acción -> (fotogramas, bucle).
ACTIONS = {
    "status_sleep": (73, True),
    "status_paralysis": (49, True),
    "status_poison": (61, True),
    "status_confusion": (49, True),
    "status_freeze": (49, True),
    "status_burn": (49, True),
    "ko": (37, False),
    "hit": (16, False),
}


def _args():
    return sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def import_raw(name):
    """.blend con el .glb tal cual, sin cambiar el reposo ni quitar clips (Mewtwo y Dragonite traen los de los
    juegos y setup_animations.py los borraría al hornear la pose)."""
    out = PROJECT / "art/blender" / f"{name}.blend"
    if out.exists():
        bpy.ops.wm.open_mainfile(filepath=str(out))
        return
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(PROJECT / "assets/models/pokemon" / f"{name}.glb"),
                              guess_original_bind_pose=False)
    for obj in [o for o in bpy.data.objects if o.name.startswith("Icosphere") and o.type == "MESH"]:
        bpy.data.objects.remove(obj)
    for a in bpy.data.actions:
        a.use_fake_user = True
    bpy.ops.wm.save_as_mainfile(filepath=str(out))
    print(f"Importado sin cambios: {out}")


if "--import" in _args():
    import_raw(_args()[_args().index("--import") + 1])

NAME = Path(bpy.data.filepath).stem
arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
PB = arm.pose.bones
scene = bpy.context.scene


def _canon(name):
    """"059 Head", "Head_16" y "Bip001 Head" -> "Head"."""
    return re.sub(r"_\d+$", "", re.sub(r"^(\d+ |Bip\d+ )", "", name))


def _snap(v):
    i = max(range(3), key=lambda k: abs(v[k]))
    axis = Vector((0, 0, 0))
    axis[i] = 1 if v[i] > 0 else -1
    return axis


# Ejes en el espacio de la armadura: arriba, el Z del mundo; delante, el -Y del mundo (hacia donde mira el juego).
_to_arm = arm.matrix_world.inverted().to_3x3()
UP = _snap(_to_arm @ Vector((0, 0, 1)))
FWD = _snap(_to_arm @ Vector((0, -1, 0)))
LEFT = UP.cross(FWD)
ROOTS = [pb for pb in PB if pb.parent is None]
HEAD = next((pb for pb in PB if _canon(pb.name) == "Head" and pb.parent is not None), None)


# ---------- acciones ----------
def has_motion(action):
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for fc in bag.fcurves:
                    vals = [k.co[1] for k in fc.keyframe_points]
                    if vals and max(vals) - min(vals) > 1e-4:
                        return True
    return False


def anim_map():
    tres = PROJECT / "data/pokemon" / f"{NAME}.tres"
    if not tres.exists():
        return {}
    m = re.search(r"^anim_map = \{(.*?)^\}", tres.read_text(encoding="utf-8"), re.MULTILINE | re.DOTALL)
    return dict(re.findall(r'"([^"]+)": "([^"]+)"', m.group(1))) if m else {}


ANIM_MAP = anim_map()


def find_action(key):
    """Como Unit._find_clip del juego: primero la que termina en la clave, luego la que la contiene."""
    want = ANIM_MAP.get(key, key)
    # Godot quita el sufijo "_loop" al importar (marca el clip como bucle) y el anim_map va sin él.
    acts = [(a, re.sub(r"_loop$", "", a.name)) for a in bpy.data.actions if has_motion(a)]
    return next((a for a, n in acts if n.endswith(want)), None) or \
        next((a for a, n in acts if want in n and want + "_" not in n), None)


def assign(act):
    ad = arm.animation_data
    ad.action = act
    if getattr(ad, "action_slot", 1) is None and len(act.slots):
        ad.action_slot = act.slots[0]


arm.animation_data_create()
IDLE = find_action("idle")
if IDLE is None:
    raise SystemExit(f"{NAME}: no tiene un idle animado del que partir (anímalo antes).")
I0, I1 = int(IDLE.frame_range[0]), int(IDLE.frame_range[1])
ILEN = max(I1 - I0, 1)


def sample(phase):
    """Pose del idle en la fase (ciclos; se envuelve): matriz base de cada hueso."""
    x = I0 + (phase % 1.0) * ILEN
    scene.frame_set(int(x), subframe=x - int(x))
    return {pb.name: pb.matrix_basis.copy() for pb in PB}


def _verts_now():
    dg = bpy.context.evaluated_depsgraph_get()
    to_arm = arm.matrix_world.inverted()
    pts = []
    for o in (o for o in scene.objects if o.type == "MESH" and o.find_armature() == arm):
        ev = o.evaluated_get(dg)
        mesh = ev.to_mesh()
        m = to_arm @ ev.matrix_world
        step = max(1, len(mesh.vertices) // 1500)
        pts += [m @ mesh.vertices[i].co for i in range(0, len(mesh.vertices), step)]
        ev.to_mesh_clear()
    return pts


# Medidas del cuerpo en la primera pose del idle (en la de reposo, Mewtwo está tumbado y a otra escala).
assign(IDLE)
sample(0.0)
_pts = _verts_now()
if not _pts:
    raise SystemExit(f"{NAME}: no hay malla unida al esqueleto.")


def _span(axis):
    vals = [p.dot(axis) for p in _pts]
    return min(vals), max(vals)


(_ulo, _uhi), (_llo, _lhi), (_flo, _fhi) = _span(UP), _span(LEFT), _span(FWD)
HEIGHT = max(_uhi - _ulo, 1e-4)
HALF_W = (_lhi - _llo) / 2
HALF_D = (_fhi - _flo) / 2
# Más anchos que altos (alas abiertas, cangrejos): de lado quedarían de canto, así que caen de bruces.
WIDE = 2 * HALF_W > 1.3 * HEIGHT
GROUND = LEFT * ((_llo + _lhi) / 2) + FWD * ((_flo + _fhi) / 2) + UP * _ulo


def _rest_ground():
    """Suelo de la malla sin deformar: si el idle la levanta (vuela, flota), cuánto sube."""
    pts = []
    for o in (o for o in scene.objects if o.type == "MESH" and o.find_armature() == arm):
        m = arm.matrix_world.inverted() @ o.matrix_world
        vs = o.data.vertices
        pts += [(m @ vs[i].co).dot(UP) for i in range(0, len(vs), max(1, len(vs) // 1500))]
    lo, hi = min(pts), max(pts)
    # Solo si la malla en reposo es del mismo tamaño (en los rips sin hornear el reposo no sirve de referencia).
    return lo if 0.7 < (hi - lo) / HEIGHT < 1.3 else _ulo


HOVER = max(0.0, _ulo - _rest_ground()) / HEIGHT
# Hacia qué lado cae al debilitarse: cada especie siempre al mismo, pero no todas al mismo.
SIDE = 1 if sum(map(ord, NAME)) % 2 else -1


def body(pitch=0.0, roll=0.0, yaw=0.0, up_scale=1.0, side_scale=1.0, lift=0.0, left=0.0, fwd=0.0, pivot=None):
    """Transformación del cuerpo entero (espacio de la armadura). pitch + se inclina adelante, roll + se ladea
    hacia su derecha, yaw + gira a su izquierda; escalas y desplazamientos (en alturas) sobre `pivot` (por
    defecto, el centro de la base)."""
    pivot = GROUND if pivot is None else pivot
    rot = (Matrix.Rotation(math.radians(yaw), 4, UP) @ Matrix.Rotation(math.radians(roll), 4, FWD)
           @ Matrix.Rotation(math.radians(pitch), 4, LEFT))
    basis = Matrix((LEFT, FWD, UP)).transposed().to_4x4()  # columnas: los ejes del Pokémon
    scale = basis @ Matrix.Diagonal((side_scale, side_scale, up_scale, 1)) @ basis.transposed()
    move = (LEFT * left + FWD * fwd + UP * lift) * HEIGHT
    return Matrix.Translation(pivot + move) @ rot @ scale @ Matrix.Translation(-pivot)


def head_rot(pitch=0.0, roll=0.0, yaw=0.0):
    """Giro de la cabeza en el espacio de la armadura (pitch + mira abajo)."""
    return (Quaternion(UP, math.radians(yaw)) @ Quaternion(FWD, math.radians(roll))
            @ Quaternion(LEFT, math.radians(pitch)))


def pose(phase, t=None, head=None, **kw):
    return {"phase": phase, "body": body(**kw), "head": head}


# ---------- poses por fotograma: f va de 0 a n-1; t = f / (n-1) es la vuelta del bucle ----------
def _cycles(n, speed):
    """Vueltas enteras del idle que caben en n fotogramas a esa velocidad (para que el bucle cierre)."""
    return max(1, round((n - 1) * speed / ILEN))


def _alt(f):
    return 1 if f % 2 else -1


def sleep(f, n):
    t = f / (n - 1)
    b = math.sin(2 * math.pi * 2 * t)  # dos respiraciones por vuelta
    return pose(_cycles(n, 0.33) * t, pitch=13 + 1.5 * b, up_scale=0.965 + 0.02 * b, side_scale=1.015 + 0.012 * b,
                lift=-HOVER * 0.85, head=head_rot(pitch=35 + 3 * b, roll=10))


SPASMS = [(9, 15), (31, 36)]  # fotogramas con calambre


def paralysis(f, n):
    t = f / (n - 1)
    step = (f // 4) * 4 / (n - 1)  # el idle avanza a tirones: se queda 4 fotogramas en cada pose
    spasm = next((min(f - a, b - f) for a, b in SPASMS if a <= f <= b), -1)
    j = _alt(f) * min(1.0, (spasm + 1) / 2) if spasm >= 0 else 0.0
    return pose(_cycles(n, 0.5) * step, pitch=5 - 3 * j, roll=3 + 7 * j, yaw=4 * j,
                up_scale=0.96 if spasm >= 0 else 0.985, left=0.006 * j,
                head=head_rot(pitch=6, roll=10 * j + 4 * math.sin(2 * math.pi * t)))


def poison(f, n):
    t = f / (n - 1)
    s = math.sin(2 * math.pi * t)
    shiver = _alt(f) if 41 <= f <= 47 else 0
    return pose(_cycles(n, 0.6) * t, pitch=10 + 2 * math.sin(4 * math.pi * t), roll=4 * s + 3 * shiver,
                up_scale=0.97 + 0.015 * math.sin(4 * math.pi * t),
                head=head_rot(pitch=18 + 4 * math.sin(2 * math.pi * t + 1), roll=-6 * s))


def confusion(f, n):
    a = 2 * math.pi * f / (n - 1)
    return pose(_cycles(n, 1.0) * f / (n - 1), roll=9 * math.sin(a), pitch=6 * math.cos(a), yaw=18 * math.sin(a + 0.6),
                left=0.03 * math.sin(a),
                head=head_rot(roll=-16 * math.sin(a + 0.9), yaw=12 * math.cos(a), pitch=-4))


WINCES = [(4, 11), (28, 35)]  # punzadas de dolor
SHAKE = (14, 21)  # se sacude


def burn(f, n):
    t = f / (n - 1)
    k = 0.0
    for a, b in WINCES:
        if a <= f <= b:
            k = math.sin(math.pi * (f - a) / (b - a))
    shake = _alt(f) * math.sin(math.pi * (f - SHAKE[0]) / (SHAKE[1] - SHAKE[0])) if SHAKE[0] <= f <= SHAKE[1] else 0.0
    return pose(_cycles(n, 0.8) * t, pitch=6 - 10 * k, roll=2 * math.sin(2 * math.pi * t) + 3 * shake,
                yaw=7 * shake, up_scale=0.98 - 0.04 * k, fwd=-0.02 * k,
                head=head_rot(pitch=8 - 22 * k, roll=-8 * k * SIDE + 6 * shake))


def freeze(f, n):
    shiver = _alt(f) if 20 <= f <= 27 else 0
    return pose(0.0, roll=1.2 * shiver, left=0.004 * shiver)


def ko(f, n):
    pivot = GROUND + FWD * HALF_D if WIDE else GROUND - LEFT * SIDE * HALF_W  # el borde hacia el que cae

    def fall(deg, pitch):  # de lado (roll) o, si es ancho, de bruces (todo en pitch)
        return {"roll": 0.0, "pitch": pitch + deg * 0.8} if WIDE else {"roll": deg * SIDE, "pitch": pitch}
    if f <= 5:  # se echa atrás con un quejido
        k = math.sin(0.5 * math.pi * f / 5)
        return pose(f / ILEN, pitch=-8 * k, lift=0.02 * k, head=head_rot(pitch=-20 * k))
    if f <= 19:  # cae de lado, cada vez más deprisa, y baja al suelo si flotaba
        k = ((f - 5) / 14) ** 2
        return pose(5 / ILEN, **fall(88 * k, -8 + 12 * k), lift=0.02 * (1 - k) - HOVER * k, pivot=pivot,
                    head=head_rot(pitch=-20 + 50 * k))
    bounce = 8 * math.sin(math.pi * (f - 19) / 6) if f <= 25 else 0.0  # rebota un poco y queda tendido
    return pose(5 / ILEN, **fall(88 - bounce, 4), lift=-HOVER, pivot=pivot,
                head=head_rot(pitch=30 + 5 * min(1.0, (f - 19) / 10)))


def hit(f, n):
    """El golpe llega en el fotograma 2; luego vuelve a su sitio oscilando cada vez menos."""
    if f <= 2:
        k = f / 2
    else:
        x = (f - 2) / (n - 3)
        k = math.cos(1.5 * math.pi * x) * (1 - x) ** 2  # pasa un poco al otro lado y se asienta
    return pose(f / ILEN, pitch=-12 * k, roll=4 * SIDE * k, fwd=-0.05 * k, up_scale=1 - 0.06 * max(k, 0.0),
                head=head_rot(pitch=-18 * k, roll=-6 * SIDE * k))


POSES = {"status_sleep": sleep, "status_paralysis": paralysis, "status_poison": poison,
         "status_confusion": confusion, "status_freeze": freeze, "status_burn": burn, "ko": ko, "hit": hit}


def build(name):
    n, loop = ACTIONS[name]
    keys = [POSES[name](f, n) for f in range(n)]
    cache = {}
    assign(IDLE)
    for k in keys:
        ph = round(k["phase"] % 1.0, 4)
        if ph not in cache:
            cache[ph] = sample(ph)
    old = bpy.data.actions.get(name)
    if old:
        bpy.data.actions.remove(old)
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    act.use_frame_range = True
    act.frame_start, act.frame_end = 1, n
    act.use_cyclic = loop
    assign(act)
    for f, k in enumerate(keys, start=1):
        base = cache[round(k["phase"] % 1.0, 4)]
        for pb in PB:
            m = base[pb.name]
            rest = pb.bone.matrix_local
            if pb.parent is None:  # la raíz lleva el movimiento del cuerpo entero
                m = rest.inverted() @ k["body"] @ rest @ m
            elif pb == HEAD and k["head"] is not None:
                q = Quaternion((rest.to_3x3().inverted() @ k["head"].axis).normalized(), k["head"].angle)
                m = m @ q.to_matrix().to_4x4()
            pb.rotation_mode = "QUATERNION"
            pb.matrix_basis = m
            pb.keyframe_insert("location", frame=f, group=pb.name)
            pb.keyframe_insert("rotation_quaternion", frame=f, group=pb.name)
            pb.keyframe_insert("scale", frame=f, group=pb.name)


def main():
    args = [a for a in _args() if a != "--import" and not (a == NAME and "--import" in _args())]
    force = "--force" in args
    wanted = [a for a in args if not a.startswith("--")] or list(ACTIONS)
    unknown = [a for a in wanted if a not in ACTIONS]
    if unknown:
        raise SystemExit(f"Acciones desconocidas: {', '.join(unknown)}. Válidas: {', '.join(ACTIONS)}")
    previous = arm.animation_data.action
    made, kept = [], []
    for name in wanted:
        existing = find_action(name)
        if name in ANIM_MAP or (existing and not force):
            kept.append(f"{name} ({existing.name if existing else ANIM_MAP[name]})")
            continue
        build(name)
        made.append(name)
    assign(previous or IDLE)
    scene.frame_set(1)
    bpy.ops.wm.save_mainfile()
    print(f"{NAME}: arriba {tuple(UP)}, delante {tuple(FWD)}, cabeza {HEAD.name if HEAD else 'no'}, "
          f"base {IDLE.name}, flota {HOVER:.2f}")
    print("Animadas:", ", ".join(made) or "ninguna")
    if kept:
        print("Ya las tenía (no se tocan; usa --force para rehacerlas):", ", ".join(kept))


main()

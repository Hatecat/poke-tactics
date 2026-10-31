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
| ko | según el cuerpo (`KO_BODY`): los bípedos se echan atrás, se les doblan las rodillas y caen de lado; los cuadrúpedos doblan las patas delanteras y luego las traseras y se tumban de lado; los que vuelan con alas dejan de aletear, bajan nivelando el cuerpo y se posan de barriga; los que levitan se hunden balanceándose; los demás caen de lado; ver también `KO_STYLE` |

Los que flotan (aves, fantasmas) bajan al suelo al dormirse y al caer. No rehace las acciones que ya tienen
movimiento salvo con --force; las que el .tres asigna en su anim_map (el ko de Mewtwo) no se crean.
Después: tools/blender/export_animations.py.
"""
import math
import os
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
    "ko": (42, False),
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
    # Lo que el idle no anima (la escala, en los idles de animate_pokemon) vuelve al reposo: si no, se quedaba lo
    # último que dejó otra acción (el estirón del sueño en la cadera) y cada pasada lo volvía a grabar encima.
    for pb in PB:
        pb.matrix_basis = Matrix.Identity(4)
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


def pose(phase, t=None, head=None, bones=None, **kw):
    """`bones`: giros extra de otros huesos ({nombre: head_rot(...)}), como el de la cabeza."""
    return {"phase": phase, "body": body(**kw), "head": head, "bones": bones or {}}


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


# Cómo caen los que no caen de lado ni de bruces: back (de espaldas, panza arriba: Snorlax), flop (se tumba sobre la barriga, apenas ladeado: Dewgong de bruces
# quedaba de pie sobre el morro y de lado, con una aleta al cielo), slump (se desploma a medias: las pinzas de
# Kingler lo ponían vertical), melt (se derrite y se desparrama: los lodos volcaban enseñando la base) y sink (se
# hunde en su madriguera: Diglett volcaba con ella).
KO_STYLE = {"dewgong": "flop", "kingler": "slump", "grimer": "melt", "muk": "melt",
            "diglett": "sink", "dugtrio": "sink", "snorlax": "back"}.get(NAME, "fall")


def ko_fall(f, n):
    """Sin patas que doblar (peces, bolas, conchas) o con KO_STYLE: cae de lado (de bruces si es más ancho que
    alto), rebota y queda tendido; o se aplasta (melt, sink)."""
    wide = WIDE and KO_STYLE not in ("flop", "back")
    pivot = GROUND + FWD * HALF_D if wide else GROUND - LEFT * SIDE * HALF_W  # el borde hacia el que cae
    if KO_STYLE == "back":
        pivot = GROUND - FWD * HALF_D * 0.6
    tilt = {"slump": 0.4, "flop": 0.25}.get(KO_STYLE, 1.0)

    def fall(deg, pitch):  # de lado (roll) o, si es ancho, de bruces (todo en pitch); back: de espaldas
        deg *= tilt
        if KO_STYLE == "back":
            return {"roll": 4 * SIDE, "pitch": pitch - 16 - deg * 0.85}
        return {"roll": 0.0, "pitch": pitch + deg * 0.8} if wide else {"roll": deg * SIDE, "pitch": pitch}
    if f <= 5:  # se echa atrás con un quejido
        k = math.sin(0.5 * math.pi * f / 5)
        return pose(f / ILEN, pitch=-8 * k, lift=0.02 * k, head=head_rot(pitch=-20 * k))
    if KO_STYLE in ("melt", "sink"):  # se aplasta contra el suelo (y se desparrama si es lodo) y tiembla al quedar
        x = min(1.0, (f - 5) / 14)
        k = 1 - (1 - x) ** 2
        wobble = 0.06 * math.sin(math.pi * (f - 19) / 3) * (1 - (f - 19) / 18) if 19 < f < 37 else 0.0
        squash, spread = (0.38, 1.35) if KO_STYLE == "melt" else (0.45, 1.0)
        return pose(5 / ILEN, pitch=-8 * (1 - k) + (5 if KO_STYLE == "melt" else -6) * k,
                    up_scale=1 - (1 - squash) * k + wobble, side_scale=1 + (spread - 1) * k - wobble * 0.5,
                    lift=-HOVER * k, head=head_rot(pitch=-20 + 45 * k))
    if f <= 19:  # cae de lado, cada vez más deprisa, y baja al suelo si flotaba
        k = ((f - 5) / 14) ** 2
        return pose(5 / ILEN, **fall(88 * k, -8 + 12 * k), lift=0.02 * (1 - k) - HOVER * k, pivot=pivot,
                    head=head_rot(pitch=-20 + 50 * k))
    bounce = 8 * math.sin(math.pi * (f - 19) / 6) if f <= 25 else 0.0  # rebota un poco y queda tendido
    return pose(5 / ILEN, **fall(88 - bounce, 4), lift=-HOVER, pivot=pivot,
                head=head_rot(pitch=30 + 5 * min(1.0, (f - 19) / 10)))


# ---------- debilitado según el cuerpo ----------
# Las patas se doblan con IK (las de cada lado son una cadena muslo-pierna o brazo-antebrazo): mientras las
# rodillas ceden, los pies se quedan clavados donde estaban; al caer, las patas dobladas van con el cuerpo.
_BIP = {"Calf": "Leg", "UpperArm": "Arm", "Forearm": "ForeArm"}


def _limb(name):
    """"059 LLeg", "LLeg_12" y "Bip001 L Calf" -> "LLeg"."""
    n = re.sub(r"_\d+$", "", re.sub(r"^\d+ ", "", name))
    m = re.fullmatch(r"Bip\d+ ([LR]) (\w+)", n)
    return m.group(1) + _BIP.get(m.group(2), m.group(2)) if m else n


LB = {_limb(pb.name): pb for pb in PB}


def _chain(*names):
    """[muslo, pierna, pie] si cada hueso cuelga del anterior. La cabeza del pie (el tobillo) es lo que se lleva al
    objetivo; la punta de los huesos de los rips no sirve."""
    bones = [LB.get(n) for n in names]
    if not all(bones) or bones[1].parent != bones[0] or bones[2].parent != bones[1]:
        return None
    return bones


HIND = [c for c in (_chain(s + "Thigh", s + "Leg", s + "Foot") for s in "LR") if c]
FRONT = [c for c in (_chain(s + "Arm", s + "ForeArm", s + "Hand") for s in "LR") if c]
# Voladores con alas (bajan nivelando el cuerpo) y los que levitan sin alas (gases, fantasmas, imanes, Abra).
WINGED = {"pidgey", "pidgeotto", "pidgeot", "spearow", "fearow", "articuno", "zapdos", "moltres", "aerodactyl",
          "beedrill", "scyther", "butterfree", "venomoth", "zubat", "golbat"}
FLOATING = {"gastly", "haunter", "koffing", "weezing", "magnemite", "magneton", "abra"}
GASSY = {"gastly", "haunter", "koffing", "weezing"}


def _height_of(pb):
    return (pb.head.dot(UP) - _ulo) / HEIGHT


def _rest_height(pb):
    """Altura en el reposo del esqueleto: las manos de un cuadrúpedo están en el suelo; las de un bípedo no, aunque
    en el idle cuelguen hasta las rodillas (Meowth, Pinsir, Jynx)."""
    return (pb.bone.head_local.dot(UP) - _ulo) / HEIGHT


def _body_kind():
    if KO_STYLE not in ("fall",):
        return "fall"
    if NAME in WINGED:
        return "winged"
    if NAME in FLOATING:
        return "float"
    if len(HIND) == 2:
        # Cuadrúpedo: las manos llegan casi al suelo
        if len(FRONT) == 2 and max(_rest_height(c[2]) for c in FRONT) < 0.2:
            return "quad"
        return "biped"
    # Piernas sin rodilla (esqueletos de plantilla: el muslo llega al tobillo, Hypno, Electabuzz): sin patas que
    # doblar, el KO de bípedo se queda en echarse atrás y caer de lado entero, con las piernas tiesas.
    stubs = all(LB.get(s + "Thigh") and LB.get(s + "Foot") and LB[s + "Foot"].parent == LB[s + "Thigh"] for s in "LR")
    if stubs and not HIND and (len(FRONT) < 2 or max(_rest_height(c[2]) for c in FRONT) >= 0.2):
        return "biped"
    return "fall"


KO_BODY = _body_kind()
_HIP = min((_height_of(c[0]) for c in HIND), default=0.0)
_SHOULDER = min((_height_of(c[0]) for c in FRONT), default=_HIP)
# Cuánto baja el cuerpo al doblarse las patas (en alturas del modelo)
DROP = 0.45 * _HIP if KO_BODY == "biped" else 0.55 * (_HIP + _SHOULDER) / 2
CENTER = GROUND + UP * HEIGHT * 0.5


def _level_pitch():
    """Cabeceo que deja horizontal el eje largo del cuerpo (sin alas): la dirección principal de la franja
    central de la malla en el plano delante-arriba."""
    mid = (_llo + _lhi) / 2
    pts = [p for p in _pts if abs(p.dot(LEFT) - mid) < 0.25 * HALF_W + 1e-4] or _pts
    cf = sum(p.dot(FWD) for p in pts) / len(pts)
    cu = sum(p.dot(UP) for p in pts) / len(pts)
    sff = sum((p.dot(FWD) - cf) ** 2 for p in pts)
    suu = sum((p.dot(UP) - cu) ** 2 for p in pts)
    sfu = sum((p.dot(FWD) - cf) * (p.dot(UP) - cu) for p in pts)
    ang = 0.5 * math.atan2(2 * sfu, sff - suu)  # ángulo del eje principal sobre la horizontal (+ delante alto)
    deg = math.degrees(ang)
    if deg > 90:
        deg -= 180
    elif deg < -90:
        deg += 180
    return max(-30.0, min(80.0, deg))


def _bone_level():
    """Cabeceo que tumba el cuerpo de barriga con la cabeza delante: lo que sube la cabeza sobre la cadera (las
    aves y las polillas vuelan erguidas). Sin hueso de cabeza, por la forma de la malla."""
    hips = LB.get("Hips") or LB.get("Waist") or next((pb for pb in PB if pb.parent is None), None)
    if HEAD is None or hips is None:
        return _level_pitch()
    d = HEAD.head - hips.head
    return max(-20.0, min(85.0, math.degrees(math.atan2(d.dot(UP), d.dot(FWD)))))


LEVEL = _bone_level() if KO_BODY == "winged" else 0.0
# Colas largas de los que vuelan erguidos (Articuno): al tumbar el cuerpo quedaban de punta hacia el cielo, como un
# palo. Su base gira al revés que el cuerpo (grados por grado de LEVEL) para que quede tendida detrás, en el suelo.
TAIL_KO = {"articuno": ("Tail1", float(os.environ.get("TAIL_KO", "0.8")))}.get(NAME)
if TAIL_KO and TAIL_KO[0] not in {pb.name for pb in PB}:
    TAIL_KO = None


def _tail_ko(e):
    return {TAIL_KO[0]: head_rot(pitch=-TAIL_KO[1] * LEVEL * e)} if TAIL_KO else None


def _smooth(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3 - 2 * x)


def ko_biped(f, n):
    """Se echa atrás con un quejido, le fallan las rodillas (los pies quietos), se inclina y cae de lado con las
    piernas dobladas; rebota y queda. (De bruces, las piernas dobladas lo dejarían apoyado en las rodillas.)"""
    front = False
    # Gira sobre el costado del tronco (no sobre la punta del brazo): lo que se hunda lo levanta bake_ground
    pivot = GROUND + FWD * HALF_D if front else GROUND - LEFT * SIDE * HALF_W * 0.4

    def topple(deg, pitch):
        return {"pitch": pitch + deg, "roll": 4 * SIDE} if front else {"roll": deg * SIDE, "pitch": pitch}
    if f <= 6:
        k = math.sin(0.5 * math.pi * f / 6)
        return dict(pose(f / ILEN, pitch=-10 * k, lift=0.012 * k, head=head_rot(pitch=-22 * k)), ik=1.0, arms=0.0)
    if f <= 18:  # las rodillas ceden: baja la cadera y se inclina hacia delante
        e = _smooth((f - 6) / 12)
        return dict(pose(6 / ILEN, pitch=-10 + 22 * e, roll=4 * SIDE * e, lift=-DROP * e,
                         head=head_rot(pitch=-22 + 50 * e, roll=8 * SIDE * e)), ik=1.0, arms=_smooth((f - 6) / 10))
    if f <= 31:  # se vence hacia un lado, cada vez más deprisa; las piernas dobladas van con él
        x = (f - 18) / 13
        e = x * x
        return dict(pose(6 / ILEN, **topple(84 * e, 12 - 6 * e), lift=-DROP * (1 - e), pivot=pivot,
                         head=head_rot(pitch=28 + 4 * e, roll=8 * SIDE)), ik=1.0, follow=18, arms=1.0)
    bounce = 6 * math.sin(math.pi * (f - 31) / 5) if f <= 36 else 0.0
    return dict(pose(6 / ILEN, **topple(84 - bounce, 6), pivot=pivot,
                     head=head_rot(pitch=32 + 4 * min(1.0, (f - 31) / 8), roll=8 * SIDE)), ik=1.0, follow=18, arms=1.0)


def ko_quad(f, n):
    """Levanta la cabeza con un quejido, se le doblan las patas delanteras y luego las traseras hasta quedar
    echado sobre la barriga, se ladea un poco y apoya la cabeza en el suelo."""
    if f <= 6:
        k = math.sin(0.5 * math.pi * f / 6)
        return dict(pose(f / ILEN, pitch=-6 * k, head=head_rot(pitch=-18 * k)), ik=1.0)
    if f <= 22:
        x = (f - 6) / 16
        fe, he = _smooth(x * 1.6), _smooth((x - 0.3) / 0.7)
        return dict(pose(6 / ILEN, pitch=-6 + 6 * x + 14 * (fe - he), lift=-DROP * (fe + he) / 2,
                         head=head_rot(pitch=-18 + 30 * fe)), ik=1.0)
    x = min(1.0, (f - 22) / 10)
    e = _smooth(x)
    bounce = 3 * math.sin(math.pi * (f - 32) / 5) if 32 < f <= 37 else 0.0
    return dict(pose(6 / ILEN, roll=(22 * e - bounce) * SIDE, lift=-DROP, pivot=GROUND - LEFT * SIDE * HALF_W * 0.6,
                     head=head_rot(pitch=12 + 33 * e, roll=14 * SIDE * e)), ik=1.0, follow=22)


def _wing_rest_phase():
    """Fase del aleteo con las alas más abiertas (la malla menos alta): ahí se quedan al posarse."""
    best, lo = 0.0, None
    for i in range(12):
        sample(i / 12)
        ps = _verts_now()
        h = max(p.dot(UP) for p in ps) - min(p.dot(UP) for p in ps)
        if lo is None or h < lo:
            best, lo = i / 12, h
    return best


WING_REST = _wing_rest_phase() if KO_BODY == "winged" else 0.0


def ko_winged(f, n):
    """Encaja el golpe en el aire; el aleteo se apaga, baja nivelando el cuerpo (sin clavarse de cabeza) con un
    ligero bamboleo y se posa de barriga con las alas abiertas y la cabeza caída."""
    total = 1.5 + ((WING_REST - 6 / ILEN) % 1.0)  # vueltas de aleteo que da hasta pararse en WING_REST
    if f <= 6:
        k = math.sin(0.5 * math.pi * f / 6)
        return pose(f / ILEN, pitch=-12 * k, lift=0.02 * k, head=head_rot(pitch=-20 * k), pivot=CENTER)
    if f <= 30:
        x = (f - 6) / 24
        e = _smooth(x)
        flap = 6 / ILEN + total * (1 - (1 - x) ** 2)  # cada vez más lento
        wob = 10 * math.sin(3 * math.pi * x) * (1 - x)
        return pose(flap, pitch=-12 * (1 - e) + LEVEL * e, roll=SIDE * (wob + 14 * e),
                    lift=0.02 * (1 - e) - HOVER * e, pivot=CENTER, head=head_rot(pitch=-20 + 45 * e),
                    bones=_tail_ko(e))
    bounce = 0.025 * math.sin(math.pi * (f - 30) / 5) if f <= 35 else 0.0
    return pose(6 / ILEN + total, pitch=LEVEL, roll=SIDE * (14 + 4 * min(1.0, (f - 30) / 8)), lift=-HOVER + bounce,
                pivot=CENTER, head=head_rot(pitch=25 + 15 * min(1.0, (f - 30) / 8), roll=6 * SIDE),
                bones=_tail_ko(1.0))


def ko_float(f, n):
    """Los que levitan se apagan: dan un respingo, se hunden despacio balanceándose y se posan ladeados (los
    gases se deshinchan un poco)."""
    gas = NAME in GASSY
    if f <= 6:
        k = math.sin(0.5 * math.pi * f / 6)
        return pose(f / ILEN, pitch=-10 * k, lift=0.03 * k, pivot=CENTER, head=head_rot(pitch=-15 * k))
    x = min(1.0, (f - 6) / 26)
    e = _smooth(x)
    wob = 12 * math.sin(2.5 * math.pi * x) * (1 - x)
    bounce = 0.02 * math.sin(math.pi * (f - 32) / 5) if 32 < f <= 37 else 0.0
    return pose(6 / ILEN + 0.5 * x, pitch=-10 * (1 - e) + 14 * e, roll=SIDE * (wob + 20 * e),
                lift=0.03 * (1 - e) - HOVER * e + bounce, up_scale=1 - (0.14 if gas else 0.03) * e,
                side_scale=1 + (0.08 if gas else 0.0) * e, pivot=CENTER, head=head_rot(pitch=-15 + 40 * e))


def ko(f, n):
    return {"biped": ko_biped, "quad": ko_quad, "winged": ko_winged, "float": ko_float}.get(KO_BODY, ko_fall)(f, n)


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


def _ik_legs():
    """Cadenas que se doblan con IK en el debilitado: las cuatro patas de un cuadrúpedo o las dos piernas."""
    if KO_BODY == "quad":
        return HIND + FRONT
    return HIND if KO_BODY == "biped" else []


def _ik_arms():
    """Brazos de los bípedos, que se quedan flojos al caer: cuelgan junto al cuerpo con el codo algo doblado."""
    return FRONT if KO_BODY == "biped" else []


def _rotation_between(a, b):
    """Giro mínimo que lleva la dirección a a la b (matriz 4×4)."""
    return a.normalized().rotation_difference(b.normalized()).to_matrix().to_4x4()


def _about(point, rot):
    return Matrix.Translation(point) @ rot @ Matrix.Translation(-point)


def _two_bone_ik(chain, target):
    """Dobla [muslo, pierna, pie] para llevar el tobillo a `target` (espacio de la armadura) sin cambiar el plano
    en que ya se doblaba la rodilla. Calculado a mano: el IK de Blender no converge con los huesos sueltos y
    escalados de los rips."""
    upper, lower, end = chain
    hip, knee, ankle = upper.head.copy(), lower.head.copy(), end.head.copy()
    a, b = (knee - hip).length, (ankle - knee).length
    if a < 1e-6 or b < 1e-6:
        return
    to_t = target - hip
    d = max(abs(a - b) + 1e-4, min(a + b - 1e-4, to_t.length))
    u = to_t.normalized()
    normal = (knee - hip).cross(ankle - hip)
    if normal.length < 1e-6:  # pierna recta: se dobla hacia delante
        normal = LEFT.copy()
    v = normal.cross(u).normalized()
    if v.dot(knee - hip) < 0:
        v = -v
    x = (a * a - b * b + d * d) / (2 * d)
    new_knee = hip + u * x + v * math.sqrt(max(a * a - x * x, 0.0))
    r1 = _about(hip, _rotation_between(knee - hip, new_knee - hip))
    upper_m = r1 @ upper.matrix
    lower_m = r1 @ lower.matrix
    moved_ankle = r1 @ ankle
    r2 = _about(new_knee, _rotation_between(moved_ankle - new_knee, hip + u * d - new_knee))
    lower_m = r2 @ lower_m
    _set_rotation(upper, upper_m)
    _set_rotation(lower, lower_m)


def _set_rotation(pb, pose_m):
    """Lleva el hueso a `pose_m` (espacio de la armadura) cambiando solo su giro. Algunos rips traen huesos con
    escala desigual (la pierna de Poliwrath: 0,53 × 1,92): al pasar la matriz a local, Blender repartía el giro
    entre giro y escala y la pata se estiraba como una lanza."""
    keep = pb.scale.copy()
    pb.matrix_basis = arm.convert_space(pose_bone=pb, matrix=pose_m, from_space="POSE", to_space="LOCAL")
    pb.scale = keep
    bpy.context.view_layer.update()


def _hang_point(chain):
    """Dónde queda la muñeca con el brazo colgando del hombro, algo adelantado y separado del cuerpo."""
    upper, lower, end = chain[:3]
    length = (lower.head - upper.head).length + (end.head - lower.head).length
    out = 1 if (upper.head - GROUND).dot(LEFT) > 0 else -1
    return upper.head - UP * length * 0.85 + FWD * length * 0.2 + LEFT * out * length * 0.15


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
    legs = _ik_legs() if any("ik" in k for k in keys) else []
    arms = _ik_arms() if any("arms" in k for k in keys) else []

    def set_pose(k):
        base = cache[round(k["phase"] % 1.0, 4)]
        for pb in PB:
            m = base[pb.name]
            rest = pb.bone.matrix_local
            if pb.parent is None:  # la raíz lleva el movimiento del cuerpo entero
                m = rest.inverted() @ k["body"] @ rest @ m
            elif pb == HEAD and k["head"] is not None:
                q = Quaternion((rest.to_3x3().inverted() @ k["head"].axis).normalized(), k["head"].angle)
                m = m @ q.to_matrix().to_4x4()
            elif pb.name in k.get("bones", {}):
                r = k["bones"][pb.name]
                q = Quaternion((rest.to_3x3().inverted() @ r.axis).normalized(), r.angle)
                m = m @ q.to_matrix().to_4x4()
            pb.rotation_mode = "QUATERNION"
            pb.matrix_basis = m

    # Pies clavados: el objetivo de cada pata es dónde está su tobillo en el primer fotograma
    chains = legs + arms
    targets = []
    if chains:
        set_pose(keys[0])
        bpy.context.view_layer.update()
        for chain in chains:
            end = chain[-1]
            targets.append((_hang_point(chain), None) if chain in arms else (end.head.copy(), end.matrix.copy()))
    body0 = keys[0]["body"].inverted()
    follow_ref = {}
    for f, k in enumerate(keys, start=1):
        set_pose(k)
        if chains:
            ref = k.get("follow")
            move = Matrix.Identity(4)
            if ref is not None:  # las patas dobladas siguen al cuerpo desde ese fotograma
                if ref not in follow_ref:
                    follow_ref[ref] = keys[ref]["body"].inverted()
                move = k["body"] @ follow_ref[ref]
            bpy.context.view_layer.update()
            for i, ((tail, foot_rot), chain) in enumerate(zip(targets, chains)):
                is_arm = i >= len(legs)
                weight = k.get("arms", 0.0) if is_arm else k.get("ik", 0.0)
                if weight <= 0.0:
                    continue
                at = (k["body"] @ body0 @ tail) if is_arm else move @ tail  # los brazos van siempre con el cuerpo
                below = _ulo + 0.02 * HEIGHT - at.dot(UP)
                if below > 0:  # el pie no se mete bajo el suelo al caer
                    at += UP * below
                at = chain[-1].head.lerp(at, weight)
                _two_bone_ik(chain, at)
                if foot_rot is not None:  # el pie, plano como estaba (y girado con el cuerpo si ya cae)
                    end = chain[-1]
                    want = (move @ foot_rot).to_3x3().to_4x4()
                    want.translation = end.matrix.translation
                    _set_rotation(end, want)
            if os.environ.get("KO_DEBUG") and f in (7, 14, 22):
                for (tail, _), chain in zip(targets, chains):
                    print(f"  f{f} {chain[-1].name}: tobillo {tuple(round(x, 3) for x in chain[-1].head)} "
                          f"(quieto en {tuple(round(x, 3) for x in tail)})")
        for pb in PB:
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
          f"base {IDLE.name}, flota {HOVER:.2f}, debilitado {KO_BODY} (cadera {_HIP:.2f}, hombros {_SHOULDER:.2f}, "
          f"baja {DROP:.2f}, nivel {LEVEL:.0f}°)")
    print("Animadas:", ", ".join(made) or "ninguna")
    if KO_BODY in ("biped", "quad"):
        print("Patas:", "; ".join(" > ".join(b.name for b in c) for c in HIND + FRONT))
    if kept:
        print("Ya las tenía (no se tocan; usa --force para rehacerlas):", ", ".join(kept))


main()

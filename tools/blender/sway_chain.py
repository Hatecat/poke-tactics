"""Curva y ondulación de las cadenas largas de los rips (la cola de Raichu, la liana de Victreebel).

    blender --background art/blender/raichu.blend --python tools/blender/sway_chain.py

En estos rips los huesos de la cadena vienen con los ejes girados: los giros de los animadores (cabeceo,
guiñada) solo la retuercen sobre sí misma y la cola queda como un palo recto. Este script prueba en el reposo
qué eje propio de cada hueso sube la punta y cuál la lleva de lado, y con ellos suma a cada acción:
  - una curva fija (`curl`: grados por hueso, + sube la punta);
  - una onda que baja hacia la punta (`sway`: grados de la punta de lado y arriba), un ciclo cada 2 s
    (las cíclicas, idle y walk, con un número entero de ciclos para que no salten al repetirse).
Va después de los animadores y de animate_status.py (marca cada acción y no la toca dos veces); luego
tools/blender/export_animations.py.
"""
import math
import re
from pathlib import Path

import bpy
from mathutils import Quaternion, Vector

NAME = Path(bpy.data.filepath).stem
CHAINS = {
    # La cola baja un poco al salir y se curva hacia arriba hasta el rayo, como en el artwork.
    "raichu": {"chain": r"Tail\d+", "curl": (-12, 4, 6, 8, 10, 11, 10, 8, 6), "sway": (14, 7)},
    # La liana se arquea hacia atrás y cuelga con la hoja al final; se mece despacio.
    "victreebel": {"chain": r"Tail(0[2-9]|1[0-2])", "curl": (30, -4, -6, -9, -12, -15, -18, -21, -24, -27, -30),
                   "sway": (16, 8)},
}
CFG = CHAINS[NAME]
PERIOD = 48  # fotogramas por ciclo de la onda (2 s a 24 fps)
LAG = 0.07  # retraso por hueso hacia la punta, en ciclos
MARK = "sway_chain"

arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
PB = arm.pose.bones


def _canon(name):
    return re.sub(r"_\d+$", "", re.sub(r"^\d+ ", "", name))


CHAIN = sorted((pb for pb in PB if re.fullmatch(CFG["chain"], _canon(pb.name))),
               key=lambda pb: len(pb.parent_recursive))
assert len(CHAIN) == len(CFG["curl"]), f"{len(CHAIN)} huesos en la cadena y {len(CFG['curl'])} ángulos"
TIP = CHAIN[-1]
UP, SIDE = Vector((0, 0, 1)), Vector((1, 0, 0))


def _axes(pb):
    """Ejes propios del hueso (con signo) que suben la punta y la llevan de lado, probados en el reposo."""
    moves = []
    for e in (Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))):
        pb.rotation_quaternion = Quaternion(e, math.radians(5))
        bpy.context.view_layer.update()
        moves.append((e, TIP.tail - rest_tip))
    pb.rotation_quaternion = Quaternion()
    up_e, up_d = max(moves, key=lambda m: abs(m[1].dot(UP)))
    side_e, side_d = max((m for m in moves if m[0] != up_e), key=lambda m: abs(m[1].dot(SIDE)))
    return up_e * math.copysign(1, up_d.dot(UP)), side_e * math.copysign(1, side_d.dot(SIDE))


arm.animation_data_create()
saved = arm.animation_data.action
arm.animation_data.action = None
for pb in PB:
    pb.rotation_mode = "QUATERNION"
    pb.rotation_quaternion = Quaternion()
    pb.location = Vector()
bpy.context.view_layer.update()
rest_tip = TIP.tail.copy()
AXES = [_axes(pb) for pb in CHAIN]


def extra(i, frame, period):
    """Giro sumado al hueso i en ese fotograma: curva + onda (la punta describe un óvalo)."""
    n = len(CHAIN)
    w = (0.3 + 0.7 * (i + 1) / n) * 2 / n
    ph = 2 * math.pi * ((frame - 1) / period - LAG * i)
    side_amp, up_amp = CFG["sway"]
    up_e, side_e = AXES[i]
    return Quaternion(up_e, math.radians(CFG["curl"][i] + up_amp * w * math.sin(ph + math.pi / 2))) @ \
        Quaternion(side_e, math.radians(side_amp * w * math.sin(ph)))


done = []
for act in bpy.data.actions:
    if act.get(MARK):
        continue
    arm.animation_data.action = act
    for pb in CHAIN:  # los huesos sin claves en esta acción no deben heredar la pose de la anterior
        pb.rotation_quaternion = Quaternion()
    start, end = int(act.frame_start), int(act.frame_end)
    length = end - start
    period = length / max(1, round(length / PERIOD)) if act.use_cyclic and length > 0 else PERIOD
    poses = {}
    for f in range(start, end + 1):
        bpy.context.scene.frame_set(f)
        poses[f] = [pb.rotation_quaternion.copy() for pb in CHAIN]
    for f, base in poses.items():
        for i, pb in enumerate(CHAIN):
            pb.rotation_quaternion = base[i] @ extra(i, f, period)
            pb.keyframe_insert("rotation_quaternion", frame=f, group=pb.name)
    act[MARK] = True
    done.append(act.name)

arm.animation_data.action = saved
for pb in PB:
    pb.rotation_quaternion = Quaternion()
bpy.ops.wm.save_mainfile()
print(f"{NAME}: {len(CHAIN)} huesos; curva y onda en", ", ".join(done) or "ninguna (ya estaban)")

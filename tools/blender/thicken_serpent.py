"""Engorda el cuerpo de una serpiente sin tocar la cabeza (el rip de Ekans es más delgado que el artwork).

    blender --background art/blender/ekans.blend --python tools/blender/thicken_serpent.py -- --factor 1.3

En el reposo estos rips están de pie y rectos: cada anillo del cuerpo es un corte a una altura. Cada vértice se
aleja del centro de su anillo `factor` veces; justo debajo de la cabeza el factor baja poco a poco hasta 1 para que
el cuello empalme con ella. Los huesos y las acciones no cambian: después, tools/blender/export_animations.py.
"""
import re
import sys

import bpy

arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
FACTOR = float(args[args.index("--factor") + 1]) if "--factor" in args else 1.3
BINS = 200  # anillos en que se corta el cuerpo para hallar su centro
BLEND = 0.08  # tramo bajo la cabeza (en fracciones del largo) en que el factor vuelve a 1


def _canon(name):
    return re.sub(r"_\d+$", "", re.sub(r"^\d+ ", "", name))


HEAD_Z = next(b.head_local.z for b in arm.data.bones if _canon(b.name) == "Head")

for o in bpy.context.scene.objects:
    if o.type != "MESH":
        continue
    to_arm = arm.matrix_world.inverted() @ o.matrix_world
    from_arm = to_arm.inverted()
    pts = [to_arm @ v.co for v in o.data.vertices]
    lo = min(p.z for p in pts)
    length = HEAD_Z - lo
    if length <= 0:
        continue
    step = length / BINS
    sums = {}
    for p in pts:
        if p.z < HEAD_Z:
            k = int((p.z - lo) / step)
            s = sums.setdefault(k, [0.0, 0.0, 0])
            s[0] += p.x
            s[1] += p.y
            s[2] += 1
    moved = 0
    for v, p in zip(o.data.vertices, pts):
        if p.z >= HEAD_Z:
            continue
        s = sums[int((p.z - lo) / step)]
        cx, cy = s[0] / s[2], s[1] / s[2]
        t = min(1.0, (HEAD_Z - p.z) / (BLEND * length))
        f = 1 + (FACTOR - 1) * t * t * (3 - 2 * t)
        p.x = cx + (p.x - cx) * f
        p.y = cy + (p.y - cy) * f
        v.co = from_arm @ p
        moved += 1
    o.data.update()
    print(f"{o.name}: {moved} vértices del cuerpo engordados x{FACTOR}")

bpy.ops.wm.save_mainfile()

"""Suaviza una cadena larga y fina de un rip (la cola de Raichu, la liana de Victreebel) para que se curve redonda.

    blender --background art/blender/raichu.blend --python tools/blender/smooth_chain.py

La varilla del rip tiene muy pocos anillos (la cola de Raichu, cinco en 3,4 de largo) y cada vértice va con un
solo hueso: al curvarla con sway_chain.py salían tramos rectos con codos que se estiraban. Aquí:
  - se corta la varilla en anillos cada `STEP` a lo largo de la cadena (en el reposo va recta a lo largo de Y);
  - cada vértice de la varilla reparte su peso entre los huesos de la cadena según la distancia a lo largo
    (campana de `SIGMA` veces el largo del hueso), así cada curva se reparte en un arco;
  - la punta (el rayo, la hoja) y lo que hay antes de la cadena conservan sus pesos;
  - con `color`, las caras de la varilla pasan a un material liso propio (la cola de Raichu cogía trozos
    amarillos y grises de la textura del cuerpo); Unit le da el color de FLAT_COLORS.
Las acciones no cambian. Después: tools/blender/export_animations.py.
"""
import math
import re
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

NAME = Path(bpy.data.filepath).stem
CHAINS = {
    "raichu": {"chain": r"Tail\d+", "color": ("TailDark", (0.13, 0.1, 0.09))},
    # La hoja empieza en Tail11: la varilla acaba en su cabeza.
    "victreebel": {"chain": r"Tail(0\d|1[01])"},
}
CFG = CHAINS[NAME]
STEP = 0.08  # largo máximo entre anillos (unidades del rip)
SIGMA = 0.6
MAX_INFLUENCES = 4
RADIUS = 0.12  # lo que se aleja del eje de la cadena más que esto no es la varilla (alas de la hoja, el rayo)

arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")


def _canon(name):
    return re.sub(r"_\d+$", "", re.sub(r"^\d+ ", "", name))


CHAIN = sorted((b for b in arm.data.bones if re.fullmatch(CFG["chain"], _canon(b.name))),
               key=lambda b: len(b.parent_recursive))
HEADS = [b.head_local for b in CHAIN]
Y0, Y1 = HEADS[0].y, HEADS[-1].y  # la varilla: de la cabeza del primer hueso a la del último
AXIS_XZ = (HEADS[0].x, HEADS[0].z)
# Tramo de cada hueso a lo largo de Y: de su cabeza a la del siguiente (el eje de los huesos del rip no va a lo
# largo de la cadena). El padre de la cadena entra con un tramo antes del primero para que el arranque empalme.
SEGS = [(b.name, (HEADS[i].y + HEADS[i + 1].y) / 2, abs(HEADS[i + 1].y - HEADS[i].y))
        for i, b in enumerate(CHAIN[:-1])]
SEGS.append((CHAIN[-1].name, Y1 + SEGS[-1][2] / 2, SEGS[-1][2]))
SEGS.insert(0, (CHAIN[0].parent.name, Y0 - SEGS[0][2] / 2, SEGS[0][2]))


def _in_rod(p):
    return Y0 <= p.y <= Y1 and math.hypot(p.x - AXIS_XZ[0], p.z - AXIS_XZ[1]) < RADIUS


def _weights(y):
    raw = [(n, math.exp(-0.5 * ((y - c) / (SIGMA * l)) ** 2)) for n, c, l in SEGS]
    raw = sorted(raw, key=lambda t: -t[1])[:MAX_INFLUENCES]
    total = sum(w for _, w in raw)
    return [(n, w / total) for n, w in raw if w / total > 0.01]


for o in [o for o in bpy.context.scene.objects if o.type == "MESH" and o.find_armature() == arm]:
    to_arm = arm.matrix_world.inverted() @ o.matrix_world
    bm = bmesh.new()
    bm.from_mesh(o.data)
    rod = [f for f in bm.faces if all(_in_rod(to_arm @ v.co) for v in f.verts)]
    if not rod:
        bm.free()
        continue
    before = len(bm.verts)
    # Anillos nuevos: un corte plano perpendicular a la cadena cada STEP, solo en las caras de la varilla.
    n_cuts = int((Y1 - Y0) / STEP)
    from_arm = to_arm.inverted()
    for k in range(1, n_cuts):
        geom = [f for f in bm.faces if all(_in_rod(to_arm @ v.co) for v in f.verts)]
        geom = list({e for f in geom for e in f.edges} | {v for f in geom for v in f.verts}) + geom
        co = from_arm @ Vector((AXIS_XZ[0], Y0 + k * (Y1 - Y0) / n_cuts, AXIS_XZ[1]))
        no = (from_arm.to_3x3() @ Vector((0, 1, 0))).normalized()
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=co, plane_no=no, dist=1e-5)
    if "color" in CFG:
        name, rgb = CFG["color"]
        mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
        mat.diffuse_color = (*rgb, 1.0)
        mat.use_nodes = True
        mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*rgb, 1.0)
        mat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.7
        if name not in o.data.materials:
            o.data.materials.append(mat)
        idx = list(o.data.materials).index(mat)
        for f in bm.faces:
            if all(_in_rod(to_arm @ v.co) for v in f.verts):
                f.material_index = idx
    bm.to_mesh(o.data)
    bm.free()
    groups = {n: (o.vertex_groups.get(n) or o.vertex_groups.new(name=n)) for n, _, _ in SEGS}
    moved = 0
    for v in o.data.vertices:
        p = to_arm @ v.co
        if not _in_rod(p):
            continue
        for g in list(v.groups):
            o.vertex_groups[g.group].remove([v.index])
        for n, w in _weights(p.y):
            groups[n].add([v.index], w, "REPLACE")
        moved += 1
    o.data.update()
    print(f"{o.name}: {len(o.data.vertices) - before} vértices nuevos, {moved} de la varilla repesados")

bpy.ops.wm.save_mainfile()

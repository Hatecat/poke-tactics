"""Suaviza el cuerpo de una serpiente (Ekans...) para que las curvas sean redondas y no esquinas.

    blender --background art/blender/ekans.blend --python tools/blender/smooth_serpent_weights.py [-- --sigma 1.0]

El cuerpo del rip es un tubo con anillos solo cada 0,5-0,7 de largo: entre ellos no se puede doblar. Primero se
añaden anillos (se parten las aristas a lo largo del cuerpo en tramos de como mucho `STEP`); la cabeza no se toca.

En el rip cada vértice va casi entero con su hueso, y como los huesos de la cola son largos para lo fino que es el
cuerpo, al enroscarla (~45° por articulación) cada articulación se veía como una esquina. Aquí cada vértice del
cuerpo reparte su peso entre los huesos de la cadena según la distancia a lo largo del cuerpo (campana de ancho
`sigma` veces el largo del hueso): cada curva se reparte en un arco. En el reposo la serpiente está recta y de pie,
así que esa distancia es la altura. La cabeza y las mandíbulas conservan sus pesos.
Después: tools/blender/export_animations.py (las acciones no cambian).
"""
import math
import re
import sys

import bmesh
import bpy

arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SIGMA = float(args[args.index("--sigma") + 1]) if "--sigma" in args else 1.0
MAX_INFLUENCES = 4
STEP = 0.012  # largo máximo entre anillos, en fracciones del largo del cuerpo


def _canon(name):
    return re.sub(r"_\d+$", "", re.sub(r"^\d+ ", "", name))


BODY = re.compile(r"Hips|Spine\d+|Neck\d*|Tail\d+")
# Lo que no es el tubo del cuerpo (cabeza, mandíbulas, capucha de Arbok...) conserva sus pesos.
KEEP = re.compile(r"(?!(Hips|Spine\d+|Neck\d*|Tail\d+)$).*")
# Tramo de altura de cada hueso del cuerpo, en el espacio de la armadura (de pie: el eje es Z), de su cabeza a la
# de su hijo en la cadena (el eje de los huesos del rip no va a lo largo del cuerpo). Las puntas siguen la cadena.
SEGS = []
_body = [b for b in arm.data.bones if BODY.fullmatch(_canon(b.name))]
for b in _body:
    kids = [c for c in b.children if c in _body and abs(c.head_local.z - b.head_local.z) > 1e-4]
    if kids:
        z0, z1 = b.head_local.z, kids[0].head_local.z
    elif b.parent and abs(b.head_local.z - b.parent.head_local.z) > 1e-4:
        z0 = b.head_local.z
        z1 = z0 + (z0 - b.parent.head_local.z)
    else:
        continue
    SEGS.append((b.name, (z0 + z1) / 2, abs(z1 - z0)))
TOP = max(z + l / 2 for _, z, l in SEGS)
STEP *= TOP - min(z - l / 2 for _, z, l in SEGS)
NECK_TOP = next(b.head_local.z for b in arm.data.bones if _canon(b.name) == "Head")


def add_rings(o):
    """Parte las aristas largas del cuerpo que van a lo largo (de pie: en Z) para que haya anillos cada STEP."""
    to_arm = arm.matrix_world.inverted() @ o.matrix_world
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.join_triangles(bm, faces=bm.faces, angle_face_threshold=0.7, angle_shape_threshold=0.7)
    by_cuts = {}
    for e in bm.edges:
        a, b = (to_arm @ v.co for v in e.verts)
        d = abs(a.z - b.z)
        if max(a.z, b.z) > NECK_TOP or d < STEP or d < 0.7 * (a - b).length:
            continue
        by_cuts.setdefault(math.ceil(d / STEP) - 1, []).append(e)
    added = 0
    for cuts, edges in sorted(by_cuts.items()):
        edges = [e for e in edges if e.is_valid]
        if edges:
            bmesh.ops.subdivide_edges(bm, edges=edges, cuts=cuts, use_grid_fill=True)
            added += len(edges) * cuts
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    bm.to_mesh(o.data)
    bm.free()
    if o.data.has_custom_normals:
        bpy.context.view_layer.objects.active = o
        bpy.ops.mesh.customdata_custom_splitnormals_clear()
    for poly in o.data.polygons:
        poly.use_smooth = True
    return added

for o in bpy.context.scene.objects:
    if o.type != "MESH":
        continue
    print(f"{o.name}: {add_rings(o)} vértices nuevos en el cuerpo")
    to_arm = arm.matrix_world.inverted() @ o.matrix_world
    groups = {g.name: g for g in o.vertex_groups}
    for n, _, _ in SEGS:
        if n not in groups:
            groups[n] = o.vertex_groups.new(name=n)
    idx = {g.index: g.name for g in o.vertex_groups}
    changed = 0
    for v in o.data.vertices:
        kept = sum(g.weight for g in v.groups if KEEP.fullmatch(_canon(idx[g.group])))
        if kept > 0.01:
            continue  # cabeza, mandíbulas, capucha: tal cual
        z = (to_arm @ v.co).z
        if z > TOP:
            continue
        w = []
        for n, c, l in SEGS:
            d = (z - c) / (SIGMA * l)
            w.append((math.exp(-0.5 * d * d), n))
        w.sort(reverse=True)
        if w[0][0] < 1e-6:
            continue  # lejos de todo el cuerpo: se queda como estaba
        w = w[:MAX_INFLUENCES]
        total = sum(x for x, _ in w) or 1.0
        for g in list(v.groups):
            if not KEEP.fullmatch(_canon(idx[g.group])):
                o.vertex_groups[g.group].remove([v.index])
        for x, n in w:
            groups[n].add([v.index], x / total, "REPLACE")
        changed += 1
    print(f"{o.name}: {changed} vértices del cuerpo con pesos suavizados (sigma {SIGMA})")

bpy.ops.wm.save_mainfile()

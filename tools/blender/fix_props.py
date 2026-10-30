"""Arreglos de geometría de piezas que el rip dejó sueltas o desproporcionadas (el péndulo, las llamas).

    blender --background art/blender/hypno.blend --python tools/blender/fix_props.py

hypno: el péndulo (varilla + aro) quedó flotando delante de la mano, con una hilera de triangulitos sueltos
encima de ella (salían como rayas en el aire). Se borran los triangulitos y el péndulo se cuelga de la punta de
los dedos de la mano derecha: la varilla se orienta para que en el idle (frame 1, ya animado) caiga recta hacia
abajo (más corta: la del rip llegaba al suelo) y el aro queda en el plano de la varilla, como una moneda colgando. Va pesado entero a RHand, así que en
las demás acciones se mueve con la mano. Se puede repetir: si la varilla ya cuelga de la mano no hace nada.
rapidash, snorlax, magnemite y magneton: ver sus funciones (_weld_weights para los imanes).
Después: tools/blender/export_animations.py.
"""
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
SPECIES = Path(bpy.data.filepath).stem
STRING = 0.55  # largo de la varilla del péndulo respecto a la del rip
FLAME = 0.5  # tamaño de las llamas de Rapidash respecto a las del rip
CREASE_ANGLE = 60  # grados: aristas de Snorlax que se quedan vivas al subdividir


def _canon(name):
    return name.split(" ", 1)[-1] if name[:3].isdigit() else name


def _hand_rest_to_idle(bone):
    """Matriz (espacio de la armadura) que lleva el reposo del hueso a su pose en el frame 1 del idle."""
    act = bpy.data.actions.get("idle")
    if act is None:
        raise SystemExit("Hace falta el idle (tools/blender/animate_pokemon.py) antes de colgar el péndulo.")
    arm.animation_data.action = act
    if arm.animation_data.action_slot is None and len(act.slots):
        arm.animation_data.action_slot = act.slots[0]
    bpy.context.scene.frame_set(1)
    pb = arm.pose.bones[bone]
    return pb.matrix @ arm.data.bones[bone].matrix_local.inverted()


def hypno():
    hand = next(b.name for b in arm.data.bones if _canon(b.name) == "RHand")
    o = next(o for o in bpy.context.scene.objects if o.type == "MESH" and hand in o.vertex_groups)
    gi = o.vertex_groups[hand].index
    to_arm = arm.matrix_world.inverted() @ o.matrix_world
    bm = bmesh.new()
    bm.from_mesh(o.data)
    deform = bm.verts.layers.deform.verify()
    b = arm.data.bones[hand]
    h0, h1 = b.head_local, b.tail_local  # la mano va de la muñeca a la punta de los dedos
    along = (h1 - h0).normalized()

    # Piezas sueltas que van enteras con la mano
    seen, parts = set(), []
    for v in bm.verts:
        if v.index in seen:
            continue
        comp, st = [], [v]
        seen.add(v.index)
        while st:
            x = st.pop()
            comp.append(x)
            for e in x.link_edges:
                y = e.other_vert(x)
                if y.index not in seen:
                    seen.add(y.index)
                    st.append(y)
        parts.append(comp)
    loose = [c for c in parts if len(c) < 30 and all(v[deform].get(gi, 0) > 0.9 for v in c)]
    # Más allá de la mitad de la mano: lejos de ella, el péndulo; pegados a ella, los triangulitos sueltos
    size = (h1 - h0).length
    pend, junk = [], []
    for c in loose:
        p = sum((to_arm @ v.co for v in c), Vector()) / len(c)
        reach = (p - h0).dot(along)
        if reach > 0.5 * size:
            (pend if (p - (h0 + along * reach)).length > 1.5 * size else junk).append(c)
    if not pend:
        print("hypno: no hay péndulo suelto; ya estaba arreglado")
        return
    verts = [v for c in pend for v in c]
    pts = {v: to_arm @ v.co for v in verts}
    # Arriba de la varilla, lo más cerca de la mano; el aro, en el otro extremo
    top = min(pts.values(), key=lambda q: (q - h1).length)
    far = max((q - top).length for q in pts.values())
    ring = [v for v in verts if (pts[v] - top).length > 0.7 * far]
    ring_c = sum((pts[v] for v in ring), Vector()) / len(ring)
    axis = (ring_c - top).normalized()
    length = (ring_c - top).length

    # El aro, en el plano de la varilla: su normal se gira hasta quedar perpendicular a ella
    n = _ring_normal([pts[v] for v in ring], ring_c)
    rot = n.rotation_difference((n - axis * n.dot(axis)).normalized()).to_matrix()
    for v in ring:
        pts[v] = ring_c + rot @ (pts[v] - ring_c)
    # La varilla del rip llega al suelo con la mano colgando: se acorta y el aro sube con ella
    ring_set = set(ring)
    for v in verts:
        if v in ring_set:
            pts[v] = pts[v] - axis * length * (1 - STRING)
        else:
            t = (pts[v] - top).dot(axis)
            pts[v] = pts[v] - axis * t * (1 - STRING)

    # Hacia dónde tiene que ir la varilla en el reposo para que en el idle cuelgue recta
    d = _hand_rest_to_idle(hand).to_3x3()
    down = (arm.matrix_world.inverted().to_3x3() @ Vector((0, 0, -1))).normalized()
    want = (d.inverted() @ down).normalized()
    grip = h1 - along * 0.1 * (h1 - h0).length  # en la punta de los dedos
    rot = axis.rotation_difference(want).to_matrix()
    back = to_arm.inverted()
    for v in verts:
        v.co = back @ (grip + rot @ (pts[v] - top))
    for c in junk:
        for v in c:
            bm.verts.remove(v)
    bm.to_mesh(o.data)
    o.data.update()
    print(f"hypno: péndulo colgado de {hand} ({len(verts)} vértices, largo {length:.1f}); "
          f"borrados {sum(len(c) for c in junk)} vértices sueltos")


def _ring_normal(points, center):
    """Normal del plano que mejor pasa por los puntos (el menor eje de su dispersión)."""
    cov = Matrix(((0, 0, 0), (0, 0, 0), (0, 0, 0)))
    for p in points:
        d = p - center
        for i in range(3):
            for j in range(3):
                cov[i][j] += d[i] * d[j]
    # Iteración de potencia sobre la inversa (regularizada) para el autovector más pequeño
    inv = (cov + Matrix.Identity(3) * 1e-6 * (cov[0][0] + cov[1][1] + cov[2][2] + 1e-9)).inverted()
    v = Vector((0.3, 0.5, 0.8))
    for _ in range(50):
        v = (inv @ v).normalized()
    return v


def rapidash():
    """Las llamas del rip (crin y cola, FireCore/FireSten) subían a casi el doble de la altura del cuerpo y lo
    tapaban: se encogen hacia donde nacen. Cada vértice de fuego se acerca al punto del cuerpo más cercano
    (FLAME de lo que estaba), así siguen pegadas y con su forma, como la crin de Ponyta. Se marca el objeto
    para no encogerlas dos veces."""
    from mathutils.kdtree import KDTree
    for o in bpy.context.scene.objects:
        if o.type != "MESH" or o.get("fix_props_flames"):
            continue
        fire = {i for i, m in enumerate(o.data.materials) if m and m.name.startswith(("FireCore", "FireSten"))}
        if not fire:
            continue
        me = o.data
        flame_v = {i for p in me.polygons if p.material_index in fire for i in p.vertices}
        body_v = [i for i in range(len(me.vertices)) if i not in flame_v]
        tree = KDTree(len(body_v))
        for k, i in enumerate(body_v):
            tree.insert(me.vertices[i].co, k)
        tree.balance()
        for i in flame_v:
            co = me.vertices[i].co
            root, _, _ = tree.find(co)
            me.vertices[i].co = root + (co - root) * FLAME
        me.update()
        o["fix_props_flames"] = FLAME
        print(f"rapidash: llamas de {o.name} encogidas a {FLAME:.0%} ({len(flame_v)} vértices)")
        return
    print("rapidash: llamas ya encogidas")


def snorlax():
    """El rip tiene 645 vértices: la barriga y los hombros salían a facetas. Se subdivide (Catmull-Clark, nivel 2,
    antes de la armadura, así pesos y UV se interpolan) y queda redondo; las aristas de más de CREASE_ANGLE
    (garras, puntas de las orejas, dientes) llevan pliegue para no ablandarse."""
    import math
    for o in bpy.context.scene.objects:
        if o.type != "MESH" or o.get("fix_props_subdiv"):
            continue
        me = o.data
        bm = bmesh.new()
        bm.from_mesh(me)
        # El rip corta la malla en cada costura de UV (la cara, los brazos son piezas sueltas con vértices
        # repetidos): subdivididas por separado, las costuras se abrían en cuñas. Se sueldan antes (las UV van
        # por esquina de cara, no se pierden).
        welded = len(bm.verts)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
        welded -= len(bm.verts)
        crease = bm.edges.layers.float.get("crease_edge") or bm.edges.layers.float.new("crease_edge")
        sharp = 0
        for e in bm.edges:
            if len(e.link_faces) == 2 and e.calc_face_angle() > math.radians(CREASE_ANGLE):
                e[crease] = 1.0
                sharp += 1
        bm.to_mesh(me)
        bpy.context.view_layer.objects.active = o
        if me.has_custom_normals:  # las normales del rip eran de la malla gruesa
            bpy.ops.mesh.customdata_custom_splitnormals_clear()
        mod = o.modifiers.new("subdiv", "SUBSURF")
        mod.levels = mod.render_levels = 2
        mod.uv_smooth = "PRESERVE_BOUNDARIES"
        bpy.ops.object.modifier_move_to_index(modifier=mod.name, index=0)
        bpy.ops.object.modifier_apply(modifier=mod.name)
        for poly in o.data.polygons:
            poly.use_smooth = True
        o["fix_props_subdiv"] = 2
        print(f"snorlax: {o.name} subdividido ({welded} vértices soldados, {len(me.vertices)} vértices, "
              f"{sharp} aristas con pliegue)")
        return
    print("snorlax: ya subdividido")


def _weld_weights():
    """Iguala los pesos de los vértices repetidos en las costuras de UV (el rip parte la malla en cada una): en
    Magnemite y Magneton cada copia iba a un hueso distinto y al moverse la esfera se abría en grietas negras.
    Cada grupo de vértices en el mismo sitio se queda con la media de sus pesos; la malla no se suelda."""
    from mathutils.kdtree import KDTree
    total = 0
    for o in bpy.context.scene.objects:
        if o.type != "MESH":
            continue
        me = o.data
        kd = KDTree(len(me.vertices))
        for v in me.vertices:
            kd.insert(v.co, v.index)
        kd.balance()
        done = set()
        for v in me.vertices:
            if v.index in done:
                continue
            same = [j for _, j, _ in kd.find_range(v.co, 1e-4)]
            done.update(same)
            if len(same) < 2:
                continue
            avg = {}
            for j in same:
                for g in me.vertices[j].groups:
                    avg[g.group] = avg.get(g.group, 0.0) + g.weight / len(same)
            if all(abs({g.group: g.weight for g in me.vertices[j].groups}.get(k, 0.0) - w) < 1e-3
                   for j in same for k, w in avg.items()):
                continue
            total += 1
            for j in same:
                for g in list(me.vertices[j].groups):
                    o.vertex_groups[g.group].remove([j])
                for k, w in avg.items():
                    o.vertex_groups[k].add([j], w, "REPLACE")
    print(f"{SPECIES}: igualados los pesos de {total} costuras")


FIXES = {"hypno": hypno, "rapidash": rapidash, "snorlax": snorlax, "magnemite": _weld_weights,
         "magneton": _weld_weights}
if SPECIES not in FIXES:
    raise SystemExit(f"{SPECIES}: no hay arreglos de geometría para esta especie ({', '.join(FIXES)})")
FIXES[SPECIES]()
bpy.ops.wm.save_mainfile()

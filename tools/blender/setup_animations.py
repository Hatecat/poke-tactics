"""Prepara un modelo para animarlo en Blender.

Importa assets/models/pokemon/<nombre>.glb, crea en su esqueleto las acciones que
usa el juego (vacías, con la pose de reposo en el primer y último fotograma) y
guarda art/blender/<nombre>.blend. Las acciones que el modelo ya tenga se conservan.
Si el .blend ya existe, lo abre y solo añade las acciones que falten (no reimporta).

Uso (desde la carpeta del proyecto):
    blender --background --python tools/blender/setup_animations.py -- charmander
    blender --background --python tools/blender/setup_animations.py -- charmander claw bite breath
Las palabras tras el nombre son variantes de ataque (MoveData.anim_variant): crean
fight_b_claw, fight_b_bite, fight_d_breath... Sin ellas solo se crean las acciones base.
Para un segundo clip de la misma variante, añade un sufijo: kick_low crea fight_b_kick_low,
que se asigna a ataques concretos en el anim_map del Pokémon ({"lowkick": "fight_b_kick_low"}).
Después abre art/blender/charmander.blend, anima cada acción en el Action Editor
y exporta con tools/blender/export_animations.py.
"""
import math
import re
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector
from mathutils.geometry import intersect_point_line

sys.path.insert(0, str(Path(__file__).parent))
import rig_templates  # noqa: E402

PROJECT = Path(__file__).resolve().parents[2]
# Acción -> (fotogramas, bucle). Los nombres coinciden con las claves del juego.
ACTIONS = {
    "idle": (40, True),
    "walk": (24, True),
    "fight_b": (30, False),
    "fight_d": (30, False),
    "hit": (15, False),
    "ko": (40, False),
}
# Variante -> acción base a la que pertenece (ver anim_variant en tools/build_data.py).
VARIANTS = {v: "fight_b" for v in ("bite", "claw", "punch", "kick", "tail", "wing", "horn", "body")}
VARIANTS.update({v: "fight_d" for v in ("breath", "sound", "powder", "mind", "boost")})


def import_model(name):
    glb = PROJECT / "assets/models/pokemon" / f"{name}.glb"
    if not glb.exists():
        raise SystemExit(f"No existe {glb}")

    bpy.ops.wm.read_factory_settings(use_empty=True)
    # Sin "adivinar la pose de bind original": en la familia Eevee esa suposición descoloca partes de la
    # malla (una oreja de Jolteon acaba de pie en el lomo); en el resto de rips da lo mismo.
    bpy.ops.import_scene.gltf(filepath=str(glb), guess_original_bind_pose=False)
    armature = next((o for o in bpy.context.scene.objects if o.type == "ARMATURE"), None)
    if armature is None and name in AUTO_RIG:
        return auto_rig()
    if armature is None and name in rig_templates.RIGS:
        return template_rig(name)
    if armature is None:
        raise SystemExit("El modelo no tiene esqueleto.")
    # El importador de glTF dibuja cada hueso como una esfera (Icosphere): tapan la malla y, al
    # girar, una esfera se ve igual. Mejor los huesos normales, que muestran hacia dónde apuntan.
    for bone in armature.pose.bones:
        bone.custom_shape = None
    armature.data.display_type = "OCTAHEDRAL"
    armature.show_in_front = True
    for obj in [o for o in bpy.data.objects if o.name.startswith("Icosphere") and o.type == "MESH"]:
        bpy.data.objects.remove(obj)
    bake_import_pose(armature)
    attach_props(armature, name)
    return armature


# Modelos sin esqueleto con forma de bola y piezas sueltas alrededor (las nubes de gas de Koffing, la
# cabeza pequeña de Weezing, los huevos de Exeggcute, los imanes de Magneton): auto_rig() les pone uno.
# Los demás sin esqueleto llevan uno de plantilla (rig_templates.py).
AUTO_RIG = {"koffing", "weezing", "exeggcute", "gastly", "magneton"}


def _islands(mesh):
    """Piezas sueltas de una malla: listas de índices de vértices conectados por aristas."""
    parent = list(range(len(mesh.vertices)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for e in mesh.edges:
        a, b = find(e.vertices[0]), find(e.vertices[1])
        if a != b:
            parent[a] = b
    groups = {}
    for i in range(len(mesh.vertices)):
        groups.setdefault(find(i), []).append(i)
    return list(groups.values())


def auto_rig():
    """Esqueleto para un modelo sin huesos: Hips en el centro de la pieza más grande (el cuerpo) y un
    hueso por cada pieza grande que sobresale de él (nubes de gas, otra cabeza), que sale de la superficie
    del cuerpo hacia el centro de la pieza. Las piezas pequeñas (ojos, dientes) van con la pieza grande
    más cercana que las contiene. Cada vértice pesa 1 en su hueso: se mueven como piezas rígidas."""
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    parts = []  # (objeto, índices, centro, radio) en el espacio del mundo
    for obj in meshes:
        world = [obj.matrix_world @ v.co for v in obj.data.vertices]
        for idx in _islands(obj.data):
            pts = [world[i] for i in idx]
            lo = Vector([min(p[k] for p in pts) for k in range(3)])
            hi = Vector([max(p[k] for p in pts) for k in range(3)])
            parts.append((obj, idx, (lo + hi) / 2, max(hi - lo) / 2))
    parts.sort(key=lambda p: -p[3])
    body = parts[0]
    # Piezas grandes fuera del cuerpo: cada una con su hueso.
    limbs = [p for p in parts[1:] if p[3] > body[3] * 0.18 and (p[2] - body[2]).length > body[3] * 0.8]
    arm_data = bpy.data.armatures.new("Armature")
    armature = bpy.data.objects.new("Armature", arm_data)
    bpy.context.scene.collection.objects.link(armature)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.mode_set(mode="EDIT")
    hips = arm_data.edit_bones.new("Hips")
    hips.head = body[2]
    hips.tail = body[2] + Vector((0, 0, body[3] * 0.5))
    owners = [("Hips", body)]
    for i, limb in enumerate(limbs):
        d = (limb[2] - body[2]).normalized()
        bone = arm_data.edit_bones.new(f"Feeler{i + 1}")
        bone.head = body[2] + d * body[3] * 0.85
        bone.tail = limb[2]
        bone.parent = hips
        owners.append((bone.name, limb))
    bpy.ops.object.mode_set(mode="OBJECT")
    armature.data.display_type = "OCTAHEDRAL"
    armature.show_in_front = True

    def owner_of(part):
        if any(part is o[1] for o in owners):
            return next(n for n, o in owners if o is part)
        # La pieza grande más cercana que la contiene (o, si ninguna, la más cercana).
        inside = [(n, o) for n, o in owners if (part[2] - o[2]).length <= o[3] * 1.1]
        cands = inside or owners
        return min(cands, key=lambda no: (part[2] - no[1][2]).length)[0]

    for part in parts:
        obj, idx = part[0], part[1]
        name = owner_of(part)
        group = obj.vertex_groups.get(name) or obj.vertex_groups.new(name=name)
        group.add(idx, 1.0, "REPLACE")
    for obj in meshes:
        world = obj.matrix_world.copy()
        obj.parent = armature
        obj.matrix_world = world
        obj.modifiers.new("Armature", "ARMATURE").object = armature
    print(f"Esqueleto automático: cuerpo y {len(limbs)} pieza(s) con hueso propio; {len(parts)} piezas en total")
    return armature


CORE_BIAS = 0.7


def template_rig(name):
    """Esqueleto de rig_templates.RIGS (posiciones en alturas del modelo) con pesos por distancia."""
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    pts = [o.matrix_world @ v.co for o in meshes for v in o.data.vertices]
    lo = Vector([min(p[k] for p in pts) for k in range(3)])
    hi = Vector([max(p[k] for p in pts) for k in range(3)])
    height = hi.z - lo.z
    center = (lo + hi) / 2

    def world(p):
        return Vector((center.x + p[0] * height, center.y + p[1] * height, lo.z + p[2] * height))

    # Piezas sueltas fuera de sitio (el péndulo de Hypno): se giran y se llevan a su hueso.
    pinned = {}  # objeto -> {índice de vértice: hueso}
    for prop in rig_templates.RIGS[name].get("_props", []):
        box_lo, box_hi = world(prop["box"][0]), world(prop["box"][1])
        pivot, to = world(prop["pivot"]), world(prop["to"])
        move = Matrix.Translation(to) @ Matrix.Rotation(math.radians(-prop["pitch"]), 4, "X") @ \
            Matrix.Translation(-pivot)
        for obj in meshes:
            inv = obj.matrix_world.inverted()
            for idx in _islands(obj.data):
                pts = [obj.matrix_world @ obj.data.vertices[i].co for i in idx]
                if all(all(box_lo[k] <= p[k] <= box_hi[k] for k in range(3)) for p in pts):
                    for i, p in zip(idx, pts):
                        obj.data.vertices[i].co = inv @ (move @ p)
                        pinned.setdefault(obj, {})[i] = prop["bone"]

    arm_data = bpy.data.armatures.new("Armature")
    armature = bpy.data.objects.new("Armature", arm_data)
    bpy.context.scene.collection.objects.link(armature)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.mode_set(mode="EDIT")
    for bone, head, tail, parent in rig_templates.bones(name):
        eb = arm_data.edit_bones.new(bone)
        eb.head, eb.tail = world(head), world(tail)
        if parent:
            eb.parent = arm_data.edit_bones[parent]
            eb.use_connect = (eb.parent.tail - eb.head).length < 1e-6
    bpy.ops.object.mode_set(mode="OBJECT")
    armature.data.display_type = "OCTAHEDRAL"
    armature.show_in_front = True

    # Pesos por distancia a cada hueso, mezclando los cercanos. El calor de huesos de Blender trata cada
    # malla por separado y la capa de la cara se despega del cuerpo; así todas se deforman igual. El tronco
    # cuenta como más cerca (CORE_BIAS): en los cuerpos redondos las patas no se llevan media barriga.
    segs = [(b.name, b.head_local, b.tail_local) for b in arm_data.bones]
    bias = {n: CORE_BIAS if re.match(r"(Hips|Spine|Neck|Head)", n) else 1.0 for n, _, _ in segs}
    to_arm = armature.matrix_world.inverted()
    for obj in meshes:
        m = to_arm @ obj.matrix_world
        groups = {n: obj.vertex_groups.new(name=n) for n, _, _ in segs}
        for v in obj.data.vertices:
            if v.index in pinned.get(obj, {}):
                groups[pinned[obj][v.index]].add([v.index], 1.0, "REPLACE")
                continue
            p = m @ v.co
            dists = []
            for n, h, t in segs:
                _, k = intersect_point_line(p, h, t)
                dists.append((max((p - (h + (t - h) * min(max(k, 0), 1))).length * bias[n], 1e-6), n))
            near = min(dists)[0]
            ws = [((near / d) ** 6, n) for d, n in dists]
            ws = [(w, n) for w, n in ws if w > 0.05]
            total = sum(w for w, _ in ws)
            for w, n in ws:
                groups[n].add([v.index], w / total, "REPLACE")
        world = obj.matrix_world.copy()
        obj.parent = armature
        obj.matrix_world = world
        obj.modifiers.new("Armature", "ARMATURE").object = armature
    print(f"Esqueleto de plantilla: {len(segs)} huesos")
    return armature


# Accesorios: huesos raíz sueltos que en los juegos coloca una animación propia (en el rip quedan tirados
# en el suelo o flotando delante). Huesos raíz del accesorio -> (hueso que lo lleva, cómo se coloca).
PROPS = {
    "alakazam": {("LFeelerA",): ("LHand", "grip"), ("RFeelerA",): ("RHand", "grip")},
    "kangaskhan": {("HipsB", "SpineB"): ("Hips", "pouch")},  # la cría: piernas y torso
}


def attach_props(armature, name):
    """Mueve cada accesorio (malla y huesos) a su sitio y lo cuelga del hueso que lo lleva, para que
    siga sus animaciones: la cuchara de Alakazam en el puño, de pie; la cría de Kangaskhan en la bolsa."""
    props = PROPS.get(name)
    if not props:
        return
    meshes = [o for o in bpy.data.objects if o.type == "MESH" and o.find_armature() == armature]

    def verts(bones):
        """(objeto, vértice, posición en el espacio de la armadura) de los vértices de esos huesos."""
        to_arm = armature.matrix_world.inverted()
        out = []
        for o in meshes:
            groups = {g.index: g.name for g in o.vertex_groups}
            m = to_arm @ o.matrix_world
            out += [(o, v, m @ v.co) for v in o.data.vertices
                    if v.groups and groups.get(max(v.groups, key=lambda g: g.weight).group) in bones]
        return out

    moves = {}
    for prop, (holder, how) in props.items():
        bones = set(prop)
        for root in prop:
            bones |= {b.name for b in armature.data.bones[root].children_recursive}
        pts = [p for _, _, p in verts(bones)]
        if how == "grip":
            # Eje largo del accesorio; el extremo más ancho (la cabeza de la cuchara) queda arriba.
            mn = Vector([min(p[i] for p in pts) for i in range(3)])
            mx = Vector([max(p[i] for p in pts) for i in range(3)])
            k = max(range(3), key=lambda i: mx[i] - mn[i])
            span = mx[k] - mn[k]

            def width(lo, hi):
                sel = [p for p in pts if lo <= p[k] <= hi]
                return max((p - sel[0]).length for p in sel) if sel else 0.0
            axis = Vector((0, 0, 0))
            axis[k] = 1 if width(mx[k] - span * 0.3, mx[k]) > width(mn[k], mn[k] + span * 0.3) else -1
            grip = (mn + mx) / 2 - axis * span * 0.3  # en el mango, a un tercio del extremo
            hand = verts({holder})
            center = sum((p for _, _, p in hand), Vector()) / len(hand)
            rot = axis.rotation_difference(Vector((0, -0.4, 1)).normalized()).to_matrix().to_4x4()
            moves[prop] = Matrix.Translation(center) @ rot @ Matrix.Translation(-grip)
        else:  # pouch: delante de la tripa, medio metida en ella
            body = [p for _, _, p in verts({holder})]
            front = min(p.y for p in body)
            back = max(p.y for p in pts)
            depth = back - min(p.y for p in pts)
            moves[prop] = Matrix.Translation((0, front + depth * 0.45 - back, 0))
        for o, v, p in verts(bones):
            v.co = (armature.matrix_world.inverted() @ o.matrix_world).inverted() @ moves[prop] @ p

    bpy.context.view_layer.objects.active = armature
    with bpy.context.temp_override(object=armature, active_object=armature, selected_objects=[armature]):
        bpy.ops.object.mode_set(mode="EDIT")
        eb = armature.data.edit_bones
        for prop, (holder, _) in props.items():
            for root in prop:
                for b in [eb[root]] + list(eb[root].children_recursive):
                    b.transform(moves[prop])
                eb[root].parent = eb[holder]
                eb[root].use_connect = False
        bpy.ops.object.mode_set(mode="OBJECT")
    print("Accesorios colocados:", ", ".join(f"{'+'.join(p)} en {h}" for p, (h, _) in props.items()))


def bake_import_pose(armature):
    """Hace de la pose importada el reposo del esqueleto.

    En muchos rips el reposo (la pose de bind) está tumbado o encogido y lo que pone al Pokémon de
    pie son las transformaciones de los nodos del .glb, que Blender importa como pose (Nidoking:
    Hips girado 90° y escalado x2,54). Las acciones se animan sobre el reposo, así que sin esto
    todas quedarían tumbadas en el juego. Se aplica la deformación a la malla, la pose pasa a ser
    el reposo y se vuelve a poner el modificador."""
    if all(pb.matrix_basis == pb.matrix_basis.Identity(4) for pb in armature.pose.bones):
        return
    # Clips del juego que ya trae el rip (Bulbasaur): están hechos sobre el reposo original y se
    # romperían. Mejor no tocar nada.
    if any(a.name.endswith(key) for a in bpy.data.actions for key in ACTIONS):
        print("El modelo ya trae clips del juego: no se cambia el reposo.")
        return
    meshes = [o for o in bpy.data.objects if o.type == "MESH" and o.find_armature() == armature]
    for mesh in meshes:
        for mod in [m for m in mesh.modifiers if m.type == "ARMATURE" and m.object == armature]:
            with bpy.context.temp_override(object=mesh, active_object=mesh):
                bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.context.view_layer.objects.active = armature
    with bpy.context.temp_override(object=armature, active_object=armature, selected_objects=[armature]):
        bpy.ops.object.mode_set(mode="POSE")
        bpy.ops.pose.armature_apply(selected=False)
        bpy.ops.object.mode_set(mode="OBJECT")
    for mesh in meshes:
        mesh.modifiers.new("Armature", "ARMATURE").object = armature
    # Los demás clips del rip (Armature|ArmatureAction en la familia Eevee) ya no encajan con el reposo
    # nuevo y el juego no los usa.
    stale = [a.name for a in bpy.data.actions]
    for name in stale:
        bpy.data.actions.remove(bpy.data.actions[name])
    print("Pose importada aplicada como reposo." + (f" Quitados los clips del rip: {', '.join(stale)}" if stale else ""))


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if not args:
        raise SystemExit("Falta el nombre del Pokémon: ... -- charmander")
    name, variants = args[0], args[1:]
    # "kick_low" es un segundo clip de "kick": se valida por la parte antes del primer "_".
    unknown = [v for v in variants if v.split("_")[0] not in VARIANTS]
    if unknown:
        raise SystemExit(f"Variantes desconocidas: {', '.join(unknown)}. Válidas: {', '.join(VARIANTS)}"
                         " (con sufijo opcional: kick_low)")
    actions = dict(ACTIONS)
    for v in variants:
        base = VARIANTS[v.split("_")[0]]
        actions[f"{base}_{v}"] = ACTIONS[base]

    out = PROJECT / "art/blender" / f"{name}.blend"
    if out.exists():
        bpy.ops.wm.open_mainfile(filepath=str(out))
        armature = next((o for o in bpy.context.scene.objects if o.type == "ARMATURE"), None)
        if armature is None:
            raise SystemExit(f"{out} no tiene esqueleto.")
    else:
        armature = import_model(name)
    armature.animation_data_create()
    previous = armature.animation_data.action

    existing = {a.name for a in bpy.data.actions}
    created = []
    for action_name, (frames, loop) in actions.items():
        # Los rips llevan prefijo ("model_skeleton|001fight_b"); endswith evita además
        # que un fight_b_claw ya existente cuente como fight_b.
        if any(a.endswith(action_name) for a in existing):
            continue
        action = bpy.data.actions.new(action_name)
        action.use_fake_user = True
        action.use_frame_range = True
        action.frame_start, action.frame_end = 1, frames
        action.use_cyclic = loop
        armature.animation_data.action = action
        # Pose de reposo en el primer y último fotograma: así la acción no queda vacía
        # (el exportador glTF ignora las vacías) y los bucles cierran limpios.
        for bone in armature.pose.bones:
            bone.location = (0, 0, 0)
            bone.rotation_mode = "QUATERNION"
            bone.rotation_quaternion = (1, 0, 0, 0)
            bone.scale = (1, 1, 1)
            for frame in (1, frames):
                bone.keyframe_insert("location", frame=frame)
                bone.keyframe_insert("rotation_quaternion", frame=frame)
        created.append(action_name)
    armature.animation_data.action = previous or bpy.data.actions.get("idle") or armature.animation_data.action
    # Todos los huesos ya tienen claves: sin Auto Keying, un giro que no se guarde como clave
    # se pierde en cuanto Blender reevalúa la animación (p. ej. al ajustar el ángulo en el panel).
    bpy.context.scene.tool_settings.use_keyframe_insert_auto = True

    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(out))
    print(f"Listo: {out}")
    print("Acciones creadas:", ", ".join(created) or "ninguna (ya existían)")


main()

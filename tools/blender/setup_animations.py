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
import sys
from pathlib import Path

import bpy

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
    return armature


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

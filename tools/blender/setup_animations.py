"""Prepara un modelo para animarlo en Blender.

Importa assets/models/pokemon/<nombre>.glb, crea en su esqueleto las acciones que
usa el juego (vacías, con la pose de reposo en el primer y último fotograma) y
guarda art/blender/<nombre>.blend. Las acciones que el modelo ya tenga se conservan.

Uso (desde la carpeta del proyecto):
    blender --background --python tools/blender/setup_animations.py -- charmander
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


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if not args:
        raise SystemExit("Falta el nombre del Pokémon: ... -- charmander")
    name = args[0]
    glb = PROJECT / "assets/models/pokemon" / f"{name}.glb"
    if not glb.exists():
        raise SystemExit(f"No existe {glb}")

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(glb))
    armature = next((o for o in bpy.context.scene.objects if o.type == "ARMATURE"), None)
    if armature is None:
        raise SystemExit("El modelo no tiene esqueleto.")
    armature.animation_data_create()

    existing = {a.name for a in bpy.data.actions}
    created = []
    for action_name, (frames, loop) in ACTIONS.items():
        if any(action_name in a for a in existing):
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
    armature.animation_data.action = bpy.data.actions.get("idle") or armature.animation_data.action

    out = PROJECT / "art/blender" / f"{name}.blend"
    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(out))
    print(f"Listo: {out}")
    print("Acciones creadas:", ", ".join(created) or "ninguna (ya existían)")


main()

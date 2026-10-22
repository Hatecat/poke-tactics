"""Exporta un .blend animado al .glb que usa el juego (con todas sus acciones).

Uso (desde la carpeta del proyecto):
    blender --background art/blender/charmander.blend --python tools/blender/export_animations.py
o, con el .blend abierto en Blender: pestaña Scripting → abrir este archivo → Ejecutar.

Sobrescribe assets/models/pokemon/<nombre>.glb (git guarda la versión anterior).
Godot lo reimporta solo; el juego busca las acciones por nombre (idle, walk,
fight_b, fight_d, hit, ko), así que no hay que tocar el anim_map.
"""
from pathlib import Path

import bpy

PROJECT = Path(__file__).resolve().parents[2]


def _has_motion(action):
    for fc in _fcurves(action):
        values = [k.co[1] for k in fc.keyframe_points]
        if values and max(values) - min(values) > 1e-4:
            return True
    return False


def _fcurves(action):
    # Blender 4.4+ guarda las curvas en capas/strips/canales; antes, en action.fcurves.
    if hasattr(action, "layers") and action.layers:
        for layer in action.layers:
            for strip in layer.strips:
                for bag in getattr(strip, "channelbags", []):
                    yield from bag.fcurves
    else:
        yield from getattr(action, "fcurves", [])


def main():
    blend = Path(bpy.data.filepath)
    if not blend.name:
        raise SystemExit("Guarda primero el .blend (el nombre del archivo es el del Pokémon).")
    out = PROJECT / "assets/models/pokemon" / f"{blend.stem}.glb"
    # Las acciones sin animar (todas las curvas planas) no se exportan: así el juego
    # usa la animación procedural en vez de un clip quieto.
    skipped = [a.name for a in bpy.data.actions if not _has_motion(a)]
    for name in skipped:
        bpy.data.actions.remove(bpy.data.actions[name])
    if skipped:
        print("Sin animar (no se exportan):", ", ".join(skipped))
        if not bpy.app.background:
            print("Ojo: se quitaron de este .blend abierto; no lo guardes si quieres conservarlas.")
    for action in bpy.data.actions:
        action.use_fake_user = True
    bpy.ops.export_scene.gltf(
        filepath=str(out),
        export_format="GLB",
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_force_sampling=True,
        export_frame_range=False,
        export_draco_mesh_compression_enable=False,
        export_apply=False,
    )
    names = [a.name for a in bpy.data.actions]
    print(f"Exportado {out} con {len(names)} acciones: {', '.join(names)}")


main()

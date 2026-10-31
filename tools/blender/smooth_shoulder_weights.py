"""Mezcla de pesos en la axila: que la piel bajo el hombro no se meta en el torso al bajar el brazo.

    blender --background art/blender/drowzee.blend --python tools/blender/smooth_shoulder_weights.py [-- --dry-run] [-- --force]

Los esqueletos de plantilla no tienen hueso de hombro y `distance_weights()` (setup_animations.py) da la piel de
la axila y del costado casi entera al brazo: al bajarlo (`arm_drop`), esos vértices giran alrededor de la cabeza
del `Arm`, se meten hacia dentro y hacia arriba y el torso parece hundido bajo el brazo y estrechado en la cintura
(Drowzee, Snorlax). Aquí, solo en las especies de `SPECIES`, el peso de la cadena del brazo (`Arm`, `ForeArm`,
`Hand`) pasa al tronco en dos zonas: en la superficie del brazo (dentro de `ARM_R_IN`) solo por dentro de `s_in`
(medido a lo largo del brazo desde su cabeza) y nada a partir de `s_out`, con una curva suave entre medias y
desvanecida por la distancia a la cabeza del hueso (`r_core` a `r_out`); y en el costado del tronco (fuera de
`ARM_R_OUT`) entera, aunque esté lejos del hombro, para que el cuerpo no se estreche. La cara de arriba del brazo
se deja con el brazo (`UP_FULL`/`UP_NONE`) para que el hombro suba con él. El peso pasa a los huesos de tronco que
el vértice ya tuviera (en proporción) o, si no tenía, al `Spine`. Los vértices repetidos en las costuras de UV
acaban con los mismos pesos. Ambos lados con las mismas constantes. No toca huesos, acciones ni geometría.

Se puede repetir: deja en cada malla la propiedad `shoulder_blend` (versión y configuración) y una copia de los
pesos originales de lo que cambia (`shoulder_blend_orig`); una segunda pasada no hace nada y `--force` vuelve a
los pesos originales y rehace la mezcla (por ejemplo, tras cambiar la configuración). `--dry-run` solo informa.
Si se rehacen los pesos con `setup_animations.py --reweight`, hay que volver a pasar este script con `--force`.
Después: tools/blender/export_animations.py (las acciones no cambian) y tools/bake_ground.gd.
"""
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector
from mathutils.kdtree import KDTree

VERSION = 1
# Por especie, en alturas del modelo: s_in / s_out a lo largo del Arm desde su cabeza (negativo = hacia el
# tronco), r_core / r_out = distancia a la cabeza del Arm donde la mezcla empieza a desvanecerse y donde acaba;
# share = parte máxima del peso del brazo que pasa al tronco (con 1, al levantar el brazo la axila no lo sigue y
# se dobla en una arista; con menos, se reparte entre bajarlo y subirlo).
SPECIES = {
    "drowzee": {"s_in": -0.04, "s_out": 0.14, "r_core": 0.14, "r_out": 0.28, "share": 0.95},
    "snorlax": {"s_in": -0.08, "s_out": 0.16, "r_core": 0.14, "r_out": 0.28, "share": 0.95},
}
# Solo la cara de abajo del brazo: mezcla entera por debajo de UP_FULL (coseno con la vertical de la dirección
# del vértice respecto al eje del Arm) y ninguna por encima de UP_NONE.
UP_FULL, UP_NONE = -0.3, 0.6
# Radio del brazo (alturas del modelo), medido como distancia al eje del Arm: por dentro de ARM_R_IN la piel es
# del brazo y se aplica el desvanecido por s; por fuera de ARM_R_OUT es costado del tronco y se pasa entero al
# tronco aunque esté a la altura del hombro. Sin esto, el costado bajo el brazo seguía al brazo y al bajarlo el
# torso se estrechaba (parecía una cintura).
ARM_R_IN, ARM_R_OUT = 0.09, 0.13
CORE = ("Hips", "Spine")  # huesos de tronco que reciben el peso
TARGET = "Spine"  # si el vértice no tenía peso de tronco
MIN_WEIGHT = 0.01  # por debajo se quita el peso (y se renormaliza)

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
DRY = "--dry-run" in args
FORCE = "--force" in args
SPECIES_NAME = Path(bpy.data.filepath).stem


def smoothstep(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def _height(meshes):
    zs = [(o.matrix_world @ v.co).z for o in meshes for v in o.data.vertices]
    return max(zs) - min(zs)


def _read(o, names):
    return [{names[g.group]: g.weight for g in v.groups if g.weight > 0} for v in o.data.vertices]


def _write(o, i, ws):
    for g in list(o.data.vertices[i].groups):
        o.vertex_groups[g.group].remove([i])
    for n, w in ws.items():
        grp = o.vertex_groups.get(n) or o.vertex_groups.new(name=n)
        grp.add([i], w, "REPLACE")


def blend(o, arm, cfg, height):
    """Devuelve {índice: pesos nuevos} y el informe por lado; no escribe nada."""
    names = {g.index: g.name for g in o.vertex_groups}
    old = _read(o, names)
    to_arm = arm.matrix_world.inverted() @ o.matrix_world
    new = {}
    factor = {}
    report = {}
    for side in "LR":
        chain = [side + n for n in ("Arm", "ForeArm", "Hand")]
        bone = arm.data.bones.get(chain[0])
        if bone is None:
            print(f"{SPECIES_NAME}: {o.name} sin hueso {chain[0]}, lado {side} sin tocar")
            continue
        h = bone.head_local
        d = (bone.tail_local - h).normalized()
        for i, v in enumerate(o.data.vertices):
            arm_w = sum(old[i].get(n, 0.0) for n in chain)
            if arm_w <= 0:
                continue
            q = (to_arm @ v.co - h) / height
            dist = q.length
            s = q.dot(d)
            # Cara del brazo: -1 debajo (la axila), 0 delante/detrás, 1 encima. Lo de encima sigue al brazo para
            # que el hombro suba con él al levantarlo (si se quedara con el tronco, se doblaría en una arista).
            radial = q - d * s
            axis_r = radial.length
            up = radial.z / axis_r if axis_r > 1e-6 else 0.0
            # En la superficie del brazo mandan s y la distancia a la cabeza (el brazo conserva su peso); en el
            # costado del tronco (fuera del radio del brazo) se pasa entero aunque esté lejos del hombro, para
            # que al bajar el brazo el torso no se estreche (la "cintura").
            on_arm = 1.0 - smoothstep(ARM_R_IN, ARM_R_OUT, axis_r)
            s_factor = 1.0 - on_arm * smoothstep(cfg["s_in"], cfg["s_out"], s)
            dist_factor = 1.0 - on_arm * smoothstep(cfg["r_core"], cfg["r_out"], dist)
            t = (cfg["share"]
                 * s_factor
                 * dist_factor
                 * (1 - smoothstep(UP_FULL, UP_NONE, up)))
            if t <= 0:
                continue
            factor[i] = (side, t, s, dist)
    # Costuras de UV: los vértices en el mismo sitio se llevan el mismo factor (el máximo del grupo).
    kd = KDTree(len(o.data.vertices))
    for v in o.data.vertices:
        kd.insert(v.co, v.index)
    kd.balance()
    for i in list(factor):
        for _, j, _ in kd.find_range(o.data.vertices[i].co, 1e-5 * height):
            if j not in factor or factor[j][1] < factor[i][1]:
                factor[j] = factor[i]
    for i, (side, t, s, dist) in factor.items():
        chain = [side + n for n in ("Arm", "ForeArm", "Hand")]
        ws = dict(old[i])
        moved = sum(ws.get(n, 0.0) for n in chain) * t
        if moved <= 0:
            continue
        for n in chain:
            if n in ws:
                ws[n] *= 1 - t
        core = {n: ws[n] for n in CORE if ws.get(n, 0) > 0}
        total = sum(core.values())
        if total > 0:
            for n, w in core.items():
                ws[n] += moved * w / total
        else:
            ws[TARGET] = ws.get(TARGET, 0.0) + moved
        ws = {n: w for n, w in ws.items() if w >= MIN_WEIGHT}
        norm = sum(ws.values())
        ws = {n: w / norm for n, w in ws.items()}
        new[i] = ws
        r = report.setdefault(side, {"n": 0, "before": 0.0, "after": 0.0, "max": 0.0, "pit": 0,
                                     "pit_before": 0.0, "pit_after": 0.0})
        before = sum(old[i].get(n, 0.0) for n in chain)
        after = sum(ws.get(n, 0.0) for n in chain)
        r["n"] += 1
        r["before"] += before
        r["after"] += after
        r["max"] = max(r["max"], max(abs(ws.get(n, 0) - old[i].get(n, 0)) for n in set(ws) | set(old[i])))
        if s <= 0.02:  # la axila: por dentro de la cabeza del brazo
            r["pit"] += 1
            r["pit_before"] += before
            r["pit_after"] += after
    return old, new, report


def main():
    cfg = SPECIES.get(SPECIES_NAME)
    if cfg is None:
        print(f"{SPECIES_NAME}: no está en la configuración de smooth_shoulder_weights.py "
              f"({', '.join(SPECIES)}); no se hace nada")
        return
    arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH" and o.find_armature() == arm]
    height = _height(meshes)
    stamp = json.dumps({"version": VERSION, **cfg, "up": [UP_FULL, UP_NONE]}, sort_keys=True)
    changed_any = False
    for o in meshes:
        if o.get("shoulder_blend") and not FORCE:
            print(f"{SPECIES_NAME}: {o.name} ya mezclado ({o['shoulder_blend']}); usa --force para rehacerlo")
            continue
        backup = json.loads(o.get("shoulder_blend_orig", "{}"))
        if backup and not DRY:  # --force: vuelve a los pesos originales antes de rehacer
            for i, ws in backup.items():
                _write(o, int(i), ws)
        elif backup and DRY:
            print(f"{SPECIES_NAME}: {o.name} (en seco: se parte de los pesos ya mezclados)")
        old, new, report = blend(o, arm, cfg, height)
        for side, r in sorted(report.items()):
            pit = (f"axila {r['pit']} verts, brazo medio {r['pit_before'] / r['pit']:.2f} -> "
                   f"{r['pit_after'] / r['pit']:.2f}") if r["pit"] else "axila sin vértices"
            print(f"{SPECIES_NAME}: {o.name} lado {side}: {r['n']} vértices; brazo medio {r['before'] / r['n']:.2f} -> "
                  f"{r['after'] / r['n']:.2f}; {pit}; cambio máximo de un peso {r['max']:.3f}")
        if not new:
            print(f"{SPECIES_NAME}: {o.name} sin vértices cerca del hombro")
            continue
        if DRY:
            continue
        keep = {str(i): ws for i, ws in backup.items()} if backup else {}
        for i in new:
            keep.setdefault(str(i), old[i])
        for i, ws in new.items():
            _write(o, i, ws)
        o["shoulder_blend_orig"] = json.dumps(keep)
        o["shoulder_blend"] = stamp
        changed_any = True
    if changed_any:
        bpy.ops.wm.save_mainfile()
        print(f"{SPECIES_NAME}: guardado")
    elif DRY:
        print(f"{SPECIES_NAME}: en seco, no se guarda nada")


main()

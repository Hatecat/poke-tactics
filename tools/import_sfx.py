#!/usr/bin/env python3
"""Copia una selección de efectos de los paquetes CC0 de Kenney (kenney.nl) a assets/audio/sfx
con nombres descriptivos. Cada efecto puede tener variantes (nombre_0.ogg, nombre_1.ogg...).

Uso: python3 tools/import_sfx.py <carpeta con los zips de Kenney descomprimidos>
Paquetes: impact-sounds, interface-sounds, rpg-audio, digital-audio, music-jingles, sci-fi-sounds.
"""
import shutil
import sys
from pathlib import Path

SFX = {
    # Interfaz
    "ui_click": ["interface-sounds/Audio/click_002.ogg"],
    "ui_hover": ["interface-sounds/Audio/tick_002.ogg"],
    "ui_confirm": ["interface-sounds/Audio/confirmation_001.ogg"],
    "ui_back": ["interface-sounds/Audio/back_002.ogg"],
    "ui_error": ["interface-sounds/Audio/error_004.ogg"],
    "ui_place": ["interface-sounds/Audio/drop_002.ogg"],
    # Turnos
    "turn_player": ["digital-audio/Audio/pepSound1.ogg"],
    "turn_enemy": ["digital-audio/Audio/lowRandom.ogg"],
    # Pasos según el suelo
    "step_grass": [f"impact-sounds/Audio/footstep_grass_00{i}.ogg" for i in range(5)],
    "step_snow": [f"impact-sounds/Audio/footstep_snow_00{i}.ogg" for i in range(5)],
    "step_stone": [f"impact-sounds/Audio/footstep_concrete_00{i}.ogg" for i in range(5)],
    "step_soft": [f"impact-sounds/Audio/footstep_carpet_00{i}.ogg" for i in range(5)],
    "step_water": ["sci-fi-sounds/Audio/slime_000.ogg", "sci-fi-sounds/Audio/slime_001.ogg"],
    # Golpes
    "hit_punch": [f"impact-sounds/Audio/impactPunch_medium_00{i}.ogg" for i in range(5)],
    "hit_heavy": [f"impact-sounds/Audio/impactPunch_heavy_00{i}.ogg" for i in range(5)],
    "hit_soft": [f"impact-sounds/Audio/impactSoft_medium_00{i}.ogg" for i in range(5)],
    "hit_rock": [f"impact-sounds/Audio/impactMining_00{i}.ogg" for i in range(5)],
    "hit_metal": [f"impact-sounds/Audio/impactMetal_heavy_00{i}.ogg" for i in range(5)],
    "hit_glass": [f"impact-sounds/Audio/impactGlass_medium_00{i}.ogg" for i in range(5)],
    "hit_wood": [f"impact-sounds/Audio/impactPlank_medium_00{i}.ogg" for i in range(5)],
    "hit_bell": [f"impact-sounds/Audio/impactBell_heavy_00{i}.ogg" for i in range(5)],
    "hit_zap": ["digital-audio/Audio/zap1.ogg", "digital-audio/Audio/zap2.ogg", "digital-audio/Audio/zapTwoTone.ogg"],
    "hit_fire": [f"sci-fi-sounds/Audio/thrusterFire_00{i}.ogg" for i in range(3)],
    "hit_slime": ["sci-fi-sounds/Audio/slime_000.ogg", "sci-fi-sounds/Audio/slime_001.ogg"],
    "hit_psychic": ["digital-audio/Audio/phaserDown1.ogg", "digital-audio/Audio/phaserDown2.ogg"],
    "hit_shadow": ["digital-audio/Audio/lowDown.ogg"],
    "hit_wind": ["rpg-audio/Audio/cloth1.ogg", "rpg-audio/Audio/cloth2.ogg", "rpg-audio/Audio/cloth3.ogg"],
    "explosion": [f"sci-fi-sounds/Audio/explosionCrunch_00{i}.ogg" for i in range(3)],
    # Lanzamientos
    "launch_projectile": [f"sci-fi-sounds/Audio/laserSmall_00{i}.ogg" for i in range(5)],
    "launch_beam": [f"sci-fi-sounds/Audio/laserLarge_00{i}.ogg" for i in range(3)],
    "launch_special": ["digital-audio/Audio/phaserUp1.ogg", "digital-audio/Audio/phaserUp3.ogg"],
    "miss": ["rpg-audio/Audio/knifeSlice.ogg", "rpg-audio/Audio/knifeSlice2.ogg"],
    # Efectos
    "faint": ["digital-audio/Audio/phaserDown3.ogg"],
    "heal": ["digital-audio/Audio/powerUp2.ogg"],
    "buff": ["digital-audio/Audio/zapThreeToneUp.ogg"],
    "debuff": ["digital-audio/Audio/zapThreeToneDown.ogg"],
    "status": ["digital-audio/Audio/threeTone1.ogg", "digital-audio/Audio/twoTone1.ogg"],
    "protect": [f"sci-fi-sounds/Audio/forceField_00{i}.ogg" for i in range(3)],
    "trap": [f"impact-sounds/Audio/impactMetal_light_00{i}.ogg" for i in range(3)],
    "weather": ["digital-audio/Audio/highUp.ogg"],
    # Fanfarrias
    "victory": ["music-jingles/Audio/8-Bit jingles/jingles_NES12.ogg"],
    "defeat": ["music-jingles/Audio/8-Bit jingles/jingles_NES11.ogg"],
}


def main():
    src = Path(sys.argv[1])
    dest = Path(__file__).resolve().parent.parent / "assets/audio/sfx"
    dest.mkdir(parents=True, exist_ok=True)
    count = 0
    for name, files in SFX.items():
        for i, f in enumerate(files):
            shutil.copyfile(src / f, dest / f"{name}_{i}.ogg")
            count += 1
    shutil.copyfile(src / "impact-sounds/License.txt", dest / "LICENSE_kenney_CC0.txt")
    print(f"{count} archivos en {dest}")


if __name__ == "__main__":
    main()

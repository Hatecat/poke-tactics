"""Ajusta el color de las texturas de los Pokémon para la luz del tablero.

    python3 tools/tune_textures.py            # todas
    python3 tools/tune_textures.py eevee abra  # solo esas especies

Los rips vienen de juegos cuyo shader satura y tiñe el color; con la luz normal del juego salen desteñidos (Charmander
melocotón) y, como el sol del tablero llega a energía 1,5, un albedo claro y saturado pasa de 1 en el rojo: el canal
se recorta y los naranjas viran a amarillo (Charizard amarillo, Pidgey dorado). Subir la saturación igual en todo
(lo que hacía `Unit._vivid_materials`) tampoco servía: los colores ya fuertes se pasaban (Eevee rojo, Abra limón).

Aquí cada píxel se ajusta según su propia saturación: los pálidos suben hacia un color franco, los ya fuertes bajan
un poco, los grises y blancos no cambian; y los claros y saturados se oscurecen algo para que la luz no los queme.
`TUNE` corrige especies sueltas frente a sus colores oficiales (tono, saturación, brillo).

Escribe assets/models/pokemon/tuned/<archivo>.webp (los originales no se tocan) y su .import; después hay que
importar en Godot (`godot --headless --path . --import`). `Unit._vivid_materials` usa la versión ajustada si existe.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

PROJECT = Path(__file__).resolve().parents[1]
SRC = PROJECT / "assets/models/pokemon"
OUT = SRC / "tuned"

# Saturación hacia la que van los colores (0-1, HSV) y cuánto se acercan (0 = nada, 1 = del todo).
SAT_TARGET = 0.74
SAT_PULL = 0.7
# Saturación por debajo de la cual un píxel se trata como gris o blanco y no se toca (rampa entre las dos).
GRAY_LO, GRAY_HI = 0.1, 0.38
# Oscurece los claros y saturados: brillo * (1 - EXPOSURE * saturación * brillo).
EXPOSURE = 0.24
CONTRAST = 1.05

# Por especie o por textura (el principio del nombre del archivo; gana el más largo): hue (grados que gira el tono),
# sat (saturación objetivo), pull, bright (multiplica el brillo), exposure (en vez de EXPOSURE), grow_dark (píxeles que
# engordan pupilas y párpados sobre el blanco del ojo).
# Referencia: los colores oficiales (artwork de Sugimori / Pokémon HOME).
TUNE = {
    # Crema pálido, no limón (solo el cuerpo: las llamas siguen naranjas).
    "ninetales": {"sat": 0.36, "pull": 0.8},
    "rapidash_pm0078_00_Body": {"sat": 0.3, "pull": 0.8},
    # La melena de Flareon es crema amarillento, no amarillo puro.
    "flareon_1": {"sat": 0.45, "pull": 0.9, "bright": 1.12},
    "flareon_Image_1": {"sat": 0.45, "pull": 0.9, "bright": 1.12},
    # El cuerpo de Flareon es naranja vivo, no marrón.
    "flareon": {"sat": 0.8, "bright": 1.3},
    # Las llamas de Ponyta (textura propia, con luz): naranja luminoso.
    "ponyta_1": {"sat": 0.85, "exposure": 0.0},
    "ponyta_Image_1": {"sat": 0.85, "exposure": 0.0},
    # Todo él es fuego: se queda luminoso.
    "moltres": {"exposure": 0.0},
    # Amarillos que quedaban chillones frente al artwork (amarillo dorado, no limón).
    "abra": {"sat": 0.6},
    "drowzee": {"sat": 0.6},
    "hypno": {"sat": 0.6},
    "electabuzz": {"sat": 0.62},
    # Roca gris media: con el sol del tablero la textura (gris claro) salía casi blanca.
    "geodude_pm0074_00_Body": {"bright": 0.72},
    "graveler_pm0075_00_Body": {"bright": 0.75},
    # Las pupilas de Magikarp (5 píxeles en la textura) desaparecían en el tablero.
    "magikarp_pm0129_00_Eye1": {"grow_dark": 3},
    # Eevee salía marrón chocolate: el castaño claro del artwork (algo más claro y menos saturado; el collar crema
    # apenas cambia).
    "eevee": {"sat": 0.6, "bright": 1.15},
    # El naranja de Growlithe tiraba a salmón: naranja franco, sin tocar la melena crema (BodyB1).
    "growlithe_pm0058_00_BodyA1": {"hue": 6, "sat": 0.82},
    # Cuerpo de Weezing: la textura es malva muy oscuro; el artwork es morado medio (el humo y la boca no cambian).
    "weezing_0": {"hue": -12, "sat": 0.45, "bright": 1.6},
    "weezing_Image_0": {"hue": -12, "sat": 0.45, "bright": 1.6},
    # Las texturas de Grimer y Muk son lavanda azulado: en los juegos el shader las tiñe de morado.
    "grimer": {"hue": 55, "bright": 0.68, "sat": 0.62},
    "muk": {"hue": 50, "bright": 0.72, "sat": 0.62},
}


def _rgb_to_hsv(rgb):
    mx = rgb.max(-1)
    mn = rgb.min(-1)
    d = mx - mn
    s = np.where(mx > 0, d / np.maximum(mx, 1e-6), 0.0)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    dd = np.maximum(d, 1e-6)
    h = np.where(mx == r, ((g - b) / dd) % 6, np.where(mx == g, (b - r) / dd + 2, (r - g) / dd + 4)) / 6.0
    h = np.where(d > 0, h, 0.0)
    return h, s, mx


def _hsv_to_rgb(h, s, v):
    i = np.floor(h * 6).astype(int) % 6
    f = h * 6 - np.floor(h * 6)
    p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    choices = [(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)]
    out = np.zeros(h.shape + (3,))
    for k, (r, g, b) in enumerate(choices):
        m = i == k
        out[m, 0], out[m, 1], out[m, 2] = r[m], g[m], b[m]
    return out


def _smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def _grow_dark(rgb, px):
    """Engorda `px` píxeles los trazos negros (pupilas, párpados) solo sobre el blanco del ojo: en las texturas
    pequeñas la pupila mide 5 píxeles y con los mipmaps del tablero se borraba."""
    lum = rgb.mean(-1)
    chroma = rgb.max(-1) - rgb.min(-1)
    ink = (lum < 0.25) & (chroma < 0.15)  # negro de verdad: no el borde marrón del iris
    white = (lum > 0.6) & (chroma < 0.25)
    near = ink.copy()
    for dy in range(-px, px + 1):
        for dx in range(-px, px + 1):
            if dx * dx + dy * dy <= px * px:
                near |= np.roll(np.roll(ink, dy, 0), dx, 1)
    tone = rgb[ink].mean(0) if ink.any() else np.array([0.08, 0.08, 0.1])
    return np.where((near & white)[..., None], tone, rgb)


def tune(img, opts):
    a = np.asarray(img.convert("RGBA")).astype(np.float64) / 255.0
    rgb, alpha = a[..., :3], a[..., 3:]
    h, s, v = _rgb_to_hsv(rgb)
    h = (h + opts.get("hue", 0) / 360.0) % 1.0
    w = _smoothstep(GRAY_LO, GRAY_HI, s) * opts.get("pull", SAT_PULL)
    s = np.clip(s + (opts.get("sat", SAT_TARGET) - s) * w, 0, 1)
    v = v * (1 - opts.get("exposure", EXPOSURE) * s * v) * opts.get("bright", 1.0)
    out = _hsv_to_rgb(h, s, np.clip(v, 0, 1))
    out = np.clip((out - 0.5) * CONTRAST + 0.5, 0, 1)
    if opts.get("grow_dark"):
        out = _grow_dark(out, opts["grow_dark"])
    return Image.fromarray((np.concatenate([out, alpha], -1) * 255 + 0.5).astype(np.uint8), "RGBA")


# Mismos ajustes de importación que las texturas originales (comprimidas en VRAM, con mipmaps).
IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=2
compress/high_quality=false
compress/lossy_quality=0.7
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
process/fix_alpha_border=true
process/premult_alpha=false
process/size_limit=0
detect_3d/compress_to=0
"""


def species_of(path):
    return path.stem.split("_")[0]


def options_for(path):
    keys = [k for k in TUNE if path.stem.startswith(k)]
    return TUNE[max(keys, key=len)] if keys else {}


def main():
    wanted = set(sys.argv[1:])
    OUT.mkdir(exist_ok=True)
    done = 0
    for src in sorted(SRC.glob("*.webp")):
        sp = species_of(src)
        if wanted and sp not in wanted:
            continue
        dst = OUT / src.name
        tune(Image.open(src), options_for(src)).save(dst, quality=92, method=6)
        imp = dst.with_name(dst.name + ".import")
        if not imp.exists():
            imp.write_text(IMPORT)
        done += 1
    print(f"{done} texturas ajustadas en {OUT.relative_to(PROJECT)}")


if __name__ == "__main__":
    main()

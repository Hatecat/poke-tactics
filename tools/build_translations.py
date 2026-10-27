#!/usr/bin/env python3
"""Actualiza las traducciones de los datos (formato gettext) a partir de data/ y de PokeAPI.

Cada tema tiene su carpeta en locale/ con una plantilla <tema>.pot (los textos en español) y un <idioma>.po por
idioma, para que cada quien traduzca un tema sin chocar con los demás:

    locale/ataques/      nombres y descripciones de los ataques (data/moves)
    locale/objetos/      nombres y descripciones de los objetos (data/items)
    locale/habilidades/  nombres y descripciones de las habilidades (data/abilities.json)

La clave (msgid) es el texto en español tal como está en data/; el juego traduce con tr(texto).
Al ejecutarlo se rehace la plantilla y se fusiona cada .po: lo ya traducido se conserva, los textos nuevos se
rellenan con PokeAPI cuando lo tiene en ese idioma, y los que ya no existen se quitan. Hay que ejecutarlo después
de build_data.py o build_items.py.

Uso:
    python3 tools/build_translations.py <dir_datos>              # actualiza todos los .po que haya
    python3 tools/build_translations.py <dir_datos> --nuevo fr   # crea además fr.po en cada tema

<dir_datos> es el mismo de build_data.py (move_names.csv, move_flavor_text.csv, item_*.csv, ability_*.csv).
"""
import argparse
import csv
import json
import re
from pathlib import Path

import po

PROJECT = Path(__file__).resolve().parent.parent
LOCALE = PROJECT / "locale"
SPANISH = 7
# Idiomas de PokeAPI (language_id) con el código que usa Godot.
POKEAPI_LANGS = {"en": 9, "fr": 5, "de": 6, "it": 8, "ja": 11, "ko": 3, "zh_TW": 4, "zh_CN": 12}

# Textos propios del juego, que PokeAPI no tiene: {idioma: {español: traducción}}.
MANUAL = {
    "en": {
        "Garra ligera y afilada. Al terminar cada turno, el Pokémon que la lleva tiene un 20 % de probabilidad de que su siguiente turno llegue antes (casi un tercio de turno).":
            "A light, sharp claw. At the end of each turn, the holder has a 20% chance that its next turn comes sooner (almost a third of a turn).",
        "Salta y salpica sin ningún efecto. Así es Magikarp.": "It just flops and splashes around to no effect. That's Magikarp for you.",
        "Ataque desesperado que solo se usa cuando no queda otro.": "A desperate attack, used only when nothing else is left.",
        "Se teletransporta a una casilla libre, sin importar obstáculos ni desniveles.":
            "Teleports to any free tile, ignoring obstacles and height differences.",
        "Se transforma en el Pokémon objetivo: copia su aspecto, tipos, stats (salvo los PS), cambios de stats, habilidad y ataques.":
            "Transforms into the target Pokémon: copies its look, types, stats (except HP), stat changes, ability and moves.",
        "Roseli Berry": "Roseli Berry",
    },
}


def load_csv(path):
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def clean(text):
    return " ".join(text.split())


def latest(rows, key, text_field, lang_field, lang):
    """{id: texto} en un idioma, de la versión más reciente."""
    out, best = {}, {}
    for r in rows:
        if int(r[lang_field]) != lang:
            continue
        vg = int(r.get("version_group_id", 0))
        if vg >= best.get(r[key], -1):
            best[r[key]] = vg
            out[r[key]] = clean(r[text_field])
    return out


def pokeapi(src, lang):
    """Pares español → idioma de los nombres y descripciones de ataques, objetos y habilidades."""
    found = {}
    for prefix in ("move", "item", "ability"):
        for file, field, lang_field in ((f"{prefix}_names.csv", "name", "local_language_id"),
                                        (f"{prefix}_flavor_text.csv", "flavor_text", "language_id")):
            rows = load_csv(src / file)
            es = latest(rows, f"{prefix}_id", field, lang_field, SPANISH)
            other = latest(rows, f"{prefix}_id", field, lang_field, lang)
            for rid, text in es.items():
                if rid in other:
                    found.setdefault(text, other[rid])
    return found


# --- Textos de los datos ---------------------------------------------------------

def tres_entries(folder, fields):
    """[(texto, referencia, nota)] de los campos de texto de cada .tres."""
    out = []
    for path in sorted(folder.glob("*.tres")):
        for line in path.read_text(encoding="utf-8").splitlines():
            m = re.match(r'(\w+) = (".*")$', line)
            if m and m.group(1) in fields:
                text = json.loads(m.group(2))
                if text:
                    out.append((text, f"data/{folder.name}/{path.name}", fields[m.group(1)]))
    return out


def ability_entries():
    out = []
    for aid, a in json.loads((PROJECT / "data/abilities.json").read_text(encoding="utf-8")).items():
        for field, note in (("name", "nombre"), ("desc", "descripción")):
            if a.get(field):
                out.append((a[field], f"data/abilities.json:{aid}", note))
    return out


THEMES = {
    "ataques": lambda: tres_entries(PROJECT / "data/moves", {"display_name": "nombre", "flavor": "descripción"}),
    "objetos": lambda: tres_entries(PROJECT / "data/items", {"display_name": "nombre", "description": "descripción"}),
    "habilidades": ability_entries,
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src", type=Path)
    ap.add_argument("--nuevo", action="append", default=[], help="crea el .po de este idioma (código de Godot, p. ej. fr)")
    args = ap.parse_args()
    filled = {}

    def fill(lang):
        if lang not in filled:
            filled[lang] = dict(pokeapi(args.src, POKEAPI_LANGS[lang])) if lang in POKEAPI_LANGS else {}
            filled[lang].update(MANUAL.get(lang, {}))
        return filled[lang]

    for theme, collect in THEMES.items():
        folder = LOCALE / theme
        folder.mkdir(parents=True, exist_ok=True)
        entries = {}
        for text, ref, note in collect():
            e = entries.setdefault(text, {"id": text, "plural": None, "refs": [], "notes": []})
            e["refs"].append(ref)
            if note not in e["notes"]:
                e["notes"].append(note)
        for lang in args.nuevo:
            if not (folder / f"{lang}.po").exists():
                po.write(folder / f"{lang}.po", lang, [], {})
        for lang, n in po.merge(folder, theme, list(entries.values()), fill).items():
            print(f"locale/{theme}/{lang}.po: {len(entries)} textos, {n} sin traducir")

if __name__ == "__main__":
    main()

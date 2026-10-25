#!/usr/bin/env python3
"""Genera data/items/*.tres (ItemData) a partir de un catálogo curado. Nombres y descripciones
en español de PokeAPI (items.csv, item_names.csv, item_flavor_text.csv); sprites de PokeAPI/sprites.

Uso: python3 tools/build_items.py <dir_datos> [--sprites]
La lógica de cada efecto está en scripts/battle/items.gd.
"""
import argparse
import csv
import json
import subprocess
import time
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent
OUT = PROJECT / "data/items"
SPRITES = PROJECT / "assets/items"
SPANISH = "7"
SPRITE_URL = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/items/{}.png"
TYPES = ["normal", "fire", "water", "electric", "grass", "ice", "fighting", "poison", "ground",
         "flying", "psychic", "bug", "rock", "ghost", "dragon", "dark", "steel", "fairy"]

# categoría: 0 baya, 1 equipable, 2 piedra evolutiva. rareza: 0 común, 1 poco común, 2 rara.
# (identificador de PokeAPI, categoría, efecto, parámetros, potencia de Lanzamiento, rareza)
CATALOG = [
    ("oran-berry", 0, "heal_flat", {"amount": 10, "threshold": 0.5}, 10, 0),
    ("sitrus-berry", 0, "heal_frac", {"amount": 0.25, "threshold": 0.5}, 10, 0),
    ("lum-berry", 0, "cure", {"status": "all"}, 10, 1),
    ("cheri-berry", 0, "cure", {"status": "par"}, 10, 0),
    ("chesto-berry", 0, "cure", {"status": "slp"}, 10, 0),
    ("pecha-berry", 0, "cure", {"status": "psn"}, 10, 0),
    ("rawst-berry", 0, "cure", {"status": "brn"}, 10, 0),
    ("aspear-berry", 0, "cure", {"status": "frz"}, 10, 0),
    ("persim-berry", 0, "cure", {"status": "confusion"}, 10, 0),
    ("leppa-berry", 0, "pp", {"amount": 2}, 10, 0),
    ("liechi-berry", 0, "pinch", {"stat": "attack"}, 10, 1),
    ("ganlon-berry", 0, "pinch", {"stat": "defense"}, 10, 1),
    ("salac-berry", 0, "pinch", {"stat": "speed"}, 10, 1),
    ("petaya-berry", 0, "pinch", {"stat": "sp_attack"}, 10, 1),
    ("apicot-berry", 0, "pinch", {"stat": "sp_defense"}, 10, 1),
]
RESIST_BERRIES = {
    "chilan-berry": "normal", "occa-berry": "fire", "passho-berry": "water", "wacan-berry": "electric",
    "rindo-berry": "grass", "yache-berry": "ice", "chople-berry": "fighting", "kebia-berry": "poison",
    "shuca-berry": "ground", "coba-berry": "flying", "payapa-berry": "psychic", "tanga-berry": "bug",
    "charti-berry": "rock", "kasib-berry": "ghost", "haban-berry": "dragon", "colbur-berry": "dark",
    "babiri-berry": "steel", "roseli-berry": "fairy",
}
CATALOG += [(k, 0, "resist", {"type": t}, 10, 1) for k, t in RESIST_BERRIES.items()]
CATALOG += [
    ("leftovers", 1, "leftovers", {}, 10, 1),
    ("black-sludge", 1, "black_sludge", {}, 30, 1),
    ("focus-sash", 1, "focus_sash", {}, 10, 1),
    ("focus-band", 1, "focus_band", {"chance": 0.1}, 10, 0),
    ("life-orb", 1, "life_orb", {"boost": 1.3, "cost": 0.1}, 30, 2),
    ("choice-band", 1, "choice", {"stat": "attack"}, 10, 2),
    ("choice-specs", 1, "choice", {"stat": "sp_attack"}, 10, 2),
    ("choice-scarf", 1, "choice", {"stat": "speed"}, 10, 2),
    ("expert-belt", 1, "expert_belt", {"boost": 1.2}, 10, 1),
    ("muscle-band", 1, "category_boost", {"category": 0, "boost": 1.1}, 10, 0),
    ("wise-glasses", 1, "category_boost", {"category": 1, "boost": 1.1}, 10, 0),
    ("scope-lens", 1, "crit", {"stages": 1}, 30, 1),
    ("quick-claw", 1, "quick_claw", {"chance": 0.2, "ct": 30}, 80, 1),
    ("kings-rock", 1, "flinch", {"chance": 10}, 30, 0),
    ("shell-bell", 1, "shell_bell", {"amount": 0.125}, 30, 0),
    ("rocky-helmet", 1, "rocky_helmet", {"amount": 1.0 / 6.0}, 60, 1),
    ("eviolite", 1, "eviolite", {}, 40, 1),
    ("assault-vest", 1, "assault_vest", {}, 80, 2),
    ("light-clay", 1, "light_clay", {"rounds": 8}, 30, 0),
    ("bright-powder", 1, "evasion", {"mult": 0.9}, 10, 0),
    ("wide-lens", 1, "accuracy", {"mult": 1.1}, 10, 0),
    ("big-root", 1, "big_root", {"mult": 1.3}, 10, 0),
    ("white-herb", 1, "white_herb", {}, 10, 0),
    ("mental-herb", 1, "mental_herb", {}, 10, 0),
    ("toxic-orb", 1, "status_orb", {"status": "psn"}, 30, 1),
    ("flame-orb", 1, "status_orb", {"status": "brn"}, 30, 1),
    ("air-balloon", 1, "air_balloon", {}, 10, 1),
    ("heavy-duty-boots", 1, "boots", {}, 80, 1),
    ("heat-rock", 1, "weather_rock", {"weather": 1}, 60, 0),
    ("damp-rock", 1, "weather_rock", {"weather": 2}, 60, 0),
    ("smooth-rock", 1, "weather_rock", {"weather": 3}, 10, 0),
    ("icy-rock", 1, "weather_rock", {"weather": 4}, 40, 0),
    ("everstone", 1, "everstone", {}, 30, 0),
]
TYPE_BOOSTERS = {
    "silk-scarf": "normal", "charcoal": "fire", "mystic-water": "water", "magnet": "electric",
    "miracle-seed": "grass", "never-melt-ice": "ice", "black-belt": "fighting", "poison-barb": "poison",
    "soft-sand": "ground", "sharp-beak": "flying", "twisted-spoon": "psychic", "silver-powder": "bug",
    "hard-stone": "rock", "spell-tag": "ghost", "dragon-fang": "dragon", "black-glasses": "dark",
    "metal-coat": "steel", "fairy-feather": "fairy",
}
CATALOG += [(k, 1, "type_boost", {"type": t, "boost": 1.2}, 30, 0) for k, t in TYPE_BOOSTERS.items()]
# Descripciones propias para los objetos cuyo efecto en el tablero no es el de los juegos.
DESCRIPTIONS = {
    "quick-claw": "Garra ligera y afilada. Al terminar cada turno, el Pokémon que la lleva tiene un 20 % de probabilidad de que su siguiente turno llegue antes (casi un tercio de turno).",
}
STONES = ["fire-stone", "water-stone", "thunder-stone", "leaf-stone", "moon-stone"]
CATALOG += [(k, 2, "evolution", {}, 30, 2) for k in STONES]


def load_csv(path):
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def gd_value(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, dict):
        return "{\n" + ",\n".join(f'"{k}": {gd_value(x)}' for k, x in v.items()) + "\n}" if v else "{}"
    return json.dumps(v, ensure_ascii=False)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src", type=Path)
    ap.add_argument("--sprites", action="store_true", help="descarga los sprites de PokeAPI")
    args = ap.parse_args()
    ids = {r["identifier"]: r["id"] for r in load_csv(args.src / "items.csv")}
    names = {r["item_id"]: r["name"] for r in load_csv(args.src / "item_names.csv") if r["local_language_id"] == SPANISH}
    flavor, best = {}, {}
    for r in load_csv(args.src / "item_flavor_text.csv"):
        if r["language_id"] == SPANISH and int(r["version_group_id"]) >= best.get(r["item_id"], -1):
            best[r["item_id"]] = int(r["version_group_id"])
            flavor[r["item_id"]] = " ".join(r["flavor_text"].split())
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("*.tres"):
        old.unlink()
    SPRITES.mkdir(parents=True, exist_ok=True)
    missing = []
    for ident, cat, effect, params, fling, rarity in CATALOG:
        pid = ids.get(ident)
        item_id = ident.replace("-", "")
        fields = {
            "id": item_id, "display_name": names.get(pid, ident.replace("-", " ").title()),
            "description": DESCRIPTIONS.get(ident, flavor.get(pid, "")), "category": cat, "effect": effect, "params": params,
            "fling_power": fling, "rarity": rarity,
        }
        lines = ['[gd_resource type="Resource" script_class="ItemData" format=3]', "",
                 '[ext_resource type="Script" path="res://scripts/data/item_data.gd" id="1_script"]', ""]
        sprite = SPRITES / f"{item_id}.png"
        if args.sprites and not sprite.exists():
            for _ in range(4):
                r = subprocess.run(["curl", "-fsSL", "-o", str(sprite), SPRITE_URL.format(ident)], capture_output=True)
                if r.returncode == 0:
                    break
                time.sleep(1)
        if sprite.exists():
            lines.insert(3, f'[ext_resource type="Texture2D" path="res://assets/items/{item_id}.png" id="2_icon"]')
            fields_icon = 'icon = ExtResource("2_icon")'
        else:
            fields_icon = None
            missing.append(ident)
        lines += ["[resource]", 'script = ExtResource("1_script")']
        lines += [f"{k} = {gd_value(v)}" for k, v in fields.items()]
        if fields_icon:
            lines.append(fields_icon)
        (OUT / f"{item_id}.tres").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"{len(CATALOG)} objetos")
    if missing:
        print("Sin sprite:", ", ".join(missing))


if __name__ == "__main__":
    main()

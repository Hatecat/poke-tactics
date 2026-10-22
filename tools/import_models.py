#!/usr/bin/env python3
"""Copia modelos numerados (1.glb, 2.glb...) ya convertidos sin Draco a
assets/models/pokemon/<id>.glb usando los ids de Showdown (bulbasaur, mrmime...).

Uso: python3 tools/import_models.py <dir_glb> <dir_datos> [--max-dex 151]
"""
import argparse
import json
import shutil
from pathlib import Path

ap = argparse.ArgumentParser()
ap.add_argument("models", type=Path)
ap.add_argument("src", type=Path)
ap.add_argument("--max-dex", type=int, default=151)
args = ap.parse_args()
dex = json.loads((args.src / "pokedex.json").read_text(encoding="utf-8"))
dest = Path(__file__).resolve().parent.parent / "assets/models/pokemon"
dest.mkdir(parents=True, exist_ok=True)
copied = 0
for pid, mon in dex.items():
    n = mon.get("num", 0)
    if 1 <= n <= args.max_dex and not mon.get("forme") and not mon.get("baseSpecies"):
        src = args.models / f"{n}.glb"
        if src.exists():
            shutil.copyfile(src, dest / f"{pid}.glb")
            copied += 1
print(f"{copied} modelos copiados a {dest}")

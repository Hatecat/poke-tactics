#!/usr/bin/env python3
"""Rellena anim_variant en data/moves/*.tres con las reglas de build_data.anim_variant,
sin regenerar los ataques (respeta los retoques a mano del resto de campos).

Uso:
    python3 tools/assign_anim_variants.py            # escribe los .tres
    python3 tools/assign_anim_variants.py --dry-run  # solo muestra el resumen

Un anim_variant puesto a mano (distinto de "") no se toca; con --force se recalculan todos.
"""
import argparse
import re
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_data import OUT_MOVES, anim_variant  # noqa: E402


def read_fields(text):
    """Los campos que usa anim_variant, leídos de un .tres generado por build_data."""
    def value(key):
        m = re.search(rf"^{key} = (.*)$", text, re.MULTILINE)
        return m.group(1) if m else ""
    return {
        "id": value("id").strip('"'),
        "animation": value("animation").strip('"'),
        "type": value("type").strip('"'),
        "category": int(value("category") or 0),
        "targets_self": value("targets_self") == "true",
        "flags": re.findall(r'"([^"]+)"', value("flags")),
        # Solo importa si está vacío: "{}" en una línea o "{" que abre varias.
        "self_stat_changes": value("self_stat_changes") != "{}",
        "stat_changes": value("stat_changes") != "{}",
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()

    by_variant = defaultdict(list)
    changed = 0
    for path in sorted(OUT_MOVES.glob("*.tres")):
        text = path.read_text(encoding="utf-8")
        current = re.search(r'^anim_variant = "([^"]*)"$', text, re.MULTILINE)
        if current and current.group(1) and not args.force:
            variant = current.group(1)
        else:
            variant = anim_variant(read_fields(text))
        mv_anim = read_fields(text)["animation"]
        by_variant[(mv_anim, variant)].append(path.stem)
        line = f'anim_variant = "{variant}"'
        if current:
            new = text[:current.start()] + line + text[current.end():]
        else:
            new = re.sub(r'^(animation = .*)$', rf"\1\n{line}", text, count=1, flags=re.MULTILINE)
        if new != text:
            changed += 1
            if not args.dry_run:
                path.write_text(new, encoding="utf-8")

    for (anim, variant), ids in sorted(by_variant.items()):
        print(f"{anim}_{variant or '(genérico)'}: {len(ids)}")
        print("   ", ", ".join(ids))
    print(f"{'Cambiarían' if args.dry_run else 'Actualizados'}: {changed} archivos")


if __name__ == "__main__":
    main()

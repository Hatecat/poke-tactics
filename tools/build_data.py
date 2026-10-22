#!/usr/bin/env python3
"""Genera data/moves/*.tres y data/pokemon/*.tres a partir de los datos de
Pokémon Showdown (stats, tipos, ataques, learnsets) y PokeAPI (nombres y
descripciones en español). Traduce cada ataque a reglas tácticas (alcance,
área, CT extra) de forma automática.

Uso:
    tools/fetch_data.sh <dir_datos>                    # descarga las fuentes
    python3 tools/build_data.py <dir_datos> [--max-dex 151]

Los .tres generados se pueden retocar a mano después, pero se sobrescriben
si se vuelve a ejecutar el script.
"""
import argparse
import csv
import json
import math
import re
import struct
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent
MODELS = PROJECT / "assets/models/pokemon"
OUT_MOVES = PROJECT / "data/moves"
OUT_POKEMON = PROJECT / "data/pokemon"

SPANISH = 7
STAT_KEYS = {"atk": "attack", "def": "defense", "spa": "sp_attack", "spd": "sp_defense", "spe": "speed"}
STATUS = {"psn": 1, "tox": 1, "slp": 2, "par": 3, "brn": 4, "frz": 5}
CATEGORY = {"Physical": 0, "Special": 1, "Status": 2}
SINGLE, CIRCLE, CROSS, LINE = range(4)
SPECIES_NAMES = {"nidoranf": "Nidoran♀", "nidoranm": "Nidoran♂", "farfetchd": "Farfetch'd"}

# Ataques que viajan en línea recta.
LINE_MOVES = {
    "icebeam", "hyperbeam", "solarbeam", "psybeam", "aurorabeam", "bubblebeam", "signalbeam",
    "chargebeam", "flamethrower", "hydropump", "flashcannon", "hydrocannon", "blastburn",
    "frenzyplant", "gigaimpact", "pinmissile", "razorleaf", "dragonpulse", "zapcannon",
    "steelbeam", "meteorbeam", "prismaticlaser", "dynamaxcannon", "eternabeam", "lusterpurge",
    "mistball", "originpulse", "hyperbeam", "triattack", "hornleech",
}
# Ataques que se lanzan lejos aunque sean de contacto (se abalanzan desde el aire).
SWOOP_MOVES = {"fly", "bounce", "skyattack", "dive", "dig", "phantomforce", "shadowforce"}
# Potencia variable en los juegos: se aproxima con un valor fijo.
DYNAMIC_POWER = {
    "lowkick": 60, "grassknot": 60, "heavyslam": 60, "heatcrash": 60, "flail": 60, "reversal": 60,
    "return": 80, "frustration": 80, "gyroball": 60, "electroball": 60, "present": 40,
    "magnitude": 70, "punishment": 60, "storedpower": 40, "powertrip": 40, "trumpcard": 60,
    "wringout": 60, "crushgrip": 60, "spitup": 60, "beatup": 40, "naturalgift": 60,
    "hiddenpower": 60, "acrobatics": 55, "assurance": 60, "avalanche": 60, "revenge": 60,
    "payback": 50, "pursuit": 40, "rollout": 30, "iceball": 30, "furycutter": 40, "echoedvoice": 40,
    "weatherball": 50, "terrainpulse": 50, "eruption": 100, "waterspout": 100, "dragonenergy": 100,
}
UNSUPPORTED = {
    "counter", "mirrorcoat", "metalburst", "bide", "endeavor", "finalgambit", "superfang",
    "naturesmadness", "ruination", "fling", "transform", "metronome", "mimic", "mirrormove",
    "sketch", "copycat", "assist", "sleeptalk", "snore", "focuspunch", "belch", "lastresort",
    "dreameater", "futuresight", "doomdesire", "struggle", "splash", "celebrate", "holdhands",
}
FIXED_DAMAGE = {"psywave": 50}
SOUND_STATUS_AREA = 2
# Un combate táctico dura muchos menos turnos que uno de los juegos: PP reales / 5.
PP_DIVISOR = 5


def frac(pair):
    return round(pair[0] / pair[1], 3)


def load_csv(path):
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def spanish_texts(src):
    names, flavor = {}, {}
    for row in load_csv(src / "move_names.csv"):
        if int(row["local_language_id"]) == SPANISH:
            names[int(row["move_id"])] = row["name"]
    best = {}
    for row in load_csv(src / "move_flavor_text.csv"):
        if int(row["language_id"]) == SPANISH:
            mid, vg = int(row["move_id"]), int(row["version_group_id"])
            if vg >= best.get(mid, -1):
                best[mid] = vg
                flavor[mid] = " ".join(row["flavor_text"].split())
    return names, flavor


def secondaries(m):
    if m.get("secondaries"):
        return m["secondaries"]
    return [m["secondary"]] if m.get("secondary") else []


def convert_move(mid, m, names, flavor):
    """Devuelve un dict con los campos de MoveData, o None si el ataque no se puede representar."""
    if mid in UNSUPPORTED or m.get("ohko") or m.get("isZ") or m.get("isMax"):
        return None
    if m.get("isNonstandard") in ("CAP", "LGPE", "Custom", "Unobtainable", "Gigantamax"):
        return None
    cat = CATEGORY[m["category"]]
    target = m["target"]
    flags = m.get("flags", {})
    mv = {
        "id": mid, "display_name": names.get(m["num"], m["name"]), "flavor": flavor.get(m["num"], ""),
        "type": m["type"].lower(), "category": cat, "power": m.get("basePower", 0),
        "accuracy": 100 if m["accuracy"] is True else m["accuracy"],
        "range_min": 1, "range_max": 1, "area_shape": SINGLE, "area_size": 0,
        "projectile": False, "targets_self": False, "status": 0, "status_chance": 0,
        "knockback": 0, "drain": 0.0, "heal": 0.0, "recoil": 0.0, "fixed_damage": 0,
        "self_ko": False, "stat_changes": {}, "stat_chance": 100, "self_stat_changes": {},
        "extra_ct": 0, "pp": max(1, math.ceil(m.get("pp", 5) / PP_DIVISOR)),
        "animation": "fight_d" if cat == 1 else "fight_b",
    }
    if mv["type"] in ("???", "stellar"):
        return None

    # Daño
    if cat != 2:
        if isinstance(m.get("damage"), int):
            mv["fixed_damage"] = m["damage"]
        elif m.get("damage") == "level":
            mv["fixed_damage"] = 50
        elif mid in FIXED_DAMAGE:
            mv["fixed_damage"] = FIXED_DAMAGE[mid]
        elif mv["power"] <= 1:
            if mid not in DYNAMIC_POWER:
                return None
            mv["power"] = DYNAMIC_POWER[mid]
        hits = m.get("multihit")
        if isinstance(hits, list):
            mv["power"] *= 3 if hits[1] >= 5 else hits[1]
        elif isinstance(hits, int):
            mv["power"] *= hits
    mv["drain"] = frac(m["drain"]) if m.get("drain") else 0.0
    mv["recoil"] = frac(m["recoil"]) if m.get("recoil") else 0.0
    mv["heal"] = frac(m["heal"]) if m.get("heal") else 0.0
    if mid == "rest":
        mv["heal"], mv["extra_ct"] = 1.0, 100
    mv["self_ko"] = m.get("selfdestruct") == "always"

    # Estados y stats
    if m.get("status") in STATUS:
        mv["status"], mv["status_chance"] = STATUS[m["status"]], 100
    for sec in secondaries(m):
        if sec.get("status") in STATUS and not mv["status"]:
            mv["status"], mv["status_chance"] = STATUS[sec["status"]], sec.get("chance", 100)
        if sec.get("boosts"):
            mv["stat_changes"] = {STAT_KEYS[k]: v for k, v in sec["boosts"].items() if k in STAT_KEYS}
            mv["stat_chance"] = sec.get("chance", 100)
        if sec.get("self", {}).get("boosts"):
            mv["self_stat_changes"] = {STAT_KEYS[k]: v for k, v in sec["self"]["boosts"].items() if k in STAT_KEYS}
    if m.get("self", {}).get("boosts"):
        mv["self_stat_changes"] = {STAT_KEYS[k]: v for k, v in m["self"]["boosts"].items() if k in STAT_KEYS}
    self_target = target in ("self", "allySide", "allies", "adjacentAllyOrSelf", "allyTeam", "adjacentAlly")
    if m.get("boosts"):
        boosts = {STAT_KEYS[k]: v for k, v in m["boosts"].items() if k in STAT_KEYS}
        if self_target:
            mv["self_stat_changes"] = boosts
        else:
            mv["stat_changes"] = boosts
    if m.get("forceSwitch") or m.get("selfSwitch") == "copyvolatile" or mid in ("dragontail", "circlethrow"):
        mv["knockback"] = 3
    elif flags.get("wind") and cat != 2:
        mv["knockback"] = 1

    # Turno
    if flags.get("recharge"):
        mv["extra_ct"] = 50
    elif flags.get("charge"):
        mv["extra_ct"] = 30

    # Alcance y área
    big = mv["power"] >= 90
    if self_target:
        if not (mv["heal"] or mv["self_stat_changes"]):
            return None
        mv.update(range_min=0, range_max=0, targets_self=True)
    elif target in ("allAdjacentFoes", "allAdjacent"):
        mv.update(range_min=0, range_max=0, area_shape=CIRCLE, area_size=2 if big else 1)
    elif target in ("all", "foeSide", "scripted", "allySide"):
        if cat == 2:
            return None
        mv.update(range_min=0, range_max=0, area_shape=CIRCLE, area_size=2)
    elif cat == 2:
        if flags.get("powder"):
            mv.update(range_min=1, range_max=2, area_shape=CIRCLE, area_size=1)
        elif flags.get("sound"):
            mv.update(range_min=0, range_max=0, area_shape=CIRCLE, area_size=SOUND_STATUS_AREA)
        else:
            mv.update(range_min=1, range_max=3)
    elif mid in SWOOP_MOVES:
        mv.update(range_min=1, range_max=4)
    elif mid in LINE_MOVES:
        mv.update(range_min=1, range_max=4 if big else 3, area_shape=LINE, area_size=4 if big else 3)
    elif flags.get("contact"):
        mv.update(range_min=1, range_max=1)
    elif flags.get("bullet") or "bomb" in mid:
        if big or mv["power"] >= 80:
            mv.update(range_min=2, range_max=4, area_shape=CIRCLE, area_size=1)
        else:
            mv.update(range_min=1, range_max=3)
    elif flags.get("sound"):
        mv.update(range_min=1, range_max=2, area_shape=CIRCLE, area_size=1)
    elif target == "any":
        mv.update(range_min=1, range_max=4)
    elif cat == 1:
        mv.update(range_min=1, range_max=3)
    else:
        mv.update(range_min=1, range_max=2)

    # Proyectil: sale disparado en línea recta y choca con el primer obstáculo o Pokémon.
    mv["projectile"] = (not mv["targets_self"] and mv["area_shape"] != LINE and mv["range_min"] >= 1
                        and mv["range_max"] >= 2 and not flags.get("contact") and mid not in SWOOP_MOVES
                        and not flags.get("sound") and not flags.get("powder"))

    if cat == 2 and not (mv["status"] or mv["stat_changes"] or mv["self_stat_changes"] or mv["heal"] or mv["knockback"]):
        return None
    if cat == 2:
        mv["animation"] = "fight_d"
    return mv


def gd_value(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, float):
        return repr(v)
    if isinstance(v, int):
        return str(v)
    if isinstance(v, dict):
        if not v:
            return "{}"
        return "{\n" + ",\n".join(f'"{k}": {gd_value(x)}' for k, x in v.items()) + "\n}"
    return json.dumps(v, ensure_ascii=False)


def write_move(mv):
    lines = [
        '[gd_resource type="Resource" script_class="MoveData" format=3]', "",
        '[ext_resource type="Script" path="res://scripts/data/move_data.gd" id="1_script"]', "",
        "[resource]", 'script = ExtResource("1_script")',
    ]
    lines += [f"{k} = {gd_value(v)}" for k, v in mv.items()]
    (OUT_MOVES / f"{mv['id']}.tres").write_text("\n".join(lines) + "\n", encoding="utf-8")


def glb_animations(path):
    with open(path, "rb") as f:
        f.read(12)
        length = struct.unpack("<I", f.read(4))[0]
        f.read(4)
        gltf = json.loads(f.read(length))
    return [a.get("name", "") for a in gltf.get("animations", [])]


## Sinónimos de cada acción en los distintos rips. El juego busca la clave por subcadena,
## así que solo hace falta mapear cuando el clip se llama distinto.
ANIM_SYNONYMS = {
    "idle": ["battlewait01_loop", "defaultwait01_loop", "aidle", "wait"],
    "walk": ["walk01_loop", "walk", "run"],
    "fight_b": ["attack01", "fight_b"],
    "fight_d": ["rangeattack01", "fight_d", "impactrueno"],
    "hit": ["damage01", "dizzy"],
    "ko": ["down01_start", "ko"],
}


def anim_map(clips):
    """Elige el clip de cada acción comparando el nombre corto del clip (sin prefijos
    'Armature|' ni 'pm0149_00_00_20400_') con la lista de sinónimos, en orden."""
    short = {c: re.sub(r"^pm\d+(_\d+)*_", "", re.sub(r"^.*\|", "", c)).lower() for c in clips}
    result = {}
    for key, options in ANIM_SYNONYMS.items():
        for opt in options:
            hit = next((c for c in clips if short[c] == opt
                        or (short[c].endswith(opt) and not short[c][: -len(opt)][-1:].isalpha())), None)
            if hit:
                if key not in hit.lower():
                    # Godot quita al importar los sufijos "_loop"/"-cycle" (los toma como "en bucle").
                    clip = re.sub(r"^.*\|", "", hit)
                    result[key] = re.sub(r"[-_](loop|cycle)$", "", clip, flags=re.IGNORECASE)
                break
    return result


def pick_default_moves(mon, learnable):
    """4 ataques razonables: el mejor STAB, cobertura, un ataque de estado útil y relleno."""
    types = [t.lower() for t in mon["types"]]
    better_physical = mon["baseStats"]["atk"] >= mon["baseStats"]["spa"]

    def score(mv):
        if mv["category"] == 2:
            return 0
        power = mv["fixed_damage"] or min(mv["power"], 120)
        s = power * mv["accuracy"] / 100.0
        s *= 1.5 if mv["type"] in types else 1.0
        s *= 1.15 if (mv["category"] == 0) == better_physical else 0.85
        s *= 0.75 if mv["extra_ct"] else 1.0
        s *= 0.6 if mv["self_ko"] else 1.0
        return s

    damaging = sorted((m for m in learnable if m["category"] != 2), key=score, reverse=True)
    chosen = []
    if damaging:
        chosen.append(damaging[0])
        for m in damaging[1:]:
            if m["type"] not in {c["type"] for c in chosen}:
                chosen.append(m)
                break
    status = [m for m in learnable if m["category"] == 2 and m not in chosen]
    status.sort(key=lambda m: (bool(m["self_stat_changes"]) or m["status"] in (2, 3)) * 2 + bool(m["heal"]), reverse=True)
    if status:
        chosen.append(status[0])
    for m in damaging:
        if len(chosen) >= 4:
            break
        if m not in chosen:
            chosen.append(m)
    return chosen[:4]


def write_pokemon(pid, mon, default, learnset, anims):
    moves_ids = {m["id"] for m in default} | {m["id"] for m in learnset}
    ext = ['[ext_resource type="PackedScene" path="res://assets/models/pokemon/%s.glb" id="1_model"]' % pid,
           '[ext_resource type="Script" path="res://scripts/data/move_data.gd" id="2_move"]',
           '[ext_resource type="Script" path="res://scripts/data/pokemon_data.gd" id="3_script"]']
    ref = {}
    for i, mid in enumerate(sorted(moves_ids)):
        ref[mid] = f"m{i}"
        ext.append(f'[ext_resource type="Resource" path="res://data/moves/{mid}.tres" id="m{i}"]')
    st = mon["baseStats"]
    types = [t.lower() for t in mon["types"]]
    height, weight = mon["heightm"], mon["weightkg"]
    flies = "flying" in types or "Levitate" in mon["abilities"].values()
    size = 3 if height >= 5.0 else (2 if height >= 1.6 or weight >= 150 else 1)
    fields = {
        "id": pid, "species_name": SPECIES_NAMES.get(pid, mon["name"]), "dex_number": mon["num"],
        "model_height": round(min(max(0.9 * math.sqrt(height / 0.7), 0.5), 2.4), 2),
        "base_hp": st["hp"], "base_attack": st["atk"], "base_defense": st["def"],
        "base_sp_attack": st["spa"], "base_sp_defense": st["spd"], "base_speed": st["spe"],
        "size": size, "move_modifier": 1 if flies else (-1 if weight >= 200 or size >= 2 and weight >= 80 else 0),
        "jump": 3 if flies else 1, "anim_map": anims,
    }
    lines = ['[gd_resource type="Resource" script_class="PokemonData" format=3]', "", *ext, "", "[resource]",
             'script = ExtResource("3_script")', 'model = ExtResource("1_model")',
             "types = PackedStringArray(%s)" % ", ".join(json.dumps(t) for t in types)]
    lines += [f"{k} = {gd_value(v)}" for k, v in fields.items()]
    arr = lambda ms: 'Array[ExtResource("2_move")]([%s])' % ", ".join(f'ExtResource("{ref[m["id"]]}")' for m in ms)
    lines.append("moves = " + arr(default))
    lines.append("learnset = " + arr(learnset))
    (OUT_POKEMON / f"{pid}.tres").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src", type=Path)
    ap.add_argument("--max-dex", type=int, default=151)
    args = ap.parse_args()
    dex = json.loads((args.src / "pokedex.json").read_text(encoding="utf-8"))
    learnsets = json.loads((args.src / "learnsets.json").read_text(encoding="utf-8"))
    moves = json.loads((args.src / "moves.json").read_text(encoding="utf-8"))
    names, flavor = spanish_texts(args.src)

    mons = {k: v for k, v in dex.items()
            if 1 <= v.get("num", 0) <= args.max_dex and not v.get("forme") and not v.get("baseSpecies")}
    struggle = convert_move("tackle", moves["tackle"], names, flavor)
    struggle.update(id="struggle", display_name="Forcejeo", power=50, recoil=0.25, knockback=0, pp=99,
                    flavor="Ataque desesperado que solo se usa cuando no queda otro.")
    converted = {"struggle": struggle}
    for mon in mons:
        for mid in learnsets.get(mon, {}).get("learnset", {}):
            if mid not in converted and mid in moves:
                mv = convert_move(mid, moves[mid], names, flavor)
                if mv:
                    converted[mid] = mv

    OUT_MOVES.mkdir(parents=True, exist_ok=True)
    OUT_POKEMON.mkdir(parents=True, exist_ok=True)
    for old in list(OUT_MOVES.glob("*.tres")) + list(OUT_POKEMON.glob("*.tres")):
        old.unlink()
    for mv in converted.values():
        write_move(mv)

    missing_models = []
    for pid, mon in sorted(mons.items(), key=lambda kv: kv[1]["num"]):
        model = MODELS / f"{pid}.glb"
        if not model.exists():
            missing_models.append(pid)
            continue
        learnable = [converted[m] for m in learnsets.get(pid, {}).get("learnset", {}) if m in converted]
        learnable.sort(key=lambda m: m["display_name"])
        default = pick_default_moves(mon, learnable) or [converted["struggle"]]
        if not learnable:
            learnable = [converted["struggle"]]
        write_pokemon(pid, mon, default, learnable, anim_map(glb_animations(model)))

    print(f"{len(converted)} ataques, {len(mons) - len(missing_models)} Pokémon")
    if missing_models:
        print("Sin modelo (omitidos):", ", ".join(missing_models), file=sys.stderr)


if __name__ == "__main__":
    main()

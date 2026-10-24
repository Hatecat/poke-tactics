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
STAT_KEYS = {"atk": "attack", "def": "defense", "spa": "sp_attack", "spd": "sp_defense", "spe": "speed",
             "accuracy": "accuracy", "evasion": "evasion"}
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
    "fling": 30,
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
    "naturesmadness", "ruination", "metronome", "mimic", "mirrormove",
    "sketch", "copycat", "assist", "sleeptalk", "snore", "focuspunch", "belch", "lastresort",
    "dreameater", "futuresight", "doomdesire", "struggle", "celebrate", "holdhands",
}
FIXED_DAMAGE = {"psywave": 50}
# Ataques con lógica propia en la batalla (MoveData.special): alcance mínimo y máximo.
# Teletransporte salta a una casilla libre; Transformación copia al Pokémon objetivo.
SPECIAL_MOVES = {"teleport": (1, 6), "transform": (1, 3), "splash": (0, 0)}
SPECIAL_FLAVOR = {
    "teleport": "Se teletransporta a una casilla libre, sin importar obstáculos ni desniveles.",
    "transform": "Se transforma en el Pokémon objetivo: copia su aspecto, tipos, stats (salvo los PS), "
                 "cambios de stats, habilidad y ataques.",
    "splash": "Salta y salpica sin ningún efecto. Así es Magikarp.",
}
# Ataques marcados como no obtenibles en los juegos actuales que sí queremos (clásicos de Kanto).
ALLOW_NONSTANDARD = {"cut", "burnup"}
# Clima que fija cada ataque (Weather.Kind: 1 sol, 2 lluvia, 3 arena, 4 granizo).
WEATHER_SETTERS = {"sunnyday": 1, "raindance": 2, "sandstorm": 3, "hail": 4, "snowscape": 4}
# Estados volátiles que el juego sabe aplicar al objetivo / al propio usuario.
TARGET_VOLATILES = {"confusion", "leechseed", "yawn", "taunt", "nightmare", "curse", "attract"}
SELF_VOLATILES = {"protect", "endure", "substitute", "ingrain", "aquaring", "destinybond", "charge", "magnetrise"}
# Efectos de campo: zonas alrededor del usuario, trampas en casillas y efectos globales.
ZONE_FIELDS = {"reflect", "lightscreen", "auroraveil", "safeguard", "mist", "tailwind"}
TRAP_FIELDS = {"spikes", "toxicspikes", "stealthrock"}
GLOBAL_FIELDS = {"electricterrain", "grassyterrain", "mistyterrain", "psychicterrain", "trickroom", "gravity"}
AREA_FIELDS = {"haze", "perishsong"}
MOVE_FLAGS = ("contact", "punch", "sound", "powder", "bite", "pulse", "wind")
# Ataques que interactúan con los objetos (ver scripts/battle/items.gd).
ITEM_MOVES = {
    "thief": "steal", "covet": "steal", "knockoff": "knockoff", "trick": "swap", "switcheroo": "swap",
    "bugbite": "eatberry", "pluck": "eatberry", "incinerate": "burnberry", "fling": "fling", "recycle": "recycle",
}
# Ataques cuyo efecto depende del clima (ver scripts/battle/weather.gd).
WEATHER_TAGS = {
    "weatherball": "weather_ball", "thunder": "storm", "hurricane": "storm", "blizzard": "blizzard",
    "solarbeam": "solar", "solarblade": "solar", "synthesis": "solar_heal", "moonlight": "solar_heal",
    "morningsun": "solar_heal", "growth": "growth",
}
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


## Variante de animación (MoveData.anim_variant): con qué parte del cuerpo se ataca.
## Se prueban en orden; gana la primera cuya palabra aparezca en el id del ataque.
## Los físicos que no encajan (Represalia, Finta...) usan el fight_b genérico.
PHYSICAL_VARIANTS = [
    ("wing", ("wingattack", "steelwing", "wingbeat", "fly", "bravebird", "skyattack", "acrobatics", "skydrop")),
    # Látigos: cola o lianas (Látigo Cepa usa el mismo clip que Cola Férrea).
    ("tail", ("tail", "whip")),
    ("kick", ("kick", "stomp", "sweep", "axel", "highhorsepower")),
    ("claw", ("claw", "slash", "scratch", "swipe", "cut", "scissor", "blade", "razorshell", "crosspoison",
              "crabhammer", "aerialace")),
    ("punch", ("chop", "slap", "pound", "lariat", "upperhand", "rocksmash", "brickbreak")),
    ("horn", ("horn", "peck", "drill", "jab", "sting", "needle", "pinmissile", "furyattack", "pluck", "smartstrike")),
]
## Embestidas: solo si el ataque es de contacto (Carámbano no es un placaje).
BODY_WORDS = ("tackle", "takedown", "doubleedge", "slam", "impact", "head", "rush", "charge", "wheel", "blitz",
              "extremespeed", "quickattack", "rollout", "iceball", "spin", "roller", "crash", "bodypress", "jet",
              "flipturn", "uturn", "lunge", "pounce", "outrage", "thrash", "struggle", "spark", "skullbash",
              "gyroball", "firstimpression", "woodhammer")
## Especiales que salen de la boca (fuego, agua, veneno, rayos...).
BREATH_WORDS = ("breath", "flame", "fire", "ember", "incinerate", "inferno", "overheat", "burn", "lava", "water",
                "hydro", "bubble", "scald", "pump", "spout", "octazooka", "brine", "sludge", "smog", "gas", "acid",
                "mud", "beam", "cannon", "powdersnow", "dragonrage", "spitup")


def anim_variant(mv):
    """Variante de animación del ataque (ver PHYSICAL_VARIANTS); "" = solo la genérica."""
    mid, flags = mv["id"], mv["flags"]
    if mv["animation"] == "fight_b":
        if "bite" in flags or "fang" in mid or mid in ("crunch", "bugbite", "leechlife", "lick"):
            return "bite"
        if "punch" in flags or mid == "hammerarm":
            return "punch"
        for variant, words in PHYSICAL_VARIANTS:
            if any(w in mid for w in words):
                return variant
        if "contact" in flags and any(w in mid for w in BODY_WORDS):
            return "body"
        return ""
    if "sound" in flags:
        return "sound"
    if "powder" in flags or mid == "sweetscent":
        return "powder"
    if mv["category"] == 2 and (mv["targets_self"] or (mv["self_stat_changes"] and not mv["stat_changes"])):
        return "boost"
    if any(w in mid for w in BREATH_WORDS):
        return "breath"
    if mv["type"] in ("psychic", "ghost"):
        return "mind"
    return ""


def convert_move(mid, m, names, flavor):
    """Devuelve un dict con los campos de MoveData, o None si el ataque no se puede representar."""
    if mid in UNSUPPORTED or m.get("ohko") or m.get("isZ") or m.get("isMax"):
        return None
    if m.get("isNonstandard") in ("CAP", "LGPE", "Custom", "Unobtainable", "Gigantamax") and mid not in ALLOW_NONSTANDARD:
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
        "always_hits": m["accuracy"] is True, "attack_stat": "", "hp_cost": 0.0,
        "hits_min": 1, "hits_max": 1, "crit_stage": max(0, m.get("critRatio", 1) - 1), "always_crit": bool(m.get("willCrit")), "flinch_chance": 0,
        "sets_weather": WEATHER_SETTERS.get(mid, 0), "weather_tag": WEATHER_TAGS.get(mid, ""),
        "flags": [], "item_effect": ITEM_MOVES.get(mid, ""), "opposite_gender": False, "special": "", "volatile": "", "volatile_chance": 0, "self_volatile": "", "field_effect": "",
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
        # Multigolpe: la potencia es la de cada golpe; la batalla sortea cuántos da.
        hits = m.get("multihit")
        if isinstance(hits, list):
            mv["hits_min"], mv["hits_max"] = hits[0], hits[1]
        elif isinstance(hits, int):
            mv["hits_min"] = mv["hits_max"] = hits
    mv["drain"] = frac(m["drain"]) if m.get("drain") else 0.0
    mv["recoil"] = frac(m["recoil"]) if m.get("recoil") else 0.0
    mv["heal"] = frac(m["heal"]) if m.get("heal") else 0.0
    if mid == "rest":
        mv["heal"], mv["extra_ct"] = 1.0, 100
    if mv["weather_tag"] == "solar_heal":
        mv["heal"] = 0.5
    if m.get("overrideOffensiveStat") == "def":
        mv["attack_stat"] = "defense"
    mv["self_ko"] = m.get("selfdestruct") == "always"

    # Banderas que usan las habilidades (Puño Férreo, Insonorizar, Mandíbula Fuerte...).
    mv["flags"] = [f for f in MOVE_FLAGS if flags.get(f)]
    if m.get("multihit"):
        mv["flags"].append("multihit")
    if secondaries(m) or (m.get("self", {}).get("boosts") and cat != 2):
        mv["flags"].append("secondary")

    # Estados volátiles y efectos de campo
    vol = m.get("volatileStatus")
    if vol in TARGET_VOLATILES:
        mv["volatile"], mv["volatile_chance"] = vol, 100
    elif vol == "partiallytrapped":
        # Atrapar: los de contacto (Constricción, Atadura...) inmovilizan también al que sujeta;
        # los remolinos (Giro Fuego, Torbellino, Bucle Arena) solo al objetivo.
        mv["volatile"], mv["volatile_chance"] = ("wrapped" if flags.get("contact") else "vortex"), 100
    elif vol in SELF_VOLATILES:
        mv["self_volatile"] = vol
    elif vol == "stockpile":
        mv["self_stat_changes"] = {"defense": 1, "sp_defense": 1}
    for sec in secondaries(m):
        if sec.get("volatileStatus") == "confusion":
            mv["volatile"], mv["volatile_chance"] = "confusion", sec.get("chance", 100)
    field = m.get("sideCondition") or m.get("terrain") or m.get("pseudoWeather") or (mid if mid in AREA_FIELDS else "")
    if field in ZONE_FIELDS | TRAP_FIELDS | GLOBAL_FIELDS | AREA_FIELDS:
        mv["field_effect"] = field
    if mid == "captivate":
        mv["opposite_gender"] = True
    if mid == "curse":
        # Sin ser Fantasma: mejora sus stats; siendo Fantasma, maldice al objetivo (lo decide la batalla).
        mv["self_stat_changes"] = {"attack": 1, "defense": 1, "speed": -1}

    # Estados y stats
    if m.get("status") in STATUS:
        mv["status"], mv["status_chance"] = STATUS[m["status"]], 100
    for sec in secondaries(m):
        if sec.get("status") in STATUS and not mv["status"]:
            mv["status"], mv["status_chance"] = STATUS[sec["status"]], sec.get("chance", 100)
        if sec.get("volatileStatus") == "flinch":
            mv["flinch_chance"] = sec.get("chance", 100)
        if sec.get("boosts"):
            mv["stat_changes"] = {STAT_KEYS[k]: v for k, v in sec["boosts"].items() if k in STAT_KEYS}
            mv["stat_chance"] = sec.get("chance", 100)
        if sec.get("self", {}).get("boosts"):
            mv["self_stat_changes"] = {STAT_KEYS[k]: v for k, v in sec["self"]["boosts"].items() if k in STAT_KEYS}
    if m.get("self", {}).get("boosts"):
        mv["self_stat_changes"] = {STAT_KEYS[k]: v for k, v in m["self"]["boosts"].items() if k in STAT_KEYS}
    self_target = target in ("self", "allySide", "allies", "adjacentAllyOrSelf", "allyTeam", "adjacentAlly")
    if mid == "bellydrum":
        mv["self_stat_changes"], mv["hp_cost"] = {"attack": 6}, 0.5
    if mid == "defog":
        mv["stat_changes"] = {"evasion": -1}
    if mid == "focusenergy":
        mv["self_stat_changes"] = {"crit": 2}
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

    if mid in SPECIAL_MOVES:
        lo, hi = SPECIAL_MOVES[mid]
        mv.update(special=mid, range_min=lo, range_max=hi, animation="fight_d", flavor=SPECIAL_FLAVOR[mid],
                  targets_self=hi == 0)
        return mv

    # Alcance y área
    big = mv["power"] >= 90
    fe = mv["field_effect"]
    if mv["sets_weather"] or mv["self_volatile"] or fe in ZONE_FIELDS | GLOBAL_FIELDS:
        mv.update(range_min=0, range_max=0, targets_self=True)
    elif fe in TRAP_FIELDS:
        mv.update(range_min=1, range_max=4, area_shape=CIRCLE, area_size=1)
    elif fe in AREA_FIELDS:
        mv.update(range_min=0, range_max=0, area_shape=CIRCLE, area_size=2)
    elif self_target:
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
                        and not flags.get("sound") and not flags.get("powder") and not mv["field_effect"])

    if mid == "recycle":
        mv.update(range_min=0, range_max=0, targets_self=True)
    if cat == 2 and not (mv["status"] or mv["stat_changes"] or mv["self_stat_changes"] or mv["heal"]
                         or mv["knockback"] or mv["sets_weather"] or mv["volatile"] or mv["self_volatile"]
                         or mv["field_effect"] or mv["item_effect"]):
        return None
    if cat == 2:
        mv["animation"] = "fight_d"
    mv["anim_variant"] = anim_variant(mv)
    return mv


def gd_value(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, float):
        return repr(v)
    if isinstance(v, int):
        return str(v)
    if isinstance(v, list):
        return "PackedStringArray(%s)" % ", ".join(json.dumps(x, ensure_ascii=False) for x in v)
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


def manual_anim_map(pid):
    """Entradas del anim_map puestas a mano en el .tres actual (por ataque, como
    {"lowkick": "fight_b_kick_low"}, o por variante): las que no salen de ANIM_SYNONYMS.
    Así regenerar los datos no las borra."""
    path = OUT_POKEMON / f"{pid}.tres"
    if not path.exists():
        return {}
    m = re.search(r"^anim_map = (\{\}|\{.*?^\})$", path.read_text(encoding="utf-8"), re.MULTILINE | re.DOTALL)
    if not m:
        return {}
    return {k: v for k, v in json.loads(m.group(1)).items() if k not in ANIM_SYNONYMS}


def expected_hits(mv):
    """Golpes medios (igual que Combat.expected_hits): 2-5 da 3,1 de media."""
    if mv["hits_max"] <= 1:
        return 1
    if mv["id"] == "tripleaxel":
        return 6
    if mv["hits_min"] == mv["hits_max"]:
        return mv["hits_min"]
    return 3.1


def pick_default_moves(mon, learnable):
    """4 ataques razonables: el mejor STAB, cobertura, un ataque de estado útil y relleno."""
    types = [t.lower() for t in mon["types"]]
    better_physical = mon["baseStats"]["atk"] >= mon["baseStats"]["spa"]

    def score(mv):
        if mv["category"] == 2:
            return 0
        power = mv["fixed_damage"] or min(mv["power"] * expected_hits(mv), 120)
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


def ability_id(name):
    return re.sub(r"[^a-z0-9]", "", name.lower())


def write_abilities(src, mons):
    """data/abilities.json: {id: {"name", "desc"}} con textos en español de PokeAPI."""
    ids = {}
    for row in load_csv(src / "abilities.csv"):
        ids[int(row["id"])] = row["identifier"].replace("-", "")
    names, desc, best = {}, {}, {}
    for row in load_csv(src / "ability_names.csv"):
        if int(row["local_language_id"]) == SPANISH and int(row["ability_id"]) in ids:
            names[ids[int(row["ability_id"])]] = row["name"]
    for row in load_csv(src / "ability_flavor_text.csv"):
        aid = int(row["ability_id"])
        if int(row["language_id"]) == SPANISH and aid in ids and int(row["version_group_id"]) >= best.get(aid, -1):
            best[aid] = int(row["version_group_id"])
            desc[ids[aid]] = " ".join(row["flavor_text"].split())
    out = {}
    for mon in mons.values():
        for name in mon["abilities"].values():
            aid = ability_id(name)
            out[aid] = {"name": names.get(aid, name), "desc": desc.get(aid, "")}
    path = PROJECT / "data/abilities.json"
    path.write_text(json.dumps(dict(sorted(out.items())), ensure_ascii=False, indent=1), encoding="utf-8")
    return len(out)


# Evoluciones por piedra, intercambio o amistad: en la Torre ocurren a este nivel.
NON_LEVEL_EVOLUTION = 30


def evolution_info(pid, mon, mons):
    """(destinos por nivel, nivel, etapa, legendario, {piedra: destino})."""
    by_name = {v["name"]: k for k, v in mons.items()}
    all_targets = [by_name[n] for n in mon.get("evos") or [] if n in by_name]
    # Las de piedra necesitan la piedra; el resto (nivel, intercambio, amistad) evoluciona por nivel.
    stones = {mons[t]["evoItem"].lower().replace(" ", ""): t for t in all_targets
              if mons[t].get("evoType") == "useItem" and mons[t].get("evoItem")}
    targets = [t for t in all_targets if t not in stones.values()]
    level = 0
    if targets:
        level = min(mons[t].get("evoLevel") or NON_LEVEL_EVOLUTION for t in targets)
    stage, cur = 1, mon
    while cur.get("prevo") in by_name:
        stage += 1
        cur = mons[by_name[cur["prevo"]]]
    return targets, level, stage, bool(mon.get("tags")), stones


def level_moves(pid, learnsets, converted):
    """{ataque: nivel} de la generación más reciente con datos de nivel para la especie."""
    learn = learnsets.get(pid, {}).get("learnset", {})
    gens = [int(s[0]) for srcs in learn.values() for s in srcs if s[:1].isdigit() and s[1:2] == "L"]
    if not gens:
        return {}
    g = str(max(gens))
    out = {}
    for mid, srcs in learn.items():
        if mid not in converted:
            continue
        lv = [int(s[2:]) for s in srcs if s.startswith(g + "L")]
        if lv:
            out[mid] = max(1, min(lv))
    return dict(sorted(out.items(), key=lambda kv: kv[1]))


def write_pokemon(pid, mon, default, learnset, anims, evo=None, lv_moves=None):
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
    # Proporción de machos (-1 = sin género).
    gender = mon.get("gender")
    male_ratio = -1.0 if gender == "N" else (1.0 if gender == "M" else (0.0 if gender == "F" else mon.get("genderRatio", {}).get("M", 0.5)))
    size = 3 if height >= 5.0 else (2 if height >= 1.6 or weight >= 150 else 1)
    fields = {
        "id": pid, "species_name": SPECIES_NAMES.get(pid, mon["name"]), "dex_number": mon["num"],
        "model_height": round(min(max(0.9 * math.sqrt(height / 0.7), 0.5), 2.4), 2),
        "base_hp": st["hp"], "base_attack": st["atk"], "base_defense": st["def"],
        "base_sp_attack": st["spa"], "base_sp_defense": st["spd"], "base_speed": st["spe"],
        "size": size, "move_modifier": 1 if flies else (-1 if weight >= 200 or size >= 2 and weight >= 80 else 0),
        "jump": 3 if flies else 1, "anim_map": anims, "male_ratio": male_ratio,
        "abilities": [ability_id(a) for k, a in sorted(mon["abilities"].items())],
        "evolves_to": evo[0] if evo else [], "evolve_level": evo[1] if evo else 0,
        "stage": evo[2] if evo else 1, "legendary": evo[3] if evo else False,
        "level_moves": lv_moves or {}, "stone_evolutions": evo[4] if evo else {},
    }
    lines = ['[gd_resource type="Resource" script_class="PokemonData" format=3]', "", *ext, "", "[resource]",
             'script = ExtResource("3_script")', 'model = ExtResource("1_model")',
             "types = PackedStringArray(%s)" % ", ".join(json.dumps(t) for t in types)]
    abilities = fields.pop("abilities")
    lines.append("abilities = PackedStringArray(%s)" % ", ".join(json.dumps(a) for a in abilities))
    lines.append("evolves_to = PackedStringArray(%s)" % ", ".join(json.dumps(a) for a in fields.pop("evolves_to")))
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
        write_pokemon(pid, mon, default, learnable, anim_map(glb_animations(model)) | manual_anim_map(pid),
                      evolution_info(pid, mon, mons), level_moves(pid, learnsets, converted))

    n_abilities = write_abilities(args.src, mons)
    print(f"{len(converted)} ataques, {len(mons) - len(missing_models)} Pokémon, {n_abilities} habilidades")
    if missing_models:
        print("Sin modelo (omitidos):", ", ".join(missing_models), file=sys.stderr)


if __name__ == "__main__":
    main()

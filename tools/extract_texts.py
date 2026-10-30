#!/usr/bin/env python3
"""Extrae los textos traducibles del código y actualiza sus plantillas y traducciones (gettext) en locale/.

Busca en los scripts:
  - tr("texto"), tr_n("singular", "plural", n), TranslationServer.translate("texto") y los mensajes guardados
    Msg.make("texto", [...]) / Msg.plural("singular", "plural", n, [...]);
  - las constantes marcadas con el comentario `# i18n` (al final de su primera línea o en la línea de antes):
    se toman sus textos, salvo las claves de diccionario, las rutas y los identificadores en minúsculas que no
    son valores de un diccionario (["idle", "Reposo"] → solo "Reposo").

En los capítulos de la historia (data/story/*.json) se toman los campos de texto (JSON_FIELDS): diálogos,
narración, nombres de personajes y lugares, rótulos.

Cada carpeta de scripts va a un tema (THEMES); un texto que aparece en varios temas queda en el primero.
Se rehace locale/<tema>/<tema>.pot y se fusiona cada <idioma>.po: lo ya traducido se conserva, lo nuevo queda
vacío para traducir y lo que ya no existe se quita.

Uso:
    python3 tools/extract_texts.py              # actualiza todos los temas
    python3 tools/extract_texts.py --faltan en  # además lista lo que falta traducir en inglés
"""
import argparse
import ast
import json
import re
from pathlib import Path

import po

PROJECT = Path(__file__).resolve().parent.parent
LOCALE = PROJECT / "locale"
# Tema → scripts (en orden: un texto repetido se queda en el primer tema).
THEMES = {
    "interfaz": ["scripts/ui/*.gd", "scripts/game.gd", "scripts/audio.gd", "scripts/tower_run.gd", "scripts/data/*.gd",
                 "scripts/grid/*.gd", "scripts/net/*.gd"],
    "combate": ["scripts/battle/*.gd"],
    "historia": ["scripts/story/*.gd", "data/story/*.json"],
}
# Campos de los capítulos que se muestran al jugador.
JSON_FIELDS = {"texto", "narrar", "nombre", "titulo", "subtitulo", "rival"}
CALLS = re.compile(r"(?:\btr|\btr_n|TranslationServer\.translate|TranslationServer\.translate_plural|Msg\.make|Msg\.plural)\(\s*$")
PLACEHOLDER = re.compile(r"%[-0-9.]*[sdf]|\{\w*\}")


def tokens(src):
    """[(tipo, texto, inicio)] con tipo "str" (texto ya decodificado), "comment" o "code"."""
    out, i, n, code_start = [], 0, len(src), 0

    def flush_code(end):
        if end > code_start:
            out.append(("code", src[code_start:end], code_start))

    while i < n:
        c = src[i]
        if c == "#":
            flush_code(i)
            j = src.find("\n", i)
            j = n if j < 0 else j
            out.append(("comment", src[i:j], i))
            i = code_start = j
        elif c in "\"'":
            flush_code(i)
            triple = src[i:i + 3] in ('"""', "'''")
            q = src[i:i + 3] if triple else c
            j = i + len(q)
            while j < n and not src.startswith(q, j):
                j += 2 if src[j] == "\\" else 1
            j += len(q)
            raw = src[i:j]
            try:
                text = ast.literal_eval(raw)
            except (SyntaxError, ValueError):
                text = raw[len(q):-len(q)]
            out.append(("str", text, i))
            i = code_start = j
        else:
            i += 1
    flush_code(n)
    return out


def line_of(src, pos):
    return src.count("\n", 0, pos) + 1


def statement_range(src, toks, begin):
    """Índices [primero, último] de los tokens de la sentencia que empieza en la posición `begin`
    (hasta el fin de línea con los corchetes equilibrados)."""
    first = next(k for k, t in enumerate(toks) if t[2] + len(t[1]) > begin or t[0] == "str" and t[2] >= begin)
    depth, k = 0, first
    while k < len(toks):
        kind, text, pos = toks[k]
        if kind == "code":
            for off, ch in enumerate(text):
                if pos + off < begin:
                    continue
                if ch in "([{":
                    depth += 1
                elif ch in ")]}":
                    depth -= 1
                elif ch == "\n" and depth <= 0 and pos + off > begin:
                    return first, k
        k += 1
    return first, k


def useful(text):
    return bool(re.search(r"[^\W\d_]", text)) and not text.startswith(("res://", "user://"))


def extract(path):
    """[(texto, plural o None, línea)] del script."""
    src = path.read_text(encoding="utf-8")
    toks = tokens(src)
    found = []
    for k, (kind, text, pos) in enumerate(toks):
        if kind != "str":
            continue
        before = toks[k - 1][1] if k > 0 and toks[k - 1][0] == "code" else ""
        if CALLS.search(before):
            plural = None
            if before.rstrip().endswith(("tr_n(", "translate_plural(", "Msg.plural(")) and k + 2 < len(toks) \
                    and toks[k + 1][0] == "code" and toks[k + 1][1].strip() == "," and toks[k + 2][0] == "str":
                plural = toks[k + 2][1]
            found.append((text, plural, line_of(src, pos)))
    # Constantes marcadas con # i18n.
    for k, (kind, text, pos) in enumerate(toks):
        if kind != "comment" or text.strip() != "# i18n":
            continue
        line_start = src.rfind("\n", 0, pos) + 1
        if src[line_start:pos].strip() == "":
            # Comentario solo en su línea: marca la sentencia siguiente.
            begin = src.find("\n", pos) + 1
            while src[begin:src.find("\n", begin)].strip() == "":
                begin = src.find("\n", begin) + 1
        else:
            begin = line_start
        first, last = statement_range(src, toks, begin)
        for j in range(first, min(last + 1, len(toks))):
            kind2, s, p = toks[j]
            if kind2 != "str" or not useful(s):
                continue
            after = toks[j + 1][1] if j + 1 < len(toks) and toks[j + 1][0] == "code" else ""
            prev = toks[j - 1][1] if toks[j - 1][0] == "code" else ""
            if after.lstrip().startswith(":") or prev.rstrip().endswith("preload("):
                continue
            if re.fullmatch(r"[a-z_0-9]+", s) and not prev.rstrip().endswith(":"):
                continue
            found.append((s, None, line_of(src, p)))
    return found


def extract_json(path):
    """[(texto, None, ruta dentro del JSON, nota)] de un capítulo."""
    data = json.loads(path.read_text(encoding="utf-8"))
    names = {k: v.get("nombre", k) for k, v in data.get("personajes", {}).items()}
    found = []

    def walk(node, where):
        if isinstance(node, list):
            for i, v in enumerate(node):
                walk(v, f"{where}[{i}]")
        elif isinstance(node, dict):
            speaker = node.get("decir") or node.get("siente")
            for k, v in node.items():
                if k in JSON_FIELDS and isinstance(v, str) and useful(v):
                    note = ""
                    if k == "texto" and speaker:
                        note = ("Lo que siente " if "siente" in node else "Habla: ") + names.get(speaker, speaker)
                    elif k == "narrar":
                        note = "Narración"
                    found.append((v, None, f"{where}.{k}", note))
                else:
                    walk(v, f"{where}.{k}" if where else k)

    walk(data, "")
    return found


def collect():
    """{tema: [entradas]} de todos los scripts."""
    seen, out = set(), {}
    for theme, globs in THEMES.items():
        entries = {}
        for g in globs:
            for path in sorted(PROJECT.glob(g)):
                rel = path.relative_to(PROJECT)
                found = extract_json(path) if path.suffix == ".json" else [(*f, "") for f in extract(path)]
                for text, plural, line, note in found:
                    key = (text, plural)
                    if key in seen and key not in entries:
                        continue
                    seen.add(key)
                    e = entries.setdefault(key, {"id": text, "plural": plural, "refs": [], "notes": []})
                    e["refs"].append(f"{rel}:{line}")
                    if note and note not in e["notes"]:
                        e["notes"].append(note)
                    if PLACEHOLDER.search(text) and not e["notes"]:
                        e["notes"].append("%s, %d y {...} se rellenan con datos del juego: déjalos tal cual.")
        out[theme] = list(entries.values())
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--faltan", help="lista lo que falta traducir en este idioma")
    args = ap.parse_args()
    for theme, entries in collect().items():
        folder = LOCALE / theme
        if not entries and not folder.exists():
            continue
        missing = po.merge(folder, theme, entries)
        print(f"locale/{theme}: {len(entries)} textos" + "".join(f", {lang} sin traducir: {n}" for lang, n in missing.items()))
        if args.faltan and (folder / f"{args.faltan}.po").exists():
            old = po.read(folder / f"{args.faltan}.po")
            for e in entries:
                if not any(old.get((e["id"], e["plural"]), {}).get("str", [""])):
                    print("   ", repr(e["id"]) + (f" / {e['plural']!r}" if e["plural"] else ""))

if __name__ == "__main__":
    main()

"""Lectura y escritura de archivos gettext (.po / .pot) para las herramientas de traducción.

Una entrada es un dict: {"id", "plural" (o None), "refs": [ruta...], "notes": [texto...]}. Una traducción es
{"str": [texto, ...] (una forma, o una por forma de plural), "fuzzy": bool}.
"""
import json

# Forma de plural de cada idioma (las que usa Godot con tr_n).
PLURAL_FORMS = {
    "en": "nplurals=2; plural=(n != 1);", "fr": "nplurals=2; plural=(n > 1);", "pt_BR": "nplurals=2; plural=(n > 1);",
    "de": "nplurals=2; plural=(n != 1);", "it": "nplurals=2; plural=(n != 1);", "pt": "nplurals=2; plural=(n != 1);",
    "ja": "nplurals=1; plural=0;", "ko": "nplurals=1; plural=0;", "zh_CN": "nplurals=1; plural=0;", "zh_TW": "nplurals=1; plural=0;",
}


def quote(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t") + '"'


def _field(name, text):
    """Una línea, o varias si el texto tiene saltos (como hace msgmerge)."""
    if "\n" not in text[:-1]:
        return f"{name} {quote(text)}\n"
    lines = text.split("\n")
    parts = [l + "\n" for l in lines[:-1]] + ([lines[-1]] if lines[-1] else [])
    return f'{name} ""\n' + "".join(quote(p) + "\n" for p in parts)


def read(path):
    """{(msgid, plural): traducción} de un .po existente (sin la cabecera)."""
    out = {}
    if not path.exists():
        return out
    entry, target, fuzzy = {}, None, False

    def flush():
        nonlocal entry, fuzzy
        if entry.get("id"):
            strs = [entry.get(f"str{i}", "") for i in range(entry["n"])] if entry.get("n") else [entry.get("str", "")]
            out[(entry["id"], entry.get("plural"))] = {"str": strs, "fuzzy": fuzzy}
        entry, fuzzy = {}, False

    for line in path.read_text(encoding="utf-8").splitlines() + [""]:
        if line.startswith("#,"):
            fuzzy = "fuzzy" in line
        elif line.startswith("msgid_plural "):
            entry["plural"], target = json.loads(line[13:]), "plural"
        elif line.startswith("msgid "):
            entry["id"], target = json.loads(line[6:]), "id"
        elif line.startswith("msgstr["):
            i = int(line[7:line.index("]")])
            entry["n"] = max(entry.get("n", 0), i + 1)
            target = f"str{i}"
            entry[target] = json.loads(line[line.index("]") + 2:])
        elif line.startswith("msgstr "):
            entry["str"], target = json.loads(line[7:]), "str"
        elif line.startswith('"') and target:
            entry[target] = entry.get(target, "") + json.loads(line)
        elif not line.strip():
            flush()
            target = None
    return out


def header(lang):
    lines = ["Project-Id-Version: Poké Tactics", "MIME-Version: 1.0", "Content-Type: text/plain; charset=UTF-8",
             "Content-Transfer-Encoding: 8bit"]
    if lang:
        lines.append(f"Language: {lang}")
        if lang in PLURAL_FORMS:
            lines.append(f"Plural-Forms: {PLURAL_FORMS[lang]}")
    return 'msgid ""\nmsgstr ""\n' + "".join(quote(l + "\n") + "\n" for l in lines)


def write(path, lang, entries, translations):
    """entries: lista de entradas; translations: {(msgid, plural): traducción} (vacío para el .pot)."""
    nplurals = 2
    if lang in PLURAL_FORMS:
        nplurals = int(PLURAL_FORMS[lang].split("nplurals=")[1].split(";")[0])
    parts = [header(lang)]
    for e in entries:
        block = "".join(f"#. {n}\n" for n in e.get("notes", []))
        block += "".join(f"#: {r}\n" for r in e.get("refs", [])[:5])
        t = translations.get((e["id"], e.get("plural")))
        if t and t.get("fuzzy"):
            block += "#, fuzzy\n"
        block += _field("msgid", e["id"])
        if e.get("plural") is not None:
            block += _field("msgid_plural", e["plural"])
            strs = (t or {}).get("str", [])
            for i in range(nplurals):
                block += _field(f"msgstr[{i}]", strs[i] if i < len(strs) else "")
        else:
            block += _field("msgstr", (t or {}).get("str", [""])[0])
        parts.append(block)
    path.write_text("\n".join(parts), encoding="utf-8")


def merge(folder, theme, entries, fill=None):
    """Escribe <theme>.pot y fusiona cada <idioma>.po de la carpeta: conserva lo traducido, quita lo que ya no
    existe y rellena lo nuevo con fill(idioma) -> {msgid: traducción, (msgid, plural): [formas]} si se da. Devuelve {idioma: sin traducir}."""
    folder.mkdir(parents=True, exist_ok=True)
    write(folder / f"{theme}.pot", None, entries, {})
    missing = {}
    for path in sorted(folder.glob("*.po")):
        lang = path.stem
        old = read(path)
        known = fill(lang) if fill else {}
        out, n = {}, 0
        for e in entries:
            key = (e["id"], e.get("plural"))
            if key in old and any(old[key]["str"]):
                out[key] = old[key]
            elif (e["id"] if e.get("plural") is None else key) in known:
                value = known[e["id"] if e.get("plural") is None else key]
                out[key] = {"str": value if isinstance(value, list) else [value], "fuzzy": False}
            else:
                n += 1
        write(path, lang, entries, out)
        missing[lang] = n
    return missing

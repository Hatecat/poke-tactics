# Traducciones / Translations

El juego está escrito en español; cada idioma es un archivo `.po` (gettext) por tema, para que varias personas
puedan traducir temas distintos a la vez sin pisarse.

| Carpeta | Qué contiene | Cómo se actualiza |
|---|---|---|
| `ataques/` | nombres y descripciones de los ataques | `tools/build_translations.py` (rellena con PokeAPI) |
| `objetos/` | nombres y descripciones de los objetos | `tools/build_translations.py` (rellena con PokeAPI) |
| `habilidades/` | nombres y descripciones de las habilidades | `tools/build_translations.py` (rellena con PokeAPI) |
| `interfaz/` | menús, editores, Torre de Batallas | `tools/extract_texts.py` (desde el código) |
| `combate/` | combate: tipos, climas, estados y mensajes | `tools/extract_texts.py` (desde el código) |
| `historia/` | modo historia: diálogos, narración, personajes, lugares | `tools/extract_texts.py` (código y `data/story/*.json`) |

En `historia/`, el comentario de cada texto dice quién habla («Habla: Cristina»), si es narración o lo que
Cristina siente de Gengar, para que el tono encaje.

**Traducir a un idioma nuevo:** copia la plantilla `<tema>.pot` de cada carpeta como `<idioma>.po` (código de
Godot: `fr`, `de`, `pt_BR`...) y tradúcela con [Poedit](https://poedit.net) o cualquier editor de `.po`. El juego
detecta el idioma solo y lo muestra en *Opciones → Idioma*. Para ataques, objetos y habilidades es mejor
`python3 tools/build_translations.py <dir_datos> --nuevo fr`, que ya trae los nombres oficiales de PokeAPI.

**Huecos:** `{nombre}` o `%s` se rellenan con datos del juego; déjalos tal cual (los `{...}` se pueden mover de sitio).
Las líneas `#.` son notas de contexto para quien traduce.

---

The game is written in Spanish. Each language is one gettext `.po` file per topic (folders above: moves, items,
abilities, interface, battle; story dialogue coming soon). To add a language, copy each `<topic>.pot` to
`<lang>.po` (Godot locale code) and translate it with Poedit or any PO editor; the game picks it up automatically
in *Options → Language*. Keep placeholders like `{name}` and `%s`.

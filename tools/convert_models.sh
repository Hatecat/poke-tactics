#!/usr/bin/env bash
# Convierte modelos del repo 3d-pokemon a un formato que Godot importa:
# quita la compresión Draco (Godot no la soporta). Las texturas WebP se mantienen.
#
# Uso: tools/convert_models.sh <dir_repo_3d-pokemon> <numero_pokedex> <nombre> [forma]
#   tools/convert_models.sh ~/Documentos/modelos\ pokemon/3d-pokemon 4 charmander
#   tools/convert_models.sh ~/Documentos/modelos\ pokemon/3d-pokemon 212 scizor_mega mega
set -euo pipefail
REPO="$1"; DEX="$2"; NAME="$3"; FORM="${4:-regular}"
SRC="$REPO/models/opt/$FORM/$DEX.glb"
DEST="$(dirname "$0")/../assets/models/pokemon/$NAME.glb"
[[ -f "$SRC" ]] || { echo "No existe $SRC" >&2; exit 1; }
npx -y @gltf-transform/cli@4.1.1 copy "$SRC" "$DEST"
echo "OK -> $DEST"

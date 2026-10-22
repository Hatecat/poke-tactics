#!/usr/bin/env bash
# Exporta la demo para Windows y Linux y la empaqueta en .zip listos para enviar.
# Requiere las plantillas de exportación de Godot 4.7.2 (Editor → Administrar plantillas de exportación).
set -euo pipefail
GODOT="${GODOT:-$HOME/Godot_v4.7.2-stable_linux.x86_64}"
PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$PROJECT/../poke-tactics-builds"
mkdir -p "$OUT/windows" "$OUT/linux"
"$GODOT" --headless --path "$PROJECT" --export-release "Windows Desktop" "$OUT/windows/poke-tactics.exe"
"$GODOT" --headless --path "$PROJECT" --export-release "Linux" "$OUT/linux/poke-tactics.x86_64"
cd "$OUT"
rm -f poke-tactics-windows.zip poke-tactics-linux.zip
(cd windows && zip -q -r ../poke-tactics-windows.zip .)
(cd linux && zip -q -r ../poke-tactics-linux.zip .)
ls -lh "$OUT"/*.zip

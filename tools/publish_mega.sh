#!/usr/bin/env bash
# Sube las builds de Windows y Linux (las de tools/export_demo.sh) a la carpeta de MEGA y muestra su enlace
# público.
#
#   tools/publish_mega.sh            sube los zips que ya hay en ../poke-tactics-builds
#   tools/publish_mega.sh --export   los exporta antes (tools/export_demo.sh)
#
# Carpeta: $MEGA_DIR (por defecto /POKE-TACTICS). Los zips se suben siempre con el mismo nombre
# (poke-tactics-windows.zip, poke-tactics-linux.zip): MEGA guarda los anteriores como versiones y el enlace de la
# carpeta no cambia. Requiere MEGAcmd con la sesión iniciada (mega-cmd → login tu@correo, una vez).
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")/.."
OUT="../poke-tactics-builds"
DIR="${MEGA_DIR:-/POKE-TACTICS}"

if ! command -v mega-put >/dev/null; then
	echo "Falta MEGAcmd: sudo dnf install https://mega.nz/linux/repo/Fedora_44/x86_64/megacmd-Fedora_44.x86_64.rpm" >&2
	exit 1
fi
if ! mega-whoami >/dev/null 2>&1; then
	echo "No hay sesión en MEGA: abre mega-cmd y escribe login tu@correo" >&2
	exit 1
fi

if [[ "${1:-}" == "--export" ]]; then
	tools/export_demo.sh
fi

# Versión que se sube: commit (y "-mod" si hay cambios sin commitear: la build no sale de ese commit tal cual).
VERSION="$(git rev-parse --short HEAD)"
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
	VERSION="$VERSION-mod"
fi

mega-mkdir -p "$DIR" 2>/dev/null || true
for platform in windows linux; do
	src="$OUT/poke-tactics-$platform.zip"
	if [[ ! -f "$src" ]]; then
		echo "No está $src: exporta antes (tools/publish_mega.sh --export)" >&2
		exit 1
	fi
	echo "Subiendo poke-tactics-$platform.zip ($(du -h "$src" | cut -f1), $(date -r "$src" '+%d/%m %H:%M'))…"
	mega-put "$src" "$DIR/poke-tactics-$platform.zip"
done

# Enlace público de la carpeta (se crea si aún no lo tiene).
link="$(mega-export "$DIR" 2>/dev/null | grep -o 'https://mega\.nz/[^ )]*' | head -1 || true)"
if [[ -z "$link" ]]; then
	link="$(mega-export -a -f "$DIR" | grep -o 'https://mega\.nz/[^ )]*' | head -1)"
fi
echo
echo "Publicado en MEGA ($DIR), commit $VERSION:"
mega-ls -lh "$DIR" | grep -E "poke-tactics-.*\.zip" || true
echo "Enlace: $link"

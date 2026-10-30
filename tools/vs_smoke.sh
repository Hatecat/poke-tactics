#!/usr/bin/env bash
# Prueba de humo del modo VS: lanza un anfitrión y un cliente headless en esta máquina, que se conectan por
# ENet y se mandan pings (tools/vs_smoke.gd). Sale con 0 si los dos terminan bien.
# Uso: tools/vs_smoke.sh [puerto]
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")/.."
G="${GODOT:-$HOME/Godot_v4.7.2-stable_linux.x86_64}"
PORT="${1:-24680}"
export POKE_TACTICS_NO_SAVE=1

"$G" --headless --path . --script tools/vs_smoke.gd -- host "$PORT" &
HOST=$!
sleep 0.5
"$G" --headless --path . --script tools/vs_smoke.gd -- join 127.0.0.1 "$PORT" && JOIN=0 || JOIN=$?
wait "$HOST" && HOSTRC=0 || HOSTRC=$?

if [[ $JOIN -eq 0 && $HOSTRC -eq 0 ]]; then
	echo "vs_smoke: OK"
else
	echo "vs_smoke: FALLO (cliente $JOIN, anfitrión $HOSTRC)" >&2
	exit 1
fi

#!/usr/bin/env bash
# Partidas VS entre dos procesos headless en esta máquina (tools/vs_match_test.gd): cada uno juega su lado con
# la IA y todo pasa por la red. Comprueba que ninguna se desincroniza y que los dos ven el mismo resultado.
# Uso: tools/vs_match.sh [partidas] [semilla de los equipos] [puerto] [modo del invitado]
# Con VS_RELAY=1 arranca tools/vs_server.gd en ese puerto y los dos juegan a través de él.
set -uo pipefail

cd "$(dirname "$(readlink -f "$0")")/.."
G="${GODOT:-$HOME/Godot_v4.7.2-stable_linux.x86_64}"
GAMES="${1:-3}"
SEED="${2:-1}"
PORT="${3:-24690}"
export POKE_TACTICS_NO_SAVE=1
MODE="${4:-}"
OUT=$(mktemp -d)
if [[ "${VS_RELAY:-}" == "1" ]]; then
	export VS_RELAY
	"$G" --headless --path . --script tools/vs_server.gd -- "$PORT" >"$OUT/server.txt" 2>&1 &
	SERVER=$!
	trap 'kill $SERVER 2>/dev/null' EXIT
	sleep 1
fi

"$G" --headless --fixed-fps 60 --path . --script tools/vs_match_test.gd -- host "$GAMES" "$PORT" "$SEED" >"$OUT/host.txt" 2>&1 &
HOST=$!
sleep 1
"$G" --headless --fixed-fps 60 --path . --script tools/vs_match_test.gd -- join "$GAMES" "$PORT" "$SEED" $MODE >"$OUT/join.txt" 2>&1
JOIN=$?
wait "$HOST"
HOSTRC=$?

grep -E '^\[(host|join)\] (partida|RESUMEN)|FALLO|tiempo agotado|SCRIPT ERROR' "$OUT/host.txt" "$OUT/join.txt" | sed "s|$OUT/||"
H=$(grep -o 'RESUMEN.*' "$OUT/host.txt")
J=$(grep -o 'RESUMEN.*' "$OUT/join.txt")
if [[ $JOIN -eq 0 && $HOSTRC -eq 0 && -n "$H" && "$H" == "$J" ]]; then
	echo "vs_match: OK ($GAMES partidas, mismo resultado y huella en los dos lados)"
	rm -rf "$OUT"
else
	echo "vs_match: FALLO (anfitrión $HOSTRC, invitado $JOIN; registros en $OUT)" >&2
	exit 1
fi

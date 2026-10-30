#!/usr/bin/env bash
# Prueba de humo de la red del modo VS en esta máquina (procesos headless con tools/vs_net_test.gd):
#   1. directo: anfitrión e invitado se saludan e intercambian intents
#   2. el anfitrión rechaza otra versión y otros datos
#   3. relay: tools/vs_server.gd empareja a dos clientes y reenvía; también rechaza versión y datos
#   4. dirección sin nadie: "unreachable"
# Sale con 0 si todo va bien. Uso: tools/vs_smoke.sh [puerto]
set -uo pipefail

cd "$(dirname "$(readlink -f "$0")")/.."
G="${GODOT:-$HOME/Godot_v4.7.2-stable_linux.x86_64}"
PORT="${1:-24680}"
export POKE_TACTICS_NO_SAVE=1
FAILS=0

run() {  # run <etiqueta> <args de vs_net_test.gd...>
	local tag=$1; shift
	"$G" --headless --path . --script tools/vs_net_test.gd -- "$@" 2>&1 | grep -v '^Godot Engine\|^$' | sed "s/^/  $tag| /"
	return "${PIPESTATUS[0]}"
}

check() {  # check <descripción> <código>
	if [[ $2 -eq 0 ]]; then echo "OK    $1"; else echo "FALLO $1 (código $2)"; FAILS=$((FAILS + 1)); fi
}

echo "== directo"
run host host "$PORT" & HOST=$!
sleep 1
run join join 127.0.0.1 "$PORT"; check "invitado conecta e intercambia intents" $?
wait "$HOST"; check "anfitrión" $?

P2=$((PORT + 1))
run host host "$P2" & HOST=$!
sleep 1
run bad bad-version 127.0.0.1 "$P2"; check "anfitrión rechaza otra versión" $?
run bad bad-data 127.0.0.1 "$P2"; check "anfitrión rechaza otros datos" $?
run idle idle 127.0.0.1 "$P2" & IDLE=$!
sleep 1.5
run full full 127.0.0.1 "$P2"; check "anfitrión con rival rechaza a un tercero" $?
pkill -f "vs_net_test.gd -- idle"; wait "$IDLE" 2>/dev/null
pkill -f "vs_net_test.gd -- host $P2"; wait "$HOST" 2>/dev/null

echo "== relay"
P3=$((PORT + 2))
"$G" --headless --path . --script tools/vs_server.gd -- "$P3" 2>&1 | grep -v '^Godot Engine\|^$' | sed 's/^/  srv| /' & SERVER=$!
sleep 1
run bad bad-version 127.0.0.1 "$P3"; check "servidor rechaza otra versión" $?
run bad bad-data 127.0.0.1 "$P3"; check "servidor rechaza otros datos" $?
run A relay 127.0.0.1 "$P3" & A=$!
sleep 0.5
run B relay 127.0.0.1 "$P3"; check "relay: segundo cliente" $?
wait "$A"; check "relay: primer cliente" $?
pkill -f "tools/vs_server.gd -- $P3"; wait "$SERVER" 2>/dev/null

echo "== sin nadie"
run nadie unreachable 127.0.0.1 "$((PORT + 3))"; check "dirección sin nadie: unreachable" $?

if [[ $FAILS -eq 0 ]]; then echo "vs_smoke: OK"; else echo "vs_smoke: $FAILS fallos" >&2; exit 1; fi

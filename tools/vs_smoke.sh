#!/usr/bin/env bash
# Prueba de humo de la red del modo VS en esta máquina (procesos headless con tools/vs_net_test.gd):
#   1. directo: anfitrión e invitado se saludan e intercambian intents
#   2. el anfitrión rechaza otra versión y otros datos
#   3. relay: tools/vs_server.gd empareja a dos clientes y reenvía; también rechaza versión y datos;
#      salas, emparejamiento rápido y reconexión con tools/vs_lobby_test.gd
#   4. dirección sin nadie: "unreachable"
# Sale con 0 si todo va bien. Usa los puertos del indicado al indicado+4. Uso: tools/vs_smoke.sh [puerto]
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

## Como run, pero en segundo plano; deja en BG el PID del propio Godot (para matarlo sin pkill).
bg() {  # bg <etiqueta> <script> <args...>
	local tag=$1 script=$2; shift 2
	"$G" --headless --path . --script "$script" -- "$@" > >(grep -v '^Godot Engine\|^$' | sed "s/^/  $tag| /") 2>&1 &
	BG=$!
}

check() {  # check <descripción> <código>
	if [[ $2 -eq 0 ]]; then echo "OK    $1"; else echo "FALLO $1 (código $2)"; FAILS=$((FAILS + 1)); fi
}

echo "== directo"
bg host tools/vs_net_test.gd host "$PORT"; HOST=$BG
sleep 1
run join join 127.0.0.1 "$PORT"; check "invitado conecta e intercambia intents" $?
wait "$HOST"; check "anfitrión" $?

P2=$((PORT + 1))
bg host tools/vs_net_test.gd host "$P2"; HOST=$BG
sleep 1
run bad bad-version 127.0.0.1 "$P2"; check "anfitrión rechaza otra versión" $?
run bad bad-data 127.0.0.1 "$P2"; check "anfitrión rechaza otros datos" $?
bg idle tools/vs_net_test.gd idle 127.0.0.1 "$P2"; IDLE=$BG
sleep 1.5
run full full 127.0.0.1 "$P2"; check "anfitrión con rival rechaza a un tercero" $?
kill "$IDLE" "$HOST" 2>/dev/null; wait "$IDLE" "$HOST" 2>/dev/null
P4=$((PORT + 3))
bg host tools/vs_net_test.gd host "$P4"; HOST=$BG
sleep 1
run flood flood 127.0.0.1 "$P4"; check "anfitrión echa al que inunda" $?
kill "$HOST" 2>/dev/null; wait "$HOST" 2>/dev/null

echo "== relay"
P3=$((PORT + 2))
bg srv tools/vs_server.gd "$P3" --quiet; SERVER=$BG
sleep 1
run bad bad-version 127.0.0.1 "$P3"; check "servidor rechaza otra versión" $?
run bad bad-data 127.0.0.1 "$P3"; check "servidor rechaza otros datos" $?
run flood flood-relay 127.0.0.1 "$P3"; check "servidor echa al que inunda" $?
bg A tools/vs_net_test.gd relay 127.0.0.1 "$P3"; A=$BG
sleep 0.5
run B relay 127.0.0.1 "$P3"; check "relay: segundo cliente" $?
wait "$A"; check "relay: primer cliente" $?
"$G" --headless --path . --script tools/vs_lobby_test.gd -- "$P3" 2>&1 | grep -E '^(OK|FALLO)' | sed 's/^/  salas| /'
check "salas y reconexión (vs_lobby_test)" "${PIPESTATUS[0]}"
kill "$SERVER" 2>/dev/null; wait "$SERVER" 2>/dev/null

echo "== sin nadie"
run nadie unreachable 127.0.0.1 "$((PORT + 4))"; check "dirección sin nadie: unreachable" $?

if [[ $FAILS -eq 0 ]]; then echo "vs_smoke: OK"; else echo "vs_smoke: $FAILS fallos" >&2; exit 1; fi

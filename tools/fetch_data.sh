#!/usr/bin/env bash
# Descarga los datos que usa tools/build_data.py.
# Pokémon Showdown (MIT): stats, tipos, ataques y learnsets. PokeAPI (BSD): textos en español.
set -euo pipefail
DIR="${1:?Uso: tools/fetch_data.sh <dir_destino>}"
mkdir -p "$DIR"
for f in moves.json learnsets.json pokedex.json; do
  curl -fsSL -o "$DIR/$f" "https://play.pokemonshowdown.com/data/$f"
done
for f in move_names.csv move_flavor_text.csv; do
  curl -fsSL -o "$DIR/$f" "https://raw.githubusercontent.com/PokeAPI/pokeapi/master/data/v2/csv/$f"
done
echo "Datos en $DIR"

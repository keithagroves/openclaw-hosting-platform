#!/usr/bin/env bash
# Random word-based subdomain generator.
# Generates names like: swift-falcon, bold-river, calm-ember

set -euo pipefail

_ADJECTIVES=(
  able bold calm cool dark deep fair fast firm free
  glad gold good gray keen kind lean live loud mild
  neat next open pale pure rare real rich safe slim
  soft sure tall tidy true vast warm wide wild wise
  blue bold cold crisp dusk easy fine glad hazy iron
  jade keen lime mint neon opal pink ruby sage teal
)

_NOUNS=(
  arch bass beam bolt cave claw coal cove dawn deer
  dock dove dune dust echo edge fern fire flux frog
  gate glow gulf hare hawk haze hill iris jade lake
  lark leaf lion lynx mesa mist moon moth nest nova
  opal orca palm peak pine pond rain reef root sage
  seal star stem tide vale vine wave wren yard zero
  aspen birch cedar cliff cloud coral creek delta ember
  fjord flame forge frost gleam haven heron maple marsh
  orbit pearl plume ridge river robin scout shell shore
  spine stone swift tiger trail vapor whale
)

# Generate a random word-pair subdomain (e.g. "swift-falcon").
# Retries up to 10 times if the name collides with an existing customer.
# Usage: generate_subdomain
generate_subdomain() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  # Source db.sh if not already loaded
  if ! command -v db_get_customer &>/dev/null; then
    source "${script_dir}/db.sh"
    db_init
  fi

  local attempts=0
  while [ $attempts -lt 10 ]; do
    local adj="${_ADJECTIVES[$((RANDOM % ${#_ADJECTIVES[@]}))]}"
    local noun="${_NOUNS[$((RANDOM % ${#_NOUNS[@]}))]}"
    local name="${adj}-${noun}"

    # Check if name is already taken
    local existing
    existing=$(db_get_customer "$name" 2>/dev/null || true)
    if [ -z "$existing" ]; then
      echo "$name"
      return 0
    fi

    attempts=$((attempts + 1))
  done

  # Fallback: append random digits
  local adj="${_ADJECTIVES[$((RANDOM % ${#_ADJECTIVES[@]}))]}"
  local noun="${_NOUNS[$((RANDOM % ${#_NOUNS[@]}))]}"
  local suffix=$((RANDOM % 100))
  echo "${adj}-${noun}-${suffix}"
}

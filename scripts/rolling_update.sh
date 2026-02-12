#!/usr/bin/env bash
# Pull a new image and rolling-restart all active customer containers.
# Usage: rolling_update.sh [image:tag]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/db.sh"

IMAGE="${1:-${IMAGE:-clawbot-desktop:latest}}"
BASE_DOMAIN="${BASE_DOMAIN:-reptar.ai}"
NETWORK="${NETWORK:-clawbot_net}"
CPUS="${CPUS:-1}"
MEMORY="${MEMORY:-2g}"
SHM_SIZE="${SHM_SIZE:-1g}"
HEALTHCHECK_TIMEOUT="${HEALTHCHECK_TIMEOUT:-120}"

echo "Pulling image: ${IMAGE}"
docker pull "$IMAGE"

db_init
CUSTOMERS=$(db_list_customers "active")
COUNT=$(echo "$CUSTOMERS" | jq 'length')

if [ "$COUNT" -eq 0 ]; then
  echo "No active customers to update."
  exit 0
fi

echo "Updating ${COUNT} customer(s)..."

SUCCESS=0
FAILED=0

for i in $(seq 0 $((COUNT - 1))); do
  SUBDOMAIN=$(echo "$CUSTOMERS" | jq -r ".[$i].subdomain")
  PASSWORD=$(echo "$CUSTOMERS" | jq -r ".[$i].vnc_password")

  NAME="clawbot-${SUBDOMAIN//./-}"
  VOLUME="clawbot-${SUBDOMAIN//./-}-home"
  NET_PER_CUSTOMER="clawbot-${SUBDOMAIN//./-}-net"

  echo "  Updating ${SUBDOMAIN}..."

  # Stop and remove old container
  docker rm -f "$NAME" >/dev/null 2>&1 || true

  # Recreate network if needed
  if ! docker network inspect "$NET_PER_CUSTOMER" >/dev/null 2>&1; then
    docker network create "$NET_PER_CUSTOMER" >/dev/null
  fi

  # Launch new container with same config, new image
  if docker run -d \
    --name "$NAME" \
    --restart unless-stopped \
    --network "$NET_PER_CUSTOMER" \
    --shm-size "$SHM_SIZE" \
    --cpus "$CPUS" \
    --memory "$MEMORY" \
    -e VNC_PW="$PASSWORD" \
    -v "${VOLUME}:/home/kasm-user" \
    --label "caddy=${SUBDOMAIN}.${BASE_DOMAIN}" \
    --label "caddy.reverse_proxy={{upstreams 6901}}" \
    "$IMAGE" >/dev/null 2>&1; then

    # Reconnect Caddy
    if docker ps --format '{{.Names}}' | grep -qx "clawbot-caddy"; then
      docker network connect "$NET_PER_CUSTOMER" clawbot-caddy >/dev/null 2>&1 || true
    fi

    # Wait for healthcheck
    HEALTHY=false
    for _ in $(seq 1 $((HEALTHCHECK_TIMEOUT / 5))); do
      STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$NAME" 2>/dev/null || echo "unknown")
      if [ "$STATUS" = "healthy" ]; then
        HEALTHY=true
        break
      fi
      sleep 5
    done

    if [ "$HEALTHY" = true ]; then
      echo "    OK"
      SUCCESS=$((SUCCESS + 1))
    else
      echo "    WARNING: container started but healthcheck not passing (status: ${STATUS})"
      SUCCESS=$((SUCCESS + 1))
    fi
  else
    echo "    FAILED to start container"
    FAILED=$((FAILED + 1))
  fi
done

echo "Update complete: ${SUCCESS} ok, ${FAILED} failed"

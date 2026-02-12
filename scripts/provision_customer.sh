#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/db.sh"
source "${SCRIPT_DIR}/lib/cloudflare.sh"
source "${SCRIPT_DIR}/lib/namegen.sh"

# Parse arguments
STRIPE_CUSTOMER_ID=""
STRIPE_SUBSCRIPTION_ID=""
EMAIL=""
POSITIONAL=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stripe-customer-id)     STRIPE_CUSTOMER_ID="$2"; shift 2 ;;
    --stripe-subscription-id) STRIPE_SUBSCRIPTION_ID="$2"; shift 2 ;;
    --email)                  EMAIL="$2"; shift 2 ;;
    *)                        POSITIONAL+=("$1"); shift ;;
  esac
done

# Subdomain: use positional arg if provided, otherwise auto-generate
SUBDOMAIN="${POSITIONAL[0]:-}"
if [ -z "$SUBDOMAIN" ]; then
  db_init
  SUBDOMAIN=$(generate_subdomain)
  echo "Generated subdomain: ${SUBDOMAIN}"
fi

BASE_DOMAIN="${BASE_DOMAIN:-reptar.ai}"
IMAGE="${IMAGE:-clawbot-desktop:latest}"
NETWORK="${NETWORK:-clawbot_net}"
CPUS="${CPUS:-1}"
MEMORY="${MEMORY:-2g}"
SHM_SIZE="${SHM_SIZE:-1g}"

NAME="clawbot-${SUBDOMAIN//./-}"
VOLUME="clawbot-${SUBDOMAIN//./-}-home"
NET_PER_CUSTOMER="clawbot-${SUBDOMAIN//./-}-net"

# VNC password: use positional arg or generate
PASSWORD="${POSITIONAL[1]:-}"
if [ -z "$PASSWORD" ]; then
  if command -v openssl >/dev/null 2>&1; then
    PASSWORD="$(openssl rand -base64 12)"
  else
    PASSWORD="$(python3 -c 'import secrets; print(secrets.token_urlsafe(12))')"
  fi
fi

# Check if customer already exists in DB
db_init
if db_get_customer "$SUBDOMAIN" >/dev/null 2>&1 && [ -n "$(db_get_customer "$SUBDOMAIN")" ]; then
  echo "ERROR: customer '$SUBDOMAIN' already exists" >&2
  exit 1
fi

# Create networks
if ! docker network inspect "$NETWORK" >/dev/null 2>&1; then
  docker network create "$NETWORK" >/dev/null
fi
if ! docker network inspect "$NET_PER_CUSTOMER" >/dev/null 2>&1; then
  docker network create "$NET_PER_CUSTOMER" >/dev/null
fi

# Launch container
docker run -d \
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
  "$IMAGE"

# Connect Caddy to customer network
if docker ps --format '{{.Names}}' | grep -qx "clawbot-caddy"; then
  docker network connect "$NET_PER_CUSTOMER" clawbot-caddy >/dev/null 2>&1 || true
fi

# Create Cloudflare DNS record
CF_RECORD_ID=""
if [ -n "${CLOUDFLARE_API_TOKEN:-}" ] && [ -n "${CLOUDFLARE_ZONE_ID:-}" ]; then
  CF_RECORD_ID=$(cf_create_a_record "$SUBDOMAIN") || {
    echo "WARNING: DNS record creation failed. Container is running but DNS is not configured." >&2
    echo "You can manually create an A record for ${SUBDOMAIN}.${BASE_DOMAIN} -> ${SERVER_IP}" >&2
  }
fi

# Create Cloudflare Access policy (requires email)
ACCESS_APP_ID=""
if [ -n "$EMAIL" ] && [ -n "${CLOUDFLARE_ACCOUNT_ID:-}" ] && [ -n "${CLOUDFLARE_API_TOKEN:-}" ]; then
  ACCESS_APP_ID=$(cf_create_access_policy "$SUBDOMAIN" "$EMAIL") || {
    echo "WARNING: Access policy creation failed. Desktop is accessible but not protected by login." >&2
  }
fi

# Record customer in database
db_add_customer "$SUBDOMAIN" "$PASSWORD" "$EMAIL" "$STRIPE_CUSTOMER_ID" "$STRIPE_SUBSCRIPTION_ID" "$CF_RECORD_ID" "$ACCESS_APP_ID"

echo "Provisioned: https://${SUBDOMAIN}.${BASE_DOMAIN}"
echo "VNC password: ${PASSWORD}"
[ -n "$EMAIL" ] && echo "Access restricted to: ${EMAIL}"

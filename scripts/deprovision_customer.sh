#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/db.sh"
source "${SCRIPT_DIR}/lib/cloudflare.sh"

KEEP_DATA=false

POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep-data) KEEP_DATA=true; shift ;;
    *)           POSITIONAL+=("$1"); shift ;;
  esac
done

if [ "${#POSITIONAL[@]}" -lt 1 ]; then
  echo "Usage: $0 <customer-subdomain> [--keep-data]" >&2
  exit 1
fi

SUBDOMAIN="${POSITIONAL[0]}"
NAME="openclaw-${SUBDOMAIN//./-}"
VOLUME="openclaw-${SUBDOMAIN//./-}-home"
NET_PER_CUSTOMER="openclaw-${SUBDOMAIN//./-}-net"

# Look up Cloudflare record ID from database before removing anything
db_init
CUSTOMER_JSON=$(db_get_customer "$SUBDOMAIN" 2>/dev/null || true)
CF_RECORD_ID=""
ACCESS_APP_ID=""
if [ -n "$CUSTOMER_JSON" ]; then
  CF_RECORD_ID=$(echo "$CUSTOMER_JSON" | jq -r '.cloudflare_record_id // ""')
  ACCESS_APP_ID=$(echo "$CUSTOMER_JSON" | jq -r '.access_app_id // ""')
fi

# Remove container
docker rm -f "$NAME" >/dev/null 2>&1 || true

# Remove volume unless --keep-data was passed
if [ "$KEEP_DATA" = false ]; then
  docker volume rm "$VOLUME" >/dev/null 2>&1 || true
fi

# Remove per-customer network
docker network rm "$NET_PER_CUSTOMER" >/dev/null 2>&1 || true

# Delete Cloudflare DNS record
if [ -n "$CF_RECORD_ID" ] && [ -n "${CLOUDFLARE_API_TOKEN:-}" ] && [ -n "${CLOUDFLARE_ZONE_ID:-}" ]; then
  cf_delete_record "$CF_RECORD_ID" || {
    echo "WARNING: failed to delete DNS record ${CF_RECORD_ID}" >&2
  }
fi

# Delete Cloudflare Access application
if [ -n "$ACCESS_APP_ID" ] && [ -n "${CLOUDFLARE_ACCOUNT_ID:-}" ] && [ -n "${CLOUDFLARE_API_TOKEN:-}" ]; then
  cf_delete_access_app "$ACCESS_APP_ID" || {
    echo "WARNING: failed to delete Access app ${ACCESS_APP_ID}" >&2
  }
fi

# Remove from database
if [ -n "$CUSTOMER_JSON" ]; then
  db_remove_customer "$SUBDOMAIN"
fi

if [ "$KEEP_DATA" = true ]; then
  echo "Deprovisioned: $SUBDOMAIN (volume preserved)"
else
  echo "Deprovisioned: $SUBDOMAIN"
fi

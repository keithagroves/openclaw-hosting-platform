#!/usr/bin/env bash
# Cloudflare DNS + Access (Zero Trust) API helpers
# Required env vars: CLOUDFLARE_API_TOKEN, CLOUDFLARE_ZONE_ID, SERVER_IP, BASE_DOMAIN
# For Access: CLOUDFLARE_ACCOUNT_ID

set -euo pipefail

CF_API="https://api.cloudflare.com/client/v4"

_cf_curl() {
  local method="$1"
  local endpoint="$2"
  shift 2
  curl -sf -X "$method" \
    "${CF_API}${endpoint}" \
    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
    -H "Content-Type: application/json" \
    "$@"
}

# Create an A record for <subdomain>.<BASE_DOMAIN> pointing to SERVER_IP.
# Prints the Cloudflare record ID on success.
# Usage: cf_create_a_record <subdomain> [ip]
cf_create_a_record() {
  local subdomain="$1"
  local ip="${2:-${SERVER_IP}}"
  local base_domain="${BASE_DOMAIN:-reptar.ai}"
  local fqdn="${subdomain}.${base_domain}"

  local response
  response=$(_cf_curl POST "/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
    -d "{\"type\":\"A\",\"name\":\"${fqdn}\",\"content\":\"${ip}\",\"ttl\":1,\"proxied\":false}")

  local success
  success=$(echo "$response" | jq -r '.success')
  if [ "$success" != "true" ]; then
    echo "ERROR: failed to create DNS record for ${fqdn}" >&2
    echo "$response" | jq -r '.errors' >&2
    return 1
  fi

  echo "$response" | jq -r '.result.id'
}

# Delete a DNS record by its Cloudflare record ID.
# Usage: cf_delete_record <record_id>
cf_delete_record() {
  local record_id="$1"

  local response
  response=$(_cf_curl DELETE "/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${record_id}")

  local success
  success=$(echo "$response" | jq -r '.success')
  if [ "$success" != "true" ]; then
    echo "ERROR: failed to delete DNS record ${record_id}" >&2
    echo "$response" | jq -r '.errors' >&2
    return 1
  fi
}

# Look up the Cloudflare record ID for a subdomain.
# Prints the record ID, or returns 1 if not found.
# Usage: cf_get_record_id <subdomain>
cf_get_record_id() {
  local subdomain="$1"
  local base_domain="${BASE_DOMAIN:-reptar.ai}"
  local fqdn="${subdomain}.${base_domain}"

  local response
  response=$(_cf_curl GET "/zones/${CLOUDFLARE_ZONE_ID}/dns_records?type=A&name=${fqdn}")

  local count
  count=$(echo "$response" | jq -r '.result | length')
  if [ "$count" -eq 0 ]; then
    echo "ERROR: no DNS record found for ${fqdn}" >&2
    return 1
  fi

  echo "$response" | jq -r '.result[0].id'
}

# ── Cloudflare Access (Zero Trust) ───────────────────────────────────────────

# Create an Access application + policy that restricts a subdomain to a single email.
# Prints the application ID on success.
# Usage: cf_create_access_policy <subdomain> <email>
cf_create_access_policy() {
  local subdomain="$1"
  local email="$2"
  local base_domain="${BASE_DOMAIN:-reptar.ai}"
  local fqdn="${subdomain}.${base_domain}"
  local account_id="${CLOUDFLARE_ACCOUNT_ID}"

  # Create the Access application
  local app_response
  app_response=$(_cf_curl POST "/accounts/${account_id}/access/apps" \
    -d "{
      \"name\": \"clawbot-${subdomain}\",
      \"domain\": \"${fqdn}\",
      \"type\": \"self_hosted\",
      \"session_duration\": \"24h\",
      \"auto_redirect_to_identity\": true
    }")

  local success
  success=$(echo "$app_response" | jq -r '.success')
  if [ "$success" != "true" ]; then
    echo "ERROR: failed to create Access app for ${fqdn}" >&2
    echo "$app_response" | jq -r '.errors' >&2
    return 1
  fi

  local app_id
  app_id=$(echo "$app_response" | jq -r '.result.id')

  # Create a policy allowing only the customer's email
  local policy_response
  policy_response=$(_cf_curl POST "/accounts/${account_id}/access/apps/${app_id}/policies" \
    -d "{
      \"name\": \"allow-${subdomain}\",
      \"decision\": \"allow\",
      \"include\": [{
        \"email\": {\"email\": \"${email}\"}
      }],
      \"precedence\": 1
    }")

  local policy_success
  policy_success=$(echo "$policy_response" | jq -r '.success')
  if [ "$policy_success" != "true" ]; then
    echo "WARNING: Access app created but policy failed for ${fqdn}" >&2
    echo "$policy_response" | jq -r '.errors' >&2
  fi

  echo "$app_id"
}

# Delete a Cloudflare Access application (and its policies) by app ID.
# Usage: cf_delete_access_app <app_id>
cf_delete_access_app() {
  local app_id="$1"
  local account_id="${CLOUDFLARE_ACCOUNT_ID}"

  local response
  response=$(_cf_curl DELETE "/accounts/${account_id}/access/apps/${app_id}")

  local success
  success=$(echo "$response" | jq -r '.success')
  if [ "$success" != "true" ]; then
    echo "ERROR: failed to delete Access app ${app_id}" >&2
    echo "$response" | jq -r '.errors' >&2
    return 1
  fi
}

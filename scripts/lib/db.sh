#!/usr/bin/env bash
# Customer JSON database helpers
# Uses jq for JSON manipulation and flock for concurrent access safety.
# Database file path: ${OPENCLAW_DATA_DIR:-./data}/customers.json

set -euo pipefail

DB_DIR="${OPENCLAW_DATA_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/data}"
DB_FILE="${DB_DIR}/customers.json"
LOCK_FILE="${DB_FILE}.lock"

# Ensure the database file exists with an empty array.
db_init() {
  mkdir -p "$DB_DIR"
  if [ ! -f "$DB_FILE" ]; then
    echo '[]' > "$DB_FILE"
  fi
}

# Run a jq query against the database (read-only, no lock needed).
_db_read() {
  jq -r "$@" "$DB_FILE"
}

# Write the full database content under an exclusive lock.
_db_write() {
  local tmp
  tmp=$(mktemp "${DB_FILE}.XXXXXX")
  # Run jq with the provided filter and write to temp file
  if jq "$@" "$DB_FILE" > "$tmp"; then
    mv "$tmp" "$DB_FILE"
  else
    rm -f "$tmp"
    return 1
  fi
}

# Acquire an exclusive lock, run a jq write, then release.
_db_locked_write() {
  (
    flock -w 5 200 || { echo "ERROR: could not acquire DB lock" >&2; return 1; }
    _db_write "$@"
  ) 200>"$LOCK_FILE"
}

# Add a customer record. Fails if the subdomain already exists.
# Usage: db_add_customer <subdomain> <vnc_password> [email] [stripe_customer_id] [stripe_subscription_id] [cloudflare_record_id] [access_app_id]
db_add_customer() {
  local subdomain="$1"
  local vnc_password="$2"
  local email="${3:-}"
  local stripe_customer_id="${4:-}"
  local stripe_subscription_id="${5:-}"
  local cloudflare_record_id="${6:-}"
  local access_app_id="${7:-}"
  local created_at
  created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  db_init

  # Check if subdomain already exists
  local existing
  existing=$(_db_read --arg s "$subdomain" '[.[] | select(.subdomain == $s)] | length')
  if [ "$existing" -gt 0 ]; then
    echo "ERROR: customer '$subdomain' already exists" >&2
    return 1
  fi

  _db_locked_write \
    --arg subdomain "$subdomain" \
    --arg vnc_password "$vnc_password" \
    --arg email "$email" \
    --arg stripe_customer_id "$stripe_customer_id" \
    --arg stripe_subscription_id "$stripe_subscription_id" \
    --arg cloudflare_record_id "$cloudflare_record_id" \
    --arg access_app_id "$access_app_id" \
    --arg created_at "$created_at" \
    '. += [{
      subdomain: $subdomain,
      vnc_password: $vnc_password,
      email: $email,
      stripe_customer_id: $stripe_customer_id,
      stripe_subscription_id: $stripe_subscription_id,
      cloudflare_record_id: $cloudflare_record_id,
      access_app_id: $access_app_id,
      created_at: $created_at,
      status: "active"
    }]'
}

# Remove a customer record (hard delete).
db_remove_customer() {
  local subdomain="$1"
  db_init
  _db_locked_write --arg s "$subdomain" 'map(select(.subdomain != $s))'
}

# Get a customer record as JSON. Returns empty string if not found.
db_get_customer() {
  local subdomain="$1"
  db_init
  _db_read --arg s "$subdomain" '.[] | select(.subdomain == $s)'
}

# List customers, optionally filtered by status.
# Usage: db_list_customers [status]
db_list_customers() {
  local status="${1:-}"
  db_init
  if [ -n "$status" ]; then
    _db_read --arg s "$status" '[.[] | select(.status == $s)]'
  else
    _db_read '.'
  fi
}

# Update a single field for a customer.
# Usage: db_update_field <subdomain> <field> <value>
db_update_field() {
  local subdomain="$1"
  local field="$2"
  local value="$3"
  db_init
  _db_locked_write \
    --arg s "$subdomain" \
    --arg f "$field" \
    --arg v "$value" \
    'map(if .subdomain == $s then .[$f] = $v else . end)'
}

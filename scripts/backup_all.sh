#!/usr/bin/env bash
# Back up all active customer volumes as compressed tarballs.
# Intended to run as a daily cron job:
#   0 3 * * * /path/to/scripts/backup_all.sh >> /var/log/openclaw-backup.log 2>&1
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/db.sh"

BACKUP_DIR="${BACKUP_DIR:-${OPENCLAW_DATA_DIR:-./data}/backups}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

mkdir -p "$BACKUP_DIR"
db_init

echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Starting backup run"

CUSTOMERS=$(db_list_customers "active")
COUNT=$(echo "$CUSTOMERS" | jq 'length')

if [ "$COUNT" -eq 0 ]; then
  echo "No active customers to back up."
  exit 0
fi

SUCCESS=0
FAILED=0

for i in $(seq 0 $((COUNT - 1))); do
  SUBDOMAIN=$(echo "$CUSTOMERS" | jq -r ".[$i].subdomain")
  VOLUME="openclaw-${SUBDOMAIN//./-}-home"
  BACKUP_FILE="${BACKUP_DIR}/${SUBDOMAIN}-${TIMESTAMP}.tar.gz"

  echo "  Backing up ${SUBDOMAIN} (volume: ${VOLUME})..."

  if docker run --rm \
    -v "${VOLUME}:/source:ro" \
    -v "${BACKUP_DIR}:/backup" \
    alpine tar czf "/backup/${SUBDOMAIN}-${TIMESTAMP}.tar.gz" -C /source . 2>/dev/null; then
    SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    echo "    OK (${SIZE})"
    SUCCESS=$((SUCCESS + 1))
  else
    echo "    FAILED"
    FAILED=$((FAILED + 1))
  fi
done

# Prune old backups
PRUNED=$(find "$BACKUP_DIR" -name "*.tar.gz" -mtime +"$RETENTION_DAYS" -print -delete | wc -l)

echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Backup complete: ${SUCCESS} ok, ${FAILED} failed, ${PRUNED} pruned"

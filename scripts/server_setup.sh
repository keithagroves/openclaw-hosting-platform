#!/usr/bin/env bash
# server_setup.sh — Bootstrap a fresh Ubuntu 24.04 server for Clawbot Hosting.
# Run as root: curl -sSL <raw-url> | bash
# Or after cloning: sudo ./scripts/server_setup.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DATA_DIR="/opt/clawbot/data"
ENV_FILE="/opt/clawbot/.env"

echo "==> Clawbot server setup"

# ── Check root ────────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  echo "ERROR: Run as root (sudo $0)" >&2
  exit 1
fi

# ── Install Docker if missing ────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
  echo "==> Installing Docker..."
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
fi

# ── Install jq if missing ────────────────────────────────────────────────────
if ! command -v jq &>/dev/null; then
  echo "==> Installing jq..."
  apt-get install -y jq
fi

# ── Set up directories ───────────────────────────────────────────────────────
echo "==> Creating directories..."
mkdir -p "$DATA_DIR/backups"
mkdir -p /opt/clawbot

# ── Symlink repo into /opt/clawbot ───────────────────────────────────────────
echo "==> Linking repo..."
ln -sfn "$REPO_DIR/scripts" /opt/clawbot/scripts
ln -sfn "$REPO_DIR/webhook" /opt/clawbot/webhook
ln -sfn "$REPO_DIR/docker-compose.caddy.yml" /opt/clawbot/docker-compose.caddy.yml
ln -sfn "$REPO_DIR/docker-compose.webhook.yml" /opt/clawbot/docker-compose.webhook.yml

# ── Make scripts executable ──────────────────────────────────────────────────
chmod +x "$REPO_DIR"/scripts/*.sh "$REPO_DIR"/scripts/clawbot-admin "$REPO_DIR"/scripts/lib/*.sh 2>/dev/null || true

# ── Check for .env ───────────────────────────────────────────────────────────
if [[ ! -f "$ENV_FILE" ]]; then
  echo "==> No .env found at $ENV_FILE"
  echo "    Copy the example and fill in your values:"
  echo "    cp $REPO_DIR/.env.example $ENV_FILE"
  echo "    vi $ENV_FILE"
  echo ""
  echo "    Then re-run this script."
  exit 1
fi

# ── Detect SERVER_IP if blank ────────────────────────────────────────────────
source "$ENV_FILE"
if [[ -z "${SERVER_IP:-}" ]]; then
  DETECTED_IP=$(curl -s http://169.254.169.254/hetzner/v1/metadata/public-ipv4 2>/dev/null || curl -s https://ifconfig.me 2>/dev/null || echo "")
  if [[ -n "$DETECTED_IP" ]]; then
    echo "==> Detected server IP: $DETECTED_IP"
    sed -i "s/^SERVER_IP=.*/SERVER_IP=$DETECTED_IP/" "$ENV_FILE"
  else
    echo "WARNING: Could not detect SERVER_IP. Set it manually in $ENV_FILE"
  fi
fi

# ── Build clawbot-desktop image ──────────────────────────────────────────────
echo "==> Building clawbot-desktop image..."
docker build -t clawbot-desktop:latest "$REPO_DIR"

# ── Create shared network ────────────────────────────────────────────────────
echo "==> Creating Docker network..."
docker network create clawbot_net 2>/dev/null || true

# ── Start Caddy ──────────────────────────────────────────────────────────────
echo "==> Starting Caddy reverse proxy..."
cd /opt/clawbot
docker compose -f docker-compose.caddy.yml --env-file "$ENV_FILE" up -d

# ── Start webhook service ────────────────────────────────────────────────────
echo "==> Starting webhook service..."
docker compose -f docker-compose.webhook.yml --env-file "$ENV_FILE" up -d --build

# ── Install backup cron ──────────────────────────────────────────────────────
echo "==> Installing backup cron job..."
cat > /etc/cron.d/clawbot-backup <<CRON
0 3 * * * root cd /opt/clawbot && /opt/clawbot/scripts/backup_all.sh >> /var/log/clawbot-backup.log 2>&1
CRON

echo ""
echo "==> Setup complete!"
echo "    Admin panel: https://admin.${BASE_DOMAIN:-reptar.ai}"
echo "    SSH:         ssh root@$(grep '^SERVER_IP=' "$ENV_FILE" | cut -d= -f2)"
echo ""
echo "    Next steps:"
echo "    1. Set STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET, STRIPE_PRICE_ID in $ENV_FILE"
echo "    2. Restart webhook: cd /opt/clawbot && docker compose -f docker-compose.webhook.yml --env-file .env up -d"
echo "    3. Configure Stripe webhook endpoint: https://admin.${BASE_DOMAIN:-reptar.ai}/webhook"

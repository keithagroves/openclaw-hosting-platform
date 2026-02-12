# ── SSH Key ────────────────────────────────────────────────────────────────────

resource "hcloud_ssh_key" "clawbot" {
  name       = "clawbot-deploy"
  public_key = file(var.ssh_public_key_path)
}

# ── Firewall ──────────────────────────────────────────────────────────────────

resource "hcloud_firewall" "clawbot" {
  name = "clawbot-fw"

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "22"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "80"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}

# ── Server ────────────────────────────────────────────────────────────────────

resource "hcloud_server" "clawbot" {
  name        = "clawbot-1"
  image       = "ubuntu-24.04"
  server_type = var.server_type
  location    = var.server_location
  ssh_keys    = [hcloud_ssh_key.clawbot.id]

  firewall_ids = [hcloud_firewall.clawbot.id]

  user_data = templatefile("${path.module}/cloud-init.yml", {
    base_domain           = var.base_domain
    cloudflare_api_token  = var.cloudflare_api_token
    cloudflare_zone_id    = var.cloudflare_zone_id
    cloudflare_account_id = var.cloudflare_account_id
    admin_api_key         = local.admin_api_key
    server_ip             = "" # Filled post-creation by server_setup.sh
  })

  labels = {
    app = "clawbot"
  }
}

# ── Admin API Key ─────────────────────────────────────────────────────────────

resource "random_password" "admin_api_key" {
  count   = var.admin_api_key == "" ? 1 : 0
  length  = 32
  special = false
}

locals {
  admin_api_key = var.admin_api_key != "" ? var.admin_api_key : random_password.admin_api_key[0].result
}

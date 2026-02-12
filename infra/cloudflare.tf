# ── DNS Records ──────────────────────────────────────────────────────────────

# Root domain → server
resource "cloudflare_record" "root" {
  zone_id = var.cloudflare_zone_id
  name    = var.base_domain
  content = hcloud_server.clawbot.ipv4_address
  type    = "A"
  proxied = false
}

# admin.domain → server (webhook service)
resource "cloudflare_record" "admin" {
  zone_id = var.cloudflare_zone_id
  name    = "admin"
  content = hcloud_server.clawbot.ipv4_address
  type    = "A"
  proxied = false
}

# Wildcard *.domain → server (customer subdomains)
resource "cloudflare_record" "wildcard" {
  zone_id = var.cloudflare_zone_id
  name    = "*"
  content = hcloud_server.clawbot.ipv4_address
  type    = "A"
  proxied = false
}

output "server_ip" {
  description = "Public IPv4 address of the Clawbot server"
  value       = hcloud_server.clawbot.ipv4_address
}

output "admin_url" {
  description = "Admin panel URL"
  value       = "https://admin.${var.base_domain}"
}

output "admin_api_key" {
  description = "Admin API key (auto-generated if not provided)"
  value       = local.admin_api_key
  sensitive   = true
}

output "ssh_command" {
  description = "SSH into the server"
  value       = "ssh root@${hcloud_server.clawbot.ipv4_address}"
}

output "env_file_hint" {
  description = "Key values needed for .env on the server"
  value       = <<-EOT
    SERVER_IP=${hcloud_server.clawbot.ipv4_address}
    BASE_DOMAIN=${var.base_domain}
    CLOUDFLARE_ZONE_ID=${var.cloudflare_zone_id}
    CLOUDFLARE_ACCOUNT_ID=${var.cloudflare_account_id}
    # CLOUDFLARE_API_TOKEN, STRIPE_*, ADMIN_API_KEY are injected via cloud-init
  EOT
}

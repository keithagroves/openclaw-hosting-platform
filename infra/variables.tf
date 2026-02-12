# ── Hetzner ────────────────────────────────────────────────────────────────────

variable "hcloud_token" {
  description = "Hetzner Cloud API token"
  type        = string
  sensitive   = true
}

variable "server_type" {
  description = "Hetzner server type (cpx31 = 4 vCPU, 8GB; cpx41 = 8 vCPU, 16GB)"
  type        = string
  default     = "cpx31"
}

variable "server_location" {
  description = "Hetzner datacenter location"
  type        = string
  default     = "nbg1"
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key for server access"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

# ── Domain / Cloudflare ───────────────────────────────────────────────────────

variable "cloudflare_api_token" {
  description = "Cloudflare API token (Zone:DNS:Edit + Account:Access:Edit)"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID for your domain"
  type        = string
}

variable "cloudflare_account_id" {
  description = "Cloudflare Account ID (for Zero Trust / Access)"
  type        = string
}

variable "base_domain" {
  description = "Base domain for the platform (e.g. example.com)"
  type        = string
}

# ── App Config ────────────────────────────────────────────────────────────────

variable "repo_url" {
  description = "Git repository URL to clone onto the server"
  type        = string
  default     = "https://github.com/keithgroves/clawbot-hosting.git"
}

variable "admin_api_key" {
  description = "API key for admin endpoints (auto-generated if empty)"
  type        = string
  default     = ""
  sensitive   = true
}

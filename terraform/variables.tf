variable "hcloud_token" {
  description = "Hetzner Cloud API token (project-scoped)."
  type        = string
  sensitive   = true
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key for node access."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "ssh_private_key_path" {
  description = "Path to the matching SSH private key."
  type        = string
  default     = "~/.ssh/id_ed25519"
}

variable "acme_email" {
  description = "Email for Let's Encrypt registration (Traefik ACME)."
  type        = string
  default     = ""
}

variable "argocd_repo_ssh_key" {
  description = "Read-only deploy key (private part) for the barbu-deploy repo, so ArgoCD can read it."
  type        = string
  sensitive   = true
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token: Zone:DNS:Edit on kour0.com + Account Cloudflare Tunnel:Edit + Access: Apps and Policies:Edit."
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Zone ID of kour0.com (Cloudflare dashboard → Overview → API → Zone ID)."
  type        = string
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID (dashboard Zero Trust, ou segment d'URL dash.cloudflare.com/<id>)."
  type        = string
}

variable "admin_email" {
  description = "Email autorisé par la politique Cloudflare Access sur Grafana et ArgoCD."
  type        = string
  default     = ""
}

variable "app_domain" {
  description = "Base host for the web app; api is derived as api.<this>."
  type        = string
  default     = "barbu.kour0.com"
}

variable "admin_domain" {
  description = "Base host for the admin UIs (grafana/argocd). 1er niveau pour rester couvert par l'Universal SSL gratuit (*.kour0.com)."
  type        = string
  default     = "kour0.com"
}

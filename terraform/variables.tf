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
  description = "Cloudflare API token scoped to Zone:DNS:Edit on the kour0.com zone."
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Zone ID of kour0.com (Cloudflare dashboard → Overview → API → Zone ID)."
  type        = string
}

variable "app_domain" {
  description = "Base host for the web app; api and grafana are derived as api.<this> and grafana.<this>."
  type        = string
  default     = "barbu.kour0.com"
}

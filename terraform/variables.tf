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

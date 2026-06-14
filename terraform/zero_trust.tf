# Un seul tunnel Cloudflare devant les UI d'admin privées (Grafana, ArgoCD).
# Remotely-managed (config_src = "cloudflare") : le cloudflared in-cluster ne porte
# que le token ; le routage ingress vit dans cloudflare_zero_trust_tunnel_cloudflared_config.
resource "random_id" "tunnel_secret" {
  byte_length = 35 # >= 32 octets décodés, contrainte de l'API
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "barbu" {
  account_id    = var.cloudflare_account_id
  name          = "barbu-admin"
  config_src    = "cloudflare"
  tunnel_secret = random_id.tunnel_secret.b64_std
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "barbu" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.barbu.id
}

output "tunnel_token" {
  description = "Token pour le cloudflared in-cluster (à injecter dans le secret cloudflared-token)."
  value       = data.cloudflare_zero_trust_tunnel_cloudflared_token.barbu.token
  sensitive   = true
}

output "tunnel_cname" {
  description = "Cible CNAME des hostnames d'admin proxied."
  value       = "${cloudflare_zero_trust_tunnel_cloudflared.barbu.id}.cfargotunnel.com"
}

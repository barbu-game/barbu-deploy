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

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "barbu" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.barbu.id

  config = {
    ingress = [
      {
        hostname = "grafana.${var.admin_domain}"
        service  = "http://kps-grafana.monitoring.svc.cluster.local:80"
      },
      {
        # argocd-server passe en --insecure → HTTP simple sur :80.
        hostname = "argocd.${var.admin_domain}"
        service  = "http://argocd-server.argocd.svc.cluster.local:80"
      },
      {
        hostname = "uptime.${var.admin_domain}"
        service  = "http://uptime-kuma.monitoring.svc.cluster.local:3001"
      },
      {
        service = "http_status:404"
      },
    ]
  }
}

resource "cloudflare_zero_trust_access_policy" "admins" {
  account_id = var.cloudflare_account_id
  name       = "barbu-admins"
  decision   = "allow"

  include = [{
    email = {
      email = var.admin_email
    }
  }]
}

resource "cloudflare_zero_trust_access_application" "grafana" {
  account_id       = var.cloudflare_account_id
  name             = "Barbu Grafana"
  domain           = "grafana.${var.admin_domain}"
  type             = "self_hosted"
  session_duration = "24h"

  policies = [{
    id         = cloudflare_zero_trust_access_policy.admins.id
    precedence = 1
  }]
}

resource "cloudflare_zero_trust_access_application" "argocd" {
  account_id       = var.cloudflare_account_id
  name             = "Barbu ArgoCD"
  domain           = "argocd.${var.admin_domain}"
  type             = "self_hosted"
  session_duration = "24h"

  policies = [{
    id         = cloudflare_zero_trust_access_policy.admins.id
    precedence = 1
  }]
}

resource "cloudflare_zero_trust_access_application" "uptime" {
  account_id       = var.cloudflare_account_id
  name             = "Barbu Uptime Kuma"
  domain           = "uptime.${var.admin_domain}"
  type             = "self_hosted"
  session_duration = "24h"

  policies = [{
    id         = cloudflare_zero_trust_access_policy.admins.id
    precedence = 1
  }]
}

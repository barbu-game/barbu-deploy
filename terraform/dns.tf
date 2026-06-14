locals {
  # web et api restent servis par Traefik sur l'IP du worker (grey cloud).
  # grafana/argocd passent par le tunnel (CNAME proxied, plus bas).
  dns_records = {
    web = var.app_domain
    api = "api.${var.app_domain}"
  }
}

# All three hosts point at the worker's public IP, where Klipper exposes Traefik.
# proxied = false (grey cloud): Cloudflare's proxy would break Traefik's ACME
# HTTP challenge and the WebSocket upgrade, so DNS-only is mandatory here.
resource "cloudflare_dns_record" "app" {
  for_each = local.dns_records

  zone_id = var.cloudflare_zone_id
  name    = each.value
  type    = "A"
  content = module.kube-hetzner.agents_public_ipv4[0]
  ttl     = 1 # automatic
  proxied = false
}

# Les UI d'admin atteignent le cluster via le tunnel, pas l'IP du worker.
# proxied = true (orange cloud) pour que Cloudflare Access garde au bord ; le tunnel
# est sortant-seul, donc aucun port entrant exposé et les contraintes ACME/WebSocket
# qui imposent le grey-cloud sur web/api ne s'appliquent pas ici (TLS terminé par Cloudflare).
resource "cloudflare_dns_record" "admin" {
  for_each = toset(["grafana", "argocd"])

  zone_id = var.cloudflare_zone_id
  name    = "${each.key}.${var.app_domain}"
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.barbu.id}.cfargotunnel.com"
  ttl     = 1 # automatic
  proxied = true
}

output "ingress_ipv4" {
  description = "Worker public IPv4 the DNS records point at."
  value       = module.kube-hetzner.agents_public_ipv4[0]
}

output "app_hosts" {
  description = "Hostnames served by the cluster."
  value       = values(local.dns_records)
}

locals {
  # web and api stay served by Traefik on the worker's IP (grey cloud).
  # grafana/argocd go through the tunnel (proxied CNAME, below).
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

# Admin UIs reach the cluster through the tunnel, not the worker's IP.
# proxied = true (orange cloud) so Cloudflare Access guards at the edge; the tunnel
# is egress-only, so no inbound port is exposed and the ACME/WebSocket constraints
# that force grey-cloud on web/api don't apply here (TLS terminated by Cloudflare).
resource "cloudflare_dns_record" "admin" {
  for_each = toset(["grafana", "argocd", "uptime"])

  zone_id = var.cloudflare_zone_id
  name    = "${each.key}.${var.admin_domain}"
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

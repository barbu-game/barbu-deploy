locals {
  # The web app sits on app_domain; api and grafana are derived subdomains.
  dns_records = {
    web     = var.app_domain
    api     = "api.${var.app_domain}"
    grafana = "grafana.${var.app_domain}"
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

output "ingress_ipv4" {
  description = "Worker public IPv4 the DNS records point at."
  value       = module.kube-hetzner.agents_public_ipv4[0]
}

output "app_hosts" {
  description = "Hostnames served by the cluster."
  value       = values(local.dns_records)
}

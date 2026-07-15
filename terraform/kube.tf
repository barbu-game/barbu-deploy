module "kube-hetzner" {
  source  = "kube-hetzner/kube-hetzner/hcloud"
  version = "2.18.0" # pin: reconcile traefik_values/extra-manifests against this version

  providers = { hcloud = hcloud }

  hcloud_token    = var.hcloud_token
  ssh_public_key  = file(var.ssh_public_key_path)
  ssh_private_key = file(var.ssh_private_key_path)

  network_region = "eu-central"

  control_plane_nodepools = [
    {
      name        = "control-plane"
      server_type = "cx23"
      location    = "nbg1"
      labels      = []
      taints      = [] # kube-hetzner taints control-plane by default (no app workloads)
      count       = 1
    }
  ]

  agent_nodepools = [
    {
      name        = "worker"
      server_type = "cx33"
      location    = "nbg1"
      labels      = []
      taints      = []
      count       = 1
    }
  ]

  # Élasticité des machines : le cluster-autoscaler ajoute/retire des VM worker sous charge. Taint
  # `barbu.dev/elastic` + toleration côté chart barbu-server → seuls les pods serveur élastiques y
  # atterrissent ; le socle reste sur le nodepool `worker` fixe. min 0 = 0 nœud (0 coût) au repos.
  autoscaler_nodepools = [
    {
      name        = "elastic"
      server_type = "cx23"
      location    = "nbg1"
      min_nodes   = 0
      max_nodes   = 3
      taints = [
        {
          key    = "barbu.dev/elastic"
          value  = "true"
          effect = "NoSchedule"
        }
      ]
    }
  ]

  # Scale-down patient (évite le flapping ; facturation Hetzner horaire de toute façon).
  cluster_autoscaler_extra_args = [
    "--scale-down-unneeded-time=10m",
    "--scale-down-delay-after-add=10m",
  ]

  # Ingress: Traefik (default), exposed on the worker's public IP via Klipper — no billed Hetzner LB.
  ingress_controller      = "traefik"
  enable_klipper_metal_lb = true

  # The default firewall whitelists egress (53/80/123/443/icmp). cloudflared needs port
  # 7844 outbound to reach the Cloudflare edge: UDP for QUIC, TCP as the http2 fallback.
  extra_firewall_rules = [
    {
      description     = "cloudflared tunnel QUIC egress"
      direction       = "out"
      protocol        = "udp"
      port            = "7844"
      source_ips      = []
      destination_ips = ["0.0.0.0/0", "::/0"]
    },
    {
      description     = "cloudflared tunnel http2 egress"
      direction       = "out"
      protocol        = "tcp"
      port            = "7844"
      source_ips      = []
      destination_ips = ["0.0.0.0/0", "::/0"]
    },
  ]

  # We use Traefik's own ACME, not cert-manager.
  enable_cert_manager = false

  # Pin: kured ≥1.20 renamed its manifest asset to `-combined.yaml`, but module 2.18.0
  # still fetches `kured-<v>-dockerhub.yaml`. 1.19.0 is the last release shipping that name.
  kured_version = "1.19.0"

  # Pin the chart: overriding traefik_values REPLACES the module's defaults wholesale, so the
  # schema must match this exact version (40.x/Traefik v3.7 moved redirect+TLS under ports.*.http).
  traefik_version = "40.2.0"

  # Single-replica Traefik terminating TLS via its own ACME (Let's Encrypt). Recreate strategy
  # so the RWO ACME volume isn't held by two pods during a rollout. publishedservice arg restored
  # from the module default (lost when overriding) so Ingress status gets the real ingress IP.
  traefik_values = <<-EOT
    deployment:
      replicas: 1
      # Mesh Traefik so its egress to the meshed app pods is mTLS. skip-inbound-ports keeps the
      # external listeners (web 8000 / websecure 8443 / dashboard-ping 8080 / metrics 9100) out of the
      # proxy — they receive non-mTLS external traffic and must not be intercepted.
      podAnnotations:
        linkerd.io/inject: enabled
        config.linkerd.io/skip-inbound-ports: "8000,8443,8080,9100"
    updateStrategy:
      type: Recreate
    service:
      type: LoadBalancer
    # fsGroup so the kubelet chowns the CSI volume to Traefik's gid — otherwise the
    # non-root process can't create /data/acme.json and the ACME resolver is skipped.
    podSecurityContext:
      fsGroup: 65532
      fsGroupChangePolicy: OnRootMismatch
      runAsGroup: 65532
      runAsNonRoot: true
      runAsUser: 65532
    persistence:
      enabled: true
      storageClass: hcloud-volumes
      size: 10Gi
      path: /data
    certificatesResolvers:
      le:
        acme:
          email: ${var.acme_email}
          storage: /data/acme.json
          httpChallenge:
            entryPoint: web
    ports:
      web:
        http:
          redirections:
            entryPoint:
              to: websecure
              scheme: https
              permanent: true
      websecure:
        http:
          tls:
            enabled: true
            certResolver: le
    additionalArguments:
      - "--providers.kubernetesingress.ingressendpoint.publishedservice=traefik/traefik"
  EOT

  # Bootstrap ArgoCD : on attend seulement le repo-server. Le secret du repo
  # (barbu-deploy-repo) est créé hors-git (cf. docs/secrets-runbook.md) : il ne peut
  # pas l'être ici car extra_kustomize_parameters n'alimente que le rendu templatefile
  # des .tpl, jamais l'environnement shell — $ARGOCD_REPO_SSH_KEY y était donc toujours
  # vide et réécrasait le secret en clé vide à chaque apply.
  extra_kustomize_deployment_commands = <<-EOT
    kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=300s
  EOT
}

output "kubeconfig" {
  value     = module.kube-hetzner.kubeconfig
  sensitive = true
}

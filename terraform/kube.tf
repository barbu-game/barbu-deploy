module "kube-hetzner" {
  source  = "kube-hetzner/kube-hetzner/hcloud"
  version = "2.18.0" # pin: reconcile traefik_values/extra-manifests against this version

  providers = { hcloud = hcloud }

  hcloud_token    = var.hcloud_token
  ssh_public_key  = file(var.ssh_public_key_path)
  ssh_private_key = file(var.ssh_private_key_path)

  network_region = "eu-central"

  # Single worker: an auto k3s/OS upgrade cordons+drains it, evicting Traefik and downing the site.
  # Upgrade manually in a chosen window.
  automatically_upgrade_k3s = false
  automatically_upgrade_os  = false

  # Control-plane HA: 3 etcd members (quorum tolerates 1 failure) across 3 DCs. The existing
  # `control-plane` nodepool (nbg1) stays untouched so the CP isn't recreated in place; the two
  # added nodepools (fsn1, hel1) plus the apiserver LB give an HA endpoint.
  control_plane_nodepools = [
    {
      name        = "control-plane"
      server_type = "cx33"
      location    = "nbg1"
      labels      = []
      taints      = [] # kube-hetzner taints control-plane by default (no app workloads)
      count       = 1
    },
    {
      name        = "control-plane-fsn"
      server_type = "cx33"
      location    = "fsn1"
      labels      = []
      taints      = []
      count       = 1
    },
    {
      name        = "control-plane-hel"
      server_type = "cx33"
      location    = "hel1"
      labels      = []
      taints      = []
      count       = 1
    }
  ]

  use_control_plane_lb = true

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

  # Cluster-autoscaler adds/removes worker VMs under load. The `barbu.dev/elastic` taint + matching
  # toleration keep only elastic server pods here; the baseline stays on the fixed `worker` nodepool.
  # min 0 scales to zero (no cost) when idle.
  autoscaler_nodepools = [
    {
      name        = "elastic"
      server_type = "cx33"          # same profile as the baseline worker; 1 node holds all elastic pods
      location    = "nbg1"
      min_nodes   = 0
      max_nodes   = 2               # 1 cx33 covers peak KEDA load (~6 elastic pods); +1 for headroom
      taints = [
        {
          key    = "barbu.dev/elastic"
          value  = "true"
          effect = "NoSchedule"
        }
      ]
    }
  ]

  # Patient scale-down avoids flapping (Hetzner bills hourly).
  # skip-nodes-with-local-storage=false: meshed pods carry ephemeral emptyDirs (Linkerd sidecar,
  # app /tmp); without the flag the autoscaler won't evict them and scale-to-zero never happens.
  cluster_autoscaler_extra_args = [
    "--scale-down-unneeded-time=10m",
    "--scale-down-delay-after-add=10m",
    "--skip-nodes-with-local-storage=false",
  ]

  # Traefik ingress on the worker's public IP via Klipper — no billed Hetzner LB.
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

  # Traefik's own ACME handles certs; cert-manager off.
  enable_cert_manager = false

  # Pin: module 2.18.0 fetches `kured-<v>-dockerhub.yaml`; kured ≥1.20 renamed that asset to
  # `-combined.yaml`. 1.19.0 is the last release shipping the old name.
  kured_version = "1.19.0"

  # Overriding traefik_values replaces the module defaults wholesale, so the schema must match this
  # chart version (40.x/Traefik v3.7 moved redirect+TLS under ports.*.http).
  traefik_version = "40.2.0"

  # Single-replica Traefik terminating TLS via its own ACME (Let's Encrypt). Recreate strategy so the
  # RWO ACME volume isn't held by two pods during rollout. publishedservice arg restored (lost when
  # overriding defaults) so Ingress status reports the real ingress IP.
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

  # Bootstrap ArgoCD: wait only for the repo-server. The repo secret (barbu-deploy-repo) is created
  # out-of-git because extra_kustomize_parameters feeds only the templatefile render, not the shell
  # env — $ARGOCD_REPO_SSH_KEY would be empty and overwrite the secret with an empty key each apply.
  extra_kustomize_deployment_commands = <<-EOT
    kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=300s
  EOT
}

output "kubeconfig" {
  value     = module.kube-hetzner.kubeconfig
  sensitive = true
}

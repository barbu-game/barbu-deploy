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

  # Ingress: Traefik (default), exposed on the worker's public IP via Klipper — no billed Hetzner LB.
  ingress_controller      = "traefik"
  enable_klipper_metal_lb = true

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

  # Bootstrap ArgoCD after the cluster is up, then hand it the deploy key + app-of-apps.
  extra_kustomize_deployment_commands = <<-EOT
    kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=300s
    kubectl -n argocd create secret generic barbu-deploy-repo \
      --from-literal=type=git \
      --from-literal=url=ssh://git@ssh.github.com:443/barbu-game/barbu-deploy.git \
      --from-literal=sshPrivateKey="$ARGOCD_REPO_SSH_KEY" \
      --dry-run=client -o yaml | kubectl apply -f - \
      && kubectl -n argocd label secret barbu-deploy-repo argocd.argoproj.io/secret-type=repository --overwrite
  EOT

  extra_kustomize_parameters = {
    ARGOCD_REPO_SSH_KEY = var.argocd_repo_ssh_key
  }
}

output "kubeconfig" {
  value     = module.kube-hetzner.kubeconfig
  sensitive = true
}

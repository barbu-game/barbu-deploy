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

  traefik_values = <<-EOT
    persistence:
      enabled: true
      size: 128Mi
    certificatesResolvers:
      le:
        acme:
          email: ${var.acme_email}
          storage: /data/acme.json
          httpChallenge:
            entryPoint: web
    ports:
      web:
        redirectTo:
          port: websecure
      websecure:
        tls:
          certResolver: le
  EOT

  # Bootstrap ArgoCD after the cluster is up, then hand it the deploy key + app-of-apps.
  extra_kustomize_deployment_commands = <<-EOT
    kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=300s
    kubectl -n argocd create secret generic barbu-deploy-repo \
      --from-literal=type=git \
      --from-literal=url=git@github.com:barbu-game/barbu-deploy.git \
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

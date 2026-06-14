apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - argocd-namespace.yaml
  - https://raw.githubusercontent.com/argoproj/argo-cd/v2.13.2/manifests/install.yaml
  - app-of-apps.yaml
namespace: argocd
# argocd-server termine derrière le Cloudflare Tunnel (TLS terminé par Cloudflare) :
# --insecure pour servir du HTTP simple sur :80, sinon redirection HTTPS en boucle.
patches:
  - patch: |-
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: argocd-cmd-params-cm
      data:
        server.insecure: "true"

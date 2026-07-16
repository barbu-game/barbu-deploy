apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - argocd-namespace.yaml
  - https://raw.githubusercontent.com/argoproj/argo-cd/v2.13.2/manifests/install.yaml
  - app-of-apps.yaml
namespace: argocd
# argocd-server sits behind the Cloudflare Tunnel (TLS terminated by Cloudflare):
# --insecure to serve plain HTTP on :80, otherwise an HTTPS redirect loop.
patches:
  - patch: |-
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: argocd-cmd-params-cm
      data:
        server.insecure: "true"

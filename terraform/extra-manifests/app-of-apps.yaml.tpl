apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: barbu
  namespace: argocd
spec:
  project: default
  source:
    repoURL: ssh://git@ssh.github.com:443/barbu-game/barbu-deploy.git
    targetRevision: main
    path: argocd/apps
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true

# barbu-deploy

Deployment artifacts for the Barbu stack (GitOps via ArgoCD).

```
charts/barbu-server   Helm chart — Micronaut game server (single replica, sticky WS routing)
charts/barbu-web      Helm chart — Next.js client (stateless, scaled)
argocd/app-of-apps    Root ArgoCD Application
argocd/apps/*         Child Applications (server, web)
docker-compose.yml    Local full stack (postgres + redis + server + web)
```

## Local

```sh
docker compose up --build
# web:    http://localhost:3000
# server: http://localhost:8080/health
```

## Cluster

1. Build and push images to `ghcr.io/<org>/barbu-server` and `barbu-web`.
2. Replace `REPLACE_ORG` in `argocd/` and `charts/*/values.yaml`.
3. Apply the root app: `kubectl apply -f argocd/app-of-apps.yaml`.

ArgoCD reconciles the child Applications, which render the Helm charts into the
`barbu` namespace. Image bumps are picked up by ArgoCD Image Updater (or a CI
commit to the chart values).

> The game server holds room state in memory, so it runs a single replica with
> cookie-affinity ingress for now. Horizontal sharding (a Redis room directory
> routing each table to a pod) is the next step.

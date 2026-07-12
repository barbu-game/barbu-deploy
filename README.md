# barbu-deploy

Deployment artifacts for the Barbu stack (GitOps via ArgoCD). Kubernetes is the only
deployment target; local development runs each service from its own repo.

```
charts/barbu-server   Helm chart — Micronaut game server (StatefulSet, per-pod WS routing)
charts/barbu-redis    Helm chart — Redis (room leases, snapshots, reconnect index)
charts/barbu-web      Helm chart — Next.js client (stateless, scaled)
argocd/app-of-apps    Root ArgoCD Application
argocd/apps/*         Child Applications (server, redis, web, …)
```

## Cluster

1. Build and push images to `ghcr.io/barbu-game/barbu-server` and `barbu-web`.
2. Apply the root app: `kubectl apply -f argocd/app-of-apps.yaml`.

ArgoCD reconciles the child Applications, which render the Helm charts into the
`barbu` namespace. Image bumps are picked up by ArgoCD Image Updater (or a CI
commit to the chart values).

> Room state (ownership lease + game snapshot + reconnect index) is externalized to
> Redis, so a table survives the loss or reschedule of its owning pod: a surviving pod
> rehydrates it from the snapshot and clients reconnect. The server therefore runs
> multi-replica as a StatefulSet; each table is reachable on its owning pod via the
> `/pod/<pod>` ingress path, while the sticky-cookie Service still pins the initial
> lobby/matchmaking flow.

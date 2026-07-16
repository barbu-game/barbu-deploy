# Load test — demonstrating KEDA scale-out

`rooms.js` spins up active tables to push the `barbu_rooms_active` metric past the
KEDA threshold (~10 tables/pod) and trigger pod additions. This is the "business autoscaling"
proof that Docker Compose cannot deliver.

## Run

```sh
# Prerequisite: k6 (https://k6.io). WS_URL = the server's public endpoint.
k6 run -e WS_URL=wss://api.barbu.kour0.com/ws/game load/rooms.js

# Heavier load / longer hold:
k6 run -e WS_URL=wss://api.barbu.kour0.com/ws/game -e HOLD_MS=300000 load/rooms.js
```

## Watch the scale-out

In another terminal, while k6 is running:

```sh
kubectl -n barbu get scaledobject,hpa,pods -w
```

Expected:
1. `barbu_rooms_active` climbs (also visible on the Grafana "Barbu — Scaling & self-healing" dashboard).
2. The KEDA-managed HPA increases the `barbu-server` StatefulSet replicas (2 → … up to 8).
3. When k6 stops, after the stabilization window (~5 min), the replicas scale back down — each
   removed pod **drains** its tables (readiness NotReady, then releases its leases), so **without loss**.

## Contrast with Docker Compose (the ammunition)

Under `docker compose` (single-host, single replica, manual and static `scale`):
- **no autoscaling**: the same load triggers no container addition;
- **no shared state**: restarting/recreating the server container **loses in-progress games**
  (nothing to rehydrate).

Under Kubernetes, the same load scales automatically, and the chaos test
(`barbu-server/app/.../chaos/SelfHealingChaosTest`) proves that killing the pod that owns a table
**does not lose the game**: another pod rehydrates it from Redis.

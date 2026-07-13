# Load test — démontrer le scale-out KEDA

`rooms.js` génère des tables actives pour faire monter la métrique `barbu_rooms_active` au-delà du
seuil KEDA (~10 tables/pod) et déclencher l'ajout de pods. C'est la preuve « autoscaling métier »
que Docker Compose ne peut pas fournir.

## Lancer

```sh
# Prérequis : k6 (https://k6.io). WS_URL = endpoint public du serveur.
k6 run -e WS_URL=wss://api.barbu.kour0.com/ws/game load/rooms.js

# Charge plus forte / tenue plus longue :
k6 run -e WS_URL=wss://api.barbu.kour0.com/ws/game -e HOLD_MS=300000 load/rooms.js
```

## Observer le scale-out

Dans un autre terminal, pendant que k6 tourne :

```sh
kubectl -n barbu get scaledobject,hpa,pods -w
```

Attendu :
1. `barbu_rooms_active` grimpe (visible aussi sur le dashboard Grafana « Barbu — Scaling & self-healing »).
2. Le HPA géré par KEDA augmente les réplicas du StatefulSet `barbu-server` (2 → … jusqu'à 8).
3. À l'arrêt de k6, après la fenêtre de stabilisation (~5 min), les réplicas redescendent — chaque
   pod retiré **draine** ses tables (readiness NotReady puis relâche des leases), donc **sans perte**.

## Contraste Docker Compose (la munition)

Sous `docker compose` (mono-hôte, réplique unique, `scale` manuel et statique) :
- **aucun autoscaling** : la même charge ne provoque aucun ajout de conteneur ;
- **pas de state partagé** : redémarrer/recréer le conteneur serveur **perd les parties en cours**
  (rien à réhydrater).

Sous Kubernetes, la même charge scale automatiquement, et le chaos test
(`barbu-server/app/.../chaos/SelfHealingChaosTest`) prouve que tuer le pod propriétaire d'une table
**ne perd pas la partie** : un autre pod la réhydrate depuis Redis.

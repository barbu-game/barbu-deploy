# barbu-db

CloudNativePG Postgres cluster for Barbu: one instance on a `hcloud-volumes`
PVC, the `barbu` database, the app owner role, and a read-only `grafana_ro`
role. Synced by the `barbu-db` ArgoCD application (`prune` + `selfHeal`).

## Backups (S3 / PITR)

The chart ships a complete, production-ready backup path:

- a daily `ScheduledBackup` (base backup at 03:00 UTC),
- continuous WAL archiving via `barmanObjectStore` (point-in-time recovery),
- a 30-day retention policy,
- S3 credentials from the `barbu-backup-s3` secret.

It is **disabled by default** (`backup.enabled: false`). Rationale: Hetzner
Object Storage bills a flat ~6 €/month minimum regardless of usage, which is
disproportionate for a sub-100 MB database whose live game state lives in
Redis. The wiring is kept intact so it can be turned on unchanged.

### Enable

1. Create the bucket referenced by `backup.destinationPath`
   (`s3://barbu-backups/barbu`) in the Hetzner project.
2. Provision the `barbu-backup-s3` secret (keys `ACCESS_KEY_ID`,
   `ACCESS_SECRET_KEY`) — see `charts/cluster-secrets` and
   `docs/secrets-runbook.md`.
3. Set `backup.enabled: true` in `values.yaml`, commit, and let ArgoCD sync.
4. Verify a `Backup` object reaches `completed`:
   `kubectl -n barbu get backups.postgresql.cnpg.io`.

### Disable

Set `backup.enabled: false` and let ArgoCD prune the `ScheduledBackup` and drop
the `barmanObjectStore` block. Disabling stops all writes but does **not** stop
billing — delete the `barbu-backups` bucket in Hetzner to actually clear the
flat fee.

## Restore

Restore a fresh cluster from object storage with a `bootstrap.recovery`
`externalCluster` pointing at the same `barmanObjectStore`; select a target
time for PITR. See the CNPG recovery docs and `docs/plans` cutover runbook.

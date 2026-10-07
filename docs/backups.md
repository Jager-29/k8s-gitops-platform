# Backups and restore

| Data | Tool | Schedule | Destination | Retention | Restore tested |
|---|---|---|---|---|---|
| PostgreSQL gitea-pg, gravitee-pg (Gravitee + Keycloak) | Barman Cloud plugin: continuous WAL archiving + ScheduledBackup | 02:00 UTC | Garage `cnpg` | 7 days | Yes, with WAL replay |
| OpenBao | CronJob Raft snapshot (`backups/openbao-snapshot.yaml`) | 03:30 Europe/Paris | Garage `openbao` | 7 days | Integrity only (see below) |
| Gitea files (repositories, attachments, packages, app.ini) | CronJob `gitea dump --skip-db` (`backups/gitea-dump.yaml`) | 02:30 Europe/Paris | Garage `app-dumps/gitea/` | 7 days | Content checked |
| Grafana SQLite | CronJob SQLite backup API + integrity_check (`backups/grafana-db.yaml`) | 02:30 Europe/Paris | Garage `app-dumps/grafana/` | 7 days | Content checked |
| Kubernetes objects, all namespaces | Velero, schedule `velero-daily` | 03:00 UTC | Garage `velero` | 168 h | Yes, namespace mapping |
| Virtual machines (nodes, s3-01) | Veeam | Veeam plan | Veeam repository | Veeam policy | Not yet |

## Storage: Garage

MinIO Community Edition was ruled out (repository archived, no more binaries). Garage v2.4 runs as a systemd service on `s3-01` (`infra/garage/`): 90 GB layout, dedicated logical volume mounted on `/var/lib/garage` (`RequiresMountsFor` in the unit), S3 API on 3900 open to the two Kubernetes nodes only, admin API on 127.0.0.1. One bucket and one key per consumer: `cnpg`, `openbao`, `velero`, `app-dumps`.

Recent AWS SDKs send checksums that S3 compatible servers reject; every client sets `AWS_REQUEST_CHECKSUM_CALCULATION` and `AWS_RESPONSE_CHECKSUM_VALIDATION` to `when_required` (Velero uses `checksumAlgorithm: ""`).

Do not write anything else in the Velero bucket: Velero refuses unknown prefixes and marks the location Unavailable. That is why application dumps have their own bucket.

## Why application dumps

The local-path volumes are hostPath volumes, which Velero file system backup does not support. Velero keeps the Kubernetes objects; the data of Gitea and Grafana is saved by the two CronJobs, the databases by Barman.

* **gitea-dump** runs `gitea dump` inside the Gitea pod through `kubectl exec` (dedicated Role limited to get/list pods and create pods/exec), checks the archive with `tar -tzf`, copies it out and compares the sha256 on both sides before the upload. kubectl is downloaded at each run and checked against its sha256.
* **grafana-db** mounts the Grafana volume read only and uses the SQLite online backup API, then `PRAGMA integrity_check`, before a second container uploads the copy.
* **openbao-snapshot** logs in with the Kubernetes auth method (role limited to `sys/storage/raft/snapshot`), saves the snapshot in a memory backed volume, uploads it and purges files older than 7 days.

## Restore procedures

### PostgreSQL (tested: a marker written after the base backup was found in the restored cluster)

Create a new cluster in the same namespace as the ObjectStore, without a `plugins` block so that it does not archive, same major version:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: gravitee-pg-restore
  namespace: gravitee
spec:
  instances: 1
  imageName: ghcr.io/cloudnative-pg/postgresql:16
  storage:
    size: 10Gi
    storageClass: local-path
  bootstrap:
    recovery:
      source: origin
  externalClusters:
    - name: origin
      plugin:
        name: barman-cloud.cloudnative-pg.io
        parameters:
          barmanObjectName: garage
          serverName: gravitee-pg-cluster
```

Add `bootstrap.recovery.recoveryTarget.targetTime` for a point in time recovery. Restore takes less than two minutes for this size.

### Gitea and Grafana

`tools/s3-latest.sh` downloads the latest object of a prefix with the credentials of a namespace, then checks the size:

```bash
tools/s3-latest.sh gitea app-dumps-s3 app-dumps gitea/ /dev/shm/gitea-dump.tar.gz
tools/s3-latest.sh monitoring app-dumps-s3 app-dumps grafana/ /dev/shm/grafana.db
```

Gitea: stop the deployment, extract the archive into `/data`, restore the database from Barman, start. Grafana: stop it, replace `/var/lib/grafana/grafana.db`, start. Delete the downloaded files afterwards with `shred -u`, they contain sensitive data.

### OpenBao

A snapshot is a tar.gz with `meta.json`, `state.bin`, `SHA256SUMS` and `SHA256SUMS.sealed`. `sha256sum -c SHA256SUMS` checks integrity, but `SHA256SUMS.sealed` is encrypted with the vault key: only a real restore proves the snapshot is usable. Planned test: a temporary empty OpenBao, `bao operator raft snapshot restore -force`, then unseal with 2 of the 3 real keys. Without the unseal keys, a snapshot is useless: they are part of the backup.

### Velero

```bash
velero restore create test-restore --from-backup <backup> \
  --include-namespaces oauth2-proxy --namespace-mappings oauth2-proxy:restore-test \
  --exclude-resources ingressroutes.traefik.io,ingresses.networking.k8s.io
```

Routes are excluded so that the restored copy does not compete with the live one in Traefik. The ExternalSecret resynchronizes from OpenBao by itself.

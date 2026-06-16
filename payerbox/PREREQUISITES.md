# payerbox — cluster prerequisites

The `payerbox` umbrella (and the standalone `fhir-app-portal` / `interop` / `prior-auth`
charts) deploy **only the applications and the two Aidbox instances**. By design they do
**not** create the database or any Secrets — those are infrastructure concerns that vary
per cloud/customer and need far more configuration than a Helm chart should own (backups,
WAL archiving, replication, snapshot classes, secret stores, key conventions…).

Provision the following in your cluster **before** installing the charts.

---

## 1. Operators & controllers

| Component | Why | Notes |
|-----------|-----|-------|
| **CloudNativePG operator** | PostgreSQL for both Aidboxes | provides the `Cluster` CRD; see §2 |
| **External Secrets Operator** + a `ClusterSecretStore` | sync Secrets from your secret manager (GCP SM / AWS SM) | see §3 |
| **ingress-nginx** (or your ingress controller) | portal + Aidbox ingress | `ingressClassName` is a chart value |
| **cert-manager** + a `ClusterIssuer` (e.g. `letsencrypt`) | TLS for the ingresses | referenced via ingress annotations |
| Prometheus / kube-prometheus-stack | Aidbox metrics (optional) | `serviceMonitor`/`PodMonitor` |

---

## 2. PostgreSQL (CloudNativePG)

The charts expect a reachable Postgres with **two databases** — `portal` (admin Aidbox) and
`sandbox` (sandbox Aidbox) — owned by a role whose credentials are also placed in the Aidbox
Secrets (§3). The chart's default `aidbox-*.config.BOX_DB_HOST` is `payerbox-db-rw`, i.e. the
`-rw` Service of a CNPG `Cluster` named `payerbox-db`. Override `BOX_DB_HOST`/`BOX_DB_DATABASE`
if your naming differs.

**Coupling to remember:**
- The CNPG role password **must equal** the Aidbox `BOX_DB_PASSWORD` (§3). Easiest: source both
  from the same secret-manager keys, or have CNPG use a predefined basic-auth secret.
- Aidbox needs its extensions; the CNPG role may need privileges (or pre-create extensions via
  `postInitSQL`). Note `pg_stat_statements` requires superuser — pre-create it if you want it.

### Example `Cluster` (production-grade, GCS backups) — adapt per environment

```yaml
---
apiVersion: barmancloud.cnpg.io/v1
kind: ObjectStore
metadata:
  name: payerbox-db-store
spec:
  configuration:
    destinationPath: gs://<your-bucket>/payerbox-postgres-backup
    googleCredentials: { gkeEnvironment: true }
    data: { compression: snappy }
    wal: { compression: snappy }
  retentionPolicy: 84m
---
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: payerbox-db            # -> Service payerbox-db-rw  (== BOX_DB_HOST)
spec:
  instances: 3
  imageCatalogRef:
    apiGroup: postgresql.cnpg.io
    kind: ClusterImageCatalog
    name: postgresql-standard-trixie
    major: 18
  bootstrap:
    initdb:
      database: portal          # admin Aidbox DB
      owner: aidbox             # role whose password == Aidbox BOX_DB_PASSWORD
      secret:
        name: payerbox-db-credentials   # basic-auth secret (§3)
      postInitSQL:
        - CREATE DATABASE sandbox OWNER aidbox;   # sandbox Aidbox DB
  enablePDB: true
  plugins:
    - name: barman-cloud.cloudnative-pg.io
      isWALArchiver: true
      parameters: { barmanObjectName: payerbox-db-store }
  postgresql:
    parameters:
      shared_buffers: "1GB"
      max_slot_wal_keep_size: "10GB"
      pg_stat_statements.max: "10000"
      pg_stat_statements.track: all
    synchronous: { method: any, number: 1, dataDurability: required, failoverQuorum: true }
  backup:
    volumeSnapshot: { className: csi-gce-pd-snapshot }
  resources:
    requests: { cpu: 200m, memory: 4Gi }
  serviceAccountTemplate:
    metadata: { name: payerbox-db }     # Workload Identity for GCS, if used
  storage:
    pvcTemplate:
      accessModes: [ReadWriteOnce]
      resources: { requests: { storage: 500Gi } }
      storageClassName: hyperdisk-balanced
      volumeMode: Filesystem
---
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: payerbox-db
spec:
  cluster: { name: payerbox-db }
  method: volumeSnapshot
  schedule: "0 0 0 * * *"
  backupOwnerReference: cluster
---
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: payerbox-db
spec:
  selector: { matchLabels: { cnpg.io/cluster: payerbox-db } }
  podMetricsEndpoints: [ { port: metrics } ]
```

> AWS: use RDS/Aurora or CNPG with S3 (`barmanObjectStore` S3 + IRSA) instead. The charts only
> care that `BOX_DB_HOST` resolves and the two databases exist.

---

## 3. Secrets

All Secrets are consumed via `envFrom` and must exist in the release namespace **before**
install. Provision them with External Secrets Operator (recommended) or any tool. Names below
are the chart defaults.

| Secret | Consumed by | Required keys |
|--------|-------------|---------------|
| `payerbox-db-credentials` (basic-auth) | CNPG `Cluster` (§2) | `username` (= `aidbox`), `password` |
| `aidbox-admin-env` | admin Aidbox (`extraEnvFromSecrets`) | `BOX_LICENSE`, `BOX_ADMIN_PASSWORD`, `BOX_ROOT_CLIENT_SECRET`, `BOX_DB_USER`, `BOX_DB_PASSWORD`, `ADMIN_API_CLIENT_SECRET`, `INTEROP_APP_CLIENT_SECRET`, `PRIOR_AUTH_APP_CLIENT_SECRET` |
| `aidbox-sandbox-env` | sandbox Aidbox | `BOX_LICENSE`, `BOX_ADMIN_PASSWORD`, `BOX_ROOT_CLIENT_SECRET`, `BOX_DB_USER`, `BOX_DB_PASSWORD`, `DEVELOPER_API_CLIENT_SECRET` |
| `fhir-app-portal-secrets` | fhir-app-portal | `SESSION_SECRET`, `ADMIN_API_CLIENT_SECRET`, `DEVELOPER_API_CLIENT_SECRET` |
| `interop-secrets` | interop | `AIDBOX_CLIENT_SECRET`, `AIDBOX_APP_SECRET` |
| `prior-auth-secrets` | prior-auth | `AIDBOX_CLIENT_SECRET`, `AIDBOX_APP_SECRET` |

**Consistency requirements:**
- `aidbox-*-env.BOX_DB_USER/BOX_DB_PASSWORD` **must match** the CNPG role (`payerbox-db-credentials`).
- The client secrets in `aidbox-admin-env` (`*_CLIENT_SECRET`) **must match** the corresponding
  app Secrets — `ADMIN_API_CLIENT_SECRET` ↔ `fhir-app-portal-secrets`, `INTEROP_APP_CLIENT_SECRET`
  ↔ `interop-secrets.AIDBOX_CLIENT_SECRET`, `PRIOR_AUTH_APP_CLIENT_SECRET` ↔
  `prior-auth-secrets.AIDBOX_CLIENT_SECRET`. Source them from the same secret-manager keys.

### Example `ExternalSecret` (GCP Secret Manager)

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: interop-secrets
spec:
  refreshInterval: 1h
  secretStoreRef: { kind: ClusterSecretStore, name: gcp-store }
  target: { name: interop-secrets, creationPolicy: Owner, deletionPolicy: Retain }
  data:
    - { secretKey: AIDBOX_CLIENT_SECRET, remoteRef: { key: interop--aidbox-client-secret } }
    - { secretKey: AIDBOX_APP_SECRET,    remoteRef: { key: interop--aidbox-app-secret } }
```

The basic-auth DB secret needs a template type:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: payerbox-db-credentials
spec:
  refreshInterval: 1h
  secretStoreRef: { kind: ClusterSecretStore, name: gcp-store }
  target:
    name: payerbox-db-credentials
    creationPolicy: Owner
    template: { type: kubernetes.io/basic-auth }
  data:
    - { secretKey: username, remoteRef: { key: payerbox-db--username } }   # value must be "aidbox"
    - { secretKey: password, remoteRef: { key: payerbox-db--password } }
```

> On AWS use `secretStoreRef.name: secrets-manager` and your SM key naming.

---

## 4. Still TODO in the chart (separate from these prerequisites)

The Aidbox **init-bundles** (`files/aidbox-*-init-bundle.json`) are starter content. Their
OAuth-client secrets use `${ENV}` placeholders that Aidbox does **not** substitute in a mounted
bundle — this needs an `initContainer` (envsubst) step and finalized bundle content, validated
against a live Aidbox. See `payerbox/README.md`.

# payerbox — cluster prerequisites

The `payerbox` umbrella (and the standalone `fhir-app-portal` / `interop` / `prior-auth`
charts) deploy **only the applications and the two Aidbox instances**. By design they do
**not** create the database or any Secrets — those are infrastructure concerns that vary
per cloud/customer and need far more configuration than a Helm chart should own (backups,
WAL archiving, replication, snapshot classes, secret stores, key conventions…).

Provision the following in your cluster **before** installing the charts, in this order:

1. [Operators & controllers](#1-operators--controllers)
2. [Secrets](#2-secrets) — **6 Secrets, 23 keys, all required**
3. [PostgreSQL](#3-postgresql-cloudnativepg)

---

## 1. Operators & controllers

| Component | Why | Notes |
|-----------|-----|-------|
| **CloudNativePG operator** | PostgreSQL for both Aidboxes | provides the `Cluster` CRD; see §3 |
| **External Secrets Operator** + a `ClusterSecretStore` | sync Secrets from your secret manager (GCP Secret Manager / Azure Key Vault / AWS SM) | see §2 |
| **ingress-nginx** (or your ingress controller) | portal + Aidbox ingress | `ingressClassName` is a chart value |
| **cert-manager** + a `ClusterIssuer` (e.g. `letsencrypt`) | TLS for the ingresses | referenced via ingress annotations |
| Prometheus / kube-prometheus-stack | Aidbox metrics (optional) | `serviceMonitor`/`PodMonitor` |

---

## 2. Secrets

### How to read this section

A Kubernetes **Secret** is a named object that holds several **keys**. The charts load every key
of a Secret into the pod as an environment variable (`envFrom`). So you need to create **6
Secrets**, and **each one must contain every key listed for it — 23 keys in total**. A Secret
with the right name but missing keys is not enough.

```
prior-auth-secrets            ← Secret: a Kubernetes object, its name is what the chart references
├── AIDBOX_CLIENT_SECRET      ← key: becomes an env var in the prior-auth pod — required
└── AIDBOX_APP_SECRET         ← key: becomes an env var in the prior-auth pod — required
```

All Secrets live in the **release namespace** (e.g. `payerbox`) and must exist **before**
`helm install`. If something is missing:

- **Secret missing** → the pod never starts (`CreateContainerConfigError`).
- **Key missing** → the Aidbox pods also stop at `CreateContainerConfigError` (the init-bundle
  keys), but most other keys only fail later at runtime: Aidbox refuses to boot without a
  license, the portal login returns 401, interop/prior-auth can't register with Aidbox. These are
  harder to trace back to a missing key, so run the check in
  [README → Step 2](./README.md#step-2--create-the-secrets) before installing.

The steps: **[2.1](#21-generate-the-values)** prepare the 15 values →
**[2.2](#22-secret-reference-all-23-keys)** know where each one goes → create the Secrets with
External Secrets Operator on **[GCP](#23-option-a--gcp-secret-manager)** or
**[Azure](#24-option-b--azure-key-vault)** ([2.5](#25-the-externalsecrets-same-for-every-cloud)),
or with **[plain `kubectl`](#26-option-c--plain-kubectl-dev--test-only)**.

### 2.1 Generate the values

There are **15 distinct values**. Some of them go into more than one Secret and **must be
identical** everywhere they appear — that's how the apps authenticate to Aidbox and Aidbox to
PostgreSQL. Store each value once in your secret manager (the "Remote key" column is the name
the examples below use) and let every Secret read it from there.

| # | Value | How to get it | Remote key | Goes into (`Secret` → key) |
|---|-------|---------------|------------|----------------------------|
| 1 | DB username | the literal string `aidbox` | `payerbox-db-username` | `payerbox-db-credentials` → `username`<br>`aidbox-admin-env` → `BOX_DB_USER`<br>`aidbox-sandbox-env` → `BOX_DB_USER` |
| 2 | DB password | generate | `payerbox-db-password` | `payerbox-db-credentials` → `password`<br>`aidbox-admin-env` → `BOX_DB_PASSWORD`<br>`aidbox-sandbox-env` → `BOX_DB_PASSWORD` |
| 3 | Admin Aidbox license | issued by Health Samurai | `aidbox-admin-license` | `aidbox-admin-env` → `BOX_LICENSE` |
| 4 | Sandbox Aidbox license | issued by Health Samurai | `aidbox-sandbox-license` | `aidbox-sandbox-env` → `BOX_LICENSE` |
| 5 | Admin Aidbox `admin` user password | generate | `aidbox-admin-admin-password` | `aidbox-admin-env` → `BOX_ADMIN_PASSWORD` |
| 6 | Sandbox Aidbox `admin` user password | generate | `aidbox-sandbox-admin-password` | `aidbox-sandbox-env` → `BOX_ADMIN_PASSWORD` |
| 7 | Admin Aidbox root client secret | generate | `aidbox-admin-root-client-secret` | `aidbox-admin-env` → `BOX_ROOT_CLIENT_SECRET` |
| 8 | Sandbox Aidbox root client secret | generate | `aidbox-sandbox-root-client-secret` | `aidbox-sandbox-env` → `BOX_ROOT_CLIENT_SECRET` |
| 9 | Admin API client secret (portal → admin Aidbox) | generate | `admin-api-client-secret` | `aidbox-admin-env` → `ADMIN_API_CLIENT_SECRET`<br>`fhir-app-portal-secrets` → `ADMIN_API_CLIENT_SECRET` |
| 10 | Developer API client secret (portal → sandbox Aidbox) | generate | `developer-api-client-secret` | `aidbox-sandbox-env` → `DEVELOPER_API_CLIENT_SECRET`<br>`fhir-app-portal-secrets` → `DEVELOPER_API_CLIENT_SECRET` |
| 11 | Portal session secret | generate | `portal-session-secret` | `fhir-app-portal-secrets` → `SESSION_SECRET` |
| 12 | Interop client secret (interop → admin Aidbox) | generate | `interop-client-secret` | `aidbox-admin-env` → `INTEROP_APP_CLIENT_SECRET`<br>`interop-secrets` → `AIDBOX_CLIENT_SECRET` |
| 13 | Interop app secret | generate | `interop-app-secret` | `interop-secrets` → `AIDBOX_APP_SECRET` |
| 14 | Prior-auth client secret (prior-auth → admin Aidbox) | generate | `prior-auth-client-secret` | `aidbox-admin-env` → `PRIOR_AUTH_APP_CLIENT_SECRET`<br>`prior-auth-secrets` → `AIDBOX_CLIENT_SECRET` |
| 15 | Prior-auth app secret | generate | `prior-auth-app-secret` | `prior-auth-secrets` → `AIDBOX_APP_SECRET` |

"Generate" means any long random string, e.g. `openssl rand -hex 32`. The two app secrets (13,
15) are dedicated to each app — don't reuse the portal's or each other's.

The remote key names use only lowercase letters, digits and hyphens, so the same names are valid
in GCP Secret Manager, Azure Key Vault and AWS Secrets Manager.

### 2.2 Secret reference: all 23 keys

Every row is required. The "Value" column points back to the table above.

| Secret | Key | Value | Consumed by |
|--------|-----|-------|-------------|
| `payerbox-db-credentials` (type `kubernetes.io/basic-auth`) | `username` | #1 (`aidbox`) | CNPG `Cluster` (§3) |
| | `password` | #2 | |
| `aidbox-admin-env` | `BOX_LICENSE` | #3 | admin Aidbox |
| | `BOX_ADMIN_PASSWORD` | #5 | |
| | `BOX_ROOT_CLIENT_SECRET` | #7 | |
| | `BOX_DB_USER` | #1 | |
| | `BOX_DB_PASSWORD` | #2 | |
| | `ADMIN_API_CLIENT_SECRET` | #9 | |
| | `INTEROP_APP_CLIENT_SECRET` | #12 | |
| | `PRIOR_AUTH_APP_CLIENT_SECRET` | #14 | |
| `aidbox-sandbox-env` | `BOX_LICENSE` | #4 | sandbox Aidbox |
| | `BOX_ADMIN_PASSWORD` | #6 | |
| | `BOX_ROOT_CLIENT_SECRET` | #8 | |
| | `BOX_DB_USER` | #1 | |
| | `BOX_DB_PASSWORD` | #2 | |
| | `DEVELOPER_API_CLIENT_SECRET` | #10 | |
| `fhir-app-portal-secrets` | `SESSION_SECRET` | #11 | fhir-app-portal |
| | `ADMIN_API_CLIENT_SECRET` | #9 | |
| | `DEVELOPER_API_CLIENT_SECRET` | #10 | |
| `interop-secrets` | `AIDBOX_CLIENT_SECRET` | #12 | interop |
| | `AIDBOX_APP_SECRET` | #13 | |
| `prior-auth-secrets` | `AIDBOX_CLIENT_SECRET` | #14 | prior-auth |
| | `AIDBOX_APP_SECRET` | #15 | |

The Secret names are the chart defaults. To use other names, override
`aidbox-admin.extraEnvFromSecrets`, `aidbox-sandbox.extraEnvFromSecrets` and
`<app>.secrets.existingSecretName` in `values.yaml`.

### 2.3 Option A — GCP Secret Manager

**1. Store the 15 values.** Define `put` for GCP, then run the [shared list](#store-the-values):

```bash
PROJECT=<gcp-project-id>
put() { printf '%s' "$2" | gcloud secrets create "$1" --project "$PROJECT" --replication-policy automatic --data-file=- ; }
```

**2. Create the `ClusterSecretStore`.** The External Secrets Operator service account needs
GKE Workload Identity bound to a Google service account with `roles/secretmanager.secretAccessor`
on the project.

```yaml
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: payerbox-secret-store
spec:
  provider:
    gcpsm:
      projectID: <gcp-project-id>
```

**3. Apply the ExternalSecrets** from [§2.5](#25-the-externalsecrets-same-for-every-cloud).

### 2.4 Option B — Azure Key Vault

**1. Store the 15 values.** Define `put` for Azure, then run the [shared list](#store-the-values):

```bash
VAULT=<key-vault-name>
put() { az keyvault secret set --vault-name "$VAULT" --name "$1" --value "$2" --output none ; }
```

**2. Let External Secrets Operator read the vault** with AKS Workload Identity: a managed
identity with the `Key Vault Secrets User` role on the vault (RBAC-mode vault), federated to the
ESO service account.

```bash
RG=<resource-group>; AKS=<aks-cluster>
ESO_NS=external-secrets; ESO_SA=external-secrets    # namespace + service account of your ESO install

az aks update -g "$RG" -n "$AKS" --enable-oidc-issuer --enable-workload-identity
az identity create -g "$RG" -n payerbox-eso
CLIENT_ID=$(az identity show -g "$RG" -n payerbox-eso --query clientId -o tsv)
PRINCIPAL_ID=$(az identity show -g "$RG" -n payerbox-eso --query principalId -o tsv)
VAULT_ID=$(az keyvault show -n "$VAULT" --query id -o tsv)

az role assignment create --role "Key Vault Secrets User" \
  --assignee-object-id "$PRINCIPAL_ID" --assignee-principal-type ServicePrincipal --scope "$VAULT_ID"
az identity federated-credential create -g "$RG" --identity-name payerbox-eso --name eso \
  --issuer "$(az aks show -g "$RG" -n "$AKS" --query oidcIssuerProfile.issuerUrl -o tsv)" \
  --subject "system:serviceaccount:${ESO_NS}:${ESO_SA}" \
  --audiences api://AzureADTokenExchange
```

Annotate the ESO service account with `azure.workload.identity/client-id: <CLIENT_ID>` (via the
ESO Helm chart's `serviceAccount.annotations`).

**3. Create the `ClusterSecretStore`:**

```yaml
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: payerbox-secret-store
spec:
  provider:
    azurekv:
      authType: WorkloadIdentity
      vaultUrl: https://<key-vault-name>.vault.azure.net
      tenantId: <azure-tenant-id>
      serviceAccountRef:
        name: external-secrets        # ESO_SA from above
        namespace: external-secrets   # ESO_NS from above
```

**4. Apply the ExternalSecrets** from [§2.5](#25-the-externalsecrets-same-for-every-cloud).

> **AWS:** same pattern — a `ClusterSecretStore` with the `aws` provider (`service: SecretsManager`,
> IRSA or Pod Identity for auth), `aws secretsmanager create-secret --name "$1" --secret-string "$2"`
> as `put`, and the ExternalSecrets from §2.5 unchanged.

#### Store the values

Shared by GCP and Azure — run after defining `put` for your cloud. Values 3–4 are the Aidbox
licenses you received; everything else is generated.

```bash
put payerbox-db-username              aidbox
put payerbox-db-password              "$(openssl rand -hex 32)"
put aidbox-admin-license              '<admin Aidbox license>'
put aidbox-sandbox-license            '<sandbox Aidbox license>'
put aidbox-admin-admin-password       "$(openssl rand -hex 32)"
put aidbox-sandbox-admin-password     "$(openssl rand -hex 32)"
put aidbox-admin-root-client-secret   "$(openssl rand -hex 32)"
put aidbox-sandbox-root-client-secret "$(openssl rand -hex 32)"
put admin-api-client-secret           "$(openssl rand -hex 32)"
put developer-api-client-secret       "$(openssl rand -hex 32)"
put portal-session-secret             "$(openssl rand -hex 32)"
put interop-client-secret             "$(openssl rand -hex 32)"
put interop-app-secret                "$(openssl rand -hex 32)"
put prior-auth-client-secret          "$(openssl rand -hex 32)"
put prior-auth-app-secret             "$(openssl rand -hex 32)"
```

### 2.5 The ExternalSecrets (same for every cloud)

Apply in the release namespace. Only the `ClusterSecretStore` differs per cloud; these manifests
don't change. Each ExternalSecret produces one Secret from §2.2 with **all** its keys.

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: payerbox-db-credentials
spec:
  refreshInterval: 1h
  secretStoreRef: { kind: ClusterSecretStore, name: payerbox-secret-store }
  target:
    name: payerbox-db-credentials
    creationPolicy: Owner
    template: { type: kubernetes.io/basic-auth }
  data:
    - { secretKey: username, remoteRef: { key: payerbox-db-username } }   # value must be "aidbox"
    - { secretKey: password, remoteRef: { key: payerbox-db-password } }
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: aidbox-admin-env
spec:
  refreshInterval: 1h
  secretStoreRef: { kind: ClusterSecretStore, name: payerbox-secret-store }
  target: { name: aidbox-admin-env, creationPolicy: Owner }
  data:
    - { secretKey: BOX_LICENSE,                  remoteRef: { key: aidbox-admin-license } }
    - { secretKey: BOX_ADMIN_PASSWORD,           remoteRef: { key: aidbox-admin-admin-password } }
    - { secretKey: BOX_ROOT_CLIENT_SECRET,       remoteRef: { key: aidbox-admin-root-client-secret } }
    - { secretKey: BOX_DB_USER,                  remoteRef: { key: payerbox-db-username } }
    - { secretKey: BOX_DB_PASSWORD,              remoteRef: { key: payerbox-db-password } }
    - { secretKey: ADMIN_API_CLIENT_SECRET,      remoteRef: { key: admin-api-client-secret } }
    - { secretKey: INTEROP_APP_CLIENT_SECRET,    remoteRef: { key: interop-client-secret } }
    - { secretKey: PRIOR_AUTH_APP_CLIENT_SECRET, remoteRef: { key: prior-auth-client-secret } }
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: aidbox-sandbox-env
spec:
  refreshInterval: 1h
  secretStoreRef: { kind: ClusterSecretStore, name: payerbox-secret-store }
  target: { name: aidbox-sandbox-env, creationPolicy: Owner }
  data:
    - { secretKey: BOX_LICENSE,                 remoteRef: { key: aidbox-sandbox-license } }
    - { secretKey: BOX_ADMIN_PASSWORD,          remoteRef: { key: aidbox-sandbox-admin-password } }
    - { secretKey: BOX_ROOT_CLIENT_SECRET,      remoteRef: { key: aidbox-sandbox-root-client-secret } }
    - { secretKey: BOX_DB_USER,                 remoteRef: { key: payerbox-db-username } }
    - { secretKey: BOX_DB_PASSWORD,             remoteRef: { key: payerbox-db-password } }
    - { secretKey: DEVELOPER_API_CLIENT_SECRET, remoteRef: { key: developer-api-client-secret } }
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: fhir-app-portal-secrets
spec:
  refreshInterval: 1h
  secretStoreRef: { kind: ClusterSecretStore, name: payerbox-secret-store }
  target: { name: fhir-app-portal-secrets, creationPolicy: Owner }
  data:
    - { secretKey: SESSION_SECRET,              remoteRef: { key: portal-session-secret } }
    - { secretKey: ADMIN_API_CLIENT_SECRET,     remoteRef: { key: admin-api-client-secret } }
    - { secretKey: DEVELOPER_API_CLIENT_SECRET, remoteRef: { key: developer-api-client-secret } }
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: interop-secrets
spec:
  refreshInterval: 1h
  secretStoreRef: { kind: ClusterSecretStore, name: payerbox-secret-store }
  target: { name: interop-secrets, creationPolicy: Owner }
  data:
    - { secretKey: AIDBOX_CLIENT_SECRET, remoteRef: { key: interop-client-secret } }
    - { secretKey: AIDBOX_APP_SECRET,    remoteRef: { key: interop-app-secret } }
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: prior-auth-secrets
spec:
  refreshInterval: 1h
  secretStoreRef: { kind: ClusterSecretStore, name: payerbox-secret-store }
  target: { name: prior-auth-secrets, creationPolicy: Owner }
  data:
    - { secretKey: AIDBOX_CLIENT_SECRET, remoteRef: { key: prior-auth-client-secret } }
    - { secretKey: AIDBOX_APP_SECRET,    remoteRef: { key: prior-auth-app-secret } }
```

Then confirm all six synced — every row must show `SecretSynced` / `True`:

```bash
kubectl -n payerbox get externalsecret
```

A row stuck in `SecretSyncedError` usually means a remote key is missing or misspelled, or the
store can't authenticate — `kubectl -n payerbox describe externalsecret <name>` shows which.

### 2.6 Option C — plain `kubectl` (dev / test only)

Without a secret manager, create the Secrets directly. Values live only in the cluster, so this
is for throwaway environments.

```bash
NS=payerbox
gen() { openssl rand -hex 32; }
DB_PASSWORD=$(gen); ADMIN_API=$(gen); DEVELOPER_API=$(gen); INTEROP_CLIENT=$(gen); PRIOR_AUTH_CLIENT=$(gen)

kubectl create namespace "$NS"
kubectl -n "$NS" create secret generic payerbox-db-credentials --type=kubernetes.io/basic-auth \
  --from-literal=username=aidbox --from-literal=password="$DB_PASSWORD"
kubectl -n "$NS" create secret generic aidbox-admin-env \
  --from-literal=BOX_LICENSE='<admin Aidbox license>' \
  --from-literal=BOX_ADMIN_PASSWORD="$(gen)" --from-literal=BOX_ROOT_CLIENT_SECRET="$(gen)" \
  --from-literal=BOX_DB_USER=aidbox --from-literal=BOX_DB_PASSWORD="$DB_PASSWORD" \
  --from-literal=ADMIN_API_CLIENT_SECRET="$ADMIN_API" \
  --from-literal=INTEROP_APP_CLIENT_SECRET="$INTEROP_CLIENT" \
  --from-literal=PRIOR_AUTH_APP_CLIENT_SECRET="$PRIOR_AUTH_CLIENT"
kubectl -n "$NS" create secret generic aidbox-sandbox-env \
  --from-literal=BOX_LICENSE='<sandbox Aidbox license>' \
  --from-literal=BOX_ADMIN_PASSWORD="$(gen)" --from-literal=BOX_ROOT_CLIENT_SECRET="$(gen)" \
  --from-literal=BOX_DB_USER=aidbox --from-literal=BOX_DB_PASSWORD="$DB_PASSWORD" \
  --from-literal=DEVELOPER_API_CLIENT_SECRET="$DEVELOPER_API"
kubectl -n "$NS" create secret generic fhir-app-portal-secrets \
  --from-literal=SESSION_SECRET="$(gen)" \
  --from-literal=ADMIN_API_CLIENT_SECRET="$ADMIN_API" \
  --from-literal=DEVELOPER_API_CLIENT_SECRET="$DEVELOPER_API"
kubectl -n "$NS" create secret generic interop-secrets \
  --from-literal=AIDBOX_CLIENT_SECRET="$INTEROP_CLIENT" --from-literal=AIDBOX_APP_SECRET="$(gen)"
kubectl -n "$NS" create secret generic prior-auth-secrets \
  --from-literal=AIDBOX_CLIENT_SECRET="$PRIOR_AUTH_CLIENT" --from-literal=AIDBOX_APP_SECRET="$(gen)"
```

The shared values are generated once into shell variables, so the "must be identical" pairs from
§2.1 line up automatically.

---

## 3. PostgreSQL (CloudNativePG)

The charts expect a reachable Postgres with **two databases** — `portal` (admin Aidbox) and
`sandbox` (sandbox Aidbox) — owned by a role whose credentials are also placed in the Aidbox
Secrets (§2). The chart's default `aidbox-*.config.BOX_DB_HOST` is `payerbox-db-rw`, i.e. the
`-rw` Service of a CNPG `Cluster` named `payerbox-db`. Override `BOX_DB_HOST`/`BOX_DB_DATABASE`
if your naming differs.

**Coupling to remember:**
- The CNPG role password **must equal** the Aidbox `BOX_DB_PASSWORD` (§2.1, value #2). The
  example below has CNPG read it from the `payerbox-db-credentials` Secret, so create that
  Secret first.
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
        name: payerbox-db-credentials   # basic-auth secret (§2)
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

> **Azure:** keep CNPG and back up to Azure Blob Storage (`azureCredentials` in the
> `ObjectStore`, with Workload Identity), or use Azure Database for PostgreSQL – Flexible Server.
> **AWS:** RDS/Aurora, or CNPG with S3 (`s3Credentials` + IRSA). The charts only care that
> `BOX_DB_HOST` resolves and the two databases exist.

---

## 4. Init-bundle substitution (handled by the chart)

The Aidbox **init-bundles** (`files/aidbox-*-init-bundle.json`) ship as `${VAR}` templates. Aidbox
does **not** substitute env vars in a mounted bundle, so each Aidbox pod runs a small `sed`
initContainer (`busybox`) that fills the placeholders — hostnames from `aidbox-*.config` and
client secrets from the `aidbox-*-env` Secret — before Aidbox loads the bundle. It re-renders on
every pod start, so it survives `helm upgrade`. No action needed beyond creating the Secrets in §2
and setting the host config. See `README.md`.

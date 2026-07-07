# interbox

Integration Engine for Modern Healthcare Solutions — the all-in-one interbox
(engine + API + dashboard). Ingests HL7v2 over MLLP and delivers FHIR to Aidbox.

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: edge](https://img.shields.io/badge/AppVersion-edge-informational?style=flat-square)

## Prerequisites

interbox needs a **Postgres** database and an **Aidbox** endpoint — see
[PREREQUISITES.md](./PREREQUISITES.md). Postgres and Aidbox are NOT bundled; install
the sibling [`postgres`](../postgres) / [`aidbox`](../aidbox) charts if you need them
in-cluster.

## Installation

```console
helm repo add healthsamurai https://healthsamurai.github.io/helm-charts

helm upgrade --install interbox healthsamurai/interbox \
  --namespace interbox --create-namespace \
  --values /path/to/values.yaml
```

Minimal `values.yaml`:

```yaml
config:
  AIDBOX_URL: http://aidbox:8080          # your Aidbox (sibling chart or external)
secrets:
  data:
    DATABASE_URL: postgres://interbox:pass@pg:5432/interbox?sslmode=require   # user needs CREATEDB
    AIDBOX_CLIENT_SECRET: <aidbox client secret>
```

The dashboard + API serve on `3001`; MLLP (HL7v2) on TCP `2575` via a dedicated
LoadBalancer. See [`values-aks.yaml`](./values-aks.yaml) for the Azure overlay.

## Setup scenarios

All snippets are the interbox values. Add `-f values-aks.yaml` for the internal MLLP
LoadBalancer + pinned IP + idle-timeout on AKS. Aidbox/Postgres are external unless
you install the sibling charts. Sibling service names depend on their release names —
check their `helm install` output.

### 1. Existing Aidbox + managed Postgres (typical prod)
interbox creates its own `interbox` database on your managed PG and delivers to your
existing Aidbox.
```yaml
config:
  AIDBOX_URL: https://aidbox.internal
secrets:
  data:
    DATABASE_URL: postgres://interbox:pass@pg.internal:5432/interbox?sslmode=require
    AIDBOX_CLIENT_SECRET: <aidbox client secret>
```

### 2. Existing Aidbox — reuse its Postgres cluster
No separate DB server: interbox gets a dedicated `interbox` database on the same
cluster Aidbox uses (not Aidbox's own database).
```yaml
config:
  AIDBOX_URL: https://aidbox.internal
secrets:
  data:
    DATABASE_URL: postgres://interbox:pass@aidbox-pg:5432/interbox?sslmode=require
    AIDBOX_CLIENT_SECRET: <aidbox client secret>
```

### 3. No Aidbox / no Postgres yet — install the sibling charts (dev/stage)
```console
helm install pg       healthsamurai/postgres -n interbox --create-namespace
helm install aidbox   healthsamurai/aidbox   -n interbox
helm install interbox healthsamurai/interbox -n interbox -f dev-values.yaml
```
`dev-values.yaml` (point at the sibling charts' service names):
```yaml
config:
  AIDBOX_URL: http://aidbox:8080
secrets:
  data:
    DATABASE_URL: postgres://interbox:pass@pg-postgres:5432/interbox   # user needs CREATEDB
    AIDBOX_CLIENT_SECRET: secret
```

### 4. Locked-down managed PG (no admin grant)
Pre-create the db + extensions yourself (see [PREREQUISITES.md](./PREREQUISITES.md));
`createDatabase: false` sets `INTERBOX_SKIP_ENSURE_DB` so the engine skips its bootstrap.
```yaml
database:
  createDatabase: false
config:
  AIDBOX_URL: https://aidbox.internal
secrets:
  data:
    DATABASE_URL: postgres://interbox:pass@pg.internal:5432/interbox?sslmode=require
    AIDBOX_CLIENT_SECRET: <aidbox client secret>
```

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` | Affinity rules for scheduling. |
| automountServiceAccountToken | bool | `false` | Don't mount the ServiceAccount token — interbox never calls the Kubernetes API. |
| config | object | `{"AIDBOX_URL":"http://aidbox:8080","INTERBOX_WORKSPACE_POLL_MS":"5000","MLLP_HOST":"0.0.0.0","MLLP_PORT":"2575"}` | Non-secret env → ConfigMap (envFrom). Keys ARE env var names. `AIDBOX_URL` points at your Aidbox (the sibling `aidbox` chart in-cluster, or an existing external one). Uncomment `AIDBOX_CLIENT_ID` to authenticate as a scoped least-privilege client (defaults to `root`). |
| database.createDatabase | bool | `true` | Engine self-creates the `interbox` db on boot when the DATABASE_URL user has `CREATEDB`. `false` → sets `INTERBOX_SKIP_ENSURE_DB`; pre-create the db yourself (locked-down managed PG). |
| extraEnvFromConfigMaps | list | `[]` | Extra ConfigMaps to load env from (envFrom) — extend the pod's env without editing the chart. |
| extraEnvFromSecrets | list | `[]` | Extra Secrets to load env from (envFrom). |
| fullnameOverride | string | `""` | Override the full resource name (default: the chart name — keeps the in-cluster service name stable). |
| image.digest | string | `""` | Pin by digest (wins over tag when set). |
| image.pullPolicy | string | `"Always"` | Image pull policy. `Always` refreshes the moving `edge` tag; set `IfNotPresent` once pinned. |
| image.repository | string | `"healthsamurai/interbox"` | Image repository. |
| image.tag | string | `""` | Image tag; defaults to `.Chart.AppVersion` (`edge` pre-GA). Pin a semver for reproducible prod. |
| imagePullSecrets | list | `[]` | Image pull secrets for a private registry. |
| ingress.annotations | object | `{}` | Ingress annotations. |
| ingress.className | string | `""` | Ingress class name. |
| ingress.enabled | bool | `false` | Ingress for the dashboard/API. Enable ONLY with an internal ingress class — never public. |
| ingress.host | string | `"interbox.example.com"` | Ingress host. |
| ingress.path | string | `"/"` | Ingress path. Default `/` (works nginx / AGIC / modern ALB). AWS ALB + GKE gce prefer `/*` — pair it with pathType: ImplementationSpecific. |
| ingress.pathType | string | `"Prefix"` | Ingress pathType (Prefix | ImplementationSpecific | Exact). |
| ingress.tls | list | `[]` | Ingress TLS blocks. |
| mllp.enabled | bool | `true` | Expose MLLP (HL7v2 raw-TCP ingest). |
| mllp.port | int | `2575` | MLLP TCP port. |
| mllp.service.annotations | object | `{}` | Extra Service annotations (e.g. AKS internal-LB + tcp-idle-timeout — see values-aks.yaml). |
| mllp.service.externalTrafficPolicy | string | `"Local"` | Preserve the sender's source IP + skip the extra node hop (single-replica-safe). "" = Cluster. |
| mllp.service.internal | bool | `true` | Request a private LB (senders reach it over VPN/VNet). Cloud annotation supplied via overlay. |
| mllp.service.loadBalancerIP | string | `""` | Pin the LB IP so it survives reinstall (stable VPN/firewall target). Must be a free subnet IP; empty = dynamic. |
| mllp.service.loadBalancerSourceRanges | list | `[]` | Restrict the LB to known sender subnets even inside the private network (defense-in-depth). |
| mllp.service.type | string | `"LoadBalancer"` | MLLP service type. Raw TCP → LoadBalancer (HTTP ingress can't carry it). |
| nameOverride | string | `""` | Override the chart name used in resource names. |
| nodeSelector | object | `{}` | Node selector for scheduling. |
| podAnnotations | object | `{}` | Extra pod annotations. |
| probe.liveness | object | `{"failureThreshold":3,"periodSeconds":20,"timeoutSeconds":5}` | Liveness probe. |
| probe.path | string | `"/api/health"` | HTTP health path for all probes. |
| probe.readiness | object | `{"failureThreshold":3,"periodSeconds":10,"timeoutSeconds":3}` | Readiness probe. |
| probe.scheme | string | `"HTTP"` | Probe scheme (HTTP / HTTPS). |
| probe.startup | object | `{"failureThreshold":60,"initialDelaySeconds":10,"periodSeconds":10}` | Startup probe. Generous: the pod clones + installs + builds the workspace on boot. |
| replicaCount | int | `1` | Pod replicas. HA is deferred — leave at 1 (all-in-one process + single MLLP listener). |
| resources | object | `{}` | Pod resource requests / limits. NOTE: the boot-time workspace build (git clone + bun install + Bun.build) is memory-hungry — set limits generously, or omit the memory limit, to avoid an OOM kill during boot. e.g. requests: {cpu: 100m, memory: 512Mi}. |
| secrets.data | object | `{"AIDBOX_CLIENT_SECRET":"","ANTHROPIC_API_KEY":"","CLAUDE_CODE_OAUTH_TOKEN":"","DATABASE_URL":"","INTERBOX_LICENSE":"","INTERBOX_WORKSPACE_GIT_KEY":""}` | Secret env → Secret (envFrom). Keys ARE env var names; only non-empty ones are written. `DATABASE_URL` is required — its user needs `CREATEDB` (the engine self-creates the db); add `?sslmode=require` for TLS. `AIDBOX_CLIENT_SECRET` if using Aidbox. The rest are optional. |
| secrets.existingSecretName | string | `""` | Use a pre-provisioned Secret instead of creating one from `data` below (External Secrets Operator, sealed-secrets, …). |
| securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"runAsGroup":1000,"runAsNonRoot":true,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}}` | Container securityContext. The image runs as non-root `bun` (uid 1000); writable paths are HOME + /tmp, /app is read-only. Hardened for prod. (readOnlyRootFilesystem is off — /tmp + HOME need writes; enable it only with emptyDir mounts at those paths.) |
| service.port | int | `3001` | Dashboard/API port. |
| service.type | string | `"ClusterIP"` | Dashboard/API service type. |
| serviceAccount.annotations | object | `{}` | ServiceAccount annotations. |
| serviceAccount.create | bool | `false` | Create a ServiceAccount for the pod. |
| serviceAccount.name | string | `""` | ServiceAccount name (generated from the fullname if empty and create=true). |
| strategy | object | `{"type":"Recreate"}` | Deployment strategy. Recreate — one MLLP listener + boot-build, never two pods racing the TCP port. |
| terminationGracePeriodSeconds | int | `30` | Grace period for in-flight messages to persist + ACK before SIGKILL. |
| tolerations | list | `[]` | Tolerations for scheduling. |

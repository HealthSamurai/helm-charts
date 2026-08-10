# Termbox

FHIR Terminology Server by Health Samurai — CodeSystem, ValueSet and ConceptMap, with
standard FHIR terminology operations ($lookup, $validate-code, $expand, $translate,
$subsumes, $find-matches). See the [docs](https://www.health-samurai.io/docs/termbox).

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: latest](https://img.shields.io/badge/AppVersion-latest-informational?style=flat-square)

## Prerequisites

Termbox needs a **Postgres** database and a **license** — see
[PREREQUISITES.md](./PREREQUISITES.md). Postgres is NOT bundled; install the sibling
[`postgres`](../postgres) chart if you need it in-cluster.

## Installation

```console
helm repo add healthsamurai https://healthsamurai.github.io/helm-charts

helm upgrade --install termbox healthsamurai/termbox \
  --namespace termbox --create-namespace \
  --values /path/to/values.yaml
```

Minimal `values.yaml`:

```yaml
config:
  PG_HOST: pg-postgres           # your Postgres (sibling chart or external)
  PG_DATABASE: termbox
secrets:
  data:
    PG_USER: termbox
    PG_PASSWORD: <postgres password>
    LICENSE: <termbox license key>
```
The API + UI serve on `3000` (`/fhir` for FHIR, `/ui` for the dashboard). The chart's
probes `httpGet` the FHIR API (`/fhir/metadata`), which requires a valid `LICENSE`. See
[Licensing](https://www.health-samurai.io/docs/termbox/licensing).

## Setup scenarios

### 1. Managed Postgres (typical prod)

```yaml
config:
  PG_HOST: pg.internal
  PG_DATABASE: termbox
secrets:
  data:
    PG_USER: termbox
    PG_PASSWORD: <password>
    LICENSE: <production license key>
```

### 2. No Postgres yet — install the sibling chart (dev/stage)

```console
helm install pg      healthsamurai/postgres -n termbox --create-namespace
helm install termbox healthsamurai/termbox  -n termbox -f dev-values.yaml
```

`dev-values.yaml` (point at the sibling chart's service name):

```yaml
config:
  PG_HOST: pg-postgres
  PG_DATABASE: termbox
secrets:
  data:
    PG_USER: postgres
    PG_PASSWORD: postgres
    LICENSE: <termbox license key>
```

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` | Affinity rules for scheduling. |
| automountServiceAccountToken | bool | `false` | Don't mount the ServiceAccount token — termbox never calls the Kubernetes API. |
| config | object | `{"HTTP_PORT":"3000","LOG_FORMAT":"text","LOG_MIN_LEVEL":"INFO","PG_DATABASE":"termbox","PG_HOST":"postgres","PG_PORT":"5432"}` | Non-secret env → ConfigMap (envFrom). Keys ARE env var names — see https://www.health-samurai.io/docs/termbox/configuration for the full list (logging, feature toggles, FHIR API version routes, etc.). |
| extraEnvFromConfigMaps | list | `[]` | Extra ConfigMaps to load env from (envFrom) — extend the pod's env without editing the chart. |
| extraEnvFromSecrets | list | `[]` | Extra Secrets to load env from (envFrom). |
| fullnameOverride | string | `""` | Override the full resource name (default: the chart name — keeps the in-cluster service name stable). |
| image.digest | string | `""` | Pin by digest (wins over tag when set). |
| image.pullPolicy | string | `"Always"` | Image pull policy. `Always` refreshes the moving `latest` tag; set `IfNotPresent` once pinned. |
| image.repository | string | `"healthsamurai/termbox"` | Image repository. |
| image.tag | string | `""` | Image tag; defaults to `.Chart.AppVersion` (`latest`). Pin a released tag for reproducible prod. |
| imagePullSecrets | list | `[]` | Image pull secrets for a private registry. |
| ingress.annotations | object | `{}` | Ingress annotations. |
| ingress.className | string | `""` | Ingress class name. |
| ingress.enabled | bool | `false` | Ingress for the API/UI. |
| ingress.host | string | `"termbox.example.com"` | Ingress host. |
| ingress.path | string | `"/"` | Ingress path. Default `/` (works nginx / AGIC / modern ALB). AWS ALB + GKE gce prefer `/*` — pair it with pathType: ImplementationSpecific. |
| ingress.pathType | string | `"Prefix"` | Ingress pathType (Prefix | ImplementationSpecific | Exact). |
| ingress.tls | list | `[]` | Ingress TLS blocks. |
| nameOverride | string | `""` | Override the chart name used in resource names. |
| nodeSelector | object | `{}` | Node selector for scheduling. |
| podAnnotations | object | `{}` | Extra pod annotations. |
| probe.liveness | object | `{"failureThreshold":3,"periodSeconds":20,"timeoutSeconds":1}` | Liveness probe. |
| probe.path | string | `"/fhir/metadata"` | HTTP health path. |
| probe.readiness | object | `{"failureThreshold":3,"periodSeconds":10,"timeoutSeconds":1}` | Readiness probe. |
| probe.scheme | string | `"HTTP"` | Probe scheme (HTTP / HTTPS). |
| probe.startup | object | `{"failureThreshold":30,"initialDelaySeconds":10,"periodSeconds":5}` | Startup probe. Generous: covers boot-time DB migrations. |
| replicaCount | int | `1` | Pod replicas. |
| resources | object | `{}` | Pod resource requests / limits. e.g. requests: {cpu: 100m, memory: 512Mi}. |
| secrets.data | object | `{"LICENSE":"","PG_PASSWORD":"","PG_USER":""}` | Secret env → Secret (envFrom). Keys ARE env var names; only non-empty ones are written. `PG_USER`, `PG_PASSWORD` and `LICENSE` are all required. See https://www.health-samurai.io/docs/termbox/licensing. |
| secrets.existingSecretName | string | `""` | Use a pre-provisioned Secret instead of creating one from `data` below (External Secrets Operator, sealed-secrets, …). |
| securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"runAsGroup":1000,"runAsNonRoot":true,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}}` | Container securityContext. Hardened for prod. |
| service.port | int | `80` | Service port. Forwards to the container's HTTP_PORT (config.HTTP_PORT) via the named "http" targetPort — the two can differ freely. |
| service.type | string | `"ClusterIP"` | Service type. |
| serviceAccount.annotations | object | `{}` | ServiceAccount annotations. |
| serviceAccount.create | bool | `false` | Create a ServiceAccount for the pod. |
| serviceAccount.name | string | `""` | ServiceAccount name (generated from the fullname if empty and create=true). |
| strategy | object | `{"type":"RollingUpdate"}` | Deployment strategy. |
| terminationGracePeriodSeconds | int | `30` | Grace period for in-flight requests to finish before SIGKILL. |
| tolerations | list | `[]` | Tolerations for scheduling. |

# mdmbox

Probabilistic record matching service by Health Samurai

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: edge](https://img.shields.io/badge/AppVersion-edge-informational?style=flat-square)

## Installation

mdmbox needs a PostgreSQL 14+ database. The chart supports two deployment modes:

- **Standalone** — mdmbox runs on its own. You point it at any PostgreSQL.
- **Alongside Aidbox** — mdmbox shares the same PostgreSQL and reuses Aidbox's `BOX_DB_*` `ConfigMap`/`Secret`.

The chart itself does not provision PostgreSQL — bring your own (managed service, an in-cluster operator, or the [bitnami/postgresql](https://artifacthub.io/packages/helm/bitnami/postgresql) chart).

Obtain an mdmbox [license](https://www.health-samurai.io/docs/aidbox/overview/aidbox-user-portal/licenses) from Health Samurai before installing.

### Common: license and mdmbox config

mdmbox-specific environment variables (license, `JAVA_OPTS`, …) go under `config:`. The chart renders them into its own `ConfigMap` and mounts it via `envFrom`:

```yaml
config:
  MDMBOX_LICENSE: <your license string>
  JAVA_OPTS: "-XX:MaxRAMPercentage=75"
```

Do not put database credentials in `config` — its values land in a plain `ConfigMap`. Use a `Secret` referenced via `extraEnvFromSecrets` instead.

### Standalone

Create a `Secret` with the database credentials (and optionally other `BOX_DB_*` values) and reference it via `extraEnvFromSecrets`. Non-secret `BOX_DB_*` values can live in `config`:

```yaml
config:
  MDMBOX_LICENSE: <license JWT>
  BOX_DB_HOST: postgres
  BOX_DB_PORT: "5432"
  BOX_DB_DATABASE: mdmbox

extraEnvFromSecrets:
  - mdmbox-db   # contains BOX_DB_USER, BOX_DB_PASSWORD
```

### Alongside Aidbox

Reuse the `ConfigMap` and `Secret` your Aidbox already has — point the chart at them via `aidboxConfigMap` / `aidboxSecret`. They are loaded into the pod via `envFrom`:

```yaml
aidboxConfigMap: <ConfigMap with BOX_DB_HOST, BOX_DB_PORT, BOX_DB_DATABASE>
aidboxSecret: <Secret with BOX_DB_USER, BOX_DB_PASSWORD>

config:
  MDMBOX_LICENSE: <license JWT>
```

mdmbox and Aidbox then share the same PostgreSQL instance, FHIR data, and engine settings.

### Install

```console
helm repo add healthsamurai https://healthsamurai.github.io/helm-charts

helm upgrade --install mdmbox healthsamurai/mdmbox \
  --namespace mdmbox --create-namespace \
  --values /path/to/values.yaml
```

The release lands in the `mdmbox` namespace, creating it if needed.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` |  |
| aidboxConfigMap | string | `""` | Name of an existing ConfigMap with BOX_DB_* env vars (e.g. BOX_DB_HOST, BOX_DB_PORT, BOX_DB_DATABASE). Optional — convenience hook for the shared-Aidbox scenario where you already have an Aidbox ConfigMap. For standalone deployments leave empty and supply BOX_DB_* via .Values.config and/or extraEnvFromSecrets. |
| aidboxSecret | string | `""` | Name of an existing Secret with BOX_DB_USER, BOX_DB_PASSWORD. Optional — same shared-Aidbox convenience as aidboxConfigMap. For standalone, use extraEnvFromSecrets to mount your own Secret. |
| autoscaling.enabled | bool | `false` |  |
| autoscaling.maxReplicas | int | `100` |  |
| autoscaling.minReplicas | int | `1` |  |
| autoscaling.targetCPUUtilizationPercentage | int | `80` |  |
| config | object | `{"JAVA_OPTS":"-XX:MaxRAMPercentage=75"}` | mdmbox config rendered into the chart's own ConfigMap. Holds mdmbox-specific env vars (license, JAVA_OPTS, …) and, in standalone mode, non-secret BOX_DB_* values (BOX_DB_HOST/PORT/DATABASE). Do NOT put credentials here — use extraEnvFromSecrets instead. MDMBOX_HTTP_PORT is injected from .Values.service.port in deployment.yaml (single source of truth). |
| extraEnvFromConfigMaps | list | `[]` | Names of additional ConfigMaps loaded into the pod via envFrom. |
| extraEnvFromSecrets | list | `[]` | Names of additional Secrets loaded into the pod via envFrom. Use this for BOX_DB_USER / BOX_DB_PASSWORD in standalone mode. |
| fullnameOverride | string | `""` |  |
| image.digest | string | `""` |  |
| image.pullPolicy | string | `"IfNotPresent"` |  |
| image.repository | string | `"healthsamurai/mdmbox"` |  |
| image.tag | string | `""` |  |
| imagePullSecrets | list | `[]` |  |
| ingress.annotations | object | `{}` |  |
| ingress.className | string | `""` |  |
| ingress.enabled | bool | `false` |  |
| ingress.hosts[0].host | string | `"mdmbox.local"` |  |
| ingress.hosts[0].paths[0].path | string | `"/"` |  |
| ingress.hosts[0].paths[0].pathType | string | `"ImplementationSpecific"` |  |
| ingress.tls | list | `[]` |  |
| livenessProbe.failureThreshold | int | `10` |  |
| livenessProbe.httpGet.path | string | `"/healthz"` |  |
| livenessProbe.httpGet.port | string | `"main"` |  |
| livenessProbe.periodSeconds | int | `10` |  |
| nameOverride | string | `""` |  |
| nodeSelector | object | `{}` |  |
| podAnnotations | object | `{}` |  |
| podLabels | object | `{}` |  |
| podSecurityContext | object | `{}` |  |
| readinessProbe.failureThreshold | int | `5` |  |
| readinessProbe.httpGet.path | string | `"/readyz"` |  |
| readinessProbe.httpGet.port | string | `"main"` |  |
| readinessProbe.periodSeconds | int | `10` |  |
| readinessProbe.successThreshold | int | `1` |  |
| replicaCount | int | `1` |  |
| resources.requests.cpu | string | `"500m"` |  |
| resources.requests.memory | string | `"1Gi"` |  |
| securityContext | object | `{}` |  |
| service.port | int | `3000` |  |
| service.type | string | `"ClusterIP"` |  |
| serviceAccount.annotations | object | `{}` |  |
| serviceAccount.automount | bool | `true` |  |
| serviceAccount.create | bool | `false` |  |
| serviceAccount.name | string | `""` |  |
| startupProbe.failureThreshold | int | `90` |  |
| startupProbe.httpGet.path | string | `"/readyz"` |  |
| startupProbe.httpGet.port | string | `"main"` |  |
| startupProbe.initialDelaySeconds | int | `20` |  |
| startupProbe.periodSeconds | int | `5` |  |
| tolerations | list | `[]` |  |
| updateStrategy.type | string | `"RollingUpdate"` |  |
| volumeMounts | list | `[]` |  |
| volumes | list | `[]` |  |

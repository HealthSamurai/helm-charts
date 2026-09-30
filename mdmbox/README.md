# mdmbox

Probabilistic record matching service by Health Samurai

![Version: 0.1.1](https://img.shields.io/badge/Version-0.1.1-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 2608](https://img.shields.io/badge/AppVersion-2608-informational?style=flat-square)

## Installation

The default image is `healthsamurai/mdmbox:2608`. This monthly tag follows the highest published minor for August 2026. To pin a release, set `image.tag` to an exact published `YYMM.N` tag or set `image.digest`. The default `image.pullPolicy: Always` checks for an updated image whenever a pod starts; restart the deployment to pick up a newer monthly image. `edge` is a development image and must be selected explicitly.

mdmbox needs a PostgreSQL 14+ database. The chart supports two deployment modes:

- **Standalone** — mdmbox runs on its own. You point it at any PostgreSQL.
- **Alongside Aidbox** — mdmbox shares the same PostgreSQL and reuses Aidbox's `BOX_DB_*` `ConfigMap`/`Secret`.

The chart itself does not provision PostgreSQL — bring your own (managed service, an in-cluster operator, or the [bitnami/postgresql](https://artifacthub.io/packages/helm/bitnami/postgresql) chart).

MDMbox requires an active license for API access. For production, obtain a license JWT from the Aidbox portal and supply `MDMBOX_LICENSE` through a Secret. For local development, leave it unset, open MDMbox after installation, and select **Continue with Aidbox account** to activate through the browser. The browser-issued license is stored in the database and reused after restarts. See [License configuration](https://www.health-samurai.io/docs/mdmbox/config-reference#license).

### MDMbox-specific configuration

Non-secret MDMbox environment variables go under `config:`. The chart renders them into its own `ConfigMap` and loads them through `envFrom`:

```yaml
config:
  JAVA_OPTS: "-XX:MaxRAMPercentage=75"
  MDMBOX_DB_MAX_POOL_SIZE: "10"
  MDMBOX_DB_MIN_IDLE: "1"
  MDMBOX_BULK_DB_MAX_POOL_SIZE: "12"
  MDMBOX_BULK_DB_MIN_IDLE: "0"
  MDMBOX_BULK_DB_IDLE_TIMEOUT_MS: "60000"
```

Database connection settings can be shared with Aidbox, while MDMbox connection pools are sized independently. `MDMBOX_DB_*` settings control the main pool for API and admin traffic. `MDMBOX_BULK_DB_*` settings control a separate pool for matching workers; the idle timeout is in milliseconds. Include both pools when sizing PostgreSQL's connection limit.

For images that support `MDMBOX_LOG_LEVEL`, set the application log level without adding JVM options:

```yaml
config:
  MDMBOX_LOG_LEVEL: "debug"
```

Accepted levels are `trace`, `debug`, `info`, `warn`, `error`, and `off`, case-insensitively. An empty or unsupported value prevents startup. When unset, existing log settings remain effective (normally `info`). This setting requires an MDMbox image with support for the variable; updating the chart alone does not add it, and older images ignore it. Separate stdout streams configured through `BOX_OBSERVABILITY_STDOUT_LOG_LEVEL`, `BOX_OBSERVABILITY_STDOUT_PRETTY_LOG_LEVEL`, or `BOX_OBSERVABILITY_STDOUT_GOOGLE_LOG_LEVEL` remain independently controlled.

See the [Configuration reference](https://www.health-samurai.io/docs/mdmbox/config-reference) for the full environment variable list, defaults, and accepted values, including:

- Authentication: `MDMBOX_AUTH_ENABLED` (enabled by default), `MDMBOX_ADMIN_ID` / `MDMBOX_ADMIN_PASSWORD`, and `MDMBOX_API_CLIENT_ID` / `MDMBOX_API_CLIENT_SECRET`.
- Matching and FHIR: `MDMBOX_MATCH_DEFAULT_COUNT`, `MDMBOX_TEFCA_MODE`, and `MDMBOX_DEFAULT_FHIR_RELEASE`.
- Merge and unmerge algorithms: `MDMBOX_BUILT_IN_ALGORITHMS`, `MDMBOX_ALGORITHM_GIT_URL`, `MDMBOX_ALGORITHM_GIT_REF`, `MDMBOX_ALGORITHM_GIT_USERNAME`, `MDMBOX_ALGORITHM_GIT_TOKEN_FILE`, and `MDMBOX_ALGORITHM_GIT_CA_FILE`. Token and CA file paths must refer to files mounted through `volumes` and `volumeMounts`; `envFrom` does not mount files.
- HTTP: `MDMBOX_HTTP_HOST`; set the port through `service.port`, which supplies `MDMBOX_HTTP_PORT` for the container and keeps the Service and probes aligned.

### MDMbox secrets

Keep the license and credentials in a Secret, referenced through `extraEnvFromSecrets`. This Secret can be separate from the shared Aidbox database Secret:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mdmbox-secrets
  namespace: mdmbox
type: Opaque
stringData:
  MDMBOX_LICENSE: "<license JWT>"
  MDMBOX_ADMIN_ID: "mdmbox-admin"
  MDMBOX_ADMIN_PASSWORD: "<admin password>"
  MDMBOX_API_CLIENT_ID: "mdmbox-api"
  MDMBOX_API_CLIENT_SECRET: "<API client secret>"
```

Create the Secret before starting MDMbox, replacing the placeholders and using the Helm release's namespace. Reference its name in your Helm values:

```yaml
extraEnvFromSecrets:
  - mdmbox-secrets
```

The entries above are optional: omit `MDMBOX_LICENSE` for browser activation, and omit a credential pair when using an existing Aidbox User or Client. When bootstrapping credentials, supply both members of each pair. See [Authentication](https://www.health-samurai.io/docs/mdmbox/authentication). Do not put these secret values in `config`, which creates a plain ConfigMap.

### Environment variable precedence

The chart loads environment sources in this order, skipping optional references that are unset:

1. The MDMbox ConfigMap generated from `config`.
2. `aidboxConfigMap`.
3. `aidboxSecret`.
4. `extraEnvFromConfigMaps`, in list order.
5. `extraEnvFromSecrets`, in list order.

For duplicate variable names, the last source wins. For example, `JAVA_OPTS` in the shared Aidbox ConfigMap replaces `config.JAVA_OPTS`; an MDMbox-specific ConfigMap or Secret in the extra sources can supply the final override. See [Kubernetes environment sources](https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/pod-v1/#environment-variables).

`MDMBOX_HTTP_PORT` is set explicitly from `service.port` and takes precedence over all `envFrom` sources. Changes to `config` trigger a pod rollout on Helm upgrade. After changing an externally managed ConfigMap or Secret, restart the deployment so containers read the new values.

### Standalone

Create a `Secret` with the database credentials (and optionally other `BOX_DB_*` values) and reference it via `extraEnvFromSecrets`. Non-secret `BOX_DB_*` values can live in `config`:

```yaml
config:
  BOX_DB_HOST: postgres
  BOX_DB_PORT: "5432"
  BOX_DB_DATABASE: mdmbox

extraEnvFromSecrets:
  - mdmbox-db   # contains BOX_DB_USER, BOX_DB_PASSWORD
  - mdmbox-secrets   # contains MDMBOX_LICENSE and optional authentication settings
```

### Alongside Aidbox

Reuse the `ConfigMap` and `Secret` your Aidbox already has — point the chart at them via `aidboxConfigMap` / `aidboxSecret`. They are loaded into the pod via `envFrom`:

```yaml
aidboxConfigMap: <ConfigMap with BOX_DB_HOST, BOX_DB_PORT, BOX_DB_DATABASE>
aidboxSecret: <Secret with BOX_DB_USER, BOX_DB_PASSWORD>

extraEnvFromSecrets:
  - mdmbox-secrets
```

mdmbox and Aidbox then share the same PostgreSQL instance, FHIR data, and engine settings.

### Install

```console
helm repo add healthsamurai https://healthsamurai.github.io/helm-charts

helm upgrade --install mdmbox healthsamurai/mdmbox \
  --namespace mdmbox --create-namespace \
  --values /path/to/values.yaml
```

The release lands in the `mdmbox` namespace, creating it if needed. All referenced ConfigMaps and Secrets must be available in the release's namespace.

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
| config | object | `{"JAVA_OPTS":"-XX:MaxRAMPercentage=75"}` | Non-secret MDMbox environment variables rendered into the chart's ConfigMap (for example JAVA_OPTS, MDMBOX_LOG_LEVEL, MDMBOX_DB_* and MDMBOX_BULK_DB_*). Non-secret BOX_DB_* values can also be supplied here for standalone deployments. Use extraEnvFromSecrets for the license and credentials. Aidbox and extra envFrom sources override duplicate keys from this ConfigMap. MDMBOX_HTTP_PORT is set explicitly from service.port and overrides envFrom. |
| extraEnvFromConfigMaps | list | `[]` | Names of additional ConfigMaps loaded via envFrom after config and the Aidbox sources. Later sources override earlier sources with the same key. |
| extraEnvFromSecrets | list | `[]` | Names of additional Secrets loaded last via envFrom, in list order. Use for MDMBOX_LICENSE, MDMBOX_ADMIN_PASSWORD, MDMBOX_API_CLIENT_SECRET, and database credentials when not supplied by aidboxSecret. |
| fullnameOverride | string | `""` |  |
| image.digest | string | `""` |  |
| image.pullPolicy | string | `"Always"` | Check the registry when a pod starts so monthly tags pick up their latest minor. |
| image.repository | string | `"healthsamurai/mdmbox"` |  |
| image.tag | string | `""` | Overrides appVersion. Use YYMM for a monthly release or YYMM.N for an exact release. |
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

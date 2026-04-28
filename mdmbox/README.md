# mdmbox

Probabilistic record matching service by Health Samurai

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: edge](https://img.shields.io/badge/AppVersion-edge-informational?style=flat-square)

## Installation

1. Obtain an mdmbox [license](https://www.health-samurai.io/docs/aidbox/overview/aidbox-user-portal/licenses) from Health Samurai.
2. mdmbox connects to the same PostgreSQL database as Aidbox and reuses Aidbox's `BOX_DB_*` settings. Point the chart at an existing `ConfigMap` and `Secret` that hold those values — they are loaded into the pod via `envFrom`:

   ```yaml
   aidboxConfigMap: <ConfigMap with BOX_DB_HOST, BOX_DB_PORT, BOX_DB_DATABASE>
   aidboxSecret: <Secret with BOX_DB_USER, BOX_DB_PASSWORD>
   ```

3. Put mdmbox-specific environment variables (license, `JAVA_OPTS`, etc.) under `config:`. The chart renders them into its own `ConfigMap` and mounts it into the pod:

   ```yaml
   config:
     MDMBOX_LICENSE: <your license string>
     JAVA_OPTS: "-XX:MaxRAMPercentage=75"
   ```

   For values that should not live in plain Helm values (secrets, tokens), put them in your own `ConfigMap`/`Secret` and reference them via `extraEnvFromConfigMaps` / `extraEnvFromSecrets`.

```console
helm repo add healthsamurai https://healthsamurai.github.io/helm-charts

helm upgrade --install mdmbox healthsamurai/mdmbox \
  --namespace mdmbox --create-namespace \
  --values /path/to/config/file
```

It will install mdmbox in the `mdmbox` namespace, creating that namespace if it doesn't already exist.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` |  |
| aidboxConfigMap | string | `""` | Name of an existing ConfigMap with Aidbox env vars (e.g. BOX_DB_HOST, BOX_DB_PORT, BOX_DB_DATABASE). Required. |
| aidboxSecret | string | `""` | Name of an existing Secret with Aidbox credentials (e.g. BOX_DB_USER, BOX_DB_PASSWORD). Required. |
| autoscaling.enabled | bool | `false` |  |
| autoscaling.maxReplicas | int | `100` |  |
| autoscaling.minReplicas | int | `1` |  |
| autoscaling.targetCPUUtilizationPercentage | int | `80` |  |
| config | object | `{"JAVA_OPTS":"-XX:MaxRAMPercentage=75"}` | mdmbox config. All BOX_* env vars come from aidboxConfigMap/aidboxSecret; keep only mdmbox-specific vars here. MDMBOX_HTTP_PORT is injected from .Values.service.port in deployment.yaml (single source of truth). |
| extraEnvFromConfigMaps | list | `[]` |  |
| extraEnvFromSecrets | list | `[]` |  |
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

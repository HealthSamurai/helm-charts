# aidbox

[Aidbox](https://www.health-samurai.io/docs/aidbox) is an efficient and scalable FHIR server built to handle healthcare data effectively, empowering healthcare providers and developers alike with its comprehensive platform for storing, accessing, and exchanging healthcare information in accordance with FHIR standards.

![Version: 0.3.0](https://img.shields.io/badge/Version-0.3.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: edge](https://img.shields.io/badge/AppVersion-edge-informational?style=flat-square)

## Installation

1. Obtain a [license](https://www.health-samurai.io/docs/aidbox/overview/aidbox-user-portal/licenses).
2. Prepare the configuration file. Please refer to the [Recommended Aidbox environment variables](https://www.health-samurai.io/docs/aidbox/configuration/recommended-envs) for details. For the whole list of available environment variables follow [the settings documentation](https://www.health-samurai.io/docs/aidbox/reference/all-settings).

```yaml
host: <your host here, e.g. my.domain.tld>
protocol: <http or https>

config:
  BOX_DB_HOST: <PostgreSQL host to connect to>
  BOX_DB_DATABASE: <name of the database that is used to store resources>
  BOX_DB_USER: <PostgreSQL user>
  BOX_DB_PASSWORD: <PostgreSQL password>
```

```console
helm repo add healthsamurai https://healthsamurai.github.io/helm-charts

helm upgrade --install aidbox healthsamurai/aidbox \
  --namespace aidbox --create-namespace \
  --values /path/to/config/file
```

It will install the Aidbox in the `aidbox` namespace, creating that namespace if it doesn't already exist.

## Vertical Pod Autoscaler

Off by default. `verticalPodAutoscaler.enabled: true` adds a `VerticalPodAutoscaler` for the
Deployment; the cluster needs the [VPA](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler)
CRDs, recommender and admission controller. The default `updatePolicy.updateMode: Recreate` evicts pods
whose requests drift from the recommendation. `updatePolicy.minReplicas: 2` keeps it from evicting a
single-replica Deployment: there the recommendation applies only when a pod is created
(`kubectl rollout restart deployment/aidbox` applies a new one). Set `minReplicas: 1` to allow evicting a
lone pod at the cost of a short downtime per update; with 2+ replicas, pair it with `podDisruptionBudget`.
By default VPA manages memory requests only
(`controlledResources: [memory]`, `controlledValues: RequestsOnly`): CPU and limits stay as set in
`resources`. The resource policy covers the `aidbox` container only. Don't combine it with `autoscaling`
on the same resource (CPU/memory): HPA and VPA would fight over it.
```yaml
verticalPodAutoscaler:
  enabled: true
  minAllowed: {memory: 1Gi}
  maxAllowed: {memory: 8Gi}
```

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` |  |
| auditbox.auth.client | string | `""` |  |
| auditbox.auth.existingSecretName | string | `""` |  |
| auditbox.auth.host | string | `""` |  |
| auditbox.auth.path | string | `""` |  |
| auditbox.auth.secret | string | `""` |  |
| auditbox.enabled | bool | `false` |  |
| auditbox.host | string | `"auditbox.health-samurai.io"` |  |
| auditbox.port | int | `8081` |  |
| autoscaling.enabled | bool | `false` |  |
| autoscaling.maxReplicas | int | `100` |  |
| autoscaling.minReplicas | int | `1` |  |
| autoscaling.targetCPUUtilizationPercentage | int | `80` |  |
| config | object | `{"BOX_DB_PORT":5432,"BOX_METRICS_PORT":8765,"BOX_WEB_PORT":8080}` | Aidbox config see [Aidbox environment variables](https://www.health-samurai.io/docs/aidbox/reference/all-settings) for details |
| deploymentAnnotations | object | `{}` |  |
| extraContainers | string | `""` | Additional sidecar containers to run alongside Aidbox in the same pod. Rendered with `tpl`, so Helm templates (e.g. {{ .Release.Namespace }}) can be used. |
| extraEnvFromConfigMaps | list | `[]` |  |
| extraEnvFromSecrets | list | `[]` |  |
| extraEnvs | list | `[]` |  |
| fullnameOverride | string | `""` |  |
| host | string | `"my.domain.tld"` | Host name Aidbox will be available at |
| image.digest | string | `""` | Pin by digest, e.g. `sha256:...` (wins over tag when set). |
| image.pullPolicy | string | `"IfNotPresent"` |  |
| image.repository | string | `"healthsamurai/aidboxone"` |  |
| image.tag | string | `""` |  |
| imagePullSecrets | list | `[]` | Optional array of imagePullSecrets containing private registry credentials # Ref: https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/ |
| ingress.annotations | object | `{}` |  |
| ingress.className | string | `"nginx"` |  |
| ingress.defaultPath | string | `"/"` |  |
| ingress.enabled | bool | `true` |  |
| initContainers | list | `[]` |  |
| labels | object | `{}` | labels applied to the top-level Deployment resource. Rendered with `tpl`, so Helm templates (e.g. {{ .Release.Namespace }}) can be used. |
| livenessProbe.failureThreshold | int | `10` |  |
| livenessProbe.httpGet.path | string | `"/health"` |  |
| livenessProbe.httpGet.port | string | `"api"` |  |
| livenessProbe.periodSeconds | int | `10` |  |
| nameOverride | string | `""` |  |
| nodeSelector | object | `{}` |  |
| podAnnotations | object | `{}` |  |
| podDisruptionBudget.enabled | bool | `false` |  |
| podDisruptionBudget.maxUnavailable | int | `1` |  |
| podDisruptionBudget.minAvailable | int | `0` |  |
| podDisruptionBudget.unhealthyPodEvictionPolicy | string | `"IfHealthyBudget"` |  |
| podLabels | object | `{}` |  |
| podSecurityContext | object | `{}` |  |
| protocol | string | `"http"` | Protocol to be used to access Aidbox (http or https) |
| readinessProbe.failureThreshold | int | `5` |  |
| readinessProbe.httpGet.path | string | `"/health"` |  |
| readinessProbe.httpGet.port | string | `"api"` |  |
| readinessProbe.periodSeconds | int | `10` |  |
| readinessProbe.successThreshold | int | `1` |  |
| replicaCount | int | `1` |  |
| resources.requests.cpu | string | `"500m"` |  |
| resources.requests.memory | string | `"256Mi"` |  |
| route | object | `{"main":{"additionalRules":[],"annotations":{},"apiVersion":"gateway.networking.k8s.io/v1","enabled":false,"filters":[],"hostnames":[],"kind":"HTTPRoute","labels":{},"matches":[{"path":{"type":"PathPrefix","value":"/"}}],"parentRefs":[],"sessionPersistence":{},"timeouts":{}}}` | Gateway API routes (HTTPRoute by default). Disabled by default; use instead of ingress when a Gateway API implementation is available. |
| route.main.apiVersion | string | `"gateway.networking.k8s.io/v1"` | Set the route apiVersion, e.g. gateway.networking.k8s.io/v1 or gateway.networking.k8s.io/v1alpha2 |
| route.main.enabled | bool | `false` | Enables or disables the route |
| route.main.kind | string | `"HTTPRoute"` | Set the route kind Valid options are GRPCRoute, HTTPRoute, TCPRoute, TLSRoute, UDPRoute |
| securityContext.runAsNonRoot | bool | `true` |  |
| securityContext.runAsUser | int | `1000` |  |
| service.annotations | object | `{}` |  |
| service.apiPort | int | `80` |  |
| service.metricsPort | int | `80` |  |
| service.type | string | `"ClusterIP"` |  |
| serviceAccount.name | string | `""` | ServiceAccount to use |
| serviceMonitor.enabled | bool | `false` |  |
| startupProbe.failureThreshold | int | `10` |  |
| startupProbe.httpGet.path | string | `"/health"` |  |
| startupProbe.httpGet.port | string | `"api"` |  |
| startupProbe.initialDelaySeconds | int | `20` |  |
| startupProbe.periodSeconds | int | `5` |  |
| tolerations | list | `[]` |  |
| topologySpreadConstraints | list | `[]` | Pod topology spread constraints. When empty, pods are softly spread across zones (`topology.kubernetes.io/zone`, maxSkew 1, ScheduleAnyway) using the chart's selector labels. |
| updateStrategy.type | string | `"RollingUpdate"` |  |
| verticalPodAutoscaler.controlledResources[0] | string | `"memory"` |  |
| verticalPodAutoscaler.controlledValues | string | `"RequestsOnly"` |  |
| verticalPodAutoscaler.enabled | bool | `false` |  |
| verticalPodAutoscaler.maxAllowed | object | `{}` |  |
| verticalPodAutoscaler.minAllowed | object | `{}` |  |
| verticalPodAutoscaler.updatePolicy.minReplicas | int | `2` | The updater evicts only while at least this many replicas are running, so a single-replica Deployment is never evicted. Set `1` to allow it (each update is then a short downtime). |
| verticalPodAutoscaler.updatePolicy.updateMode | string | `"Recreate"` |  |
| volumeMounts | list | `[]` |  |
| volumes | list | `[]` |  |

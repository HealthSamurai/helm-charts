# interbox

Integration Engine for Modern Healthcare Solutions. This chart deploys the all-in-one
interbox, which ingests HL7v2 over MLLP and delivers FHIR to Aidbox. The API and dashboard
run in the same pod as the engine.

![Version: 0.2.0](https://img.shields.io/badge/Version-0.2.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: edge](https://img.shields.io/badge/AppVersion-edge-informational?style=flat-square)

## Installation

interbox needs a **Postgres** database and an **Aidbox** endpoint, and the chart bundles
neither. See [PREREQUISITES.md](./PREREQUISITES.md) for both, or install the sibling
[`postgres`](../postgres) and [`aidbox`](../aidbox) charts if you want them in-cluster.

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
  DATABASE_URL: postgres://interbox:pass@pg:5432/interbox?sslmode=require   # user needs CREATEDB
  AIDBOX_CLIENT_SECRET: <aidbox client secret>
```

`secrets` takes env var names as keys, the same as `config`. The 0.1 shape
`secrets.data.<KEY>` still works but is deprecated, and when a key is set both ways the flat
value wins.

The dashboard and API listen on `3001`, and MLLP (HL7v2) gets TCP `2575` on a LoadBalancer
of its own.

## Setup scenarios

Each snippet is a values file for this chart, and on AKS you add `-f values-aks.yaml` as
well. Aidbox and Postgres are external unless you install the sibling charts, whose service
names depend on their release names, so check their `helm install` output.

### 1. Existing Aidbox and managed Postgres (typical prod)

interbox creates its own `interbox` database on your managed Postgres and delivers to your
existing Aidbox.

```yaml
config:
  AIDBOX_URL: https://aidbox.internal
secrets:
  DATABASE_URL: postgres://interbox:pass@pg.internal:5432/interbox?sslmode=require
  AIDBOX_CLIENT_SECRET: <aidbox client secret>
```

### 2. Existing Aidbox, reusing its Postgres cluster

There's no separate database server: interbox gets its own `interbox` database on the
cluster Aidbox already uses, next to Aidbox's own database.

```yaml
config:
  AIDBOX_URL: https://aidbox.internal
secrets:
  DATABASE_URL: postgres://interbox:pass@aidbox-pg:5432/interbox?sslmode=require
  AIDBOX_CLIENT_SECRET: <aidbox client secret>
```

### 3. No Aidbox or Postgres yet: install the sibling charts (dev/stage)

```console
helm install pg       healthsamurai/postgres -n interbox --create-namespace
helm install aidbox   healthsamurai/aidbox   -n interbox
helm install interbox healthsamurai/interbox -n interbox -f dev-values.yaml
```

`dev-values.yaml`, pointing at the sibling charts' service names:

```yaml
config:
  AIDBOX_URL: http://aidbox:8080
secrets:
  DATABASE_URL: postgres://interbox:pass@pg-postgres:5432/interbox   # user needs CREATEDB
  AIDBOX_CLIENT_SECRET: secret
```

### 4. Locked-down managed Postgres (no admin grant)

Pre-create the database and its extensions yourself as [PREREQUISITES.md](./PREREQUISITES.md)
describes. `createDatabase: false` sets `INTERBOX_SKIP_ENSURE_DB` so the engine skips its
bootstrap.

```yaml
database:
  createDatabase: false
config:
  AIDBOX_URL: https://aidbox.internal
secrets:
  DATABASE_URL: postgres://interbox:pass@pg.internal:5432/interbox?sslmode=require
  AIDBOX_CLIENT_SECRET: <aidbox client secret>
```

## AKS

[`values-aks.yaml`](./values-aks.yaml) makes the MLLP LoadBalancer internal and raises its TCP
idle timeout. Add on top, as needed:

```yaml
mllp:
  service:
    annotations:
      service.beta.kubernetes.io/azure-load-balancer-ipv4: 10.20.0.5
    loadBalancerSourceRanges:
      - 10.10.0.0/16
ingress:
  enabled: true
  className: nginx-internal
  host: interbox.internal.example.com
```

- `azure-load-balancer-ipv4` pins the LB to a free IP in its subnet, so the VPN or firewall
  target survives a reinstall. Use it instead of `mllp.service.loadBalancerIP`: Kubernetes
  deprecated `spec.loadBalancerIP` in 1.24.
- `loadBalancerSourceRanges` limits the LB to the sender subnets.
- The dashboard stays private only behind an internal ingress class, one whose controller sits
  behind an internal LB. Annotations on the Ingress itself don't make it internal.

## Secrets from a vault

`secrets.existingSecretName` takes any Secret you provision yourself, with External Secrets
Operator, sealed-secrets or the [Secrets Store CSI Driver](https://secrets-store-csi-driver.sigs.k8s.io/).
The CSI driver creates the Secret that a `SecretProviderClass` syncs (`secretObjects`) only
while a pod mounts its volume, so mount it:

```yaml
secrets:
  existingSecretName: interbox-secrets
volumes:
  - name: kv-secrets
    csi:
      driver: secrets-store.csi.k8s.io
      readOnly: true
      volumeAttributes:
        secretProviderClass: interbox-kv
volumeMounts:
  - name: kv-secrets
    mountPath: /mnt/secrets
    readOnly: true
```

The `checksum/*` pod annotations restart the pod when the chart's own ConfigMap or Secret
changes. A Secret the chart doesn't render is invisible to it, so a rotated value only
reaches the env after a restart, which [Reloader](https://github.com/stakater/Reloader) can
do:

```yaml
deploymentAnnotations:
  secret.reloader.stakater.com/reload: interbox-secrets
```

## Vertical Pod Autoscaler

Off by default. `verticalPodAutoscaler.enabled: true` adds a `VerticalPodAutoscaler` for the
Deployment, and the cluster needs the [VPA](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler)
CRDs, recommender and admission controller.

The default `updatePolicy.updateMode: Initial` applies a recommendation only when a pod is
created and never evicts it. interbox runs a single pod that builds the workspace on boot, so
an eviction is downtime. A new recommendation therefore reaches only the next pod, and
`kubectl rollout restart deployment/interbox` applies it now. Until VPA has a first
recommendation, pods keep plain `resources`.

Every setting is a map key, so a per-environment overlay can change one, say
`maxAllowed.memory`, without restating the rest.

```yaml
verticalPodAutoscaler:
  enabled: true
  controlledValues: RequestsOnly
  minAllowed: {cpu: 100m, memory: 512Mi}
  maxAllowed: {cpu: "1", memory: 4Gi}
```

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` | Affinity rules for scheduling. |
| automountServiceAccountToken | bool | `false` | Don't mount the ServiceAccount token; interbox never calls the Kubernetes API. |
| config | object | `{"AIDBOX_URL":"http://aidbox:8080","INTERBOX_WORKSPACE_POLL_MS":"5000","MLLP_HOST":"0.0.0.0","MLLP_PORT":"2575"}` | Non-secret env → ConfigMap (envFrom). Keys are env var names. |
| database.createDatabase | bool | `true` | The engine creates the `interbox` db on boot (`DATABASE_URL` user needs `CREATEDB`). `false` sets `INTERBOX_SKIP_ENSURE_DB`: pre-create the db yourself. |
| deploymentAnnotations | object | `{}` | Deployment annotations. |
| extraEnvFromConfigMaps | list | `[]` | Extra ConfigMaps to load env from (envFrom). |
| extraEnvFromSecrets | list | `[]` | Extra Secrets to load env from (envFrom). |
| fullnameOverride | string | `""` | Override the full resource name (default: the chart name). |
| image.digest | string | `""` | Image digest; wins over `tag`. |
| image.pullPolicy | string | `"Always"` | Image pull policy. `Always` refreshes the moving `edge` tag; use `IfNotPresent` once pinned. |
| image.repository | string | `"healthsamurai/interbox"` | Image repository. |
| image.tag | string | `""` | Image tag (default: `.Chart.AppVersion`). Pin a release for prod. |
| imagePullSecrets | list | `[]` | Image pull secrets for a private registry. |
| ingress.annotations | object | `{}` | Ingress annotations. |
| ingress.className | string | `""` | Ingress class name. |
| ingress.enabled | bool | `false` | Dashboard/API Ingress. Use an internal ingress class only; never expose it publicly. |
| ingress.host | string | `"interbox.example.com"` | Ingress host. |
| ingress.path | string | `"/"` | Ingress path. AWS ALB and GKE gce want `/*` with `pathType: ImplementationSpecific`. |
| ingress.pathType | string | `"Prefix"` | Ingress pathType (Prefix | ImplementationSpecific | Exact). |
| ingress.tls | list | `[]` | Ingress TLS blocks. |
| mllp.enabled | bool | `true` | Expose MLLP (HL7v2 over raw TCP). |
| mllp.port | int | `2575` | MLLP TCP port. |
| mllp.service.annotations | object | `{}` | MLLP Service annotations. |
| mllp.service.externalTrafficPolicy | string | `"Local"` | `Local` keeps the sender's source IP. Empty = `Cluster`. |
| mllp.service.internal | bool | `true` | Shown in the install notes only. The cloud annotation makes the LB private (see values-aks.yaml). |
| mllp.service.loadBalancerIP | string | `""` | Static LB IP, a stable VPN/firewall target. Empty = dynamic. Kubernetes deprecated the field; prefer a cloud annotation. |
| mllp.service.loadBalancerSourceRanges | list | `[]` | Sender CIDRs allowed to reach the LB. |
| mllp.service.type | string | `"LoadBalancer"` | MLLP Service type. Raw TCP, so not an Ingress. |
| nameOverride | string | `""` | Override the chart name used in resource names. |
| nodeSelector | object | `{}` | Node selector for scheduling. |
| podAnnotations | object | `{}` | Pod annotations. |
| probe.liveness | object | `{"failureThreshold":3,"periodSeconds":20,"timeoutSeconds":5}` | Liveness probe. |
| probe.path | string | `"/api/health"` | HTTP health path for all probes. |
| probe.readiness | object | `{"failureThreshold":3,"periodSeconds":10,"timeoutSeconds":3}` | Readiness probe. |
| probe.scheme | string | `"HTTP"` | Probe scheme (HTTP / HTTPS). |
| probe.startup | object | `{"failureThreshold":60,"initialDelaySeconds":10,"periodSeconds":10}` | Startup probe. Generous: the pod clones, installs and builds the workspace on boot. |
| replicaCount | int | `1` | Pod replicas. Keep at 1: the pod runs a single MLLP listener. |
| resources | object | `{}` | Pod resources. The boot-time workspace build is memory-hungry: set a generous memory limit or none. |
| secrets | object | `{"AIDBOX_CLIENT_SECRET":"","ANTHROPIC_API_KEY":"","CLAUDE_CODE_OAUTH_TOKEN":"","DATABASE_URL":"","INTERBOX_LICENSE":"","INTERBOX_WORKSPACE_GIT_KEY":"","existingSecretName":""}` | Secret env → Secret (envFrom). Keys are env var names; empty ones are skipped. `DATABASE_URL` is required. `secrets.data.<KEY>` is deprecated; a flat key wins. |
| secrets.existingSecretName | string | `""` | Pre-provisioned Secret to use instead of rendering one (External Secrets Operator, sealed-secrets, …). |
| securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"runAsGroup":1000,"runAsNonRoot":true,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}}` | Container securityContext. The image runs as non-root `bun` (uid 1000) and writes to HOME and `/tmp`. |
| service.annotations | object | `{}` | Dashboard/API Service annotations. |
| service.port | int | `3001` | Dashboard/API port. |
| service.type | string | `"ClusterIP"` | Dashboard/API Service type. |
| serviceAccount.annotations | object | `{}` | ServiceAccount annotations. |
| serviceAccount.create | bool | `false` | Create a ServiceAccount for the pod. |
| serviceAccount.name | string | `""` | ServiceAccount name (default: the fullname when `create` is true). |
| strategy | object | `{"type":"Recreate"}` | Deployment strategy. `Recreate`: two pods must never run the MLLP listener at once. |
| terminationGracePeriodSeconds | int | `30` | Grace period for in-flight messages to persist and ACK before SIGKILL. |
| tolerations | list | `[]` | Tolerations for scheduling. |
| verticalPodAutoscaler.controlledResources | list | `[]` |  |
| verticalPodAutoscaler.controlledValues | string | `""` |  |
| verticalPodAutoscaler.enabled | bool | `false` |  |
| verticalPodAutoscaler.maxAllowed | object | `{}` |  |
| verticalPodAutoscaler.minAllowed | object | `{}` |  |
| verticalPodAutoscaler.updatePolicy.minReplicas | int | `1` | Lets the updater act on the single pod; by default it skips workloads with fewer than 2 replicas. `null` keeps that default. |
| verticalPodAutoscaler.updatePolicy.updateMode | string | `"Initial"` |  |
| volumeMounts | list | `[]` | Extra container volume mounts. |
| volumes | list | `[]` | Extra pod volumes. |

# interbox

Integration Engine for Modern Healthcare Solutions. This chart deploys the all-in-one
interbox, which ingests HL7v2 over MLLP and runs the pipelines from your workspace, for
example to deliver FHIR to Aidbox. The API and dashboard run in the same pod as the engine.

![Version: 0.4.0](https://img.shields.io/badge/Version-0.4.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: edge](https://img.shields.io/badge/AppVersion-edge-informational?style=flat-square)

## Installation

interbox needs a **Postgres** database. **Aidbox** is optional: you need one only when your
pipelines deliver to it. The chart bundles neither, so see [PREREQUISITES.md](./PREREQUISITES.md)
or install the sibling [`postgres`](../postgres) and [`aidbox`](../aidbox) charts if you want
them in-cluster.

```console
helm repo add healthsamurai https://healthsamurai.github.io/helm-charts

helm upgrade --install interbox healthsamurai/interbox \
  --namespace interbox --create-namespace \
  --values /path/to/values.yaml
```

Minimal `values.yaml`:

```yaml
config:
  INTERBOX_WORKSPACE_GIT_URL: https://github.com/<you>/<your-workspace>
  INTERBOX_PUBLIC_URL: https://interbox.internal.example
secrets:
  DATABASE_URL: postgres://interbox:pass@pg:5432/interbox?sslmode=require   # user needs CREATEDB
  INTERBOX_AUTH_ADMIN_PASSWORD: <20 characters or more>
```

The workspace repository holds your pipelines. The dashboard needs its public URL and a way
to sign in, and [PREREQUISITES.md](./PREREQUISITES.md) covers both.

`secrets` takes env var names as keys, the same as `config`. The 0.1 shape
`secrets.data.<KEY>` still works but is deprecated, and when a key is set both ways the flat
value wins.

The dashboard and API listen on `3001`, and MLLP (HL7v2) gets TCP `2575` on a LoadBalancer
of its own. Keep `mllp.port` equal to the port your workspace's MLLP source listens on.
Webhooks are off by default. Set `webhook.enabled: true` when the workspace declares a
`webhookSource` or a `pullSender`: the engine serves both on one port, `3002`, and tells them
apart by their `path`. The chart then gives that port a Service of its own, `interbox-webhook`,
so in-cluster callers reach a route at `http://interbox-webhook.<namespace>.svc:3002/<path>`:
Aidbox posting to a webhook source, or the Aidbox App that polls a pull sender. That Service is
always ClusterIP, whatever `service.type` is, so nothing outside the cluster reaches the port
through it. The chart always sets `INTERBOX_WEBHOOK_PORT` on the container from `webhook.port`,
so change the port there. `config.INTERBOX_WEBHOOK_PORT` fails the render, a different value
in an extra ConfigMap rejects startup, and one in `secrets` is ignored. Engine images up to
`v2.3.0` ignore the variable. There, each webhook source names its own port, and only a
source on `webhook.port` is reachable.

## Setup scenarios

Each snippet adds to the minimal values above, and on AKS you add `-f values-aks.yaml` as
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

## NetworkPolicy

Port `3001` serves the dashboard and its API, so close it to everything that has no reason
to call it. `networkPolicy.enabled: true` adds an ingress-only NetworkPolicy:

```yaml
networkPolicy:
  enabled: true
  dashboardFrom:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: ingress-nginx
  mllpFrom:
    - ipBlock:
        cidr: 10.10.0.0/16
  webhookFrom:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: aidbox
```

The dashboard port accepts only the `dashboardFrom` peers, none by default, and
`kubectl port-forward` keeps working. The MLLP port accepts the `mllpFrom` peers, or any
source when the list is empty, which leaves the filtering to `loadBalancerSourceRanges`. With
`externalTrafficPolicy: Local` the pod sees the senders' own IPs, so `ipBlock` peers match
them. With `webhook.enabled`, the webhook port accepts the `webhookFrom` peers, or any source
when the list is empty. A webhook source without a `secret` accepts every caller that reaches
the port, so give it one or narrow `webhookFrom`. Egress stays open: the workspace service clones
the workspace, and the main pods reach Postgres and Aidbox.

## Vertical Pod Autoscaler

Off by default. `verticalPodAutoscaler.enabled: true` adds a `VerticalPodAutoscaler` for the
main Deployment, and the cluster needs the [VPA](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler)
CRDs, recommender and admission controller.

The default `updatePolicy.updateMode: Initial` applies a recommendation only when a pod is
created and never evicts it. An eviction restarts a pod, and with one replica that is downtime.
A new recommendation therefore reaches only the next pod, and
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

## Replicas and rollouts

Every ready replica gets traffic through the Services. With `replicaCount` above 1, a lease
in Postgres picks one replica to process. The others stand by and take over when it stops.
Replicas add availability, not throughput.

The default `RollingUpdate` strategy (`maxSurge: 1`, `maxUnavailable: 0`) starts a new pod
and waits for it to be ready before it stops an old one. `strategy: {type: Recreate}` still
works: the chart drops `rollingUpdate` from it.

On interbox 2.5.0 or later, set the readiness path for rolling deploys, so only
ready pods with bound listeners get traffic:

```yaml
probe:
  readiness:
    path: /api/ready
```

Older engines must keep the default `/api/health`: their `/api/ready` also turns unready
without a license or while a pipeline is in backoff, and Kubernetes then takes the pod out
of the dashboard, MLLP and webhook Services at once.

## Workspace service

The `interbox-workspace` Deployment runs one pod, the workspace service. It owns the editable
workspace checkout, runs the dashboard assistant and the workspace actions, builds the
workspace once per revision and publishes the build to Postgres. The main pods load that
build and never clone or build. They reach the workspace service through
`INTERBOX_WORKSPACE_SERVICE_URL`, set to the Service `interbox-workspace` on port `3001`.

The pod runs the same image with the `workspace` argument, one replica and the `Recreate`
strategy. It takes the same env and secrets as the main pods: the `INTERBOX_WORKSPACE_*`
settings and credentials, `DATABASE_URL`, auth and, for the assistant, a Claude login
(`CLAUDE_CODE_OAUTH_TOKEN` or `ANTHROPIC_API_KEY`).

Its checkout lives on a ReadWriteOnce PersistentVolumeClaim, so uncommitted edits survive a
restart. `workspaceService.persistence.enabled: false` uses an `emptyDir` instead, and the
edits go away with the pod. While the workspace service is down, the main pods keep running
and restart from the last published build.

With `networkPolicy.enabled`, the workspace pod accepts port `3001` only from the main pods.
It carries the label `app: interbox-workspace`, not `app: interbox`, so a NetworkPolicy of
your own that selects the main pods does not cover it.

## Upgrading from chart 0.3.x

Chart 0.4.0 needs engine 2.5.0 or later, and engine 2.5.0 needs chart 0.4.0. Move the image
and the chart in the same upgrade:

- Engine 2.5.0 under chart 0.3.x has no workspace service. Its pods find no published build
  and stay unready.
- An older image under chart 0.4.0 ignores the `workspace` argument, so the workspace pod runs
  a second full engine and API alongside the main pods. With engine 2.1.x or older, a custom
  polling source (`defineSource` with `kind: pull`) can then ingest a record twice. A 2.4.x
  engine runs safely as a second replica, but the workspace pod's readiness follows that
  engine's `/api/ready`, which turns unready while a pipeline is in backoff.

A deployment whose chart version floats, with a `>=` range or none, takes 0.4.0 as soon as it
is released, whatever its image. Pin it below 0.4.0 until its image moves too.

## Pod lifecycle

- `resources` requests 1Gi of `ephemeral-storage` for the builds a main pod unpacks,
  the container filesystem and the logs together. There is no limit by default. With
  `resources.limits.ephemeral-storage` set, Kubernetes evicts a pod that outgrows it.
  A limit below the 1Gi request makes Kubernetes reject the pod, so lower
  `resources.requests.ephemeral-storage` with it.
- All probes use `/api/health` by default, which answers while the API process runs.
  An unready pod loses Service traffic without a restart. See
  [Replicas and rollouts](#replicas-and-rollouts) for `/api/ready`.
- Each probe can set its own `path`, and otherwise inherits `probe.path`. The
  workspace service ignores both: its startup and liveness probes use `/api/health`
  and its readiness probe `/api/ready`. It takes their other settings from `probe`.
- `preStopDelaySeconds` lets routing drain before shutdown (default 5s; `0` disables it).
  This counts toward `terminationGracePeriodSeconds`, so the chart refuses a delay
  that is not below it. The wait uses the kubelet's built-in `preStop.sleep` action,
  so the image needs no `sleep` binary, but the cluster needs Kubernetes 1.30 or
  later. On an older cluster set it to `0`.

## Configuration

The chart refuses a `config` key that would break the engine: `DATABASE_URL` (put it in
`secrets`), `INTERBOX_WEBHOOK_PORT` (set `webhook.port`), and `INTERBOX_WORKSPACE_CACHE`
(the workspace service keeps its checkout on its volume at the engine's default path). It
cannot see keys in extra ConfigMaps. Changes to the chart's own ConfigMap and Secret restart the pods;
external ConfigMap and Secret updates need a rollout.

## Gateway API

Requires Gateway API CRDs/controller and a Gateway permitting this namespace.
Configure TLS/auth on the Gateway; Ingress auth annotations do not transfer.

```yaml
ingress:
  enabled: false
route:
  main:
    enabled: true
    parentRefs:
      - name: internal-gateway
        namespace: gateway-system
        sectionName: https
    hostnames: [interbox.internal.example]
```

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` | Affinity rules for scheduling. |
| automountServiceAccountToken | bool | `false` | Don't mount the ServiceAccount token; interbox never calls the Kubernetes API. |
| config | object | `{"AIDBOX_URL":"http://aidbox:8080","INTERBOX_WORKSPACE_POLL_MS":"5000","MLLP_HOST":"0.0.0.0","MLLP_PORT":"2575"}` | Non-secret env → ConfigMap (envFrom). Keys are env var names; `DATABASE_URL` and `INTERBOX_WEBHOOK_PORT` fail the render. `INTERBOX_WORKSPACE_GIT_URL` and `INTERBOX_PUBLIC_URL` are required. `MLLP_HOST` and `MLLP_PORT` feed the workspace's MLLP source. |
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
| mllp.port | int | `2575` | MLLP TCP port. Match the port the workspace's MLLP source listens on. |
| mllp.service.annotations | object | `{}` | MLLP Service annotations. Without the cloud's internal-LB annotation (see values-aks.yaml), most clouds give the LoadBalancer a public IP. |
| mllp.service.externalTrafficPolicy | string | `"Local"` | `Local` keeps the sender's source IP. Empty = `Cluster`. |
| mllp.service.loadBalancerIP | string | `""` | Static LB IP, a stable VPN/firewall target. Empty = dynamic. Kubernetes deprecated the field; prefer a cloud annotation. |
| mllp.service.loadBalancerSourceRanges | list | `[]` | Sender CIDRs allowed to reach the LB. |
| mllp.service.type | string | `"LoadBalancer"` | MLLP Service type. Raw TCP, so not an Ingress. |
| nameOverride | string | `""` | Override the chart name used in resource names. |
| networkPolicy.dashboardFrom | list | `[]` | NetworkPolicyPeers allowed to reach the dashboard/API port. Empty = none; `kubectl port-forward` still works. |
| networkPolicy.enabled | bool | `false` | Render an ingress-only NetworkPolicy for the pod. Egress stays open. |
| networkPolicy.mllpFrom | list | `[]` | NetworkPolicyPeers allowed to reach the MLLP port. Empty = any source. |
| networkPolicy.webhookFrom | list | `[]` | NetworkPolicyPeers allowed to reach the webhook port, e.g. the Aidbox pods. Empty = any source. |
| nodeSelector | object | `{}` | Node selector for scheduling. |
| podAnnotations | object | `{}` | Pod annotations. |
| preStopDelaySeconds | int | `5` | Seconds the kubelet waits in `preStop` (the built-in `sleep` action, Kubernetes 1.30+), so Service routing drains before shutdown. Counts toward `terminationGracePeriodSeconds` and must stay below it; `0` turns it off. |
| priorityClassName | string | `""` | Pod priority class, so the scheduler doesn't preempt the single pod for less important work. |
| probe.liveness | object | `{"failureThreshold":3,"periodSeconds":20,"timeoutSeconds":5}` | Liveness probe. |
| probe.path | string | `"/api/health"` | Default HTTP path for every probe. A probe's own `path` wins. |
| probe.readiness | object | `{"failureThreshold":3,"periodSeconds":10,"timeoutSeconds":3}` | Readiness probe. It inherits `probe.path`. On interbox 2.5.0 or later set `path: /api/ready`, so only ready pods with bound listeners get traffic; older engines must keep `/api/health`. See the README. |
| probe.scheme | string | `"HTTP"` | Probe scheme (HTTP / HTTPS). |
| probe.startup | object | `{"failureThreshold":60,"initialDelaySeconds":10,"periodSeconds":10}` | Startup probe, for the main pods and the workspace service. Generous: the workspace service clones, installs and builds the workspace on its first start. |
| replicaCount | int | `1` | Pod replicas. Every ready replica gets traffic, and a lease in Postgres picks the one that processes (interbox 2.4.0 and later support multiple replicas). Add replicas for availability, not throughput. |
| resources | object | `{"requests":{"ephemeral-storage":"1Gi"}}` | Resources of each main pod. The main pods load published builds; `workspaceService.resources` covers the workspace build. `ephemeral-storage` covers the unpacked builds, the container filesystem and the logs: the request keeps the pod off a node with less free disk. Add `limits.ephemeral-storage` for a cap; Kubernetes evicts a pod that outgrows it, and rejects the pod when the limit is below the request, so lower `requests.ephemeral-storage` with it. Your keys merge with these; set one to `null` to drop it. |
| route.main.additionalRules | list | `[]` | Rules rendered ahead of the rule to the Service. Templated. |
| route.main.annotations | object | `{}` | Route annotations. Templated. |
| route.main.enabled | bool | `false` | Render a Gateway API HTTPRoute to the dashboard/API Service. Each key under `route` is one route; `main` takes the release's full name, others add `-<key>`. Needs the Gateway API CRDs and a Gateway. |
| route.main.filters | list | `[]` | Filters of the rule that sends traffic to the Service. |
| route.main.hostnames | list | `[]` | Hostnames the route matches. Templated. |
| route.main.httpsRedirect | bool | `false` | Replace the rule to the Service with a 301 redirect to HTTPS, for a route on an HTTP listener. |
| route.main.labels | object | `{}` | Extra route labels. |
| route.main.matches | list | `[{"path":{"type":"PathPrefix","value":"/"}}]` | Request matches of the rule that sends traffic to the Service. |
| route.main.parentRefs | list | `[]` | Gateways the route attaches to. Required when `enabled`. |
| route.main.timeouts | object | `{}` | Timeouts of the rule that sends traffic to the Service, e.g. `request: 10s`. |
| secrets | object | `{"AIDBOX_CLIENT_SECRET":"","ANTHROPIC_API_KEY":"","CLAUDE_CODE_OAUTH_TOKEN":"","DATABASE_URL":"","INTERBOX_AUTH_ADMIN_PASSWORD":"","INTERBOX_AUTH_CLIENT_SECRET":"","INTERBOX_DB_DATABRICKS_CLIENT_SECRET":"","INTERBOX_LICENSE":"","INTERBOX_WORKSPACE_GIT_KEY":"","existingSecretName":""}` | Secret env → Secret (envFrom). Keys are env var names; empty ones are skipped. `DATABASE_URL` is required. The dashboard also needs `INTERBOX_AUTH_ADMIN_PASSWORD` unless `INTERBOX_AUTH_ADMIN_ENABLED` is `false` (OIDC only; see PREREQUISITES.md). `secrets.data.<KEY>` is deprecated; a flat key wins. |
| secrets.existingSecretName | string | `""` | Pre-provisioned Secret to use instead of rendering one (External Secrets Operator, sealed-secrets, …). |
| securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"runAsGroup":1000,"runAsNonRoot":true,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}}` | Container securityContext. The image runs as non-root `bun` (uid 1000) and writes to HOME and `/tmp`. |
| service.annotations | object | `{}` | Dashboard/API Service annotations. |
| service.port | int | `3001` | Port of the dashboard/API Service. The pods listen on 3001 whatever it is. |
| service.type | string | `"ClusterIP"` | Dashboard/API Service type. |
| serviceAccount.annotations | object | `{}` | ServiceAccount annotations. |
| serviceAccount.create | bool | `false` | Create a ServiceAccount for the pod. |
| serviceAccount.name | string | `""` | ServiceAccount name (default: the fullname when `create` is true). |
| strategy | object | `{"rollingUpdate":{"maxSurge":1,"maxUnavailable":0},"type":"RollingUpdate"}` | Deployment strategy. The default starts a new pod and waits for it to be ready before it stops an old one. `type: Recreate` drops `rollingUpdate` and stops every old pod first. |
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
| webhook.enabled | bool | `false` | Expose the webhook port: a container port, `INTERBOX_WEBHOOK_PORT`, and the `interbox-webhook` Service, always ClusterIP whatever `service.type` is. One port serves every `webhookSource` and every `pullSender`; the engine routes each request to its pipeline by `path`. Turn it on when the workspace declares either: while it is off, the engine still listens on `webhook.port` for them, but no Service carries the port. |
| webhook.port | int | `3002` | Webhook port. The chart always sets `INTERBOX_WEBHOOK_PORT` on the container from it, whether `enabled` is on or off. Set the port here only: `config.INTERBOX_WEBHOOK_PORT` fails the render, a different value in an extra ConfigMap rejects startup, and one in a Secret is ignored. |
| workspaceService.persistence.enabled | bool | `true` | Keep the workspace service's workspace checkout on a ReadWriteOnce PersistentVolumeClaim, so uncommitted edits survive restarts. `false` uses an `emptyDir` that goes away with the pod. |
| workspaceService.persistence.size | string | `"5Gi"` | PVC size. |
| workspaceService.persistence.storageClass | string | `""` | PVC `storageClassName`. Empty = the cluster default. |
| workspaceService.resources | object | `{"requests":{"cpu":"100m","ephemeral-storage":"1Gi","memory":"768Mi"}}` | Resources of the workspace service pod, which runs `bun install` and the workspace build. Your keys merge with these; set one to `null` to drop it. |

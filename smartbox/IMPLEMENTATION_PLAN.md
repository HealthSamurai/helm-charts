# Smartbox / CMS-0057 Helm Charts — Implementation Plan

**Issue:** [#464 — HELM charts for CMS-0057 stack](https://github.com/HealthSamurai/smartbox/issues/464)

**Scope:** Helm charts for the core payor-portal + ePA stack — **5 components**:

| # | Component | What it is | Chart |
|---|-----------|------------|-------|
| 1 | `fhir-app-portal` | Smartbox portal (admin + developer, one image, two ports) | **new** `fhir-app-portal` |
| 2 | `interop` | ePA interop / patient-&-provider-access FHIR APIs | **new** `interop` |
| 3 | `prior-auth` | ePA prior-authorization service | **new** `prior-auth` |
| 4 | `aidbox-admin` | Production-data FHIR server | **existing** HS `aidbox` chart (as-is) |
| 5 | `aidbox-sandbox` | Developer/test-data FHIR server | **existing** HS `aidbox` chart (as-is) |

Plus an umbrella **`payerbox`** that deploys all 5 (+ CNPG + init-bundles) in one release.

Out of scope: the wider ePA-demo `cms-*` services, MPF cronjob, auditbox/mdm. (The new app charts are generic enough to cover those later.)

---

## Locked design decisions

1. **Aidbox chart stays as-is** — reuse the published HS `aidbox` chart unmodified, twice (admin + sandbox). No extension/forking.
2. **One chart per app** — `fhir-app-portal`, `interop`, `prior-auth` are three independent, standalone-installable charts (not one generic chart). Each owns its Deployment + Service + Ingress + ConfigMap + ExternalSecret.
3. **Umbrella `payerbox`** — deploys all 5 components at once, owns the glue (CNPG `Cluster`, Aidbox init-bundles, Aidbox ExternalSecrets). Each subchart remains individually deployable.
4. **DB = CNPG** — one CloudNativePG `Cluster`, two databases (`portal`, `sandbox`); both Aidboxes point `BOX_DB_HOST` at the CNPG `-rw` service. CNPG **operator** is a cluster prerequisite; the chart ships only the `Cluster` CR.
5. **Secrets = two modes**: `externalSecret` (default) and `existingSecret`. **No `create` mode.**
6. **Ingress = chart-owned, fully values-driven** — `className` + `annotations` + `hosts`/`tls` from values; zero cloud logic in templates (nginx vs ALB is purely a values difference).
7. **Version pinning** — `image.tag: "2605"` for aidbox + fhir-app-portal + interop + prior-auth (all four images move in lockstep, published on Docker Hub). Aidbox **chart** version pinned to **0.2.8** (latest on `aidbox.github.io/helm-charts`, which is what existing customers already use).
8. **Dedicated client secrets per app** — `interop-app` and `prior-auth-app` get their own client secrets (no reuse across apps). The umbrella keeps client IDs/secrets consistent between the Aidbox init-bundles and the app ExternalSecrets.

> **Note on "pin to 2605":** chart version and image tag are decoupled — the aidbox chart's `appVersion` is `"edge"` on every release and does not bake in an image. The Aidbox build is chosen by the `image.tag` value (`"2605"`); the chart `version` (`0.2.8`) is pinned separately.

---

## Implementation status (2026-06-08)

| Item | Status |
|------|--------|
| `fhir-app-portal`, `interop`, `prior-auth` charts | ✅ authored, `helm lint` + `helm template` clean; both secret modes verified |
| `payerbox` umbrella (Chart deps, CNPG, Aidbox ExternalSecrets, init-bundle ConfigMaps) | ✅ authored, `helm dependency build` + `helm template` clean (31 resources) |
| Aidbox admin/sandbox wiring (DB host, init-bundle mount, secret env) | ✅ rendered & verified |
| CNPG ⇄ Aidbox DB-credential sync | ✅ predefined basic-auth secret (`payerbox-db-credentials`) feeds CNPG + Aidbox `BOX_DB_USER/PASSWORD` from the same external keys |
| **Init-bundle content + client-secret injection** | ⏳ **STARTER bundles only — must be authored & validated against a real Aidbox** (see `payerbox/README.md` open item). This is Phase 4. |

**Chart facts learned during implementation (vs the original assumptions):**
- The aidbox 0.2.8 chart has **no `extraEnvs`** (renamed `secretKeyRef`) — only `config`, `extraEnvFromConfigMaps`, `extraEnvFromSecrets`. It auto-extracts secret-typed keys (`BOX_DB_*`, `BOX_ADMIN_PASSWORD`, `BOX_LICENSE`, …) out of `.config` into its own Secret; `extraEnvFromSecrets` are `envFrom`-appended *after* and therefore win. So all secret env is supplied via the umbrella `aidbox-*-env` ExternalSecret and kept out of `.config`.
- Because of that, CNPG can't use its auto-generated `<cluster>-app` secret (keys `username`/`password` ≠ `BOX_DB_*`). Instead CNPG uses a **predefined** basic-auth secret and Aidbox reads `BOX_DB_USER/PASSWORD` from the same external-store keys.

## Architecture revision (2026-06-09, post DevOps review)

DevOps review: a Helm chart should "do one thing well" — **CNPG and ExternalSecrets do not
belong in the chart** (CNPG especially needs heavy per-env extension: barman ObjectStore,
ScheduledBackup, sync replication, image catalogs, PodMonitor — see the villagecare example).
**Decision: removed both from the charts entirely; documented as prerequisites instead.**

- Deleted: `payerbox/templates/{cnpg-cluster,db-credentials,aidbox-externalsecrets}.yaml` and the
  app charts' `externalsecret.yaml`. Removed `cnpg`/`dbCredentials`/`aidboxSecrets`/`global.secretStore`
  from `payerbox/values.yaml`.
- App charts now only **reference** an existing Secret via `secrets.existingSecretName`
  (default `<release>-secrets`); no `secrets.mode`/ExternalSecret creation.
- Aidbox still consumes the infra-provided `aidbox-{admin,sandbox}-env` Secret via
  `extraEnvFromSecrets`, and `BOX_DB_HOST` points at an infra-provided CNPG `-rw` Service.
- New **`payerbox/PREREQUISITES.md`** (publishable) documents the required operators, the CNPG
  `Cluster` example (both DBs), and every Secret + keys + consistency rules. Charts render only
  app + Aidbox objects now.

## 1. Target topology

```
                          NGINX / ALB Ingress
                                  │
        ┌─────────────────────────┼──────────────────────────┐
        │ admin host              │ sandbox host              │ (portal serves both)
        ▼                         ▼                           ▼
 ┌──────────────┐         ┌──────────────┐          ┌────────────────────┐
 │ aidbox-admin │◄────────│ fhir-app-    │─────────►│   aidbox-sandbox   │
 │  (prod data) │  :8095  │   portal     │  :8096   │   (test data)      │
 └──────┬───────┘         └──────────────┘          └────────────────────┘
        ▲  ▲
        │  │  (in-cluster, ClusterIP — no ingress)
        │  └──────────────── prior-auth   (AIDBOX_URL → aidbox-admin)
        └─────────────────── interop      (AIDBOX_URL → aidbox-admin)
                                  │
                          CNPG Cluster (-rw svc)
                          DBs: portal, sandbox
```

**Wiring rules:**
- `fhir-app-portal` → **both** Aidboxes. Admin `:8095` ↔ `aidbox-admin`; developer `:8096` ↔ `aidbox-sandbox`.
- `interop` → **admin only** (`AIDBOX_URL = http://aidbox-admin-api`).
- `prior-auth` → **admin only** (`AIDBOX_URL = http://aidbox-admin-api`).
- App→Aidbox traffic is **in-cluster** via the chart-created service `<aidbox-fullname>-api:80`. Only the portal + two Aidboxes have Ingress; interop/prior-auth are ClusterIP-internal.

---

## 2. Repository layout (in `helm-charts/`)

```
helm-charts/
  fhir-app-portal/              # NEW standalone chart
    Chart.yaml  values.yaml
    templates/{deployment,service,ingress,configmap,externalsecret,
               registry-secret,serviceaccount,_helpers}.yaml
  interop/                      # NEW standalone chart (same template shape)
  prior-auth/                   # NEW standalone chart (same template shape)
  payerbox/                     # NEW umbrella
    Chart.yaml                  # deps: aidbox×2 (admin/sandbox) + the 3 app charts
    values.yaml                 # top-level wiring (hosts, client ids, secret store, CNPG)
    templates/
      cnpg-cluster.yaml         # CloudNativePG Cluster (DBs: portal, sandbox)
      aidbox-admin-initbundle.yaml      # ConfigMap (OAuth clients incl. interop/prior-auth)
      aidbox-sandbox-initbundle.yaml    # ConfigMap (clients + TokenIntrospector → admin)
      aidbox-admin-externalsecret.yaml  # ExternalSecret (BOX_LICENSE, BOX_DB_*, ...)
      aidbox-sandbox-externalsecret.yaml
  aidbox/                       # EXISTING chart — UNCHANGED (consumed as dependency)
  smartbox/                     # old Kustomize guide — DEPRECATE (see §7)
    IMPLEMENTATION_PLAN.md       # this file
  examples/
    epa-demo-values.yaml         # values to deploy onto smartbox-deployment
    customer-villagecare.yaml    # per-customer overlay example
```

Each app chart is `helm install`-able alone. The umbrella references the 3 app charts via `file://../<chart>` and the aidbox chart from the HS repo.

---

## 3. App chart — values schema (shared by the 3 app charts)

The three app charts share the same template/value shape; they differ only in defaults (image, ports, env keys, ingress on/off).

```yaml
image:
  repository: healthsamurai/fhir-app-portal   # or .../interop, .../prior-auth
  tag: "2605"
  digest: ""                 # optional; takes precedence over tag
  pullPolicy: Always

replicaCount: 1
ports:                       # portal=[8095,8096,8081]; interop=[8088]; prior-auth=[8092]
  - { name: portal,     containerPort: 8095 }
  - { name: dev-portal, containerPort: 8096 }
  - { name: backend,    containerPort: 8081 }
probe: { path: /health, port: 8095 }          # interop=8088, prior-auth=8092
resources:                   # CHART DEFAULTS — every raw app today sets none
  requests: { cpu: 10m, memory: 256Mi }
  limits:   { memory: 512Mi }
securityContext:
  allowPrivilegeEscalation: false
  capabilities: { drop: [ALL], add: [NET_BIND_SERVICE] }

# ----- env (non-secret) -> ConfigMap, mounted via envFrom -----
config: {}                   # per-component key list in §5

# ----- secrets -> envFrom; TWO modes, no plaintext-create -----
secrets:
  mode: externalSecret       # externalSecret | existingSecret
  # mode=externalSecret:
  storeRef: { kind: ClusterSecretStore, name: gcp-store }   # "secrets-manager" on AWS
  refreshInterval: 1h
  remoteKeyPrefix: ""        # e.g. "portal--prod--" (GCP) | "" (AWS)
  data:                      # secretKey ← remoteRef.key (prefix prepended)
    SESSION_SECRET: fhir-app---session-secret
    ADMIN_API_CLIENT_SECRET: fhir-app---admin-api-client-secret
    DEVELOPER_API_CLIENT_SECRET: fhir-app---developer-api-client-secret
  # mode=existingSecret:
  existingSecretName: ""     # chart creates nothing; envFrom this Secret

service:
  type: ClusterIP            # NodePort for portal in some clouds
  sessionAffinity: ClientIP  # portal only
  ports: [8095, 8096]        # interop/prior-auth expose their single port

ingress:                     # portal: enabled; interop/prior-auth: enabled=false
  enabled: false
  className: nginx           # "alb" on AWS
  annotations: {}            # nginx (cert-manager/body-size/CORS) OR ALB (group/scheme/subnets/cert-arn)
  hosts:
    - { host: portal.example.com,         servicePort: 8095, tlsSecret: portal-tls }
    - { host: portal-sandbox.example.com, servicePort: 8096, tlsSecret: portal-sandbox-tls }

imagePullSecret:             # for private registries (off for healthsamurai/* public)
  enabled: false
  name: artifact-registry-creds

vpa: { enabled: false }
hpa: { enabled: false }
serviceAccount: { create: false, name: "" }
```

**Secrets template logic** (the locked two-mode design):
```
{{- if eq .Values.secrets.mode "externalSecret" }}   # render ExternalSecret, envFrom its output
{{- else if eq .Values.secrets.mode "existingSecret" }} # render nothing; envFrom existingSecretName
{{- else }} {{ fail "secrets.mode must be externalSecret or existingSecret" }}
{{- end }}
```
The Deployment's `envFrom` secret name is the same in both modes (the generated name == release name, or `existingSecretName`), so the container is mode-agnostic.

---

## 4. Aidbox (admin + sandbox) — existing chart, two releases

Used unchanged as an umbrella dependency, aliased twice. Per-instance values:

```yaml
# admin  -> fullnameOverride: aidbox-admin  -> service aidbox-admin-api
aidboxAdmin:
  fullnameOverride: aidbox-admin
  image: { tag: "2605" }
  host: aidbox.example.com
  protocol: https
  config:
    BOX_ID: aidbox-admin
    BOX_INSTANCE_NAME: aidbox-admin
    BOX_DB_DATABASE: portal
    BOX_DB_HOST: <cnpg-rw-service>
    BOX_INIT_BUNDLE: file:///init-bundle/init-bundle.json
    # + FHIR-compliance / search / validation block from existing repos
  extraEnvFromSecrets: [aidbox-admin-env]   # ExternalSecret rendered by the umbrella
  ingress: { enabled: true, className: nginx }
  serviceMonitor: { enabled: true }
  volumes/volumeMounts: init-bundle ConfigMap (rendered by umbrella) at /init-bundle

# sandbox -> fullnameOverride: aidbox-sandbox -> service aidbox-sandbox-api
aidboxSandbox:
  fullnameOverride: aidbox-sandbox
  config:
    BOX_ID: aidbox-sandbox
    BOX_INSTANCE_NAME: aidbox-sandbox
    BOX_DB_DATABASE: sandbox
    # init-bundle adds TokenIntrospector trusting the admin Aidbox JWT (cross-instance auth)
  host: aidbox-sandbox.example.com
```

Chart `version: 0.2.8`, repo `https://aidbox.github.io/helm-charts`. The aidbox chart already supports external DB (`config.BOX_DB_HOST`), mounted init-bundles (`volumes`/`volumeMounts`), and secret env (`extraEnvFromSecrets`) — so **no chart change is needed** to run on CNPG with umbrella-provided bundles/secrets.

---

## 5. Per-component values (concrete wiring)

### fhir-app-portal (ingress enabled, two ports, → both Aidboxes)
```yaml
config:
  NODE_ENV: production
  PORTAL_BACKEND_PORT: "8081"
  DEPLOYMENT_MODE: prod
  CORS_ORIGINS: https://portal.example.com,https://portal-sandbox.example.com
  ADMIN_FRONTEND_URL: https://portal.example.com
  DEVELOPER_FRONTEND_URL: https://portal-sandbox.example.com
  AIDBOX_ADMIN_URL: http://aidbox-admin-api            # in-cluster
  AIDBOX_DEV_URL: http://aidbox-sandbox-api            # in-cluster
  AIDBOX_ADMIN_PUBLIC_URL: https://aidbox.example.com
  ADMIN_AIDBOX_PUBLIC_URL: https://aidbox.example.com
  AIDBOX_DEV_PUBLIC_URL: https://aidbox-sandbox.example.com
  DEVELOPER_AIDBOX_PUBLIC_URL: https://aidbox-sandbox.example.com
  AIDBOX_ADMIN_CLIENT_ID: smartbox-admin-portal
  AIDBOX_DEV_CLIENT_ID: smartbox-developer-portal
  ADMIN_API_CLIENT_ID: admin-api
  DEVELOPER_API_CLIENT_ID: developer-api
  APP_NAME: "FHIR Access Portal"
secrets.data: { SESSION_SECRET, ADMIN_API_CLIENT_SECRET, DEVELOPER_API_CLIENT_SECRET }
```

### interop (ingress disabled, ClusterIP :8088, → admin only)
```yaml
config:
  AIDBOX_URL: http://aidbox-admin-api
  AIDBOX_PUBLIC_URL: https://aidbox.example.com
  AIDBOX_CLIENT_ID: interop-app
  AIDBOX_APP_ID: interop-app
  AIDBOX_APP_PORT: "8088"
  INTEROP_APP_URL: http://interop:8088/
secrets.data: { AIDBOX_CLIENT_SECRET, AIDBOX_APP_SECRET }   # dedicated, not shared
```

### prior-auth (ingress disabled, ClusterIP :8092, → admin only)
```yaml
config:
  AIDBOX_URL: http://aidbox-admin-api
  AIDBOX_CLIENT_ID: prior-auth-app
  AIDBOX_APP_PORT: "8092"
  PRIOR_AUTH_APP_URL: http://prior-auth:8092/
secrets.data: { AIDBOX_CLIENT_SECRET, AIDBOX_APP_SECRET }   # dedicated, not shared
```

> `interop-app` / `prior-auth-app` get **their own** client secrets. The umbrella's admin init-bundle registers these clients with matching secrets (today some repos reuse the portal's `admin-api` secret — explicitly fixed here).

---

## 6. Cross-cutting: secrets & ingress abstraction (cloud-agnostic)

| Concern | GCP (villagecare, ePA demo) | AWS (paramount, ihcs) | Chart knob |
|---|---|---|---|
| Secret store | `gcp-store` / GCP Secret Manager | `secrets-manager` / AWS SM | `secrets.storeRef.name` |
| Key naming | `<app>--<env>--<purpose>` | bare / `app--KEY` | `secrets.remoteKeyPrefix` + `data` |
| Ingress | nginx + cert-manager `letsencrypt` | ALB + ACM cert ARN + subnets | `ingress.className` + `ingress.annotations` |
| DB | CNPG `Cluster` (this plan) | CNPG `Cluster` (this plan) | umbrella `cnpg.*` |

Templates stay cloud-agnostic: annotation/store values pass through verbatim. Cloud specifics live in per-customer `values.yaml`.

**Cluster prerequisites (NOT chartified, documented as prereqs):** External Secrets Operator + a `ClusterSecretStore`; CloudNativePG operator; an ingress controller (nginx/ALB); cert-manager.

---

## 7. Implementation phases

**Phase 0 — Confirm with Marat** (AC: "confirmed with Marat") — walk through this plan.

**Phase 1 — Author the 3 app charts** (`fhir-app-portal`, `interop`, `prior-auth`)
- Templates per §3; defaults + example values per §5.
- Two-mode secrets (externalSecret/existingSecret).
- `helm lint` + `helm template`; render-parity diff vs current raw manifests to prove no drift.

**Phase 2 — Aidbox values** (no chart change)
- Admin + sandbox example values per §4; pin chart `0.2.8` + image `2605`.

**Phase 3 — Umbrella `payerbox`**
- `Chart.yaml` deps (aidbox×2 + 3 app charts).
- Templates: CNPG `Cluster` (DBs portal+sandbox), 2 init-bundle ConfigMaps, 2 Aidbox ExternalSecrets — all with consistent client IDs/secrets.
- `helm install` on a scratch cluster brings up all 5 from one release.

**Phase 4 — Test on the ePA demo** (AC: "deploy portals to Payor Aidbox on ePA demo")
- In `smartbox-deployment`, replace raw `fhir-app-portal-payer` + `cms-interop` (+ prior-auth) with the new charts, wired to the payor Aidbox as admin.
- Verify: portal serves both portals, OAuth works, interop & prior-auth reach the admin Aidbox, all `/health` green.

**Phase 5 — Customer rollout & deprecation** (AC: "existing deployment deprecated")
- Migrate villagecare → willowglade → paramount → ihcs to thin per-env `values.yaml`.
- Fix audit-surfaced bugs en route (willowglade commented-out ExternalSecret; qa-sandbox ES→dev-logs; prod-sandbox DB name; paramount mixed asset hosts; reused client secrets).
- Delete raw manifests + the `helm-charts/smartbox/` Kustomize guide.

---

## 8. Validation strategy

- `helm lint` + `helm template` in CI (helm-charts repo already has `.github/workflows/package.yaml`).
- Render-parity: diff `helm template` output vs existing raw manifests per component.
- Smoke deploy to `kind`, then the real ePA demo (Phase 4).
- Confirm in-cluster DNS: `interop`/`prior-auth` → `aidbox-admin-api`; portal → both `*-api`; Aidboxes → CNPG `-rw`.
- Validate both secret modes: `externalSecret` against a real `ClusterSecretStore`, `existingSecret` against a hand-created Secret.

---

## 9. Resolved questions (was "open")

| Q | Decision |
|---|----------|
| Umbrella vs standalone | **Both** — 3 standalone app charts + a `payerbox` umbrella deploying all 5. |
| Init-bundle ownership | **Templated in the umbrella** (single from-scratch deploy; consistent client IDs/secrets). |
| Dedicated client secrets | **Yes** — `interop-app`/`prior-auth-app` get their own (no reuse). |
| Pin aidbox | **image `2605` + chart `0.2.8`** (decoupled). |
| Database | **CNPG** — one `Cluster`, DBs `portal` + `sandbox`; operator is a prereq. |
| Chart owns ExternalSecret + ingress? | **Yes, values-driven** — secrets via two modes (`externalSecret` default / `existingSecret`); ingress fully parameterized, no cloud logic in templates. |
```

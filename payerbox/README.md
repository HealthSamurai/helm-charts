# payerbox

Umbrella Helm chart for the Smartbox payor + ePA stack. One `helm install` brings up
**five components** in a single namespace:

| Component | Chart | Notes |
|-----------|-------|-------|
| `fhir-app-portal` | local `fhir-app-portal` | admin (`:8095`) + developer (`:8096`) portal; the only app with Ingress besides Aidbox |
| `interop` | local `interop` | ePA interop API → admin Aidbox (ClusterIP-internal) |
| `prior-auth` | local `prior-auth` | ePA prior-auth → admin Aidbox (ClusterIP-internal) |
| `aidbox-admin` | HS `aidbox` 0.2.8 | production-data FHIR server (DB `portal`) |
| `aidbox-sandbox` | HS `aidbox` 0.2.8 | developer/test FHIR server (DB `sandbox`) |

Plus a **CloudNativePG `Cluster`** (`payerbox-db`) hosting both databases.

All images (Aidbox + the three apps) are pinned to tag **`2605`**; the Aidbox **chart** is pinned to **0.2.8**.

## Topology

```
                         Ingress (nginx)
   portal.* :8095 ─┐                ┌─ aidbox.*  → aidbox-admin
 sandbox.* :8096 ─ fhir-app-portal ─┤
                                    └─ aidbox-sandbox.* → aidbox-sandbox
 interop ──────► aidbox-admin-api  (in-cluster)
 prior-auth ───► aidbox-admin-api  (in-cluster)
 aidbox-admin / aidbox-sandbox ──► payerbox-db-rw (CNPG)
```

Cross-app wiring relies on **stable service names** (`aidbox-admin-api`, `aidbox-sandbox-api`,
`interop`, `prior-auth`) — all components must run in the same namespace.

## Cluster prerequisites (NOT installed by this chart)

- **CloudNativePG operator** (provides the `Cluster` CRD)
- **External Secrets Operator** + a `ClusterSecretStore` (default name `gcp-store`)
- **ingress-nginx** controller + **cert-manager** (ClusterIssuer `letsencrypt`)

## Secret-store keys to populate

With the default `remoteKeyPrefix: ""`, create these in your secret manager:

| Key | Used by |
|-----|---------|
| `payerbox-db--username` / `payerbox-db--password` | CNPG owner role **and** Aidbox `BOX_DB_USER`/`BOX_DB_PASSWORD` (username value must be `aidbox`) |
| `aidbox-admin--box-license`, `aidbox-admin--box-admin-password`, `aidbox-admin--box-root-client-secret` | admin Aidbox |
| `aidbox-sandbox--box-license`, `aidbox-sandbox--box-admin-password`, `aidbox-sandbox--box-root-client-secret` | sandbox Aidbox |
| `fhir-app-portal--session-secret`, `fhir-app-portal--admin-api-client-secret`, `fhir-app-portal--developer-api-client-secret` | portal **and** Aidbox client registration |
| `interop--aidbox-client-secret`, `interop--aidbox-app-secret` | interop **and** admin init-bundle |
| `prior-auth--aidbox-client-secret`, `prior-auth--aidbox-app-secret` | prior-auth **and** admin init-bundle |

The same client-secret keys are read by both the apps and the Aidbox init-bundles, so the
values stay consistent.

## Install

```bash
helm dependency build ./payerbox
helm install payerbox ./payerbox -n payerbox --create-namespace \
  -f my-values.yaml          # override hosts, secret store, prefixes
```

Each app chart is independently installable too (`helm install interop ./interop ...`).

## ⚠️ Open item — init-bundle content must be validated against Aidbox

`files/aidbox-admin-init-bundle.json` and `files/aidbox-sandbox-init-bundle.json` are
**STARTER bundles**. Before production use they must be completed and verified against a
real Aidbox (per the repo rule "verify against a real local Aidbox, don't guess"):

1. **Client-secret injection.** The bundles reference `${INTEROP_APP_CLIENT_SECRET}` etc.
   Aidbox does **not** substitute `${ENV}` in a mounted init-bundle by default. Decide and
   wire the mechanism — either an `initContainers` envsubst step (set via the aidbox
   subchart's `initContainers` value, mirroring the cms-aidbox-payor pattern) or another
   approach — and confirm clients authenticate.
2. **AccessPolicies** for `admin-api` / `developer-api` / `interop-app` / `prior-auth-app`
   are not yet included — port them from the existing customer init-bundles.
3. **Sandbox `TokenIntrospector`** `iss`/`jwks_uri` must point at the real admin Aidbox host.

This is the next task (Phase 4 / ePA-demo test) in `../smartbox/IMPLEMENTATION_PLAN.md`.

# payerbox

Umbrella Helm chart for the **Smartbox payor + ePA stack**. One release deploys the whole stack
into a single namespace:

- **FHIR App Portal** — admin + developer portals (`fhir-app-portal`)
- **Interop APIs** — Patient / Provider / Payer-to-Payer / Provider Directory (`interop`)
- **Prior Auth** — CRD / DTR / PAS (`prior-auth`)
- **Two Aidbox FHIR servers** — `aidbox-admin` (production data) and `aidbox-sandbox` (developer/test data)

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 2605](https://img.shields.io/badge/AppVersion-2605-informational?style=flat-square)

The chart bundles the [`aidbox`](https://healthsamurai.github.io/helm-charts) chart (used twice,
unchanged) plus the three Smartbox app charts. Installing the published chart is self-contained —
all subcharts are vendored into the package.

## What the chart does and does NOT create

It deploys **only the applications and the two Aidbox instances**. By design it does **not**
provision PostgreSQL or any Secret — those are infrastructure concerns that vary per
cloud/customer. Provision them first; see **[PREREQUISITES.md](./PREREQUISITES.md)**.

| You provide (before install) | Why |
|---|---|
| **PostgreSQL** with two databases `portal` + `sandbox` | the two Aidbox instances (a CloudNativePG `Cluster` is the reference; any reachable Postgres works) |
| **Secrets** — `payerbox-db-credentials`, `aidbox-admin-env`, `aidbox-sandbox-env`, `fhir-app-portal-secrets`, `interop-secrets`, `prior-auth-secrets` | DB creds, Aidbox licenses, and OAuth client secrets — see [PREREQUISITES §3](./PREREQUISITES.md) for the exact keys |
| **Ingress controller and/or Gateway API**, plus **cert-manager** + a `ClusterIssuer` | external access + TLS for the portals and Aidbox |
| **Two Aidbox licenses** | Aidbox will not boot without `BOX_LICENSE` |

## Installation

```console
helm repo add healthsamurai https://healthsamurai.github.io/helm-charts

helm upgrade --install payerbox healthsamurai/payerbox \
  --namespace payerbox --create-namespace \
  --values /path/to/values.yaml
```

A minimal `values.yaml` overriding the per-environment hosts and URLs:

```yaml
# --- Aidbox: public hosts (drive BOX_WEB_BASE_URL and the OAuth token issuer) ---
aidbox-admin:
  host: aidbox.example.com
  config:
    ADMIN_FRONTEND_URL: https://portal.example.com          # substituted into the admin init-bundle
aidbox-sandbox:
  host: aidbox-sandbox.example.com
  config:
    DEVELOPER_FRONTEND_URL: https://portal-sandbox.example.com   # substituted into the sandbox init-bundle
    ADMIN_AIDBOX_PUBLIC_URL: https://aidbox.example.com          # admin token issuer (introspector iss)
    # AIDBOX_ADMIN_URL defaults to http://aidbox-admin-api (in-cluster JWKS) — usually no override

# --- Portal: hostnames + the URLs it advertises to the browser ---
fhir-app-portal:
  portalHost: portal.example.com
  sandboxHost: portal-sandbox.example.com
  config:
    CORS_ORIGINS: "https://portal.example.com,https://portal-sandbox.example.com"
    ADMIN_FRONTEND_URL: "https://portal.example.com"
    DEVELOPER_FRONTEND_URL: "https://portal-sandbox.example.com"
    AIDBOX_ADMIN_PUBLIC_URL: "https://aidbox.example.com"
    ADMIN_AIDBOX_PUBLIC_URL: "https://aidbox.example.com"
    AIDBOX_DEV_PUBLIC_URL: "https://aidbox-sandbox.example.com"
    DEVELOPER_AIDBOX_PUBLIC_URL: "https://aidbox-sandbox.example.com"
```

> A complete, end-to-end walkthrough (PostgreSQL, Secrets, DNS/TLS, verification) is in the
> Payerbox documentation under **Run Payerbox → Deploy**.

## Routing & TLS

Each component chooses **nginx Ingress** or **Gateway API** independently:

- **FHIR App Portal** defaults to **Gateway API** (`route.portal` / `route.dev-portal` → `HTTPRoute`s).
  To use a classic `Ingress` instead, disable the routes and enable ingress:
  ```yaml
  fhir-app-portal:
    route: { portal: { enabled: false }, dev-portal: { enabled: false } }
    ingress: { enabled: true, className: nginx }
    tlsSecretName: fhir-portal-tls
  ```
- **Aidbox admin/sandbox** use **Ingress only** (the `aidbox` chart has no Gateway support);
  enabled by default with `cert-manager.io/cluster-issuer: letsencrypt`.
- **interop / prior-auth** are **ClusterIP-internal** by default (no external route needed).

## Aidbox init bundles & environment substitution

Each Aidbox instance loads a starter **init bundle** (`files/aidbox-*-init-bundle.json`) that
registers the OAuth clients, the cross-instance `TokenIntrospector`, search parameters, and
access policies. Aidbox loads init bundles **as-is** (no native env substitution), so the chart
ships them as `${VAR}` templates and renders them with a small **`sed` initContainer** (`busybox`)
on each Aidbox pod:

- **Non-secret values** (hostnames, the in-cluster admin URL) come from `aidbox-*.config`
  (i.e. your `values.yaml`).
- **Secret values** (client secrets) come from the `aidbox-*-env` Secret via `secretKeyRef` —
  they are never written into a ConfigMap.
- `sed` replaces only the exact `${VAR}` placeholders, so Aidbox matcho operators (`$one-of`,
  `$sql`, …) inside the bundle are left untouched.

Because rendering happens at every pod start, config changes take effect on the next rollout and
**survive `helm upgrade`** — no manual patching.

## Values

| Key | Description | Default |
|---|---|---|
| `aidbox-admin.host` / `aidbox-sandbox.host` | Public hostname of each Aidbox (drives `BOX_WEB_BASE_URL` and the OAuth token `iss`) | `aidbox.example.com` / `aidbox-sandbox.example.com` |
| `aidbox-*.config.BOX_DB_HOST` | PostgreSQL host | `payerbox-db-rw` (CNPG `-rw` Service of `Cluster/payerbox-db`) |
| `aidbox-*.config.BOX_DB_DATABASE` | Database name | `portal` / `sandbox` |
| `aidbox-*.extraEnvFromSecrets` | Secret(s) with `BOX_LICENSE`, DB creds, client secrets | `[aidbox-admin-env]` / `[aidbox-sandbox-env]` |
| `aidbox-admin.config.ADMIN_FRONTEND_URL` | Admin portal URL, substituted into the admin init-bundle | `https://portal.example.com` |
| `aidbox-sandbox.config.DEVELOPER_FRONTEND_URL` | Developer portal URL, substituted into the sandbox init-bundle | `https://portal-sandbox.example.com` |
| `aidbox-sandbox.config.ADMIN_AIDBOX_PUBLIC_URL` | Admin Aidbox token issuer (introspector `iss`) | `https://aidbox.example.com` |
| `aidbox-sandbox.config.AIDBOX_ADMIN_URL` | In-cluster admin Aidbox (JWKS fetch) | `http://aidbox-admin-api` |
| `fhir-app-portal.portalHost` / `.sandboxHost` | Admin / developer portal hostnames | `portal.example.com` / `portal-sandbox.example.com` |
| `fhir-app-portal.config.*` | Portal runtime URLs (CORS, frontend, Aidbox public) | `*.example.com` placeholders |
| `<component>.enabled` | Toggle each subchart | `true` |
| `<component>.resources` | CPU/memory requests & limits | see `values.yaml` |

See [`values.yaml`](./values.yaml) for the full set, and each app chart's `PREREQUISITES.md`
(`fhir-app-portal`, `interop`, `prior-auth`) for its Secret keys and routing options.

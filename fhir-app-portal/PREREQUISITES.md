# fhir-app-portal — cluster prerequisites

Provision these in your infra layer **before** `helm install`. The chart does not create them.

## 1. External routing

The portal is exposed one of two ways, selected in `values.yaml`. **Gateway API is the default.**

### Gateway API — the default (`route.*`)

`route.portal` and `route.dev-portal` are enabled by default and render `HTTPRoute`s. They require, in the cluster:

| Prerequisite | Notes |
|---|---|
| **Gateway API CRDs** | `kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml` — pin a version you've validated |
| **A Gateway controller** | e.g. NGINX Gateway Fabric, Istio, or Envoy Gateway — something that reconciles `Gateway`/`HTTPRoute` |
| **A parent `Gateway`** | The chart attaches `HTTPRoute`s to it via `route.<name>.parentRefs`; **the chart does NOT create it.** Set `parentRefs[].name` (default placeholder `main-gateway`) and `hostnames` per environment. |

> TLS termination and controller policies (CORS, rate limiting, timeouts, redirects) live on the **parent Gateway and its listeners**, not on the `HTTPRoute`. A bare cluster with none of the above will fail to route — the `HTTPRoute` objects apply but stay unattached.

Per-route knobs (see `values.yaml`): `parentRefs`, `hostnames`, `matches`, `filters`, `timeouts`, `sessionPersistence`, `httpsRedirect`, and `backendPortName` — which selects the Service port (`portal` → 8095, `dev-portal` → 8096). Add more routes by adding a key under `route:`.

### nginx Ingress — the alternative

To use a classic `Ingress` instead, disable the routes and enable ingress:

```yaml
route:
  portal: { enabled: false }
  dev-portal: { enabled: false }
ingress:
  enabled: true
  className: nginx        # requires an ingress controller (e.g. ingress-nginx)
  # annotations / tls / hosts as in values.yaml
```

Requires an ingress controller, and — for the default `cert-manager.io/cluster-issuer` annotation — cert-manager with the referenced ClusterIssuer.

## 2. Secret

The chart consumes an **existing** Secret via `envFrom` (it does not create it). Default name `<release>-secrets`; override with `secrets.existingSecretName`.

Required keys: `SESSION_SECRET`, `ADMIN_API_CLIENT_SECRET`, `DEVELOPER_API_CLIENT_SECRET`.

Provision it with External Secrets Operator, sealed-secrets, or your secret tooling.

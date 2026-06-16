# interop — cluster prerequisites

Provision these in your infra layer **before** `helm install`. The chart does not create them.

## 1. External routing (optional)

interop is **ClusterIP-internal by default** — it talks to the admin Aidbox in-cluster and needs no ingress or route. Both `route.main` and `ingress` are disabled out of the box.

Expose it externally only if you have a specific need:

### Gateway API (`route.main`)

Set `route.main.enabled: true` and provide `parentRefs` + `hostnames`. This requires, in the cluster:

| Prerequisite | Notes |
|---|---|
| **Gateway API CRDs** | `kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml` — pin a version you've validated |
| **A Gateway controller** | e.g. NGINX Gateway Fabric, Istio, or Envoy Gateway |
| **A parent `Gateway`** | Referenced via `route.main.parentRefs`; **the chart does NOT create it.** |

`backendPortName` defaults to `http` (→ Service port 8088). TLS and controller policies live on the parent Gateway, not the `HTTPRoute`.

### nginx Ingress

Alternatively set `ingress.enabled: true` (requires an ingress controller).

## 2. Secret

The chart consumes an **existing** Secret via `envFrom` (it does not create it). Default name `<release>-secrets`; override with `secrets.existingSecretName`.

Required keys: `AIDBOX_CLIENT_SECRET`, `AIDBOX_APP_SECRET` (dedicated, not shared with the portal).

Provision it with External Secrets Operator, sealed-secrets, or your secret tooling.

# payerbox — manual test (local kind)

A reproducible, fully isolated smoke test of the `payerbox` umbrella on a local
[`kind`](https://kind.sigs.k8s.io/) cluster. Because the charts deploy **only apps + Aidbox**
(see [PREREQUISITES.md](./PREREQUISITES.md)), this guide also stands up a **minimal dev CNPG**
and creates the Secrets by hand — the parts your real infra layer owns.

> Scope: validates install mechanics, CNPG wiring, and Aidbox boot. Full OAuth (apps
> authenticating to Aidbox) needs the Phase-4 init-bundle work — see the note at the end.

## 0. Requirements

- Docker (Desktop) running. **Give it ≥ 8 GB RAM** — two Aidboxes + Postgres are heavy; the
  default ~4 GB is too small (Aidbox/CNPG won't schedule). Docker Desktop → Settings → Resources.
- `kind`, `kubectl`, `helm` (v3.14+). Install kind: `brew install kind`.
- A **dev Aidbox license** (JWT) from the Aidbox portal — Aidbox won't boot without it.

## 1. Create the cluster + CNPG operator

```bash
kind create cluster --name umbrella-test
kubectl config use-context kind-umbrella-test     # safety: make sure you're NOT on a real cluster

# CloudNativePG operator (provides the Cluster CRD)
kubectl apply --server-side -f \
  https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/v1.29.1/releases/cnpg-1.29.1.yaml
kubectl -n cnpg-system wait --for=condition=Available deploy/cnpg-controller-manager --timeout=120s

kubectl create namespace umbrella-test
```

## 2. Secrets (what your infra layer normally provisions)

DB password is shared between CNPG and Aidbox; the license is a placeholder you replace in step 5.

```bash
NS=umbrella-test
DBPASS=$(openssl rand -hex 16)
mkenv(){ kubectl -n $NS create secret generic "$1" "${@:2}" --dry-run=client -o yaml | kubectl apply -f -; }

# basic-auth secret used by the CNPG Cluster (username must equal the role/owner "aidbox")
kubectl -n $NS create secret generic payerbox-db-credentials \
  --type=kubernetes.io/basic-auth --from-literal=username=aidbox --from-literal=password="$DBPASS" \
  --dry-run=client -o yaml | kubectl apply -f -

# Aidbox env secrets (placeholder license -> replaced in step 5)
mkenv aidbox-admin-env \
  --from-literal=BOX_DB_USER=aidbox --from-literal=BOX_DB_PASSWORD="$DBPASS" \
  --from-literal=BOX_LICENSE=REPLACE_ME --from-literal=BOX_ADMIN_PASSWORD="$(openssl rand -hex 12)" \
  --from-literal=BOX_ROOT_CLIENT_SECRET="$(openssl rand -hex 16)" \
  --from-literal=ADMIN_API_CLIENT_SECRET=admin-api-secret \
  --from-literal=INTEROP_APP_CLIENT_SECRET=interop-secret \
  --from-literal=PRIOR_AUTH_APP_CLIENT_SECRET=prior-auth-secret

mkenv aidbox-sandbox-env \
  --from-literal=BOX_DB_USER=aidbox --from-literal=BOX_DB_PASSWORD="$DBPASS" \
  --from-literal=BOX_LICENSE=REPLACE_ME --from-literal=BOX_ADMIN_PASSWORD="$(openssl rand -hex 12)" \
  --from-literal=BOX_ROOT_CLIENT_SECRET="$(openssl rand -hex 16)" \
  --from-literal=DEVELOPER_API_CLIENT_SECRET=developer-api-secret

# App secrets (default names = <chart>-secrets). Client secrets MUST match the aidbox-admin-env values above.
mkenv fhir-app-portal-secrets \
  --from-literal=SESSION_SECRET="$(openssl rand -hex 32)" \
  --from-literal=ADMIN_API_CLIENT_SECRET=admin-api-secret \
  --from-literal=DEVELOPER_API_CLIENT_SECRET=developer-api-secret
mkenv interop-secrets     --from-literal=AIDBOX_CLIENT_SECRET=interop-secret    --from-literal=AIDBOX_APP_SECRET="$(openssl rand -hex 16)"
mkenv prior-auth-secrets  --from-literal=AIDBOX_CLIENT_SECRET=prior-auth-secret --from-literal=AIDBOX_APP_SECRET="$(openssl rand -hex 16)"
```

## 3. Minimal dev CNPG cluster (prod uses the full spec in PREREQUISITES.md)

```bash
kubectl -n umbrella-test apply -f - <<'YAML'
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: payerbox-db            # -> Service payerbox-db-rw == BOX_DB_HOST default
spec:
  instances: 1
  bootstrap:
    initdb:
      database: portal
      owner: aidbox
      secret: { name: payerbox-db-credentials }
      postInitSQL:
        - CREATE DATABASE sandbox OWNER aidbox;
  storage: { size: 2Gi }
  resources: { requests: { cpu: 100m, memory: 256Mi } }
YAML

kubectl -n umbrella-test wait --for=condition=Ready cluster/payerbox-db --timeout=240s
# verify both databases exist:
kubectl -n umbrella-test exec payerbox-db-1 -c postgres -- \
  psql -U postgres -tAc "SELECT datname FROM pg_database WHERE datname IN ('portal','sandbox');"
```

## 4. Vendor chart deps + install

The app charts aren't published to the Helm repo yet, so vendor them locally into `payerbox/charts/`
(run from the `helm-charts/` repo root):

```bash
helm package fhir-app-portal interop prior-auth -d payerbox/charts/
helm pull aidbox --repo https://aidbox.github.io/helm-charts --version 0.2.8 -d payerbox/charts/

helm install payerbox ./payerbox -n umbrella-test -f payerbox/ci/kind-test-values.yaml
```

A ready-made values file for kind (no ingress, shrunk resources) is at
[`ci/kind-test-values.yaml`](./ci/kind-test-values.yaml).

## 5. Add the real license + verify

```bash
LIC='<your-dev-aidbox-license-jwt>'
kubectl -n umbrella-test patch secret aidbox-admin-env   --type=merge -p "{\"stringData\":{\"BOX_LICENSE\":\"$LIC\"}}"
kubectl -n umbrella-test patch secret aidbox-sandbox-env --type=merge -p "{\"stringData\":{\"BOX_LICENSE\":\"$LIC\"}}"
kubectl -n umbrella-test rollout restart deploy/aidbox-admin deploy/aidbox-sandbox

watch kubectl -n umbrella-test get pods      # expect all 1/1 Running
```

Quick checks once green:

```bash
# Aidbox connected to DB + booted:
kubectl -n umbrella-test logs deploy/aidbox-admin --tail=5
# OAuth clients registered by the init-bundle:
kubectl -n umbrella-test exec deploy/aidbox-admin -- sh -c \
  'wget -qO- --header="Authorization: Basic $(printf "root:%s" "$BOX_ROOT_CLIENT_SECRET" | base64)" \
   "http://localhost:8080/Client?_elements=id" 2>/dev/null'
# Portal in a browser:
kubectl -n umbrella-test port-forward deploy/fhir-app-portal 8095:8095   # http://localhost:8095
```

Expected: `payerbox-db-1`, `aidbox-admin`, `aidbox-sandbox`, `fhir-app-portal`, `interop`,
`prior-auth` all `1/1 Running`; both databases present; the four app clients registered.

## 6. Teardown

```bash
kind delete cluster --name umbrella-test     # frees all Docker RAM/disk it held
```

---

## Known limitation (Phase 4)

The init-bundles (`files/aidbox-*-init-bundle.json`) register the OAuth clients with `${ENV}`
placeholder secrets that Aidbox stores **literally** (it does not substitute env in a mounted
bundle). So the clients exist but their secrets won't match the app Secrets — apps can't fully
authenticate yet. Fixing this (an `envsubst` initContainer + finalized bundles, validated on a
live Aidbox) is the remaining task in [README.md](./README.md) / the implementation plan.

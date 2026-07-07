# interbox chart — prerequisites

interbox is the all-in-one Integration Engine (engine + API + dashboard). This
chart deploys **only interbox**; Postgres and Aidbox are external dependencies you
point it at.

## 1. Postgres

interbox needs a Postgres database (its `interbox` database, with `pg_trgm` +
`btree_gist`). Options:

- **Managed** (recommended for prod) — Azure Database for PostgreSQL Flexible
  Server, Cloud SQL, RDS, etc.
- **In-cluster** — install the sibling [`postgres`](../postgres) chart.

The engine **self-creates** the `interbox` database on boot when the `DATABASE_URL`
user has `CREATEDB` (extensions come from the migrations) — like Aidbox. So a single
DSN with a CREATEDB user is all you need (`database.createDatabase=true`, default).

If your managed PG won't grant `CREATEDB`, set `database.createDatabase=false` (which
sets `INTERBOX_SKIP_ENSURE_DB` so the engine skips the bootstrap) and pre-create it:

```sql
CREATE DATABASE interbox;
\c interbox
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS btree_gist;
-- plus a role scoped to the interbox database for the app DSN
```

interbox can share a cluster with Aidbox — just a dedicated `interbox` database on
it (not Aidbox's own database).

## TLS to Postgres

Put `sslmode` in the DSN. Default **`require`** (encrypts in transit — managed PG
usually mandates it); use **`verify-full`** (+ the provider CA) to also block MITM.
Drop it only when the path is already encrypted/trusted (VPN, or same private VNet):

    postgres://interbox:pass@host:5432/interbox?sslmode=require

## 2. Aidbox

- **Already have one** — set `config.AIDBOX_URL` to it and `secrets.data.AIDBOX_CLIENT_SECRET`.
- **Need one** — install the sibling [`aidbox`](../aidbox) chart, then point
  `config.AIDBOX_URL` at its service (e.g. `http://aidbox:8080`).

## 3. Secrets

Either let the chart create the Secret from `secrets.data`, or provision your own
and set `secrets.existingSecretName`. Keys (env var names):

| Key | Required | Purpose |
|-----|----------|---------|
| `DATABASE_URL` | yes | app connection to the `interbox` db; user needs `CREATEDB` (unless `createDatabase=false`) |
| `AIDBOX_CLIENT_SECRET` | if using Aidbox | Aidbox client secret |
| `INTERBOX_LICENSE` | no | blank = activate via dashboard |
| `CLAUDE_CODE_OAUTH_TOKEN` / `ANTHROPIC_API_KEY` | no | dashboard assistant auth |
| `INTERBOX_WORKSPACE_GIT_KEY` | no | private workspace repo access |

## 4. MLLP exposure

MLLP (HL7v2) is raw TCP on `mllp.port` via a dedicated LoadBalancer. Default is an
internal LB; supply the cloud annotation via an overlay (see `values-aks.yaml`).

**Pin the LB IP** (`mllp.service.loadBalancerIP`) — a dynamic LB IP can change on
reinstall and break the hospital's VPN/firewall config that targets it. Pinning a
free subnet IP gives DevOps a stable address to build the VPN around (see the k8s
deployment/networking notes).

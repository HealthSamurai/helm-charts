# interbox chart prerequisites

This chart deploys **only interbox**, the all-in-one integration engine with its API and
dashboard, and you point it at an external Postgres and Aidbox.

## 1. Postgres

interbox needs its own `interbox` database on Postgres with the `pg_trgm` and `btree_gist`
extensions, either managed or in-cluster:

- **Managed**, recommended for prod: Azure Database for PostgreSQL Flexible Server, Cloud
  SQL, RDS and the like.
- **In-cluster**: install the sibling [`postgres`](../postgres) chart.

Like Aidbox, the engine **creates** the `interbox` database on boot when the `DATABASE_URL`
user has `CREATEDB`, and the migrations add the extensions. So one DSN with a `CREATEDB`
user is all you need, which is the default (`database.createDatabase=true`).

If your managed Postgres won't grant `CREATEDB`, set `database.createDatabase=false` and
pre-create the database yourself. The flag sets `INTERBOX_SKIP_ENSURE_DB` so the engine skips
its bootstrap.

```sql
CREATE DATABASE interbox;
\c interbox
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS btree_gist;
-- plus a role scoped to the interbox database for the app DSN
```

interbox can share a cluster with Aidbox as long as it gets its own `interbox` database
there and leaves Aidbox's alone.

**Databricks Lakebase.** interbox runs on Lakebase Autoscaling projects. A native Postgres
role with a password needs nothing beyond a plain `DATABASE_URL`. To log in as a service
principal, prepare the project as
[Databricks Lakebase](https://www.health-samurai.io/docs/interbox/ops/lakebase) describes and
set:

```yaml
config:
  INTERBOX_DB_AUTH_METHOD: databricks-autoscale
  INTERBOX_DB_DATABRICKS_HOST: https://<workspace>.cloud.databricks.com
  INTERBOX_DB_DATABRICKS_CLIENT_ID: <application-id>
  INTERBOX_DB_DATABRICKS_ENDPOINT: projects/<project>/branches/<branch>/endpoints/<endpoint>
secrets:
  INTERBOX_DB_DATABRICKS_CLIENT_SECRET: <postgres-scoped OAuth secret>
  DATABASE_URL: postgres://<application-id>@ep-<name>.database.<region>.cloud.databricks.com/interbox?sslmode=verify-full
```

`DATABASE_URL` carries no password here. interbox fetches its own tokens.

**Extension allowlists.** Some managed services refuse `CREATE EXTENSION` until the
extension is allowlisted. Interbox checks before it migrates: it logs every missing
extension with the exact `azure.extensions` value to set, exits, and the pod crash-loops
until that is fixed. On Azure Flexible Server, put `pg_trgm,btree_gist` in the
`azure.extensions` server parameter. If Aidbox shares the server, add its `unaccent`,
`pgcrypto` and `pg_stat_statements` too. The value replaces the whole list, so keep any
entries other products need.
[PostgreSQL extensions](https://www.health-samurai.io/docs/interbox/ops/sizing#postgresql-extensions)
has the full table with roles and the `az` command.

## TLS to Postgres

Put `sslmode` in the DSN. Use **`require`** by default because it encrypts in transit and
managed Postgres usually demands it. **`verify-full`** with the provider's CA also blocks MITM.
Drop `sslmode` only when the path is already encrypted or trusted, such as a VPN or the same
private VNet:

    postgres://interbox:pass@host:5432/interbox?sslmode=require

## 2. Aidbox

- **Already have one**: set `config.AIDBOX_URL` to it and set `secrets.AIDBOX_CLIENT_SECRET`.
- **Need one**: install the sibling [`aidbox`](../aidbox) chart, then point
  `config.AIDBOX_URL` at its service, e.g. `http://aidbox:8080`.

## 3. Secrets

Either let the chart create the Secret from the `secrets` keys, or provision your own
(External Secrets Operator, Secrets Store CSI or similar) and set `secrets.existingSecretName`.
The keys are env var names:

| Key | Required | Purpose |
|-----|----------|---------|
| `DATABASE_URL` | yes | app connection to the `interbox` db; user needs `CREATEDB` (unless `createDatabase=false`) |
| `AIDBOX_CLIENT_SECRET` | if using Aidbox | Aidbox client secret |
| `INTERBOX_LICENSE` | no | blank = activate via dashboard |
| `CLAUDE_CODE_OAUTH_TOKEN` / `ANTHROPIC_API_KEY` | no | dashboard assistant auth |
| `INTERBOX_WORKSPACE_GIT_KEY` | no | private workspace repo access |
| `INTERBOX_DB_DATABRICKS_CLIENT_SECRET` | on Lakebase as a service principal | the service principal's OAuth secret |

## 4. MLLP exposure

MLLP (HL7v2) is raw TCP on `mllp.port`, served by a LoadBalancer of its own. The chart
doesn't make that LB internal by itself, and without a cloud annotation most clouds give it a
public IP, so add the annotation in an overlay. On AKS, `values-aks.yaml` does it.

**Pin the LB IP.** A dynamic IP can change on reinstall and break the hospital's VPN or
firewall rules that target it, so pin a free subnet IP and give the network team a stable
address. On AKS, use the `azure-load-balancer-ipv4` annotation from the README's AKS section
instead of `mllp.service.loadBalancerIP`.

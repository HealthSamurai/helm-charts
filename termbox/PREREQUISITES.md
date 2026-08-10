# termbox chart — prerequisites

Termbox is a standalone FHIR Terminology Server. This chart deploys **only termbox**;
Postgres is an external dependency you point it at.

## 1. Postgres

Termbox connects with discrete `PG_*` variables (`PG_HOST`, `PG_PORT`, `PG_USER`,
`PG_PASSWORD`, `PG_DATABASE`). Options:

- **Managed** (recommended for prod) — Azure Database for PostgreSQL Flexible Server,
  Cloud SQL, RDS, etc. See also
  [Termbox on Managed PostgreSQL](https://www.health-samurai.io/docs/termbox/managed-postgresql)
  for Databricks Lakebase support (`PG_DATABRICKS_*`, OAuth instead of `PG_PASSWORD`).
- **In-cluster** — install the sibling [`postgres`](../postgres) chart.

Create the database (name must match `config.PG_DATABASE`, default `termbox`) and a role
termbox can connect as:

```sql
CREATE DATABASE termbox;
CREATE USER termbox WITH PASSWORD 'change-me';
GRANT ALL PRIVILEGES ON DATABASE termbox TO termbox;
```

termbox applies its own schema migrations on boot.

## 2. License

termbox needs a license to serve FHIR API requests
(https://www.health-samurai.io/docs/termbox/licensing). Set `secrets.data.LICENSE`. Get a free development
license at `/ui/license`, or a production one from Health Samurai.

## 3. Secrets

Either let the chart create the Secret from `secrets.data`, or provision your own and set
`secrets.existingSecretName`. Keys (env var names):

| Key | Required | Purpose |
|-----|----------|---------|
| `PG_USER` | yes (unless using Databricks OAuth) | Postgres user |
| `PG_PASSWORD` | yes (unless using Databricks OAuth) | Postgres password for `PG_USER` |
| `LICENSE` | yes | required for the FHIR API |

## 4. Full list of settings

See [Configuration](https://www.health-samurai.io/docs/termbox/configuration) for the
complete list of environment variables (logging, feature toggles, FHIR API version
routes, connection pool tuning, etc.) — add any of them to `config` (non-secret) or
`secrets.data` (secret) as needed.

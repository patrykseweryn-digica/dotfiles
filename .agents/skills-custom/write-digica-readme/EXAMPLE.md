# Example README

A fully-filled README in the target style. Use this as a reference for tone, length, and section formatting.

````markdown
# Invoice Sync Service

> Service that syncs ERP invoices into the data warehouse for finance reporting.

## Why this exists

Finance needs ERP invoices in the warehouse for reporting.
This service pulls them on a schedule, normalizes them, and loads them into BigQuery.
It supports analytics workflows and monthly management reports.

## Status

Working - production since 2025-Q3.

## Prerequisites

- Docker + Docker Compose
- `uv` (only for running outside the container)
- Company VPN access (ERP connectivity)

## Quick start

```bash
# 1. Clone
git clone git@github.com:company/invoice-sync.git && cd invoice-sync

# 2. Configure environment (values and sources are documented in the file)
cp .env.example .env
$EDITOR .env

# 3. Run
docker compose up --build
```

## Verify it works

- Health: `curl http://localhost:8000/health` -> expected `{"status":"ok"}`
- Smoke test: `docker compose exec app pytest tests/smoke`
- Startup logs: `docker compose logs -f app` -> look for `Sync scheduler started`

## Configuration

All environment variables, descriptions, and value sources are documented in `.env.example`.
Copy it to `.env` and fill the values. Do not commit `.env`.

## Common commands

```bash
docker compose exec app pytest                  # tests
docker compose exec app ruff check .            # lint
docker compose exec app pyright                 # typecheck
docker compose exec app bash                    # container shell
docker compose exec app alembic upgrade head    # DB migrations
```

## Architecture

The scheduler polls ERP hourly, normalizes invoice data, and loads it into BigQuery.
Services from `docker-compose.yml`: `app` (service), `db` (Postgres sync state).
Details: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Troubleshooting

- **Port 8000 is busy** -> change the mapping in `docker-compose.override.yml`.
- **`Missing env var ERP_API_KEY`** -> fill `.env` according to `.env.example`.
- **`connection refused` to ERP** -> confirm VPN is active.
- **Stale migrations** -> `docker compose exec app alembic upgrade head`.

## Owner / contact

Owner: Data Platform team - Slack `#data-platform`.
Questions and incidents go there.

## Links

- **Docs** - [`docs/`](docs/) and [`ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- **Google Drive** - project folder: `https://drive.google.com/drive/folders/abc123`
- **Slack** - `#invoice-sync` (discussion) and `#data-platform-alerts` (incidents)
- **Jira** - INV project: `https://company.atlassian.net/jira/software/projects/INV/board`
- **Environments** - staging `https://invoice-sync.staging.company.io` and prod `https://invoice-sync.company.io`
- **Monitoring** - `https://grafana.company.io/d/invoice-sync`
````

## How a TODO placeholder looks in-file

When the user skips a question, leave a comment exactly like this: visible in source, invisible in rendered Markdown.

```markdown
## Owner / contact

<!-- TODO: identify owner and Slack channel -->
```

## Post-write TODO summary (printed to chat, not to file)

```
README.md written. Remaining TODOs:
  - Owner / contact (section "Owner / contact")
  - Monitoring link (section "Links")
  - Healthcheck URL (section "Verify it works")
```

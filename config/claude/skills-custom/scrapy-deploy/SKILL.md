---
name: scrapy-deploy
description: >
  Deploy Scrapy scrapers to Docker with monitoring. Use when user wants to deploy a scraper,
  put a spider on a server, run a crawler in production, create a Dockerfile for scraping,
  set up monitoring/alerts, or mentions "deploy scraper", "run spider on server", "dockerize scraper",
  "monitor scraper", "scraper alerts".
argument-hint: "[docker] [server]"
---

# Scrapy Deploy

Deploy Scrapy projects to Docker with monitoring and scheduling.

## Context Check

Verify this is a Scrapy project (look for `scrapy.cfg`). If not, tell the user to create one first with `/scrapy-copilot`.

## Deployment: Docker (Recommended)

Auto-detect existing files (Dockerfile, docker-compose.yml) before generating.

**Generate Dockerfile (multi-stage with uv):**
```dockerfile
FROM python:3.12-slim AS base
WORKDIR /app
RUN pip install uv

FROM base AS deps
COPY pyproject.toml uv.lock* ./
RUN uv sync --no-dev --frozen 2>/dev/null || uv sync --no-dev

FROM python:3.12-slim AS runtime
WORKDIR /app
COPY --from=deps /app/.venv /app/.venv
COPY . .
ENV PATH="/app/.venv/bin:$PATH"
ENTRYPOINT ["scrapy"]
CMD ["list"]
```

**Generate docker-compose.yml:**
```yaml
services:
  scraper:
    build: .
    command: ["crawl", "${SPIDER_NAME:-products}"]
    volumes:
      - ./output:/app/output
    environment:
      - LOG_LEVEL=${LOG_LEVEL:-INFO}
    restart: "no"
```

**Generate deploy.sh (SSH deployment):**
Script does: build → save → scp upload → docker load → test run.
Uses env vars: `REMOTE_HOST` (required), `REMOTE_DIR`, `IMAGE_TAG`.

**Generate setup-cron.sh:**
Script SSHes to server, sets up crontab entries for each spider.
Uses env vars: `REMOTE_HOST` (required), `CRON_HOUR`, `SPIDERS`.
Staggers spiders by 5 minutes to avoid overlap.

## Monitoring

After deployment setup, always offer to configure monitoring. Recommended stack:

### 1. Stats JSON Export (always add)

Create `extensions.py` with `StatsJsonExporter` — a Scrapy extension that dumps crawl stats to `output/<spider>/stats/<timestamp>.json` after each run. Serialize datetimes to ISO format.

Register in settings.py:
```python
EXTENSIONS = {
    "extensions.StatsJsonExporter": 501,
}
```

### 2. SpiderMon (add for alerts)

Add `spidermon>=1.21`, `jinja2>=3.1`, `python-dotenv>=1.0` to dependencies.

**IMPORTANT:** SpiderMon's `LocalStorageStatsHistoryCollector` is incompatible with Scrapy 2.14+ (`_persist_stats` signature mismatch). Do NOT set `STATS_CLASS` to it. Use the custom `StatsJsonExporter` instead for stats persistence.

Create `monitors.py` with a `SpiderCloseMonitorSuite` that checks:
- No items extracted (count > 0)
- Abnormal finish reason (finish_reason == "finished")
- Error rate too high (< 5%)

**IMPORTANT: Monitor names appear in alerts next to ❌/✅. Name them as the PROBLEM, not the desired state.** E.g. "Abnormal finish reason" not "Spider finished normally" — so `❌ Abnormal finish reason` reads correctly.

Register in settings.py:
```python
SPIDERMON_ENABLED = True

EXTENSIONS = {
    "spidermon.contrib.scrapy.extensions.Spidermon": 500,
    "extensions.StatsJsonExporter": 501,
}

SPIDERMON_SPIDER_CLOSE_MONITORS = (
    "monitors.SpiderCloseMonitorSuite",
)
```

### 3. Notifications (optional, ask user)

SpiderMon supports notifications on both failure AND success. Use `monitors_failed_actions` for errors and `monitors_passed_actions` for successful crawls.

Supported channels:
- **Telegram**: `SendTelegramMessageSpiderFinished` — needs `SPIDERMON_TELEGRAM_SENDER_TOKEN` + `SPIDERMON_TELEGRAM_RECIPIENTS`
- **Slack**: `SendSlackMessageSpiderFinished` — needs `SPIDERMON_SLACK_SENDER_TOKEN` + `SPIDERMON_SLACK_RECIPIENTS`
- **Email**: `SendSmtpEmail` — needs SMTP config

All tokens go in env vars (`.env` file + `python-dotenv`), never hardcoded.

**IMPORTANT: Conditionally add notification actions** — SpiderMon raises `NotConfigured` if token env var is empty. Use conditional import in `monitors.py`:
```python
_failed_actions: list = []
_passed_actions: list = []
if os.environ.get("SPIDERMON_TELEGRAM_SENDER_TOKEN"):
    from spidermon.contrib.actions.telegram.notifiers import SendTelegramMessageSpiderFinished
    _failed_actions.append(SendTelegramMessageSpiderFinished)
    _passed_actions.append(SendTelegramMessageSpiderFinished)

class SpiderCloseMonitorSuite(MonitorSuite):
    monitors = [CrawlHealthMonitor]
    monitors_failed_actions = _failed_actions
    monitors_passed_actions = _passed_actions
```

Load `.env` in `settings.py`:
```python
from dotenv import load_dotenv
load_dotenv()
```

Add `env_file: .env` to `docker-compose.yml`. Create `.env` with placeholders and add it to `.gitignore`.

## Monitoring Scale Guide

If user asks about monitoring options, present this progression:
| Scale | Solution |
|---|---|
| Few spiders, simple schedules | Docker + cron + stats JSON |
| Want failure alerts | + SpiderMon with Telegram/Slack |
| Dozens of spiders, dependencies | Docker + Airflow/Celery |
| Full observability | Grafana + Prometheus (overkill for <20 spiders) |
| No infra management | Zyte Scrapy Cloud (managed, paid) |

## Post-Deploy

Verify the deployment works:
1. Run a test crawl on the server
2. Check logs for errors
3. Confirm stats JSON is being saved to `output/<spider>/stats/`
4. Confirm SpiderMon runs and reports status in logs

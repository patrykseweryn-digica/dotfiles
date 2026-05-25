# Deployment

## Dockerfile (Multi-Stage)

```dockerfile
# --- Build stage ---
FROM python:3.12-slim AS builder

RUN pip install uv

WORKDIR /app
COPY pyproject.toml uv.lock* ./
RUN uv sync --frozen --no-dev

# --- Runtime stage ---
FROM python:3.12-slim

# Playwright system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libnss3 libnspr4 libdbus-1-3 libatk1.0-0 libatk-bridge2.0-0 \
    libcups2 libdrm2 libxkbcommon0 libatspi2.0-0 libxcomposite1 \
    libxdamage1 libxfixes3 libxrandr2 libgbm1 libpango-1.0-0 \
    libasound2 libwayland-client0 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy venv from builder
COPY --from=builder /app/.venv /app/.venv
ENV PATH="/app/.venv/bin:$PATH"

# Install Playwright browsers
RUN playwright install chromium

# Copy application
COPY src/ src/
COPY pyproject.toml .

# Create output directory
RUN mkdir -p output

CMD ["python", "-m", "src.main"]
```

## docker-compose.yml

```yaml
services:
  crawler:
    build: .
    env_file: .env
    volumes:
      - ./output:/app/output
    environment:
      - CRAWLEE_STORAGE_DIR=/app/storage
    restart: "no"

  # Optional: PostgreSQL for storage
  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: scraping
      POSTGRES_USER: crawler
      POSTGRES_PASSWORD: ${DB_PASSWORD:-secret}
    volumes:
      - pgdata:/var/lib/postgresql/data
    ports:
      - "5432:5432"

volumes:
  pgdata:
```

## .env.template

```bash
# Proxy
PROXY_URLS=

# Database (if using PostgreSQL storage)
DATABASE_URL=postgresql://crawler:secret@db:5432/scraping
DB_PASSWORD=secret

# Crawler settings
MAX_REQUESTS=100
MAX_CONCURRENCY=10
TASKS_PER_MINUTE=120
IMPERSONATE_PROFILE=chrome131

# Crawlee
CRAWLEE_STORAGE_DIR=./storage
```

## Build & Run

```bash
# Build
docker compose build

# Run once
docker compose run --rm crawler

# Run with logs
docker compose up crawler

# Run with custom env
docker compose run --rm -e MAX_REQUESTS=500 crawler
```

## Scheduled Runs (cron)

```bash
# Add to crontab
# Run every day at 2 AM
0 2 * * * cd /path/to/crawler && docker compose run --rm crawler >> /var/log/crawler.log 2>&1
```

## Without Docker

```bash
# Install
uv sync
uv run playwright install chromium

# Run
uv run python -m src.main

# Or for single-file:
uv run crawler.py
```

## Playwright in Docker — Troubleshooting

If Playwright fails in Docker:
1. Make sure system deps are installed (see Dockerfile)
2. Use `chromium_sandbox: False` in browser launch options
3. Use `headless: True` (no display in Docker)
4. If OOM: increase Docker memory limit or reduce `max_concurrency`

```python
# Docker-safe Playwright config
crawler = PlaywrightCrawler(
    headless=True,
    browser_type="chromium",
    browser_launch_options={"chromium_sandbox": False},
)
```

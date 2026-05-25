# Docker Setup for Standalone Scrapers

Multi-stage build with uv for minimal image size.

## Dockerfile

```dockerfile
FROM ghcr.io/astral-sh/uv:latest AS builder

WORKDIR /app
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project
COPY . .
RUN uv sync --frozen --no-dev

FROM python:3.13-slim AS runtime

WORKDIR /app
COPY --from=builder /app/.venv /app/.venv
COPY --from=builder /app/src /app/src
COPY --from=builder /app/pyproject.toml /app/

ENV PATH="/app/.venv/bin:$PATH"

ENTRYPOINT ["python", "-m", "<project_name>"]
```

Replace `<project_name>` with the package name from `pyproject.toml` (`[project] name = "..."`),
matching the `src/<project>/` directory.

If browser automation needed, add to runtime stage:
```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends chromium && rm -rf /var/lib/apt/lists/*
```

## docker-compose.yml

```yaml
services:
  scraper:
    build: .
    volumes:
      - ./outputs:/app/outputs
      - ./data:/app/data          # optional: search configs, input files
    env_file: .env                # optional: proxy, API keys
```

## .env.template

```
# Proxy (optional)
HTTP_PROXY=
HTTPS_PROXY=

# API keys (optional)
API_KEY=
```

Add `.env` to `.gitignore`.

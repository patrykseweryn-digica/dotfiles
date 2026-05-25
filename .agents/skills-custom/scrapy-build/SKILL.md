---
name: scrapy-build
description: "Create Scrapy projects and spiders: listing-detail crawls, pipelines, middleware, scrapy-poet/web-poet, pagination, tests, JSONL/CSV output."
argument-hint: "[url] [spider]"
---

# Scrapy Build

Use when the user asks for Scrapy, or the scrape needs hundreds of pages, listing-to-detail navigation, pipelines, middleware, recurring runs, or multiple spider modules.

## Workflow

1. Confirm Scrapy is warranted. For one-off API/static HTML scrapes, prefer `web-scraping-simple`.
2. Read `../web-scraping-scout/references/scrapy-integration.md`.
3. For selectors and item extraction, read `../web-scraping-scout/references/parsers.md`.
4. For pagination/storage/tests, read only needed references:
   - `../web-scraping-scout/references/pagination.md`
   - `../web-scraping-scout/references/storage.md`
   - `../web-scraping-scout/references/testing.md`
5. Set `ROBOTSTXT_OBEY=True` unless the user explicitly decides otherwise.
6. Verify with `ruff check`, `ruff format`, `pyright`, then `scrapy crawl <spider> -O sample.jsonl`.

## Boundaries

- Deployment, Docker, cron, monitoring, SpiderMon: use `scrapy-deploy`.
- Crawlee requested: use `crawlee-build`.
- Small browser/Cloudflare path: use `web-scraping-simple`.

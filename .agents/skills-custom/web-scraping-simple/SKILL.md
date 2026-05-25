---
name: web-scraping-simple
description: "Build a small standalone Python scraper after scouting: API, static HTML, embedded JSON, or light browser path with Pydantic models and JSONL/CSV output."
argument-hint: "[url] [fields]"
---

# Web Scraping Simple

Use after `web-scraping-scout` selects a small standalone scraper. Do not create Scrapy or Crawlee projects here.

## Choose Method

- API/XHR/GraphQL: read `../web-scraping-scout/references/api-scraping.md`.
- Static HTML, JSON-LD, `__NEXT_DATA__`, tables, articles: read `../web-scraping-scout/references/parsers.md`.
- 403/429, JS-only data, Cloudflare, login/session: read `../web-scraping-scout/references/browsers.md`; try API extraction after browser discovery.

## Build

1. Read `../web-scraping-scout/references/standalone-template.md`.
2. Add HTTP/browser/parser details only as needed:
   - `../web-scraping-scout/references/http-clients.md`
   - `../web-scraping-scout/references/auth.md`
   - `../web-scraping-scout/references/proxy.md`
   - `../web-scraping-scout/references/pagination.md`
3. Use Pydantic models and default to JSONL; read `../web-scraping-scout/references/storage.md`.
4. Add `price-parser`, `dateparser`, and `ftfy` only when fields need them.
5. Verify with `ruff check`, `ruff format`, `pyright`, then a small sample run.


---
name: web-scraper-copilot
description: >
  Generate production-ready web scrapers with API-first approach — from
  reverse-engineering REST/GraphQL endpoints to curl_cffi standalone scripts and
  full Scrapy projects. Handles TLS fingerprinting, anti-bot bypass, SPA
  rendering, auth flows, and data validation.
  Use when user wants to: scrape a website, reverse engineer an API, create a
  scraper/spider, extract data from web pages, handle anti-bot protection,
  bypass Cloudflare, or build a data pipeline.
  Triggers on: "scrape", "spider", "crawl", "scrapy", "web scraping",
  "extract data from site", "parse website", any URL + "extract/scrape/get data",
  "bypass cloudflare", "tls fingerprint", "reverse engineer api".
  Also trigger when user pastes a URL and asks to get structured data from it.
argument-hint: "[url] [what to extract]"
---

# Web Scraper Copilot

Reference files (`references/*.md`) contain code examples and API details.
Read them only when the workflow directs you to — NOT all upfront.

## Tool Stack

Each layer is swappable. Read the linked reference for details.

```
Layer           Default              Alternatives
─────────────────────────────────────────────────────
HTTP Client     curl_cffi            rnet, impit, primp
Browser         pydoll (MIT)         camoufox, nodriver
Parser          parsel               selectolax, Scrapling
Data Extractor  (per content type)   chompjs+jmespath, extruct, trafilatura
Retry           stamina              tenacity
Logging         loguru               (stdlib logging)
Rate Limit      aiolimiter           pyrate-limiter
UA Rotation     fake-useragent       —
```

Include when applicable: dateparser (dates), ftfy (Unicode cleanup), price-parser (prices).

## Workflow

```
Step 1: Context    → API discovery first, then analyze target, select tools
Step 2: Docs       → Fetch current docs via Context7 if needed
Step 3: Generate   → Read references/standalone-template.md or references/scrapy-integration.md
Step 4: Quality    → ruff check + ruff format + pyright
Step 5: Validate   → Read references/analysis.md → test run, analyze output
Step 6: Fix        → If issues found → fix → repeat from Step 4
Step 7: (Optional) → Tests: read references/testing.md → generate tests, run pytest
Step 8: (Optional) → Docker: read references/docker.md → Dockerfile + docker-compose
Step 9: (Optional) → Analysis module: read references/data-analysis.md → DuckDB + Rich/Plotly
```

### Step 1: Analyze & Select Tools

#### 1a. API discovery (TRY FIRST)

Use Chrome DevTools MCP to intercept network requests while browsing the target site.
Look for REST/GraphQL endpoints returning JSON. Read `references/api-scraping.md`.

If API found → skip HTML parsing entirely. Use curl_cffi to call API directly.
If no API found → go to 1b.

#### 1b. Fetch & classify the page

WebFetch(url) → check response:
- **403/429/5xx** → anti-bot. Read `references/browsers.md` for escalation ladder.
- **200 but bot-check** ("verify you are human", "cf-ray", CAPTCHA) → same as above.
- **200 but SPA** (`<div id="root">`, mostly `<script>` tags) → go back to 1a, look harder for API.
- **200 with data** but incomplete → partial SSR, check for API first.
- **200 with all data visible** → go to 1c.
- **301/302 to /login** → read `references/auth.md`, authenticate, restart.

#### 1c. Parser selection (check in this order!)

1. `extruct(html)` → JSON-LD / microdata? → use it. Cleanest, survives redesigns.
2. `<script id="__NEXT_DATA__">` or `window.__INITIAL_STATE__`? → chompjs + jmespath.
3. Other `<script>` JS objects? → chompjs + jmespath.

If 1-3 found nothing, choose by content type:
- **Articles/news/blogs** → trafilatura (clean text + metadata, no selectors needed).
- **Structured data in HTML** (products, listings, tables):
  - parsel (default) or selectolax (>10k items for speed).
  - Scrapling if scraper is long-running and site redesigns frequently.

Use price-parser for prices, dateparser for dates, ftfy for broken Unicode — when applicable.
Read `references/parsers.md` for code examples.

#### 1d. Framework choice

Default: **standalone script**. Use Scrapy only when user explicitly requests it or ALL of these apply:
- 100+ pages with listing → detail navigation
- Complex pipelines/middleware needed
- Recurring/long-running scrapes

```
Standalone script (default):         Scrapy project:
  - API endpoint scraping              - 100+ pages with complex navigation
  - Single page / simple pagination    - Listing → detail patterns
  - Quick one-off or recurring scrape  - Middleware chains needed
  - Most use cases                     - User explicitly requests Scrapy
```

- Proxy → read `references/proxy.md` (ask about proxy EARLY, not as last resort)
- Storage → read `references/storage.md` (default: JSONL)
- Pagination → read `references/pagination.md`

Inform user about robots.txt. Set ROBOTSTXT_OBEY=True for Scrapy projects.

## Deployment

- Standalone scripts → read `references/docker.md` for Docker setup with uv
- Scrapy projects → use `/scrapy-deploy` skill

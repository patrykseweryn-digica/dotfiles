---
name: scrapy-copilot
description: >
  Generate production-ready web scrapers with smart tool selection — from simple curl_cffi scripts
  to full Scrapy projects with anti-bot bypass. Handles TLS fingerprinting, SPA rendering, API
  reverse engineering, auth flows, and data validation.
  Use when user wants to: scrape a website, create a spider, generate scraping code,
  extract data from web pages, handle anti-bot protection, bypass Cloudflare, reverse engineer
  an API, or build a data pipeline from websites.
  Triggers on: "scrape", "spider", "crawl", "scrapy", "web scraping", "extract data from site",
  "parse website", any URL followed by "extract/scrape/get data", "bypass cloudflare",
  "tls fingerprint", "reverse engineer api".
  Also trigger when user pastes a URL and asks to get structured data from it.
argument-hint: "[url] [what to extract]"
---

# Scrapy Copilot

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

Always included: dateparser (dates), ftfy (Unicode cleanup), price-parser (prices).

## Workflow

```
Step 1: Context    → Analyze target, select tools
Step 2: Docs       → Fetch current docs via Context7 if needed
Step 3: Generate   → Read references/standalone-template.md or references/scrapy-integration.md
Step 4: Quality    → ruff check + ruff format + pyright
Step 5: Test       → Read references/testing.md → generate tests, run pytest
Step 6: Validate   → Read references/analysis.md → test run, analyze output
Step 7: Fix        → If issues found → fix → repeat from Step 4
```

### Step 1: Analyze & Select Tools

#### 1a. Fetch & classify the page

WebFetch(url) → check response:
- **403/429/5xx** → anti-bot. Read `references/browsers.md` for escalation ladder.
- **200 but bot-check** ("verify you are human", "cf-ray", CAPTCHA) → same as above.
- **200 but SPA** (`<div id="root">`, mostly `<script>` tags) → go to 1c.
- **200 with data** but incomplete → partial SSR, go to 1c.
- **200 with all data visible** → go to 1b.
- **301/302 to /login** → read `references/auth.md`, authenticate, restart.

#### 1b. Parser selection (check in this order!)

1. `extruct(html)` → JSON-LD / microdata? → use it. Cleanest, survives redesigns.
2. `<script id="__NEXT_DATA__">` or `window.__INITIAL_STATE__`? → chompjs + jmespath.
3. Other `<script>` JS objects? → chompjs + jmespath.

If 1-3 found nothing, choose by content type:
- **Articles/news/blogs** → trafilatura (clean text + metadata, no selectors needed).
- **Structured data in HTML** (products, listings, tables):
  - parsel (default) or selectolax (>10k items for speed).
  - Scrapling if scraper is long-running and site redesigns frequently.

Use price-parser for prices, dateparser for dates, ftfy for broken Unicode.
Read `references/parsers.md` for code examples.

#### 1c. SPA & API discovery

Use Chrome DevTools MCP to find API endpoints → read `references/api-scraping.md`.
If no API found, render with browser → read `references/browsers.md`.

#### 1d. Framework choice

```
Standalone script:                   Scrapy project:
  - Single page / simple pagination   - 100+ pages to crawl
  - Quick one-off scrape               - Listing → detail navigation
  - API endpoint                       - Pipelines/middleware needed
  - User doesn't need a project        - Recurring/long-running scrapes
```

- Proxy → read `references/proxy.md` (ask about proxy EARLY, not as last resort)
- Storage → read `references/storage.md` (default: JSONL)
- Pagination → read `references/pagination.md`

Inform user about robots.txt. Set ROBOTSTXT_OBEY=True for Scrapy projects.

## Deployment

Use `/scrapy-deploy` skill for deploying Scrapy projects to Docker.

---
name: crawlee-build
description: "Build crawlee-python crawlers when user explicitly asks for Crawlee, AdaptivePlaywrightCrawler, ParselCrawler, HttpCrawler, or crawlee-based scraping."
argument-hint: "[url] [what to extract]"
---

# Crawlee Build

Reference files (`references/*.md`) contain code examples and API details.
Read them only when the workflow directs you to — NOT all upfront.

## Tool Stack

Each layer is swappable. Read the linked reference for details.

```
Layer           Default                        Alternatives
──────────────────────────────────────────────────────────────
Crawler         AdaptivePlaywrightCrawler      BS, Parsel, Playwright, Http
HTTP Client     CurlImpersonateHttpClient      HttpxHttpClient
Parser          parsel (context.selector)      bs4 (context.soup), selectolax
Data Extractor  (per content type)             chompjs+jmespath, extruct, trafilatura
```

Always included when parsing text: dateparser (dates), ftfy (Unicode cleanup).

## Workflow

```
Step 1: Context    → Analyze target, select crawler type
Step 2: Docs       → Fetch current crawlee docs via Context7 if needed
Step 3: Generate   → Read references/templates.md → generate code
Step 4: Quality    → ruff check + ruff format + pyright
Step 5: Test       → Read references/testing.md → generate tests, run pytest
Step 6: Validate   → Read references/analysis.md → test run, analyze output
Step 7: Fix        → If issues found → fix → repeat from Step 4
```

### Step 1: Analyze & Select Crawler

#### 1a. Fetch & classify the page

WebFetch(url) → check response:
- **403/429/5xx** → anti-bot. Read `references/browsers.md` for escalation.
- **200 but bot-check** ("verify you are human", "cf-ray", CAPTCHA) → same as above.
- **200 but SPA** (`<div id="root">`, mostly `<script>` tags) → go to 1c.
- **200 with data** but incomplete → partial SSR, use AdaptivePlaywrightCrawler.
- **200 with all data visible** → go to 1b.

#### 1b. Parser selection (check in this order!)

1. `extruct(html)` → JSON-LD / microdata? → HttpCrawler + extruct. Cleanest.
2. `<script id="__NEXT_DATA__">` or `window.__INITIAL_STATE__`? → HttpCrawler + chompjs.
3. Other `<script>` JS objects? → HttpCrawler + chompjs + jmespath.

If 1-3 found nothing, choose by content type:
- **Articles/news** → BeautifulSoupCrawler + trafilatura.
- **Structured HTML** (products, listings, tables) → ParselCrawler (CSS+XPath).
- **Large volume (>10k items)** → ParselCrawler + selectolax for speed.

Read `references/parsers.md` for code examples.

#### 1c. SPA & API discovery

Use Chrome DevTools MCP to find API endpoints → read `references/api-scraping.md`.
If API found → HttpCrawler targeting the API.
If no API → PlaywrightCrawler or AdaptivePlaywrightCrawler.

#### 1d. Crawler selection summary

```
Simple static HTML          → BeautifulSoupCrawler or ParselCrawler
Static + anti-bot           → ParselCrawler + CurlImpersonateHttpClient
SPA / JS-heavy              → PlaywrightCrawler
Unknown / mixed             → AdaptivePlaywrightCrawler (DEFAULT)
API endpoint                → HttpCrawler
Large scale + anti-bot      → AdaptivePlaywrightCrawler + proxy
```

Read `references/crawlers.md` for full configuration details.

#### 1e. Structure decision

```
Simple (1-3 page types)     → Single .py file
Complex (4+ handlers,       → Modular project:
  routing, pipeline)            crawler.py, handlers.py, models.py, config.py
```

Read `references/templates.md` for code templates.

- Proxy → read `references/proxy.md` (ask about proxy EARLY)
- Storage → read `references/storage.md` (default: JSONL via push_data)
- Pagination → read `references/pagination.md`
- Deployment → read `references/deployment.md`

Inform user about robots.txt. Set `respect_robots_txt_file=True` when appropriate.

---
name: crawlee-build
description: "Build Crawlee-python production crawlers for browser-context-heavy, SPA interaction-heavy, scroll/click/stateful UI, or adaptive browser/HTTP scraping after production design approval."
argument-hint: "[url] [what to extract]"
---

# Crawlee Build

Use after `web-scraping-pipeline-design` approves Crawlee, or when the user explicitly asks for Crawlee and the target is browser-heavy. Do not use Crawlee as the default for ordinary HTTP/API/listing-detail production scraping; route those to `scrapy-build` after design approval.

Reference files (`references/*.md`) contain code examples and API details.
Read them only when the workflow directs you to — NOT all upfront.

## Tool Stack

Each layer is swappable. Read the linked reference for details.

```
Layer           Browser-heavy default          Alternatives
──────────────────────────────────────────────────────────────
Crawler         PlaywrightCrawler              Adaptive, BS, Parsel, Http
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

Confirm Crawlee is warranted. If the target has a discoverable API, static HTML, or normal listing-detail crawl without central browser interaction, route back to `web-scraping-pipeline-design` or `scrapy-build`.

#### 1a. Fetch & classify the page

WebFetch(url) → check response:
- **403/429/5xx** → anti-bot. Read `references/browsers.md` for escalation.
- **200 but bot-check** ("verify you are human", "cf-ray", CAPTCHA) → same as above.
- **200 but SPA** (`<div id="root">`, mostly `<script>` tags) → go to 1c.
- **200 with data** but incomplete → partial SSR; use Crawlee only if render/interaction is still central.
- **200 with all data visible** → ordinary HTTP path; prefer Scrapy for production.

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
If API found → production usually belongs in Scrapy; only keep Crawlee if browser context remains necessary.
If no API and interaction/rendering is central → PlaywrightCrawler or AdaptivePlaywrightCrawler.

#### 1d. Crawler selection summary

```
SPA interaction-heavy       → PlaywrightCrawler
Scroll/click/stateful UI    → PlaywrightCrawler
Mixed HTTP/browser target   → AdaptivePlaywrightCrawler
Browser-context anti-bot    → PlaywrightCrawler or Adaptive + proxy
Static/API/listing-detail   → Not Crawlee default; prefer Scrapy production path
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
- Shared lifecycle/storage/audit/runbook expectations:
  - `../web-scraping-references/references/lifecycle.md`
  - `../web-scraping-references/references/storage-policy.md`
  - `../web-scraping-references/references/quality-gates.md`
  - `../web-scraping-references/references/operator-runbook.md`
  - `../web-scraping-references/references/downstream-ml-llm.md`

Inform user about robots.txt. Set `respect_robots_txt_file=True` when appropriate.

## Production Expectations

- Explain why Crawlee is better than Scrapy for this target, and the expected browser/runtime cost.
- Provide smoke/sample and full modes.
- Save manifest, parsed, curated, audit, raw sample, and failure evidence according to the approved design.
- Keep output provenance ready for downstream ML/LLM when relevant: stable IDs, source URLs, fetched timestamps, run IDs, schema versions, hashes.
- Include operator runbook expectations; use deployment guidance only when requested.

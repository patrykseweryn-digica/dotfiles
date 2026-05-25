---
name: web-scraping-scout
description: "Scout a website before scraping: inspect HTML, APIs/XHR, JS rendering, anti-bot, auth, pagination, and scale, then route to the right scraping skill."
argument-hint: "[url] [what to extract]"
---

# Web Scraping Scout

Use this first for unclear "scrape this site" requests. Do lightweight discovery, then route. Do not build a full scraper here.

## Scout

1. Fetch the URL and classify: status, redirects, login, bot-check, SPA shell, visible data.
2. Check cheap data sources first: JSON-LD, `__NEXT_DATA__`, initial state, script blobs.
3. Inspect XHR/fetch/GraphQL with browser tools when needed; read `references/api-scraping.md`.
4. Identify pagination: links, load-more, infinite scroll, API cursors; read `references/pagination.md` if unclear.
5. Estimate scale and project shape: one-off script, recurring scraper, listing-detail crawl, framework request.
6. Report the chosen path and why.

## Route

- Small API/HTML/browser-backed Python scraper: use `web-scraping-simple`.
- Existing scraper broken or output empty: use `web-scraping-debug`.
- Need output quality review: use `web-scraping-audit`.
- New Scrapy project or spider generation: use `scrapy-build`.
- Crawlee/crawlee-python explicitly requested: use `crawlee-build`.
- Deploying, Dockerizing, scheduling, or monitoring an existing Scrapy project: use `scrapy-deploy`.

Shared references live in `references/*.md`; load only the file needed by the selected path.

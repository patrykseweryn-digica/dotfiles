---
name: web-scraping-scout
description: "Scout a website before scraping: inspect HTML, APIs/XHR, JS rendering, anti-bot, auth, pagination, and scale, then route to the right scraping skill."
argument-hint: "[url] [what to extract]"
---

# Web Scraping Scout

Use this first for unclear or new "scrape this site" requests. Actively discover what extraction path works, then route. Do not build the final scraper or structured PoC project here.

If the user gives only a URL, ask what records/fields they want before deeper discovery.

## Scout

1. Confirm data goal: target records, fields, one-off vs recurring/production.
2. Fetch the URL and classify: status, redirects, login, bot-check, SPA shell, visible data.
3. Check cheap data sources first: JSON-LD, `__NEXT_DATA__`, initial state, script blobs.
4. Inspect XHR/fetch/GraphQL with browser tools when needed; read `references/api-scraping.md`.
5. Identify pagination: links, load-more, infinite scroll, API cursors; read `references/pagination.md` if unclear.
6. Probe the smallest useful sample path. Temporary recon scripts/snippets are allowed; do not create the final project.
7. Classify source type, scale, recurrence, browser need, auth/login/captcha/anti-bot risk, legal/ethical notes, and expected next skill.
8. Report the chosen path, evidence, and why alternatives are weaker.

## Evidence

Return concise handoff notes for the next skill:

- working source path: HTML, embedded JSON, REST/XHR, GraphQL, browser render, or blocker
- endpoint URLs, payloads, required headers, selectors, pagination clues, sample records
- what was tried and failed
- risk notes and user decisions needed
- recommended next skill

Small snippets are fine as evidence: `curl`, `httpx`, GraphQL payload, selector probe, or browser-network finding.

## Shared References

Use shared references when classifying production shape:

- `../web-scraping-references/references/lifecycle.md`
- `../web-scraping-references/references/framework-choice.md`
- `../web-scraping-references/references/legal-ethics.md`
- `../web-scraping-references/references/toolbox.md`

## Route

- One-off feasibility or small API/HTML/browser-backed proof: use `web-scraping-simple`.
- Recurring, production, long-running, or operational scraper: use `web-scraping-pipeline-design`.
- Existing scraper broken or output empty: use `web-scraping-debug`.
- Need output quality review: use `web-scraping-audit`.
- Approved Scrapy project or spider generation: use `scrapy-build`.
- Approved Crawlee/crawlee-python browser-heavy implementation: use `crawlee-build`.
- Deploying, Dockerizing, scheduling, or monitoring an existing Scrapy project: use `scrapy-deploy`.

Tactical scout references live in `references/*.md`; shared workflow references live in `../web-scraping-references/references/*.md`. Load only the file needed by the selected path.

## Escalation Boundary

Proceed without extra approval for normal HTTP requests, browser/network inspection, embedded JSON, XHR/API/GraphQL discovery, pagination probing, and small sample requests.

Ask before login/session reuse, private browser profile or stored cookies, captcha handling, proxy rotation, fingerprint/stealth escalation, paid APIs, high-rate crawling, or paywall access.

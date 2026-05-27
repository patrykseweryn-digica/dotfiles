---
name: web-scraping-debug
description: "Debug existing scrapers: empty output, selector drift, 403/429, auth/session failures, pagination drift, schema drift, flaky browser or proxy issues."
argument-hint: "[project-or-file] [symptom]"
---

# Web Scraping Debug

Use when a scraper already exists and is failing or producing bad data.

## Diagnose

1. If the symptom is output quality, run or inspect `web-scraping-audit` first.
2. Reproduce on the smallest saved raw sample, failure payload, fixture, URL, or page that fails. Prefer replay before live refetching.
3. Compare expected vs actual: status, response body, rendered DOM, network calls, manifest row, parsed row, curated row, audit finding.
4. Classify failure:
   - fetch failure: status, timeout, retry exhaustion, DNS, TLS, proxy, rate limit
   - selector/parser drift: read `../web-scraping-scout/references/parsers.md`
   - API contract drift: read `../web-scraping-scout/references/api-scraping.md`
   - pagination drift: read `../web-scraping-scout/references/pagination.md`
   - validation/schema drift: compare model, parsed output, and curated output
   - storage failure: read `../web-scraping-scout/references/storage.md`
   - auth/login failure: read `../web-scraping-scout/references/auth.md`
   - anti-bot/browser/proxy failure: read `../web-scraping-scout/references/browsers.md` or `../web-scraping-scout/references/proxy.md`
5. Fix the narrow cause; avoid rewriting from scratch unless the current method is dead.
6. Add a regression check when practical: saved HTML/API fixture, replay test, sample output assertion, or smoke command.

## Verify

Run project lint/type/test commands if present, replay the saved failure, then run the smallest live sample needed. Hand final output to `web-scraping-audit` when data trust is the question.

---
name: web-scraping-debug
description: "Debug existing scrapers: empty output, selector drift, 403/429, auth/session failures, pagination drift, schema drift, flaky browser or proxy issues."
argument-hint: "[project-or-file] [symptom]"
---

# Web Scraping Debug

Use when a scraper already exists and is failing or producing bad data.

## Diagnose

1. Reproduce on the smallest URL/page/sample that fails.
2. Compare expected vs actual: status, response body, rendered DOM, network calls, output rows.
3. Classify failure:
   - selector/parser drift: read `../web-scraping-scout/references/parsers.md`
   - API contract or pagination drift: read `../web-scraping-scout/references/api-scraping.md` or `pagination.md`
   - anti-bot/browser/proxy/auth: read `browsers.md`, `proxy.md`, or `auth.md`
   - storage/schema issue: read `storage.md`
4. Fix the narrow cause; avoid rewriting from scratch unless the current method is dead.
5. Add a regression check when practical: saved HTML/API fixture, sample output assertion, or smoke command.

## Verify

Run project lint/type/test commands if present, then a small live sample. For output quality, hand off to `web-scraping-audit`.


---
name: web-scraping-audit
description: "Audit scraped output quality: fill rates, duplicates, type consistency, suspicious constants, outliers, schema mismatch, sample review, and fix recommendations."
argument-hint: "[output-file-or-dir]"
---

# Web Scraping Audit

Use after a scrape run, before trusting data or changing extraction logic.

## Audit

1. Load recent output files; read `../web-scraping-scout/references/analysis.md`.
2. Check item count, status distribution, errors, and crawl duration when stats exist.
3. For each field, report fill rate, unique count, type consistency, examples, and suspicious constants.
4. Check duplicates and ID/key stability.
5. Compare against expected schema or Pydantic model when available.
6. Produce recommendations:
   - selector/parser fix -> `web-scraping-debug`
   - schema/storage issue -> relevant project files
   - analysis/reporting need -> read `../web-scraping-scout/references/data-analysis.md`

Do not re-run large crawls unless the user asks.


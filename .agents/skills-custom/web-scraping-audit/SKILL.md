---
name: web-scraping-audit
description: "Audit scraping runs before trusting data: run metadata, record counts, validation, fill rates, duplicates, suspicious constants, failures, throughput, run-to-run deltas, and fix recommendations."
argument-hint: "[run-output-dir-or-file]"
---

# Web Scraping Audit

Use after a scrape run, before trusting data or changing extraction logic. Audit runs, not just files.

## Audit

1. Locate run outputs: manifest, parsed, curated, audit, stats, raw samples, failures, logs.
2. Read `../web-scraping-references/references/quality-gates.md` and `../web-scraping-scout/references/analysis.md`.
3. Report run metadata: run ID, scraper version, schema version, start/end time, duration, source scope, output paths.
4. Check record counts, per-stage counts, status distribution, errors/failures, and approximate throughput.
5. For each required field, report fill rate, unique count, type consistency, examples, and suspicious constants.
6. Check duplicates, stable ID/key behavior, schema/Pydantic validation, and sample good/bad records.
7. Compare to a previous good run when available: records gained/lost, fill-rate deltas, duplicate deltas, new errors, schema drift.
8. Produce recommendations:
   - selector/parser fix -> `web-scraping-debug`
   - schema/storage issue -> relevant project files
   - analysis/reporting need -> read `../web-scraping-scout/references/data-analysis.md`

Do not re-run large crawls unless the user asks.

## Output

State whether the run is trusted, suspicious, or blocked. Include the evidence behind that call and the next action.

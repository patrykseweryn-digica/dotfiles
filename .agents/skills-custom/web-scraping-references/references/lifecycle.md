# Scraping Lifecycle

## Phases

- Feasibility: prove whether data can be extracted, which source works, approximate speed, blockers, and recommended production path.
- Production design: decide framework, storage, audit, deployment, risk, retention, and approval before implementation.
- Production implementation: build the approved Scrapy/Crawlee/rare standalone project.
- Operation: run, audit, compare with previous good run, debug from saved evidence when possible.

## Data Stages

- Raw: source responses, HTML, API JSON, screenshots, or failure payloads saved for inspection or replay.
- Parsed: direct extracted records from source structure; may still be messy or source-shaped.
- Curated: validated, normalized, stable downstream dataset with schema version and stable IDs.
- Manifest: per-run and per-source metadata: URL, status, timestamps, hashes, run ID, scraper version, errors.
- Audit: quality report for a run: counts, validation, duplicates, fill rates, suspicious constants, deltas, recommendations.

## Defaults

- Feasibility: minimal manifest, sample parsed output, basic audit, raw sample and failures.
- Production: manifest always, parsed always, curated always, audit always, raw sample and failures by default.
- Full raw archival: only when justified by replay/debug value, compliance, or source volatility.

## Handoff Notes

Every phase should leave enough notes for the next skill:

- working source path: HTML, embedded JSON, REST/XHR, GraphQL, browser render, or manual blocker
- required headers, payloads, cookies/auth assumptions, pagination, rate limits
- sample records and known failure examples
- recommended next skill and why

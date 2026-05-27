# Quality Gates

## Basic Audit Minimum

Every meaningful run audit should report:

- total records and per-stage counts when available
- required field fill rates
- duplicate rate and key stability
- type/model validation errors
- suspicious constants or all-empty/all-zero values
- sample good and bad records
- fetch/parser failure counts
- status/error distribution when manifest exists
- run duration and approximate throughput
- run-to-run deltas when a previous good run exists

## Trust Rules

- Do not trust a run only because it produced rows.
- Treat record-count drops, fill-rate drops, sudden duplicates, and new validation errors as suspicious.
- If output quality is the question, audit before changing parser logic.
- If parser behavior is the question, debug from raw samples/failures before live refetching when possible.

## Production Gate Checks

Before implementation, a production design should state:

- expected required fields and IDs
- smoke/sample acceptance criteria
- full-run acceptance criteria
- audit checks that mark a run as trusted or suspicious
- what evidence should be saved for replay

## Scenario Validation

Workflow validation should cover:

- static HTML feasibility and production
- API/XHR feasibility and production
- listing-detail crawl
- SPA with discoverable API
- occasional render
- interaction-heavy SPA
- login/captcha/anti-bot risk
- existing broken scraper
- existing production audit
- Scrapy deployment

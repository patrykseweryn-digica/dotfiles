---
name: scrapy-build
description: "Create production Scrapy projects and spiders: API/listing-detail crawls, pipelines, middleware, pagination, sample/full modes, manifest, parsed/curated outputs, audit, and tests."
argument-hint: "[url] [spider]"
---

# Scrapy Build

Use after `web-scraping-pipeline-design` approves Scrapy, or when the user explicitly asks for Scrapy. Scrapy is the default production implementation path, including API-only production cases, unless the approved design says otherwise.

## Workflow

1. Confirm this is implementation work, not production design. If framework/storage/risk choices are still undecided, route to `web-scraping-pipeline-design`.
2. Read `../web-scraping-scout/references/scrapy-integration.md`.
3. Read shared expectations as needed:
   - `../web-scraping-references/references/lifecycle.md`
   - `../web-scraping-references/references/storage-policy.md`
   - `../web-scraping-references/references/quality-gates.md`
   - `../web-scraping-references/references/downstream-ml-llm.md`
   - `../web-scraping-references/references/operator-runbook.md`
4. For selectors and item extraction, read `../web-scraping-scout/references/parsers.md`.
5. For pagination/storage/tests, read only needed tactical references:
   - `../web-scraping-scout/references/pagination.md`
   - `../web-scraping-scout/references/storage.md`
   - `../web-scraping-scout/references/testing.md`
6. Set `ROBOTSTXT_OBEY=True` unless the user explicitly decides otherwise.
7. Verify with `ruff check`, `ruff format`, `pyright`, then a smoke crawl.

## Production Expectations

- Add smoke/sample mode and full mode.
- Write manifest, parsed output, curated output, audit output, and raw samples/failures according to the approved storage policy.
- Keep outputs versioned or run-specific; avoid destructive overwrite as default.
- Include stable IDs, source URLs, fetched timestamps, run IDs, schema versions, and source/content hashes where relevant.
- Add an operator README/runbook covering run commands, output paths, audit inspection, resume, env vars, common failures, and trust rules.
- Keep deployment artifacts out unless requested; use `scrapy-deploy` for Docker, scheduling, monitoring, and alerts.

## Boundaries

- Deployment, Docker, cron, monitoring, SpiderMon: use `scrapy-deploy`.
- Browser-interaction-heavy implementation approved: use `crawlee-build`.
- Feasibility/sample proof only: use `web-scraping-simple`.

---
name: web-scraping-references
description: "Shared web-scraping workflow references for lifecycle, framework choice, storage, quality, risk, runbooks, downstream data, and toolbox selection. Use when aligning scraping skills or designing a scraping workflow."
---

# Web Scraping References

Shared vocabulary and decision rules for scraping skills. Load only the reference needed by the active workflow.

## References

- `references/lifecycle.md`: feasibility vs production, raw/parsed/curated/manifest/audit.
- `references/feasibility-poc.md`: structured feasibility PoC project and `FEASIBILITY.md`.
- `references/framework-choice.md`: Scrapy, Crawlee, standalone, and browser/API decisions.
- `references/storage-policy.md`: JSONL, Parquet, DuckDB, Postgres, retention, append-only runs.
- `references/quality-gates.md`: audits, acceptance checks, run-to-run comparisons.
- `references/legal-ethics.md`: advisory risk notes and escalation boundaries.
- `references/operator-runbook.md`: production operator README expectations.
- `references/downstream-ml-llm.md`: stable IDs, metadata, hashes, clean text.
- `references/toolbox.md`: dependency/tool selection and health checks.
- `references/checkpointing.md`: resume, retries, dedupe, latest-good pointers.

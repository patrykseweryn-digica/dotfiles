# Downstream ML And LLM Readiness

Scraping prepares stable data. ML/LLM analysis is a separate pipeline.

## Curated Data Requirements

Include where relevant:

- stable record ID
- source URL
- fetched timestamp
- run ID
- scraper version
- schema version
- source hash or content hash
- language/locale
- normalized text fields
- extraction confidence or validation status when useful

## Text Data

- Preserve source URL and timestamp with every text chunk or document.
- Keep cleaned text separate from raw HTML/API payload.
- Avoid losing provenance during dedupe or normalization.
- Record encoding or language assumptions when they affect parsing.

## Analytical Datasets

- Prefer Parquet for larger curated datasets.
- Keep JSONL samples for debugging.
- Use DuckDB for local exploration over JSONL/Parquet.
- Treat Postgres as serving/application sink unless explicitly chosen as primary.

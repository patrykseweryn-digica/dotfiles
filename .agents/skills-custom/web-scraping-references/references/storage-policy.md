# Storage Policy

## Format Defaults

- JSONL: default for small/medium outputs, samples, append/debug workflows, and human inspection.
- Parquet: preferred for large analytical datasets and downstream ML/LLM pipelines.
- DuckDB: local exploration/query layer over JSONL/Parquet; not usually the source of truth.
- Postgres: optional application/backend sink; not the only source of truth unless explicitly chosen.

## Production Outputs

Production runs should write:

- manifest: always
- parsed output: always
- curated output: always
- audit report: always
- raw sample and failures: default
- full raw: only when justified

## Versioning

- Prefer append-only or versioned run directories.
- Avoid destructive overwrite as default.
- Use a `latest-good` pointer, metadata record, or symlink only after audit passes.
- Include run ID, timestamp, scraper version, and schema version in outputs or metadata.

## Retention

Document retention for:

- raw samples
- failures
- manifests
- parsed output
- curated output
- audit reports

Retention may be manual at first, but the policy must be explicit.

## Storage Recommendation

Design briefs must name the primary output format and why it fits. Mention alternatives only when relevant.

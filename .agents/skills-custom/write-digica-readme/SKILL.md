---
name: write-digica-readme
description: "Digica README.md audit/write: new, stale, weak; software and data science repos."
---

# write-digica-readme

Use only for explicit Digica README authoring or audit requests. Ignore incidental README mentions.

## Rules

- Auto-detect first; ask only unresolved gaps.
- Ask one question at a time.
- Confirm detected facts before drafting.
- Existing README: preserve good content; improve only missing or weak sections.
- User may skip; skipped gaps become visible `<!-- TODO: ... -->` comments.
- Preview the full README or diff before writing; write only after explicit yes.
- README links to deeper docs; do not duplicate `.env.example` or architecture docs.

## Workflow

1. Detect mode: `README.md` exists -> audit; missing -> new.
2. Detect language from README, docs, and comments; ask once only if there is no signal.
3. Inspect repo facts:
   - manifests: `pyproject.toml`, `package.json`, `Cargo.toml`
   - runtime: `Dockerfile`, `docker-compose.yml`
   - config: `.env.example`
   - migrations: `alembic/`, `prisma/`, `migrations/`
   - checks: tests, pytest config, package scripts
   - existing README headings
4. Present detection summary; ask for confirmation or corrections.
5. Load [STANDARD.md](STANDARD.md); build a gap list. For existing READMEs, include only missing or weak sections.
6. Interview gaps one by one. Offer `skip` every time.
7. Draft using [STANDARD.md](STANDARD.md). Load [EXAMPLE.md](EXAMPLE.md) only if formatting or tone is unclear.
8. Preview the full draft or diff; ask whether to write.
9. Write `README.md`.
10. Print TODO summary.

## Weak Signals

- Placeholder or TODO body text.
- Quick start lacks env setup.
- Configuration duplicates env vars instead of linking to `.env.example`.
- Missing smoke or health verification.
- Missing owner/contact.

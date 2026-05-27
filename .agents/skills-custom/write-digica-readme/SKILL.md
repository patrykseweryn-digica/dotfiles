---
name: write-digica-readme
description: "Digica README.md audit/write: new, stale, weak; software and data science repos."
---

# write-digica-readme

Use only for explicit Digica README authoring or audit requests. Ignore incidental README mentions.

## Rules

- Digica README default language is English.
- Auto-detect first; ask only unresolved gaps.
- Ask one question at a time.
- Confirm detected facts before drafting.
- Existing README is working material to verify, not source of truth.
- Repository files override README claims for technical facts.
- Preserve good content; replace stale or weak sections.
- User may skip; skipped gaps become visible `<!-- TODO: ... -->` comments.
- Work section by section; edit `README.md` after approval for each section.
- README links to deeper docs; do not duplicate `.env.example` or architecture docs.
- README-only edits do not require changelog updates.
- Do not commit unless the user asks.

## Workflow

1. Detect README mode:
   - new: no `README.md`
   - stale: existing README conflicts with repo facts
   - weak: existing README is current but thin, unclear, or incomplete
2. Inspect repo facts before asking:
   - manifests: `pyproject.toml`, `package.json`, `Cargo.toml`
   - runtime: `Dockerfile`, `docker-compose.yml`
   - config: `.env.example`
   - migrations: `alembic/`, `prisma/`, `migrations/`
   - checks: tests, pytest config, package scripts
   - existing README headings
3. Present mode, detected facts, and conflicts; ask for confirmation or corrections.
4. Load [STANDARD.md](STANDARD.md); walk sections in Digica order.
5. For each section:
   - state what the repo already proves
   - show the proposed section or diff
   - ask for approval or one missing fact
   - write approved content immediately
6. Use `<!-- TODO: <what is missing> -->` for skipped or unknown mandatory facts.
7. Print a short closeout: changed sections, why, final effect, verified commands, TODOs, unverified items.

## Weak Signals

- Placeholder or TODO body text.
- Quick start lacks env setup.
- Configuration duplicates env vars instead of linking to `.env.example`.
- Missing smoke or health verification.
- Missing owner/contact.
- Stale command, port, package manager, or runtime claims contradicted by repo files.

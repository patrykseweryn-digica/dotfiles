# README Standard

Spec for a Digica repository README. README is the entry point: it links to deeper docs and never duplicates them.

## Section order

1. Title + one-line tagline (mandatory)
2. Table of contents (mandatory)
3. Why this exists (mandatory)
4. Status (mandatory)
5. Prerequisites (mandatory)
6. Quick start (mandatory)
7. Verify it works (mandatory)
8. Configuration / secrets (mandatory)
9. Owner / contact (mandatory)
10. Links (mandatory)
11. Common commands (recommended)
12. Architecture (recommended)
13. Troubleshooting (recommended)
14. Development workflow (conditional)
15. Project structure (conditional)

Mandatory sections must appear unless explicitly confirmed as not applicable. Unknown mandatory details become `<!-- TODO: ... -->` comments.

## Project type

Classify the repo before building the section plan. Present evidence and ask the user to confirm.

- **Software** - app/service/tool signals: source entrypoints, API routes, frontend/backend scripts, Docker services, migrations, deploy or infra config.
- **Data science** - ML/analytics signals: notebooks, `data/`, `datasets/`, `models/`, `artifacts/`, DVC, MLflow, training/evaluation scripts, pandas/polars/sklearn/torch/tensorflow/xgboost/lightgbm dependencies.
- **Mixed** - both product/runtime and data science pipeline are meaningful.

For all Digica repos, use the all-project mandatory sections above.

For data science or mixed repos, also require:
- Data
- Architecture & Pipeline
- Results / Evaluation

For deployed software/app repos, also require:
- Architecture
- Deployment / Environments
- Troubleshooting

Conditional sections:
- Common commands
- Development workflow
- Project structure
- Agent instructions link
- Mermaid diagram

## Per-section spec

### Title + tagline
- H1 with project name, then a single sentence quote (`>`).
- The quote answers "what is this and for whom" in <140 chars, no jargon.

### Table of contents
- Always include a short table of contents after the tagline.
- Link only top-level sections.

### Why this exists
- 2-4 sentences. The business problem and the user.
- Bad: "A service to sync data." Good: "Finance needs invoices in BQ for reporting; this service pulls them from ERP hourly."

### Status
- One line. Visual cue (`green` / `yellow` / `red`, emoji, or badge) plus optional date or note.
- Values: `Active`, `WIP`, `Maintenance`, or `Deprecated`.

### Prerequisites
- Bullet list. Tools and access required *before* setup.
- Docker + Compose by default. Add `uv`, VPN, registry credentials, secrets-manager access as relevant.

### Quick start
- A single fenced bash block, 3-5 numbered steps, ending in `docker compose up` (or project equivalent).
- Each step is a real, copy-pasteable command.
- Canonical pattern: clone -> `cp .env.example .env` -> edit -> `docker compose up --build`.

### Verify it works
- Bullets, each one a concrete check: healthcheck URL with `curl`, UI URL, smoke test command, log line to grep for.
- Without this section, "I ran it" does not mean "it works".

### Configuration / secrets
- Pointer to `.env.example`, nothing else.
- Do not duplicate the env-var table in README; single source of truth lives in `.env.example` (variables, descriptions, where to obtain real values).
- Mention "don't commit `.env`" once.

### Common commands
- Fenced bash block. Test / lint / typecheck / shell-in-container / migrations.
- Each line has a `# comment` explaining what it does.

### Architecture
- 2-3 sentences. Services listed from `docker-compose.yml`. Link to `docs/ARCHITECTURE.md` for depth.

### Data
- Mandatory for data science and mixed repos; optional for software repos.
- Explain what data is needed, where to get it, where to place it, and what must not be committed.
- Mention refresh/regeneration steps when known.

### Architecture & Pipeline
- Mandatory for data science and mixed repos.
- Explain the project flow from inputs through processing/training/inference/evaluation to outputs.
- Keep Architecture and Pipeline together unless system architecture and ML pipeline are meaningfully different.

### Results / Evaluation
- Mandatory for data science and mixed repos.
- State where results live and how to reproduce evaluation.
- Explain what should be measured, the target goal, and why those metrics were chosen.
- Do not include result tables in README; link to reports, trackers, notebooks, or dashboards.

### Deployment / Environments
- Mandatory for deployed apps/services.
- Link or summarize staging/prod URLs, deploy ownership, logs, monitoring, and runbook/deploy docs.
- Do not include long deploy procedures if deeper docs exist.

### Development workflow
- Add when the repo has real process beyond basic commands: migrations, data refresh, codegen, test-before-PR, or build artifacts.

### Project structure
- Add when folder layout is not obvious.
- Keep it short: list important directories and what each is for, not a full tree.

### Troubleshooting
- 3-5 bullets. Format: **symptom** -> fix command/action.
- Cover the most common first-run failures: port conflict, missing env var, VPN/network, stale migrations.
- For data science, cover missing data paths, access, dependency/native package issues, GPU/CPU mismatch, stale cache, or stale artifacts when relevant.

### Owner / contact
- One line. Team name + Slack channel + (optional) escalation path.
- For Digica repos this is often the single most-read line.

### Links
Bullets, grouped by purpose. Cover at minimum:

- **Docs** - `docs/`, `ARCHITECTURE.md`, or external wiki.
- **Google Drive** - project folder for PRDs, notes, and business specs.
- **Slack** - project or team channel. If incident escalation uses a different channel than *Owner / contact*, list both.
- **Issue tracker** - Jira, Linear, GitHub Issues, or the board used by the team. Optional if work is tracked elsewhere.
- **Environments** - staging and production URLs.
- **Monitoring** - Grafana, Datadog, or equivalent dashboard.

Rules:
- Each item is a one-line bullet in format `**Label** - <url>` or `**Label** - <short note> <url>`.
- Omit categories the team does not use; do not add `N/A`.
- If the user does not know a URL, insert `<!-- TODO: link to <category> -->`.

## Audit rules (existing README)

For each section above, mark it:
- **Present & good** - leave alone.
- **Present but weak** - placeholder text, single-line where multi is needed, generic phrasing. Offer to improve.
- **Missing** - add via interview.
- **Stale** - contradicts repository files or current user confirmation. Replace or remove.

Specific weak-signals:
- "TODO: add description" or any literal TODO in body.
- Quick-start that doesn't include `.env` setup.
- Configuration section that re-lists env vars instead of linking to `.env.example`.
- Missing healthcheck/smoke-test -> user can't tell if it ran correctly.
- No owner / contact line.
- README claims a package manager, command, port, runtime, or service that repo files contradict.

## Edit workflow

- Work in the section order above, not in the existing README order.
- Existing README prose is working material to verify, not source of truth.
- Repository files are the source of truth for technical facts.
- Show the proposed section or diff before writing it.
- Write approved sections immediately instead of waiting for one final full rewrite.
- Preserve good existing prose, but remove stale content. Git history is the archive.
- README-only edits do not require changelog updates.
- Do not commit unless the user asks.

## Intentionally omitted

- License section
- CONTRIBUTING.md prominence
- Code of conduct
- Marketing badges

## Cross-cutting rules

- Every command block must be copy-pasteable and verified to work on a clean clone.
- No duplication: env vars in `.env.example`, architecture in `ARCHITECTURE.md`, README links to both.
- Skipped sections become `<!-- TODO: <what's missing> -->` in the file and appear in the post-write summary.

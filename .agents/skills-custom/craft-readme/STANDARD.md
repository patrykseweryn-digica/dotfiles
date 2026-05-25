# README Standard

Spec for an internal application repository README. README is the entry point — it links to deeper docs, never duplicates them.

## Section order

1. Title + one-line tagline (mandatory)
2. Why this exists (mandatory)
3. Status (mandatory)
4. Prerequisites (mandatory)
5. Quick start (mandatory)
6. Verify it works (mandatory)
7. Configuration / secrets (mandatory)
8. Common commands (recommended)
9. Architecture in a pill (recommended)
10. Troubleshooting (recommended)
11. Owner / contact (mandatory)
12. Links (recommended)

Mandatory sections must appear. Recommended sections appear unless clearly N/A.

## Per-section spec

### Title + tagline
- H1 with project name, then a single sentence quote (`>`).
- The quote answers "what is this and for whom" in <140 chars, no jargon.

### Why this exists
- 2–4 sentences. The business problem and the user.
- Bad: "A service to sync data." Good: "Finance needs invoices in BQ for reporting; this service pulls them from ERP hourly."

### Status
- One line. Visual cue (🟢/🟡/🔴) + optional date or note.
- Values: `Działa` / `WIP` / `Deprecated` (or English equivalents).

### Prerequisites
- Bullet list. Tools and access required *before* setup.
- Docker + Compose by default. Add `uv`, VPN, registry credentials, secrets-manager access as relevant.

### Quick start
- A single fenced bash block, 3–5 numbered steps, ending in `docker compose up` (or project equivalent).
- Each step is a real, copy-pasteable command.
- Canonical pattern: clone → `cp .env.example .env` → edit → `docker compose up --build`.

### Verify it works
- Bullets, each one a concrete check: healthcheck URL with `curl`, UI URL, smoke test command, log line to grep for.
- Without this section, "I ran it" ≠ "it works".

### Configuration / secrets
- Pointer to `.env.example`, nothing else.
- Do not duplicate the env-var table in README — single source of truth lives in `.env.example` (variables, descriptions, where to obtain real values).
- Mention "don't commit `.env`" once.

### Common commands
- Fenced bash block. Test / lint / typecheck / shell-in-container / migrations.
- Each line has a `# comment` explaining what it does.

### Architecture in a pill
- 2–3 sentences. Services listed from `docker-compose.yml`. Link to `docs/ARCHITECTURE.md` for depth.

### Troubleshooting
- 3–5 bullets. Format: **symptom** → fix command/action.
- Cover the most common first-run failures: port conflict, missing env var, VPN/network, stale migrations.

### Owner / contact
- One line. Team name + Slack channel + (optional) escalation path.
- For internal repos this is often the single most-read line.

### Links
Bullets, grouped by purpose. Cover at minimum:

- **Dokumentacja / docs** — `docs/`, `ARCHITECTURE.md`, ewentualnie zewnętrzna wiki.
- **Google Drive** — folder projektu (PRD-y, notatki, specyfikacje biznesowe).
- **Slack** — kanał projektu/zespołu. Jeśli różni się od kanału z sekcji *Owner / contact*, oba mają być wymienione (np. `#invoice-sync` dla dyskusji + `#data-platform-alerts` dla incydentów).
- **Issue tracker (Jira / Linear / GitHub Issues)** — link do projektu/boardu. Opcjonalne, jeśli zespół trackuje pracę gdzie indziej.
- **Środowiska** — staging i prod URL.
- **Monitoring** — dashboard Grafana / Datadog / inne.

Zasady:
- Dla każdej pozycji: jednoliniowy bullet w formacie `**Label** — <url>` lub `**Label** — <opis> <url>`.
- Pomiń kategorię, której zespół nie używa (nie wstawiaj „N/A").
- Jeśli użytkownik nie zna URL-a danej kategorii — `<!-- TODO: link do <kategoria> -->`.

## Audit rules (existing README)

For each section above, mark it:
- **Present & good** — leave alone.
- **Present but weak** — placeholder text, single-line where multi is needed, generic phrasing. Offer to improve.
- **Missing** — add via interview.

Specific weak-signals:
- "TODO: add description" or any literal TODO in body.
- Quick-start that doesn't include `.env` setup.
- Configuration section that re-lists env vars instead of linking to `.env.example`.
- Missing healthcheck/smoke-test → user can't tell if it ran correctly.
- No owner / contact line.

## Intentionally omitted (internal repos)

- License section
- CONTRIBUTING.md prominence
- Code of conduct
- Marketing badges

## Cross-cutting rules

- Every command block must be copy-pasteable and verified to work on a clean clone.
- No duplication: env vars in `.env.example`, architecture in `ARCHITECTURE.md`, README links to both.
- Skipped sections become `<!-- TODO: <what's missing> -->` in the file and appear in the post-write summary.

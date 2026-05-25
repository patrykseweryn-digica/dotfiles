---
name: craft-readme
description: Audit an existing README.md or author a new one through a sequential interview, ensuring all required sections are present and well-filled. Use only on explicit request — when the user says "craft readme", "napisz README", "wygeneruj README", "audyt README", "uzupełnij README", "stwórz README", or invokes /craft-readme. Do not trigger on incidental mentions of README files.
---

# craft-readme

Authors a high-quality repository README by either auditing an existing one or building a new one from scratch. Always interviews the user to fill missing information.

## Operating principles

- **One question at a time** — never batch. Use `AskUserQuestion` for each gap.
- **Auto-detect first, ask second** — extract everything possible from repo files before asking the user.
- **Confirm detections** — show the user what you found and let them correct it; never silently fill.
- **Surgical for existing READMEs** — preserve the user's content and structure; only fill or improve missing/weak sections. Never rewrite what already works.
- **Allow "skip"/"don't know"** — insert an HTML-comment TODO placeholder and collect them for a final summary.
- **Diff before writing** — show the proposed README (or diff vs existing), require explicit confirmation, then write.

## Workflow

1. **Detect mode** — check if `README.md` exists in cwd.
   - Exists → **audit mode**.
   - Missing → **new mode**.

2. **Auto-detect language** — scan existing README, repo docstrings/comments, top-level docs.
   - Polish content detected → output in Polish.
   - Otherwise → English.
   - New repo with no signal → ask the user once.

3. **Auto-detect facts from repo files** — read what's available and don't ask if the file answers it:
   - `pyproject.toml` / `package.json` / `Cargo.toml` → stack, project name, deps.
   - `docker-compose.yml` / `Dockerfile` → services, ports, run command.
   - `.env.example` → required env vars (don't duplicate the table in README — link to the file).
   - `alembic/` / `prisma/` / `migrations/` → migration command.
   - `tests/`, `pytest.ini`, `package.json` scripts → test/lint commands.
   - Existing README headings → which sections are present.

4. **Present detection summary** — list everything found in one message and ask "potwierdzasz?" / "confirm?". Correct mistakes before proceeding.

5. **Identify gaps** — compare detected state vs [STANDARD.md](STANDARD.md). Build an ordered list of sections to ask about (mandatory first, then recommended). For existing READMEs, only include sections that are missing or visibly weak (one-liner, placeholder text).

6. **Interview** — walk the gap list, one `AskUserQuestion` per gap. For each:
   - Lead with what you already know from auto-detection.
   - Offer "skip / pomiń" as an explicit option for every question.
   - Skip → insert `<!-- TODO: <what's missing> -->` placeholder and remember it.

7. **Assemble README** — apply the structure and style from [STANDARD.md](STANDARD.md). For a worked example see [EXAMPLE.md](EXAMPLE.md). Keep the user's existing prose where it was acceptable.

8. **Preview & confirm** — show the full proposed README (new mode) or a diff vs current (audit mode). Ask explicitly: "zapisać do README.md?" / "write to README.md?". Wait for yes.

9. **Write** — overwrite `README.md`.

10. **Print TODO summary** — list every `<!-- TODO -->` inserted, with file location and what's missing, so the user can finish them off-line.

## Anti-patterns

- Asking about something the repo already answers (e.g., asking for the stack when `pyproject.toml` lists it).
- Rewriting an existing section just because the standard would phrase it differently.
- Writing the file before showing a preview.
- Asking multiple questions in one message.
- Hiding skipped sections — TODOs must be visible in the file *and* in the summary.

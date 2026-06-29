---
name: project-statement
description: "Generate or update project statement documents."
---

# project-statement

Maintains `PROJECT_STATEMENT.yaml` (source of truth, gitignored) and renders it to `PROJECT_STATEMENT.md` (paste into a copy of the company-template Google Doc).

## Operating principles

- **One question at a time** via `AskUserQuestion` — never batch.
- **Auto-detect first, ask second.** Scan the repo before prompting.
- **Confirm detections** with `[Y/n/e]` (and `[a]` for DVC: abandoned).
- **TODOs allowed everywhere** — sentinel string `"TODO: <reason>"`, rendered inline with 🚧.
- **YAML is the source of truth.** Updates = edit YAML by hand and re-run the skill to re-render. Never edit the rendered `.md` directly.
- **No fields outside SCHEMA.md.** Don't invent ad-hoc keys.

## Workflow

1. **Detect mode** — check for `PROJECT_STATEMENT.yaml` in cwd:
   - Missing → **interview mode** (steps 2–8).
   - Present, valid → **render mode** (step 9 only).
   - Present, missing required fields → run interview only for missing fields, then render.

2. **Scan repo** for pre-fill data. See SCHEMA.md § "Pre-fill scan list". Build a detection summary.

3. **Confirm `project_type`** — auto-detect from signals, present, confirm with single Y/n prompt. Defaults: notebooks + ML deps + `.dvc/` → `data-science`; otherwise `software`.

4. **Confirm `name`** — from README H1, else `pyproject.toml`/`package.json` name, else repo directory name.

5. **Interview** — walk sections in this order:

   `goal` → `definition_of_done` → `team` → `constraints` → `repositories` → `tools` → `folders` → `datasets` (DS only) → `experiment_log` (DS only)

   For each section:
   - Show detected items first; user accepts with **Y**, rejects with **n**, edits with **e**.
   - For DVC tool detection, also offer **a** = abandoned (adds entry with `note: abandoned`).
   - After detections, ask for additional manual entries until user says no more.
   - For every prompt offer "value / skip / TODO" — skip writes a `TODO:` sentinel.
   - **List sections support one-by-one entry.** For `team`, `repositories`, `tools`, `folders`, and `datasets`, after the detections always offer an "add one more" path: a question whose **Other** free-text field accepts a *single* entry (e.g. one person: "Name — Role — YYYY-MM[ — YYYY-MM]"). Capture it, then re-ask "add another?" and loop until the user declines. Don't force the user to type the whole roster/list as one blob — accept it if they do, but the default offer is one entry at a time.
   - **No personal contact details.** Never collect or store email addresses (or phone/handles) for team members. Name, role, and join/leave months only.
   - Role picker uses the fixed list: Tech Lead, Project Manager, Data Scientist, Software Developer, Annotator, Full Stack Engineer, Frontend Developer, Tester, Other. DS-related roles last for software projects; software-related roles last for DS projects.
   - **Constraints must be concrete and measurable.** Ask for the actual number/threshold and what it applies to — e.g. "latency: <100ms per model on iPhone 15 Pro", "detection mAP ≥ 0.90", "model size < 50MB" — not vague adjectives like "low latency" or "high accuracy". If the user has no number yet, write a `TODO:` sentinel describing the missing target instead of a vague phrase.
   - Tool picker (DS-related at end): Slack, GDrive, Jira, Confluence, NAS, Miro, MLFlow, DVC, CVAT, Label Studio, Other. **`url` is optional** — do NOT prompt for a **Slack** URL (record the entry with just an optional note); omit `url` for any tool with no useful link.
   - **Datasets in DS projects is mandatory** — must have ≥ 1 entry. A TODO entry counts.

6. **Validate** — see SCHEMA.md § "Validation rules". On failure, re-prompt for the offending fields only.

7. **Write YAML** to `PROJECT_STATEMENT.yaml` at project root.

8. **Ensure gitignore** — append `PROJECT_STATEMENT.*` to `.gitignore` if not already present. Create `.gitignore` with that single line if it doesn't exist. Warn (do not skip) if `.gitignore` is tracked but read-only.

9. **Render** — run `python scripts/render.py PROJECT_STATEMENT.yaml > PROJECT_STATEMENT.md` (use the skill's own scripts dir). The script needs `PyYAML` — most project Python envs already have it; if not, activate one that does (e.g., a conda env), or `pip install pyyaml`. Then print a short summary: total TODOs, where the file is, "paste into a copy of the company template Google Doc".

## Files written

- `PROJECT_STATEMENT.yaml` — source of truth, gitignored.
- `PROJECT_STATEMENT.md` — rendered output, gitignored. Paste this into the Google Doc.
- `.gitignore` — appended if needed.

## Anti-patterns

- Inferring values silently — always show detections and confirm.
- Batching multiple questions in one prompt.
- Rendering without saving YAML first.
- Editing the `.md` directly (it's a generated artifact and will be overwritten).
- Adding fields not defined in SCHEMA.md.
- Auto-pre-filling team members from `CODEOWNERS`/`AUTHORS`/`pyproject.toml` authors (signal is too stale; ask the user instead).

## References

- Full schema, enums, scan list, validation rules, icon registry → [SCHEMA.md](SCHEMA.md)
- Worked example with filled YAML + rendered MD → [EXAMPLE.md](EXAMPLE.md)
- Deterministic renderer → [scripts/render.py](scripts/render.py)

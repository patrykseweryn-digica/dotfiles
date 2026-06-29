# SCHEMA — `PROJECT_STATEMENT.yaml`

This file is the authoritative schema reference for the `project-statement` skill. Everything the skill writes to YAML — and everything `scripts/render.py` reads — must conform to what's here.

## Top-level keys

| Key | Type | Required | Notes |
|---|---|---|---|
| `name` | string | yes | Project name. Title-cased prose; no slug. |
| `project_type` | enum: `data-science` \| `software` | yes | Drives DS-only sections. |
| `goal` | string (multi-line allowed via `\|`) | yes | 1–4 sentences. Elevator pitch. |
| `definition_of_done` | list[string] | yes | Flat list of one-liners. ≥ 1 entry. |
| `team` | list[TeamMember] | yes | ≥ 1 entry. See below. |
| `constraints` | object (categorized) | yes | At least one non-empty category. |
| `repositories` | list[Repository] | yes | ≥ 1 entry; exactly one `primary: true`. |
| `tools` | list[Tool] | no | Empty allowed (rare). |
| `folders` | list[Folder] | no | Empty allowed. |
| `datasets` | list[Dataset] | **yes for DS, absent for software** | ≥ 1 entry for DS (TODO entry counts). |
| `experiment_log` | string (URL) | **yes for DS, absent for software** | Google Sheet URL. |

Any field value may instead be a **TODO sentinel string** of the form `"TODO: <optional reason>"`.

---

## `team` entries

```yaml
team:
  - name: <string>            # required
    role: <string>            # required; picker suggests fixed list, "Other" accepts free text
    joined: YYYY-MM           # required; month precision
    left: YYYY-MM             # optional; absent = currently on team
```

**Do NOT collect or store email addresses** (or any other personal contact details) for team members. Name, role, and dates only. There is no `contact` field — ignore it if present in older YAML.

**Role picker order** (the interview presents this list; user picks one or types Other):

- DS projects: Data Scientist, Annotator, Tech Lead, Project Manager, Tester, Software Developer, Full Stack Engineer, Frontend Developer, Other
- Software projects: Software Developer, Full Stack Engineer, Frontend Developer, Tech Lead, Project Manager, Tester, Data Scientist, Annotator, Other

The role is stored in YAML as a **free-form string** (not an enum). The picker is interview UX only.

---

## `constraints` (categorized)

```yaml
constraints:
  performance: [<one-liner>, ...]      # latency, throughput, model size, memory
  accuracy:    [<one-liner>, ...]      # mAP, FAR/FRR, BLEU — mostly DS
  hardware:    [<one-liner>, ...]      # target device/chip/OS/RAM
  scalability: [<one-liner>, ...]      # concurrent users, request rate
  compliance:  [<one-liner>, ...]      # privacy, GDPR, data residency
  deadlines:   [<one-liner>, ...]      # hard dates
  other:       [<one-liner>, ...]      # anything else
```

**Closed vocabulary.** Don't add new category keys. Anything that doesn't fit goes under `other`. Empty categories are absent from YAML (don't write `performance: []`).

**Prefer concrete, measurable one-liners.** A constraint should carry a number wherever one exists — a target, threshold, or limit — not a vague adjective. The interview must ask for the concrete figure (and, where relevant, the model/device it applies to).

- ✅ `"latency: <100ms per model on iPhone 15 Pro"`, `"detection mAP: ≥0.90 on Digica test set"`, `"model size: <50MB exported"`
- ❌ `"low latency"`, `"high accuracy"`, `"small model"`

If the user genuinely doesn't have a number yet, record a TODO sentinel (e.g. `"TODO: latency target per model"`) rather than a vague adjective.

---

## `repositories` entries

```yaml
repositories:
  - name: <string>            # required; repo short name
    url: <string>             # required; GitHub URL (or other host)
    primary: true             # exactly one entry must have this
    description: <string>     # required; free-form prose about role/relation
```

**Validation:** exactly one entry has `primary: true`. Auto-detect marks `origin` as primary; user can reassign during the interview.

---

## `tools` entries

```yaml
tools:
  - name: <string>            # required; case-insensitive icon lookup
    url: <string>             # optional; omit when there's no useful link
    note: <string>            # optional one-liner
```

**`url` is optional.** Some tools have no meaningful link — notably **Slack**: do NOT prompt for a Slack URL, just record the entry (with an optional `note` like "project channel"). Omit the `url` key entirely rather than writing a TODO sentinel for it.

**Icon registry (case-insensitive name match):**

| `name:` value | Icon |
|---|---|
| `Jira` | 🗂️ |
| `Slack` | 💬 |
| `GDrive` / `Google Drive` | 📁 |
| `Confluence` | 📘 |
| `NAS` | 💽 |
| `Miro` | 🧠 |
| `MLFlow` / `MLflow` | 📊 |
| `DVC` | 🧬 |
| `CVAT` | 🏷️ |
| `Label Studio` | 🏷️ |
| *(any other name)* | 🔧 |

**Multi-instance allowed** — repeat the entry with the same `name`. Renderer groups by name.

**Picker order during interview** (DS-related tools at the end so the top of the list works for every project):

Slack, GDrive, Jira, Confluence, NAS, Miro, MLFlow, DVC, CVAT, Label Studio, Other.

---

## `folders` entries

```yaml
folders:
  - location: gdrive | nas    # closed enum; drives icon
    purpose: <string>         # required; free-form one-liner (e.g., "customer reports")
    url: <string>             # required
```

**Location icons:** `gdrive` → 📁, `nas` → 💽. Renderer groups by location in the doc.

---

## `datasets` entries (DS only)

```yaml
datasets:
  - name: <string>            # required
    purpose: <string>         # required; one-liner
    location: nas | gdrive | other   # required; drives icon
    url: <string>             # required (or a TODO sentinel)
    license: <string>         # required, free-form
    on_DVC: tracked | untracked | abandoned  # required enum
    version: <string>         # optional
    notes: <string>           # optional one-liner
```

**Mandatory section in DS projects** — must have ≥ 1 entry. A TODO entry like `name: "TODO: dataset not yet collected"` counts.

---

## `experiment_log` (DS only)

```yaml
experiment_log: <Google Sheet URL>
```

Single URL string. Expected to be a Google Sheet (the human-readable companion to MLflow/DVC).

---

## Pre-fill scan list

The skill runs these scans before any interview prompt and presents detections with `[Y/n/e]` (and `[a]` for DVC).

| Source | Extracts | Pre-fills |
|---|---|---|
| `README.{md,rst,txt}` | First H1 → name candidate; first paragraph → goal candidate; URLs categorized by domain | `name`, `goal`, `tools[]`, `folders[]`, `experiment_log` |
| `.git/config` `[remote "origin"]` | URL | `repositories[]` first entry, marked `primary: true` |
| `.gitmodules` | Each submodule's URL | additional `repositories[]` entries |
| `pyproject.toml` / `package.json` | `name`, `description` | `name`, `goal` fallback (authors NOT scanned) |
| `.dvc/` directory presence | DVC usage | `tools[]` DVC entry + `on_DVC` hint on datasets |
| Dependency mentions: torch / tensorflow / sklearn / mlflow | DS signal | `project_type: data-science` |
| `**/*.ipynb` (count) | DS signal | `project_type: data-science` |
| `data/`, `datasets/` directories | Data presence | `datasets[]` candidate (url = TODO if path is local) |

**URL → tool/folder/experiment_log domain mapping:**

| URL domain | Mapped to |
|---|---|
| `*.atlassian.net/jira` or `atlassian.net/browse` | tool: Jira |
| `*.atlassian.net/wiki` or `confluence` | tool: Confluence |
| `miro.com` | tool: Miro |
| `mlflow*` | tool: MLFlow |
| `slack.com` | tool: Slack |
| `cvat*` | tool: CVAT |
| `labelstud.io` / `label-studio` | tool: Label Studio |
| `github.com` | already in repositories — skipped here |
| `drive.google.com/drive/folders/` | folder (gdrive) |
| `docs.google.com/spreadsheets/` | experiment_log (DS projects only) |
| `docs.google.com/document/` | folder (gdrive) |

**Explicitly NOT scanned** (signal too unreliable):

- `CODEOWNERS`, `AUTHORS`, `CONTRIBUTORS.md`
- `pyproject.toml` `authors`
- git commit history (for team timeline)
- Confluence / Jira / MLflow APIs

---

## Validation rules

The skill validates after writing the YAML; `scripts/render.py` re-validates on load. Failures must be fixed before render proceeds.

1. `name` non-empty.
2. `project_type` is one of `data-science`, `software`.
3. `goal` non-empty string.
4. `definition_of_done` is a list with ≥ 1 entry.
5. `team` is a list with ≥ 1 entry; each entry has `name`, `role`, `joined`. No `contact`/email field is collected.
6. `joined` and `left` (if present) match `^\d{4}-\d{2}$` or start with `TODO:`.
7. `constraints` has at least one non-empty category from the closed vocabulary.
8. `repositories` has ≥ 1 entry; exactly one has `primary: true`; each entry has `name`, `url`, `description`.
9. `tools[].name` non-empty (if `tools` present); `tools[].url` is optional but must be non-empty when present.
10. `folders[].location` ∈ {`gdrive`, `nas`}; `folders[].purpose` and `folders[].url` non-empty.
11. **DS-only:** `datasets` present with ≥ 1 entry; each entry has `name`, `purpose`, `location` ∈ {`nas`, `gdrive`, `other`}, `url`, `license`, `on_DVC` ∈ {`tracked`, `untracked`, `abandoned`}.
12. **DS-only:** `experiment_log` present and non-empty.
13. **Software:** `datasets` and `experiment_log` must be absent (warn and ignore if present rather than fail).

TODO sentinel strings (`"TODO: ..."`) pass these checks — a TODO is a valid value for any field except the closed-enum fields (`project_type`, `on_DVC`, `folders.location`, `datasets.location`) where the enum value itself is required.

---

## Section icons (rendered doc)

| Section | Icon |
|---|---|
| Header | 🚀 |
| Goal | 🎯 |
| Definition of Done | ✅ |
| Team | 👥 |
| Constraints | ⚙️ |
| Repositories | 🐙 (primary entry prefixed ⭐) |
| Tools | 🔧 |
| Folders | 📁 |
| Datasets | 🗃️ |
| Experiment Log | 📊 |
| TODO inline | 🚧 |

**Constraint category sub-icons:** Performance ⚡ · Accuracy 🎯 · Hardware 📱 · Scalability 📈 · Compliance 🔒 · Deadlines 📅 · Other 🔹

---

## Section order in the rendered doc

1. Header (`# 🚀 <name>` + subtitle `*Type: <type> · generated YYYY-MM-DD*`)
2. 🎯 Goal
3. ✅ Definition of Done
4. 👥 Team (Current / Past subsections)
5. ⚙️ Constraints (per-category subsections)
6. 🐙 Repositories (⭐ primary first, then others)
7. 🔧 Tools (registry order: Slack, GDrive, Jira, Confluence, NAS, Miro, MLFlow, DVC, CVAT, Label Studio, then unknowns)
8. 📁 Folders (grouped by location: GDrive first, then NAS)
9. 🗃️ Datasets *(DS only)*
10. 📊 Experiment Log *(DS only)*
11. Footer (`*Maintained as PROJECT_STATEMENT.yaml in <primary repo>. To update: edit the YAML and re-run /project-statement.*`)

#!/usr/bin/env python3
"""Render a PROJECT_STATEMENT.yaml file to markdown for paste into a Google Doc.

Usage:
    python render.py PROJECT_STATEMENT.yaml > PROJECT_STATEMENT.md

The TODO summary line is printed to stderr; stdout is the rendered markdown.
Exits non-zero on validation failure.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import re
import sys
from collections import defaultdict
from pathlib import Path

import yaml


# ---------- icon registry ----------

SECTION_ICONS = {
    "header": "🚀",
    "goal": "🎯",
    "definition_of_done": "✅",
    "team": "👥",
    "constraints": "⚙️",
    "repositories": "🐙",
    "primary_repo": "⭐",
    "tools": "🔧",
    "folders": "📁",
    "datasets": "🗃️",
    "experiment_log": "📊",
    "todo": "🚧",
}

TOOL_ICONS = {
    "jira": "🗂️",
    "slack": "💬",
    "gdrive": "📁",
    "google drive": "📁",
    "confluence": "📘",
    "nas": "💽",
    "miro": "🧠",
    "mlflow": "📊",
    "dvc": "🧬",
    "cvat": "🏷️",
    "label studio": "🏷️",
}
TOOL_FALLBACK_ICON = "🔧"

LOCATION_ICONS = {
    "gdrive": "📁",
    "nas": "💽",
    "other": "🗄️",
}

CONSTRAINT_CATEGORY_ORDER = [
    "performance",
    "accuracy",
    "hardware",
    "scalability",
    "compliance",
    "deadlines",
    "other",
]

CONSTRAINT_CATEGORY_ICONS = {
    "performance": "⚡",
    "accuracy": "🎯",
    "hardware": "📱",
    "scalability": "📈",
    "compliance": "🔒",
    "deadlines": "📅",
    "other": "🔹",
}

CONSTRAINT_CATEGORY_LABELS = {
    "performance": "Performance",
    "accuracy": "Accuracy",
    "hardware": "Hardware",
    "scalability": "Scalability",
    "compliance": "Compliance",
    "deadlines": "Deadlines",
    "other": "Other",
}

TOOL_RENDER_ORDER = [
    "slack",
    "gdrive",
    "google drive",
    "jira",
    "confluence",
    "nas",
    "miro",
    "mlflow",
    "dvc",
    "cvat",
    "label studio",
]

VALID_PROJECT_TYPES = {"data-science", "software"}
VALID_ON_DVC = {"tracked", "untracked", "abandoned"}
VALID_FOLDER_LOCATIONS = {"gdrive", "nas"}
VALID_DATASET_LOCATIONS = {"nas", "gdrive", "other"}
YYYY_MM_RE = re.compile(r"^\d{4}-\d{2}$")


# ---------- helpers ----------


def _is_todo(value) -> bool:
    return isinstance(value, str) and value.strip().lower().startswith("todo:")


def _todo_render(value: str) -> str:
    """Strip the TODO: prefix and prepend the construction icon."""
    body = value.strip()[len("TODO:") :].strip()
    return f"{SECTION_ICONS['todo']} TODO" + (f": {body}" if body else "")


def _value_or_todo(value: str) -> str:
    """Render a value verbatim, or with the TODO marker if it's a sentinel."""
    if _is_todo(value):
        return _todo_render(value)
    return value


def _tool_icon(name: str) -> str:
    return TOOL_ICONS.get(name.strip().lower(), TOOL_FALLBACK_ICON)


def _location_icon(loc: str) -> str:
    return LOCATION_ICONS.get(loc, LOCATION_ICONS["other"])


# ---------- validation ----------


class ValidationError(Exception):
    pass


def _require(cond: bool, msg: str, errors: list[str]) -> None:
    if not cond:
        errors.append(msg)


def validate(data: dict) -> list[str]:
    errors: list[str] = []

    _require(isinstance(data, dict), "top-level must be a mapping", errors)
    if errors:
        return errors

    name = data.get("name")
    _require(isinstance(name, str) and name.strip(), "`name` is required (non-empty string)", errors)

    ptype = data.get("project_type")
    _require(
        ptype in VALID_PROJECT_TYPES,
        f"`project_type` must be one of {sorted(VALID_PROJECT_TYPES)}",
        errors,
    )
    is_ds = ptype == "data-science"

    goal = data.get("goal")
    _require(isinstance(goal, str) and goal.strip(), "`goal` is required (non-empty string)", errors)

    dod = data.get("definition_of_done") or []
    _require(
        isinstance(dod, list) and len(dod) >= 1 and all(isinstance(x, str) and x.strip() for x in dod),
        "`definition_of_done` must be a list with >= 1 non-empty string",
        errors,
    )

    team = data.get("team") or []
    _require(isinstance(team, list) and len(team) >= 1, "`team` must be a list with >= 1 entry", errors)
    if isinstance(team, list):
        for i, m in enumerate(team):
            prefix = f"team[{i}]"
            if not isinstance(m, dict):
                errors.append(f"{prefix} must be a mapping")
                continue
            for k in ("name", "role", "joined"):
                v = m.get(k)
                _require(isinstance(v, str) and v.strip(), f"{prefix}.{k} required", errors)
            joined = m.get("joined", "")
            if isinstance(joined, str) and not _is_todo(joined):
                _require(
                    YYYY_MM_RE.match(joined) is not None,
                    f"{prefix}.joined must be YYYY-MM (got {joined!r})",
                    errors,
                )
            left = m.get("left")
            if isinstance(left, str) and left.strip() and not _is_todo(left):
                _require(
                    YYYY_MM_RE.match(left) is not None,
                    f"{prefix}.left must be YYYY-MM (got {left!r})",
                    errors,
                )

    constraints = data.get("constraints") or {}
    _require(isinstance(constraints, dict), "`constraints` must be a mapping", errors)
    if isinstance(constraints, dict):
        has_any = any(
            isinstance(v, list) and len(v) > 0
            for k, v in constraints.items()
            if k in CONSTRAINT_CATEGORY_ORDER
        )
        _require(has_any, "`constraints` must have at least one non-empty category", errors)
        for k in constraints:
            if k not in CONSTRAINT_CATEGORY_ORDER:
                errors.append(
                    f"`constraints.{k}` is not in the closed vocabulary "
                    f"{CONSTRAINT_CATEGORY_ORDER}"
                )

    repos = data.get("repositories") or []
    _require(
        isinstance(repos, list) and len(repos) >= 1,
        "`repositories` must be a list with >= 1 entry",
        errors,
    )
    if isinstance(repos, list):
        primary_count = sum(1 for r in repos if isinstance(r, dict) and r.get("primary") is True)
        _require(
            primary_count == 1,
            f"exactly one repository must have primary: true (found {primary_count})",
            errors,
        )
        for i, r in enumerate(repos):
            prefix = f"repositories[{i}]"
            if not isinstance(r, dict):
                errors.append(f"{prefix} must be a mapping")
                continue
            for k in ("name", "url", "description"):
                v = r.get(k)
                _require(isinstance(v, str) and v.strip(), f"{prefix}.{k} required", errors)

    tools = data.get("tools") or []
    if tools:
        _require(isinstance(tools, list), "`tools` must be a list", errors)
        for i, t in enumerate(tools):
            prefix = f"tools[{i}]"
            if not isinstance(t, dict):
                errors.append(f"{prefix} must be a mapping")
                continue
            _require(
                isinstance(t.get("name"), str) and t["name"].strip(),
                f"{prefix}.name required",
                errors,
            )
            # `url` is optional — some tools (e.g. Slack) have no useful link.
            url = t.get("url")
            if url is not None:
                _require(
                    isinstance(url, str) and url.strip(),
                    f"{prefix}.url must be a non-empty string when present",
                    errors,
                )

    folders = data.get("folders") or []
    if folders:
        _require(isinstance(folders, list), "`folders` must be a list", errors)
        for i, f in enumerate(folders):
            prefix = f"folders[{i}]"
            if not isinstance(f, dict):
                errors.append(f"{prefix} must be a mapping")
                continue
            loc = f.get("location")
            _require(
                loc in VALID_FOLDER_LOCATIONS,
                f"{prefix}.location must be one of {sorted(VALID_FOLDER_LOCATIONS)}",
                errors,
            )
            for k in ("purpose", "url"):
                v = f.get(k)
                _require(isinstance(v, str) and v.strip(), f"{prefix}.{k} required", errors)

    if is_ds:
        datasets = data.get("datasets") or []
        _require(
            isinstance(datasets, list) and len(datasets) >= 1,
            "DS projects require `datasets` with >= 1 entry (TODO entry allowed)",
            errors,
        )
        if isinstance(datasets, list):
            for i, d in enumerate(datasets):
                prefix = f"datasets[{i}]"
                if not isinstance(d, dict):
                    errors.append(f"{prefix} must be a mapping")
                    continue
                for k in ("name", "purpose", "url", "license"):
                    v = d.get(k)
                    _require(isinstance(v, str) and v.strip(), f"{prefix}.{k} required", errors)
                loc = d.get("location")
                _require(
                    loc in VALID_DATASET_LOCATIONS,
                    f"{prefix}.location must be one of {sorted(VALID_DATASET_LOCATIONS)}",
                    errors,
                )
                on_dvc = d.get("on_DVC")
                _require(
                    on_dvc in VALID_ON_DVC,
                    f"{prefix}.on_DVC must be one of {sorted(VALID_ON_DVC)}",
                    errors,
                )
        explog = data.get("experiment_log")
        _require(
            isinstance(explog, str) and explog.strip(),
            "DS projects require `experiment_log` (Google Sheet URL or TODO sentinel)",
            errors,
        )

    return errors


# ---------- rendering ----------


def _line(buf: list[str], s: str = "") -> None:
    buf.append(s)


def _bullet(buf: list[str], s: str, indent: int = 0) -> None:
    buf.append(" " * indent + f"- {s}")


def _render_header(buf: list[str], data: dict) -> None:
    name = _value_or_todo(str(data["name"]))
    _line(buf, f"# {SECTION_ICONS['header']} {name}")
    today = _dt.date.today().isoformat()
    _line(buf, f"*Type: {data['project_type']} · generated {today}*")
    _line(buf)


def _render_goal(buf: list[str], data: dict) -> None:
    _line(buf, f"## {SECTION_ICONS['goal']} Goal")
    _line(buf)
    _line(buf, _value_or_todo(str(data["goal"])).strip())
    _line(buf)


def _render_dod(buf: list[str], data: dict) -> None:
    _line(buf, f"## {SECTION_ICONS['definition_of_done']} Definition of Done")
    _line(buf)
    for item in data["definition_of_done"]:
        _bullet(buf, _value_or_todo(item))
    _line(buf)


def _team_sort_key(member: dict) -> tuple:
    joined = member.get("joined", "")
    return (0 if _is_todo(joined) else 1, joined)


def _render_team(buf: list[str], data: dict) -> None:
    _line(buf, f"## {SECTION_ICONS['team']} Team")
    _line(buf)

    members = list(data.get("team") or [])
    current = [m for m in members if not m.get("left")]
    past = [m for m in members if m.get("left")]
    current.sort(key=_team_sort_key)
    past.sort(key=_team_sort_key)

    def _render_member(m: dict, with_end: bool) -> str:
        name = _value_or_todo(str(m["name"]))
        role = _value_or_todo(str(m["role"]))
        joined = _value_or_todo(str(m["joined"]))
        if with_end:
            left = _value_or_todo(str(m.get("left", "")))
            tail = f"{joined} → {left}"
        else:
            tail = f"since {joined}"
        return f"{name} — {role} — {tail}"

    if current:
        _line(buf, "### Current")
        for m in current:
            _bullet(buf, _render_member(m, with_end=False))
        _line(buf)
    if past:
        _line(buf, "### Past")
        for m in past:
            _bullet(buf, _render_member(m, with_end=True))
        _line(buf)


def _render_constraints(buf: list[str], data: dict) -> None:
    constraints = data.get("constraints") or {}
    if not any(constraints.get(k) for k in CONSTRAINT_CATEGORY_ORDER):
        return
    _line(buf, f"## {SECTION_ICONS['constraints']} Constraints")
    _line(buf)
    for cat in CONSTRAINT_CATEGORY_ORDER:
        entries = constraints.get(cat) or []
        if not entries:
            continue
        icon = CONSTRAINT_CATEGORY_ICONS[cat]
        label = CONSTRAINT_CATEGORY_LABELS[cat]
        _line(buf, f"### {icon} {label}")
        for entry in entries:
            _bullet(buf, _value_or_todo(entry))
        _line(buf)


def _render_repositories(buf: list[str], data: dict) -> None:
    repos = data.get("repositories") or []
    if not repos:
        return
    _line(buf, f"## {SECTION_ICONS['repositories']} Repositories")
    _line(buf)
    ordered = sorted(repos, key=lambda r: 0 if r.get("primary") else 1)
    for r in ordered:
        marker = f"{SECTION_ICONS['primary_repo']} " if r.get("primary") else ""
        name = _value_or_todo(str(r["name"]))
        desc = _value_or_todo(str(r["description"]))
        url = _value_or_todo(str(r["url"]))
        _bullet(buf, f"{marker}**{name}** — {desc}")
        _bullet(buf, url, indent=4)
    _line(buf)


def _tool_sort_key(name: str) -> tuple:
    lname = name.strip().lower()
    if lname in TOOL_RENDER_ORDER:
        return (0, TOOL_RENDER_ORDER.index(lname))
    return (1, lname)


def _render_tools(buf: list[str], data: dict) -> None:
    tools = data.get("tools") or []
    if not tools:
        return
    _line(buf, f"## {SECTION_ICONS['tools']} Tools")
    _line(buf)
    grouped: dict[str, list[dict]] = defaultdict(list)
    for t in tools:
        grouped[str(t["name"]).strip()].append(t)
    for name in sorted(grouped, key=_tool_sort_key):
        icon = _tool_icon(name)
        entries = grouped[name]
        if len(entries) == 1:
            t = entries[0]
            note = t.get("note")
            note_part = f" — {_value_or_todo(note)}" if isinstance(note, str) and note.strip() else ""
            url = t.get("url")
            url_part = f" — {_value_or_todo(str(url))}" if isinstance(url, str) and url.strip() else ""
            _bullet(buf, f"{icon} **{name}**{url_part}{note_part}")
        else:
            _bullet(buf, f"{icon} **{name}**")
            for t in entries:
                note = t.get("note")
                note_part = f" — {_value_or_todo(note)}" if isinstance(note, str) and note.strip() else ""
                url = t.get("url")
                url_part = _value_or_todo(str(url)) if isinstance(url, str) and url.strip() else ""
                _bullet(buf, f"{url_part}{note_part}".lstrip(" —"), indent=4)
    _line(buf)


def _render_folders(buf: list[str], data: dict) -> None:
    folders = data.get("folders") or []
    if not folders:
        return
    _line(buf, f"## {SECTION_ICONS['folders']} Folders")
    _line(buf)
    by_loc: dict[str, list[dict]] = defaultdict(list)
    for f in folders:
        by_loc[f["location"]].append(f)
    for loc in ("gdrive", "nas"):
        entries = by_loc.get(loc) or []
        if not entries:
            continue
        icon = _location_icon(loc)
        label = "GDrive" if loc == "gdrive" else "NAS"
        _line(buf, f"### {icon} {label}")
        for f in entries:
            purpose = _value_or_todo(str(f["purpose"]))
            url = _value_or_todo(str(f["url"]))
            _bullet(buf, f"{purpose} — {url}")
        _line(buf)


def _render_datasets(buf: list[str], data: dict) -> None:
    if data.get("project_type") != "data-science":
        return
    datasets = data.get("datasets") or []
    _line(buf, f"## {SECTION_ICONS['datasets']} Datasets")
    _line(buf)
    for d in datasets:
        name = _value_or_todo(str(d["name"]))
        purpose = _value_or_todo(str(d["purpose"]))
        _bullet(buf, f"**{name}** — {purpose}")
        loc = d.get("location", "other")
        icon = _location_icon(loc)
        label = {"gdrive": "GDrive", "nas": "NAS", "other": "Other"}.get(loc, "Other")
        url = _value_or_todo(str(d["url"]))
        _bullet(buf, f"{icon} {label} — {url}", indent=4)
        license_part = _value_or_todo(str(d["license"]))
        on_dvc = d.get("on_DVC", "untracked")
        _bullet(buf, f"license: {license_part}; on_DVC: {on_dvc}", indent=4)
        meta_bits = []
        version = d.get("version")
        if isinstance(version, str) and version.strip():
            meta_bits.append(f"version: {_value_or_todo(version)}")
        notes = d.get("notes")
        if isinstance(notes, str) and notes.strip():
            meta_bits.append(_value_or_todo(notes))
        if meta_bits:
            _bullet(buf, "; ".join(meta_bits), indent=4)
    _line(buf)


def _render_experiment_log(buf: list[str], data: dict) -> None:
    if data.get("project_type") != "data-science":
        return
    explog = data.get("experiment_log")
    if not isinstance(explog, str) or not explog.strip():
        return
    _line(buf, f"## {SECTION_ICONS['experiment_log']} Experiment Log")
    _line(buf)
    _line(buf, _value_or_todo(explog))
    _line(buf)


def _render_footer(buf: list[str], data: dict) -> None:
    primary = next(
        (r for r in data.get("repositories", []) if r.get("primary")),
        None,
    )
    repo_name = primary["name"] if primary else "<primary repo>"
    _line(buf, "---")
    _line(
        buf,
        f"*Maintained as `PROJECT_STATEMENT.yaml` in {repo_name}. "
        "To update: edit the YAML and re-run `/project-statement`.*",
    )


def render(data: dict) -> str:
    buf: list[str] = []
    _render_header(buf, data)
    _render_goal(buf, data)
    _render_dod(buf, data)
    _render_team(buf, data)
    _render_constraints(buf, data)
    _render_repositories(buf, data)
    _render_tools(buf, data)
    _render_folders(buf, data)
    _render_datasets(buf, data)
    _render_experiment_log(buf, data)
    _render_footer(buf, data)
    return "\n".join(buf).rstrip() + "\n"


# ---------- TODO accounting ----------


def _walk_strings(obj):
    if isinstance(obj, str):
        yield obj
    elif isinstance(obj, dict):
        for v in obj.values():
            yield from _walk_strings(v)
    elif isinstance(obj, list):
        for v in obj:
            yield from _walk_strings(v)


def count_todos(data: dict) -> int:
    return sum(1 for s in _walk_strings(data) if _is_todo(s))


# ---------- entrypoint ----------


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("yaml_path", type=Path, help="path to PROJECT_STATEMENT.yaml")
    parser.add_argument(
        "--check",
        action="store_true",
        help="validate only; do not render",
    )
    args = parser.parse_args(argv)

    try:
        with args.yaml_path.open() as f:
            data = yaml.safe_load(f)
    except FileNotFoundError:
        print(f"error: {args.yaml_path} not found", file=sys.stderr)
        return 2
    except yaml.YAMLError as e:
        print(f"error: failed to parse YAML: {e}", file=sys.stderr)
        return 2

    errors = validate(data)
    if errors:
        print("validation failed:", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        return 1

    if args.check:
        print(f"ok ({count_todos(data)} TODO(s))", file=sys.stderr)
        return 0

    md = render(data)
    sys.stdout.write(md)
    print(f"rendered {len(md.splitlines())} lines · {count_todos(data)} TODO(s)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

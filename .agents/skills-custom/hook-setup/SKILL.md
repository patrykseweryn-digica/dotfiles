---
name: hook-setup
description: "Set up or repair Python and JS/TS pre-commit hooks with repo-native tooling."
argument-hint: "[repo path] [python|js|both]"
---

# Setup Pre-Commit Multi

Set up or repair pre-commit checks without swapping the repo's package manager or overwriting existing config.

## Workflow

1. Inspect first:
   - `git status -sb`
   - `pyproject.toml`, `uv.lock`
   - `package.json`, lockfiles
   - existing `.pre-commit-config.yaml`, `.husky/`, `lint-staged`, `eslint.config.*`, `.prettier*`
2. Read `references/policy.md` before choosing tools, hook stages, or verification commands.
3. Choose scope:
   - Python only: read `references/python.md`
   - JS/TS only: read `references/js-ts.md`
   - both: read both, then keep the two systems independent unless the repo already integrates them
4. Preserve existing config. Patch narrowly; do not replace working hook files or package scripts without a clear reason.
5. Check current docs/releases before adding pinned hook versions or new packages.
6. Install with the repo's package manager/runtime.
7. Verify with the exact hook commands and fix resulting issues.

## Rules

- Python uses `uv` by default here. Do not introduce pip/pipx/poetry unless the repo already uses them or the user approves.
- JS/TS uses the detected package manager consistently: pnpm, bun, yarn, then npm fallback.
- Do not auto-commit after setup.
- Do not add new lint/type tools when equivalent repo tooling already exists; wire existing commands into hooks.
- If both Python and JS/TS are present, ask before setting up both unless the user already requested both.

## Verify

- Python: `uv run pre-commit run --all-files`
- JS/TS: run the hook command directly, then run the package manager lint/typecheck scripts that the hook calls
- Final report: files changed, installed packages, commands run, remaining manual steps

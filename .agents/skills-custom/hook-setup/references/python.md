# Python Pre-Commit

Use for Python projects with `pyproject.toml`. Prefer `uv` because this dotfiles setup treats it as the Python default.

Apply `references/policy.md` before adding hooks or choosing stages.

## Inspect

- Read `pyproject.toml` for dependency groups, ruff config, pyright config, pytest config, package layout.
- Check for `.pre-commit-config.yaml`; if present, patch it instead of replacing it.
- Check for `uv.lock`; if missing, confirm whether the repo actually uses `uv`.
- Check whether `ruff`, `pyright`, `pytest`, or equivalent commands already exist in project docs or scripts.

## Install

If `pre-commit` is missing and the repo uses `uv`:

```bash
uv add --dev pre-commit
```

If the repo already has a dev dependency group convention, follow it.

## Configure

Resolve hook versions at use time. Prefer `gh api` when available:

```bash
gh api repos/astral-sh/ruff-pre-commit/releases/latest --jq .tag_name
gh api repos/pre-commit/pre-commit-hooks/releases/latest --jq .tag_name
gh api repos/RobertCraigie/pyright-python/releases/latest --jq .tag_name
gh api repos/compilerla/conventional-pre-commit/releases/latest --jq .tag_name
```

Fallback:

```bash
curl -fsSL https://api.github.com/repos/astral-sh/ruff-pre-commit/releases/latest | jq -r .tag_name
curl -fsSL https://api.github.com/repos/pre-commit/pre-commit-hooks/releases/latest | jq -r .tag_name
curl -fsSL https://api.github.com/repos/RobertCraigie/pyright-python/releases/latest | jq -r .tag_name
curl -fsSL https://api.github.com/repos/compilerla/conventional-pre-commit/releases/latest | jq -r .tag_name
```

For new `.pre-commit-config.yaml`, include only hooks the repo needs:

```yaml
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: <ruff-pre-commit-latest>
    hooks:
      - id: ruff
        args: [--fix, --exit-non-zero-on-fix]
      - id: ruff-format

  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: <pre-commit-hooks-latest>
    hooks:
      - id: check-ast
      - id: check-json
      - id: check-yaml
      - id: check-toml
      - id: check-added-large-files
      - id: check-merge-conflict
      - id: check-case-conflict
      - id: check-symlinks
      - id: end-of-file-fixer
      - id: trailing-whitespace
```

Add `pyright` only when the project already uses it or the user asks for typechecking:

```yaml
  - repo: https://github.com/RobertCraigie/pyright-python
    rev: <pyright-python-latest>
    hooks:
      - id: pyright
```

Add `conventional-pre-commit` only when the repo uses Conventional Commits or the user asks for commit-msg enforcement:

```yaml
  - repo: https://github.com/compilerla/conventional-pre-commit
    rev: <conventional-pre-commit-latest>
    hooks:
      - id: conventional-pre-commit
        stages: [commit-msg]
```

Replace all `<...-latest>` placeholders with resolved release tags before writing config. Do not leave placeholders in repo files.

## Pyright Notes

- Do not dump application dependencies into `additional_dependencies` by default.
- Prefer a project-managed pyright invocation when one already exists.
- If the hook cannot import project dependencies, either use the repo's existing typecheck command outside pre-commit or add only the minimal missing dependencies with a comment explaining why.

## Install Hooks

```bash
uv run pre-commit install --install-hooks
uv run pre-commit install --hook-type commit-msg
```

Install `commit-msg` only if a commit-msg hook is configured.

## Verify

```bash
uv run pre-commit run --all-files
```

If hooks modify files, inspect the diff and rerun until clean.

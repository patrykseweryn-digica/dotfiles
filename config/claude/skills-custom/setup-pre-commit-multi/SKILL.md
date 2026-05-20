---
name: setup-pre-commit-multi
description: Multi-language pre-commit hook setup for Python (pre-commit + ruff + pyright + conventional-commits) AND JS/TS (Husky + lint-staged + ESLint + Prettier). Auto-detects project type from pyproject.toml/package.json and configures both when present. Use for polyglot repos or when you need Python tooling — for JS-only projects prefer `setup-pre-commit` (mattpocock Husky-only).
---

# Setup Pre-Commit Hooks

Detect project type and set up appropriate pre-commit hooks.

## Step 1: Detect Project Type

- `pyproject.toml` → **Python**
- `package.json` → **JS/TS**
- Both → ask the user which to set up (or both)

---

## Python Project

### 1. Install pre-commit

```bash
uv add --dev pre-commit
```

### 2. Create `.pre-commit-config.yaml`

```yaml
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.9.6
    hooks:
      - id: ruff
        args: [--fix, --exit-non-zero-on-fix]
      - id: ruff-format

  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: check-ast
      - id: check-json
      - id: check-yaml
      - id: check-toml
      - id: check-added-large-files
      - id: check-merge-conflict
      - id: check-case-conflict
      - id: check-symlinks
      - id: check-executables-have-shebangs
      - id: end-of-file-fixer
      - id: trailing-whitespace

  - repo: https://github.com/RobertCraigie/pyright-python
    rev: v1.1.394
    hooks:
      - id: pyright
        additional_dependencies:
          - pytest

  - repo: https://github.com/compilerla/conventional-pre-commit
    rev: v4.0.0
    hooks:
      - id: conventional-pre-commit
        stages: [commit-msg]
```

**Adapt**:
- If `pyproject.toml` lists dependencies needed by pyright (pydantic, sqlalchemy, etc.), add them to `additional_dependencies`
- Check for latest hook versions before using the pinned ones above

### 3. Install hooks

```bash
uv run pre-commit install --install-hooks
uv run pre-commit install --hook-type commit-msg
```

### 4. Verify

Run `uv run pre-commit run --all-files` and fix any issues.

---

## JS/TS Project

### 1. Detect package manager

Check for `pnpm-lock.yaml` (pnpm), `yarn.lock` (yarn), `bun.lockb` (bun), `package-lock.json` (npm). Default to npm.

### 2. Install dependencies

Install as devDependencies:

```
husky lint-staged prettier eslint eslint-config-prettier @eslint/js
```

If TypeScript: also `typescript-eslint`.
If React: also `eslint-plugin-react`.

### 3. Initialize Husky

```bash
npx husky init
```

This creates `.husky/` and adds `prepare: "husky"` to package.json.

### 4. Create `.husky/pre-commit`

```
<pm> run typecheck
npx lint-staged
```

Replace `<pm>` with detected package manager. If no `typecheck` script exists in package.json, omit that line and tell the user.

### 5. Configure lint-staged in `package.json`

```json
{
  "lint-staged": {
    "*.{js,mjs,cjs,ts,mts,cts,jsx,tsx}": [
      "eslint --fix",
      "prettier --write"
    ],
    "*.md": [
      "prettier --write"
    ]
  }
}
```

### 6. Create ESLint config (if missing)

Only if no `eslint.config.*` exists. Create `eslint.config.mjs` with flat config:

```js
import js from "@eslint/js";
import tseslint from "typescript-eslint";
import prettier from "eslint-config-prettier";
import { defineConfig } from "eslint/config";

export default defineConfig([
  { ignores: ["**/dist/**", "**/build/**", "**/node_modules/**"] },
  js.configs.recommended,
  ...tseslint.configs.recommendedTypeChecked,
  {
    languageOptions: {
      parserOptions: { projectService: true },
    },
    rules: {
      "no-unused-vars": "off",
      "@typescript-eslint/no-unused-vars": "warn",
      "@typescript-eslint/no-floating-promises": "error",
      "@typescript-eslint/no-misused-promises": "error",
    },
  },
  prettier,
]);
```

**Adapt**: Add React plugin if React project. Always put `prettier` LAST.

### 7. Create `.prettierignore` (if missing)

```
node_modules
dist
build
coverage
pnpm-lock.yaml
package-lock.json
yarn.lock
```

### 8. Verify

Stage a file and run `npx lint-staged` to verify it works.

---

## Important

- Do NOT auto-commit after setup — let the user review and commit manually
- Python: `uv` is the only package manager (never pip)
- JS/TS: always put `eslint-config-prettier` LAST in ESLint config
- Husky v9+ doesn't need shebangs in hook files

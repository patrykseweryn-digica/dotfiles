# JS/TS Pre-Commit

Use for projects with `package.json`. Keep commands aligned with the detected package manager.

Apply `references/policy.md` before adding packages, hook stages, or lint/typecheck commands.

## Inspect

- Detect package manager from lockfiles: `pnpm-lock.yaml`, `bun.lockb`, `yarn.lock`, `package-lock.json`.
- Read `package.json` scripts before adding new ones.
- Check existing `.husky/`, `lint-staged`, `eslint.config.*`, `.eslintrc*`, `.prettier*`, `tsconfig*.json`.
- Detect TypeScript from `tsconfig*.json` or TypeScript dependencies.
- Detect React from dependencies and source extensions.

## Package Manager Commands

- pnpm: `pnpm exec <tool>` and `pnpm add -D <pkg>`
- bun: `bunx <tool>` and `bun add -d <pkg>`
- yarn: `yarn <tool>` or `yarn dlx <tool>` depending on project version
- npm: `npx <tool>` and `npm install -D <pkg>`

Use one package manager consistently.

## Install

Add only missing dev dependencies. Common base:

```text
husky lint-staged prettier eslint eslint-config-prettier @eslint/js
```

Add `typescript-eslint` only for TypeScript. Add React plugins only for React projects.

## Husky

Initialize only if `.husky/` is missing:

```bash
<pm-exec> husky init
```

For an existing Husky setup, patch `.husky/pre-commit` instead of reinitializing.

Hook body should call repo scripts when they exist:

```bash
<pm> run typecheck
<pm-exec> lint-staged
```

Omit `typecheck` if there is no script. Do not invent a typecheck script unless the project has TypeScript and the user wants it.

## Lint-Staged

Prefer package-local config if already present. For a new config:

```json
{
  "lint-staged": {
    "*.{js,mjs,cjs,jsx}": [
      "eslint --fix",
      "prettier --write"
    ],
    "*.{ts,mts,cts,tsx}": [
      "eslint --fix",
      "prettier --write"
    ],
    "*.{json,md,yml,yaml,css,scss}": [
      "prettier --write"
    ]
  }
}
```

Remove TS globs for JS-only projects.

## ESLint

If `eslint.config.*` exists, patch it. If no ESLint config exists, create the smallest flat config matching the project.

JS-only baseline:

```js
import js from "@eslint/js";
import prettier from "eslint-config-prettier";
import { defineConfig } from "eslint/config";

export default defineConfig([
  { ignores: ["**/dist/**", "**/build/**", "**/coverage/**", "**/node_modules/**"] },
  js.configs.recommended,
  prettier,
]);
```

TypeScript baseline:

```js
import js from "@eslint/js";
import prettier from "eslint-config-prettier";
import tseslint from "typescript-eslint";
import { defineConfig } from "eslint/config";

export default defineConfig([
  { ignores: ["**/dist/**", "**/build/**", "**/coverage/**", "**/node_modules/**"] },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  prettier,
]);
```

Use type-aware `recommendedTypeChecked` only when the repo already has reliable TS project config and the user wants stricter checks. Always keep `eslint-config-prettier` last.

## Verify

Run the hook command directly:

```bash
<pm-exec> lint-staged
```

Then run any scripts the hook calls, such as:

```bash
<pm> run lint
<pm> run typecheck
```

If no staged files exist, stage a harmless already-modified file only when appropriate, then unstage after verification if needed.

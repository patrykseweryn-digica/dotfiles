# Pre-Commit Policy

Use this before choosing tools, hook stages, or verification commands.

## Speed Budget

- `pre-commit` must stay fast enough for frequent commits.
- Default to formatting, linting, cheap syntax checks, and staged-file checks.
- Put slow full test suites, production builds, and broad scans in `pre-push` or CI unless the user asks otherwise.

## Hook Stages

- `pre-commit`: format, lint, cheap static checks, staged-file secret checks.
- `commit-msg`: commit message format only.
- `pre-push`: typecheck, full tests, builds, or expensive scans when the repo benefits from local gating.

## Fail Modes

- Formatters may auto-fix and fail when they changed files.
- Linters may auto-fix only when the tool is already configured that way or the user agrees.
- Typecheck, tests, builds, and secret scanning must fail hard without mutating files.

## Existing Config First

- Prefer existing config and package scripts over new tool config.
- Hooks should call the same commands maintainers already run.
- Do not create a second source of truth for lint/type rules.

## CI Parity

- Critical local checks should have a CI equivalent or call the same scripts CI uses.
- If a hook introduces a critical check not present in CI, report that gap.

## Staged vs All Files

- Normal commits should run staged-file checks.
- Bootstrap verification should run all-files checks once.
- Do not make every commit run all-files checks in large repos.

## Monorepos

- Detect workspaces before installing JS hooks.
- Prefer root workspace commands.
- Do not install separate Husky setups in packages unless the repo already does that or the user asks.

## Generated Files

- Exclude generated outputs such as `dist`, `build`, `coverage`, generated clients, and vendored code.
- Avoid formatting lockfiles unless the repo already does.
- Keep ignore patterns aligned across Prettier, ESLint, and pre-commit excludes.

## New Dependency Threshold

- Add a tool only when repo signals justify it: source files, existing CI, docs, or user request.
- Prefer wiring existing tools before adding new dependencies.
- Ask before adding noisy or policy-heavy tools such as secret scanners, markdown lint, full typecheck, or commit-message enforcement.

## Versions

- Resolve latest release tags when creating new hook config.
- For existing hooks, do not run broad autoupdates unless the user asks; autoupdate can create a large unrelated diff.

## Large Repo Mode

- Avoid hooks that scan the whole repo per commit.
- Use staged/pre-commit modes where supported.
- Reserve full scans for bootstrap verification, pre-push, or CI.

## Escape Hatch

- Report how to run hooks manually.
- Do not recommend `--no-verify` except as an emergency escape hatch with a follow-up fix.

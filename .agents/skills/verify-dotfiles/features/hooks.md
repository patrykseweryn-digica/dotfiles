# Commit hooks

The installed prek hook (prek 0.5.4 or newer) selects tests from staged paths.
Smoke hooks include matching deletions; ShellCheck only checks existing files.
Ordinary documentation such as `README.md` and `docs/agents/domain.md` does not
select smoke tests. Agent instruction files are runtime inputs. Repo-layout
policy inputs include `.agents/skills/` (including the allowed `verify-dotfiles`
skill), `.agents/skills-custom`, the Claude `skills-custom` symlink path, and the
legacy root `skills-lock.json` path. The non-smoke `architecture-map` check always
runs, even on docs-only commits. `just test` and the CI check job run all hooks,
independent of the staged paths.

Run `prek validate-config .pre-commit-config.yaml` and `just test`. The
`hook-filters-smoke` hook checks the real prek selector against the fixture
input inventory in `scripts/smoke-hook-filters.py`. It also checks literal
checkout paths in shell fixture entries and follows their ShellCheck source
annotations independently of the inventory. This is not a complete dependency
scan. Update the inventory and `.pre-commit-config.yaml` together when a fixture
starts using another checkout script, config or data file. Include sourced and
executed dependencies and platform branches; distinguish checkout inputs from
generated fixtures. The audit also checks selection for representative forbidden
paths before and after staging them in a disposable Git repo. Layout checks
for required repo-local docs and arbitrary broken symlinks still run in the
full suite; the staged filter does not cover ordinary docs or unknown symlinks.

For staged selection, use an isolated checkout with the candidate config,
`prek install`, and an empty disposable index diff. Stage a harmless edit to
`README.md` and use `git commit` to confirm only `architecture-map` runs. Stage
a deletion of `docs/architecture.json` and confirm `git commit` rejects it;
restore the artifact before proceeding. Stage a harmless edit to
`scripts/groups.sh` and confirm `local-update-smoke` and the other consumers run.
Stage a harmless edit to `Makefile` and confirm `install-groups-smoke` runs.
Stage a deletion of `scripts/host-tools.sh` and confirm its consumers are
selected and the commit fails. Restore it, then stage each policy probe on its
own: a nested non-Markdown file under `.agents/skills/`, a file at
`.agents/skills-custom`, a file beneath `.agents/skills-custom/`, a symlink at
`config/claude/skills-custom` to `../../.agents/skills`, a root
`skills-lock.json` file, and a file beneath `skills-lock.json/`. Confirm
`agent-repo-layout-smoke` rejects each; an edit under
`.agents/skills/verify-dotfiles/` should pass that hook.
Use `prek run --dry-run --no-hide-status --verbose` to inspect staged selection;
do not stage fixture edits in the real checkout.

For the dependency-audit regression, remove `scripts/groups.sh` from both the
`local-update-smoke` inventory and its `files:` regex in the isolated checkout.
Run `prek run hook-filters-smoke --all-files`; it must report
`local-update-smoke: files filter misses scripts/groups.sh`.

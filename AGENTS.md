# Dotfiles instructions

Resolve the following paths from the repository root.

## Agent skills

### Issue tracker

Use GitHub Issues in `p-severin/dotfiles`.
See `docs/agents/issue-tracker.md`.

### Triage labels

Use the five standard roles. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context. See `docs/agents/domain.md`.

## Skill sources

Remote skills intentionally track current upstream. Do not pin them to commits
or retain obsolete copies to keep installation green. Before changing live
skill state, validate every inventory entry against current upstream; reconcile
removed or renamed skills explicitly and fail before modifying runtimes.

## Verification

Before changes, applying config to a machine, or committing, use
`.agents/skills/verify-dotfiles/SKILL.md`. Run its relevant feature recipes
after changes and `just check` before commits. Compare live doctor failures
with the baseline; investigate every new failure. Do not bypass failed hooks
or claim Linux verification without a Linux run. Keep proof artifacts local.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.

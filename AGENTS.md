# Dotfiles instructions

Resolve the following paths from the repository root.

## Issue tracker

Use GitHub Issues; read `docs/agents/issue-tracker.md` before ticket work.

## Triage labels

Use the five standard roles; read `docs/agents/triage-labels.md` for triage.

## Domain docs

Single-context; read `docs/agents/domain.md` before domain exploration.

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

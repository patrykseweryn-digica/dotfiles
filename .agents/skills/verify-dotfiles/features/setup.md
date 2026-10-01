# Setup and synchronization

Install or apply dotfiles while preserving runtime credentials and sessions.

## Sub-features

- `setup` creates links and invokes agent adapters in a disposable HOME.
- `sync` applies repository config and detects drift on a second read.
- `portable-shell` starts Zsh on simulated macOS/Linux layouts.

## How to get to it (user POV)

- `just install` for full setup.
- `just update-dotfiles` for config only.
- `just skills-preflight` to resolve current upstream skills without applying.
- `just push-mcp`, `just push-skills`, `just push-plugins`, `just push`.

## Driving it with Bash smoke scripts

Preconditions: dependencies from SKILL.md; run from the checkout root.

- **Install and repeat.** Run `bash scripts/smoke-install-dotfiles.sh` and
  `bash scripts/smoke-plugin-install.sh`. They drive the public install/update
  recipes with an isolated HOME and inspect links, package/config state,
  preserved credentials, repeated setup and failures.
- **Stage and apply skills.** Run `bash scripts/smoke-skill-install.sh`.
  Require current content in every runtime, no live changes after staging or
  network failures, rollback after apply failures, and no new backup on an
  unchanged repeated push.
- **Sync public entries.** Run `bash scripts/smoke-agent-sync-interface.sh`.
  Pull previews, cancellation/conflicts and public push entry points are
  exercised without importing or replacing live user preferences.
- **Start shell.** Run `bash scripts/smoke-zshrc-startup.sh`. Require clean
  startup, correct platform paths and Cursor/Grok command precedence.
- **Proof.** Capture stdout/stderr and exit codes; each script must exit zero.

## Gotchas

- `just install` and config push can replace local preferences and skills.
  Use fixture scripts for testing; back up and review before live application.
- SSH, sudo and external downloads are simulated by smoke tests. The separate
  upstream CI preflight and a live `just skills-preflight` use real networks;
  report which boundary was exercised.
- Darwin/Linux uname fixtures do not replace actual Linux CI execution.

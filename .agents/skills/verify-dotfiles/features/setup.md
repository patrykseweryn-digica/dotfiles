# Setup and synchronization

Install or apply dotfiles while preserving runtime credentials and sessions.

## Sub-features

- `setup` creates links and invokes agent adapters in a disposable HOME.
- `sync` applies repository config and detects drift on a second read.
- `update` plans local state, preserves export-required additions, applies
  independent settings/MCP/link/hook categories, and checks the final state.
- `export` prepares settings, MCP, skills, plugins, and recognized tools in one
  transaction.
- `portable-shell` starts Zsh on simulated macOS/Linux layouts.

## How to get to it (user POV)

- `just install` for full setup.
- `just sync` for a fast-forward pull and controlled local/upstream updates.
- `just export` for one confirmed portable export into a clean checkout.

## Driving it with Bash smoke scripts

Preconditions: dependencies from SKILL.md; run from the checkout root.

- **Install and repeat.** Run `bash scripts/smoke-install-dotfiles.sh` and
  `bash scripts/smoke-plugin-install.sh`. They drive the public install recipe
  with an isolated HOME through fresh, partial, converged, failed and repeated
  states on the platform matrix. External installers are stubbed.
- **Plan and update.** Run `bash scripts/smoke-update-local.sh`. It drives
  public `just sync` in an isolated HOME and checkout, checks a blocked export
  alongside successful independent categories and upstream refreshes, then
  proves a compatible repeat causes no unnecessary downloads or installs.
  The caller starts with an older Node; the final check must see the Node
  and npm CLIs that the refresh installed.
- **Export once.** Run `bash scripts/smoke-export.sh`. It checks the clean-tree
  gate, one confirmation, settings allowlists, MCP conflict/privacy rejection,
  skill upstream/rename gates, plugin providers, recognized and unknown tools,
  rollback, and absence of staging, commits, pushes, or live mutations.
- **Stage and apply skills.** Run `bash scripts/smoke-skill-install.sh`.
  Require current content in every runtime, no live changes after staging or
  network failures, rollback after apply failures, and no new backup on an
  unchanged repeated push.
- **Sync internals.** Run `bash scripts/smoke-agent-sync-interface.sh`.
  Pull previews, cancellation/conflicts and direct adapter entries are
  exercised without importing or replacing live user preferences.
- **Start shell.** Run `bash scripts/smoke-zshrc-startup.sh`. Require clean
  startup, correct platform paths and Cursor/Grok command precedence.
- **Proof.** Capture stdout/stderr and exit codes; each script must exit zero.

## Gotchas

- `just install` and `just sync` can replace local preferences and skills.
  Use fixture scripts for testing; back up and review before live application.
- SSH, sudo and external downloads are simulated by smoke tests. The separate
  upstream CI preflight and a live `./sync-agents.sh skills-preflight` use real
  networks; report which boundary was exercised.
- Darwin/Linux uname fixtures do not replace actual Linux CI execution.

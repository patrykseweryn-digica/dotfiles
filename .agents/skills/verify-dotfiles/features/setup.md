# Setup and synchronization

Install or apply dotfiles while preserving runtime credentials and sessions.

## Sub-features

- `setup` creates links and invokes agent adapters.
- `sync` applies repository config and detects drift on a second read.
- `update` plans local state, preserves export-required additions, applies
  managed MCP state plus independent settings/link/hook categories, and checks
  the final state without removing export-required MCP additions.
- `export` prepares settings, MCP, skills, plugins, and recognized tools in one
  transaction.
- `portable-shell` starts Zsh on simulated macOS/Linux layouts.

## How to get to it (user POV)

- `just install` for full setup.
- `just sync` for a fast-forward pull and controlled local/upstream updates.
  The checkout must be clean.
- `just export` for one confirmed portable export into a clean checkout.

## Driving it with Bash smoke scripts

Preconditions: dependencies from SKILL.md; run from the checkout root.

- **Install and repeat.** Run `bash scripts/smoke-install-dotfiles.sh` and
  `bash scripts/smoke-plugin-install.sh`. They drive install helpers with an
  isolated HOME through fresh, partial, converged, failed and repeated states
  on the platform matrix. External installers are stubbed.
- **Plan and update.** Run `bash scripts/smoke-update-local.sh`. It drives
  public `just sync` in an isolated HOME and checkout. A stalled fetch and a
  local addition stop sync before changes. A stalled operation stops with its
  child process; independent phases continue and dependent phases report
  `NOT RUN` with a reason. The test then
  proves a compatible repeat causes no unnecessary downloads or installs.
  The caller starts with an older Node; the final check must see the Node
  and npm CLIs that the refresh installed.
- **Bounded operations.** Run `bash scripts/smoke-operation.sh`. It stalls a
  command with a child process under a 1 s limit, without GNU `timeout`, and
  on Linux also without `ps`. Both processes must stop. The report must name
  the element, operation, cause, exit code, tool output, next step, and log.
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
- **Clean Linux install.** Build `.github/ci/clean-install.Dockerfile` on the
  native amd64 and arm64 CI runners. The image runs `install`, two `sync`
  commands, and `doctor` as a user without sudo or SSH state.
- **Proof.** Capture stdout/stderr and exit codes; each script must exit zero.

## Gotchas

- `just install` and `just sync` can replace local preferences and skills.
  Use fixture scripts for testing; back up and review before live application.
- SSH, sudo and external downloads are simulated by smoke tests. The separate
  upstream CI preflight and a live `./sync-agents.sh skills-preflight` use real
  networks; report which boundary was exercised.
- Darwin/Linux uname fixtures do not replace actual Linux CI execution.
- A local Docker build proves only the host architecture unless emulation is
  requested explicitly.

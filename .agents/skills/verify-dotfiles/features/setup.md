# Setup and synchronization

Install or apply dotfiles while preserving runtime credentials and sessions.

## Sub-features

- `setup` creates links and invokes agent adapters.
- `sync` applies repository config and detects drift on a second read.
- `update` plans local state, preserves export-required additions, applies
  managed MCP state plus independent settings/link/hook categories, and checks
  the final state without removing export-required MCP additions.
- `export` prepares settings, MCP, skills, plugins, and recognized tools in one
  transaction. `export skills` lets the user select global skill additions,
  removals, and source changes without changing installed skills.
- `portable-shell` starts Zsh on simulated macOS/Linux layouts.
- `groups` limits install and sync to selected groups ([groups](groups.md)).

## How to get to it (user POV)

- `just install` for full setup.
- `just sync` for a fast-forward pull and controlled local/upstream updates.
  The checkout must be clean.
- `just export` for one confirmed portable export into a clean checkout.
- `just export skills` for a searchable list of global skill changes.

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
  checks repeat orchestration and unchanged HOME with updater stubs.
  This does not prove real download reuse or installer idempotence.
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
  A live Herdr hook with an absolute path must export as one `$HOME` hook.
  It also drives `just export skills` in a terminal with a stubbed selector.
  Require unmarked and unrestorable skills to stay out of the export plan.
  Check the real selector with several differences in an isolated HOME.
  Press Enter without marking; require no review. Filter to a subset, mark
  with Ctrl+A, and review with Enter. Require only matching changes.
  Repeat without a filter; require all changes. Refuse the write both times.
  Verify Tab still marks one change and Esc cancels.
- **Stage and apply skills.** Run `bash scripts/smoke-skill-install.sh`.
  Require current content in every runtime, no live changes after staging or
  network failures, rollback after apply failures, and no new backup on an
  unchanged repeated push. Deleting a skill from the shared directory must
  remove its entry from Pi without leaving a broken link. The script also
  runs public `just sync` with a real Git fast-forward and installed skills.
  Require repository removals to apply, unknown and locally replaced skills
  to stop sync, and a failed swap to preserve the last applied inventory for
  retry. The test stubs skill downloads and unrelated categories.
- **Skill support docs.** Run `bash scripts/smoke-skill-docs.sh`. A skill
  linking `../../docs/<path>` must get that file in `~/.agents/docs`, with
  each runtime `docs` directory linked to it. Doctor reports a missing doc
  as skills `UPDATE` without network access. A failed download changes
  nothing. Staging rejects unsafe paths. Two packages may ship one doc;
  only different content fails. The test simulates downloads.
  For real upstream, run `skills-update` with a scratch HOME and a lock
  subset, then `skills-check` in that HOME.
- **Upstream skill path.** `smoke-skill-install.sh` also covers a skill that
  the skills CLI resolves from another upstream path than `skillPath`.
  Staging must fail and name both paths. Upstream repositories can hold two
  copies of one skill, for example `cursor/plugins` pstack.
  `./sync-agents.sh skills-preflight` checks every real entry.
- **Sync internals.** Run `bash scripts/smoke-agent-sync-interface.sh`.
  Pull previews, cancellation/conflicts and direct adapter entries are
  exercised without importing or replacing live user preferences.
- **Start shell.** Run `bash scripts/smoke-zshrc-startup.sh`. Require clean
  startup, correct platform paths, Cursor/Grok command precedence, unknown
  terminal fallback, preservation of a known terminal, and `~/.zfunc`
  completions ahead of zsh's own (`delta` maps to `_delta`, not `_sccs`).
- **SSH startup.** Run `bash scripts/smoke-ssh-zsh.sh`. Require generated
  startup files to execute noninteractive Bash commands and start Zsh only
  for interactive sessions. This does not cover migration of old blocks.
- **Login shells.** The same script drives real `zsh -lc` in a fixture HOME:
  the `~/.zprofile` block must put mise shims ahead of a Homebrew line, keep
  local lines, stay unchanged on repeat, move after a later Homebrew line,
  and do nothing without mise. `smoke-doctor.sh` covers the `shell` row and
  `smoke-update-local.sh` covers its sync apply.
- **Clean Linux install.** Build `.github/ci/clean-install.Dockerfile` on the
  native amd64 and arm64 CI runners. The image runs `install`, two `sync`
  commands, and `doctor` as a user without sudo or SSH state.
  Use the build command in `.github/workflows/check.yml`; it requires Docker
  with BuildKit, network access, and the `github_token` build secret.
  The image excludes SSH and account-dependent remote Codex plugins.
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
- The shell fixtures do not prove live Ghostty SSH integration.

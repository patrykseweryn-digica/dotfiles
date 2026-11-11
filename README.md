# dotfiles

Personal machine setup and agent config.

Use `just` as the public interface. Treat raw scripts as implementation
details unless you are debugging them.

## Daily commands

```bash
just sync     # daily pull, local convergence, and managed updates
just install  # prepare or repair a machine
just export   # review and save portable local additions
just doctor   # inspect local state offline and without writes
```

## Sync direction

Repository state is authoritative for `sync`. Portable runtime additions
enter the repository only through `export`.

`just export` requires a clean checkout and builds one plan for allowlisted
settings, normalized MCP, skills, plugin membership, and recognized tools.
It validates every managed skill against current upstream and enforces plugin
provider ownership before one confirmation. A removed skill stops export while
its name remains in the current upstream source. A verified upstream removal
allows the reviewed inventory change. Export never stages, commits, pushes, or
changes runtime files; an
apply failure rolls the checkout back. Environment values, HTTP headers,
credentials, OAuth state, unsupported transports, and local paths stay local.

`just sync` requires a clean checkout. It fetches upstream, fast-forwards,
applies repository settings and membership, then refreshes managed tools,
remote skills, and plugins. A local addition (`EXPORT`) stops sync before any
environment change and points to `just export`. The final result is `PASS`,
`EXPORT`, or `FAIL`. Sync never exports, commits, or pushes.
`SKIP` rows keep the final result at `PASS` and state why no action applies.
Remote skills remain unpinned and follow current upstream.
Doctor ignores Codex's active model and reasoning selection; repository values
remain install defaults.

Anthropic marketplaces belong only in Claude Code; OpenAI marketplaces belong
only in Codex. Checks and exports reject cross-provider marketplaces without
changing them. Sync removes cross-provider marketplaces before reconciliation.
The rule includes aliases pointing at the provider's GitHub repositories.
Codex uses OpenAI plugins and third-party plugins with an upstream native
`.codex-plugin/plugin.json`;
do not import Claude-only packages through Codex's compatibility conversion.
Keep each runtime's membership explicit in `.agents/plugin-manifest.json`.

Pi retains `pi-mcporter` for the existing MCP inventory and `pi-mcp-adapter`
for the used scripting/OAuth UI surface. See [Pi configuration](config/pi/README.md)
for the audit, theme, title lifecycle, compaction and live-test results.

## Developer tool versions

`config/mise/config.toml` keeps Node on the current LTS line. Setup records
that policy in mise's generated global config before developer CLIs. Sync
refreshes only the LTS line. New Zsh sessions activate the configured runtime.
Doctor compares the active runtime with mise's installed policy selection
without using the network.

`.agents/tool-versions.json` is the single inventory for core, system, and
developer CLIs. Managed entries follow stable releases without stored version
numbers. Mise installs and updates every portable core tool through
`scripts/core-tools.sh`. System-only entries retain package-manager names.
Entries without a user-local source declare `requires: "sudo"`.
The generated `~/.config/mise/conf.d/10-core-tools.toml` keeps core tools
independent from system package versions. Developer entries use
`channel: "latest"`; update resolves current releases without rewriting the
inventory. npm CLI entries become independent mise tools, so Node upgrades do
not hide them. Reports resolve npm `latest` and fail explicitly when the
registry is unavailable.
Native latest installers resolve their own releases; local checks verify
installed availability, not whether a newer release exists.
Herdr refuses to update from inside its own panes. In a Herdr pane, sync
reports `[SKIP] Herdr` and continues; run `herdr update` after detaching.

`just sync` resolves known online versions and performs managed updates.
Native latest installers do not expose one common version source.

Each npm CLI uses the mise npm backend. Claude Code uses
`claude install latest` for updates and Anthropic's native installer for a
missing command.
Configuration application never resolves channels or updates tool versions.

To add an npm CLI, add one entry to the manifest:

```json
{
  "name": "Example",
  "command": "example",
  "package": "example-cli",
  "installer": "npm",
  "channel": "latest"
}
```

Install, report, check and update discover the entry automatically. A tool
needing a new native installer uses a small bootstrap function and a corresponding
installer case and validation entry in the existing tool script.

`just export` can add a CLI when its executable is an unambiguous global npm
link with one command. It scans command directories, not complete package
manager inventories. Unknown or manual executables are reported by command
name for explicit description; paths and package-manager state are not saved.

`config/pi/settings.json` owns Pi's stable provider, model, thinking level, and
package list. Package sources omit versions and commits. Sync runs Pi's native
extension update. Install keeps `auth.json`, sessions, `trust.json`, and
the `deviceId`, `trackingId`, `apiKeys`, and changelog settings local. Fast
Mode remains off by default; its existing local preference is untouched. No
runtime state or credentials are imported.
Apply only Pi with `./sync-agents.sh pi-install`; check semantic JSON and
installed package versions with `./sync-agents.sh pi-check`.
Before repository checks, run `npm --prefix config/pi ci --ignore-scripts`
to install Pi's development-only typechecking and lint tools.
Development dependency locks and check-tool revisions remain separate from the
CLI inventory.
Global preferences in `.agents/AGENTS.md` are linked to
`~/.pi/agent/AGENTS.md`. Repository-only instructions live in root `AGENTS.md`,
with `CLAUDE.md` linking to it for Claude. Shared skills are linked into
`~/.pi/agent/skills/`.

`config/codex/settings.toml` owns portable Codex settings; project trust,
notices, and hook hashes stay local. Codex synchronization requires `uv`;
its TOML parser dependency is pinned in `scripts/codex-toml.py`.
Comparison uses TOML values, so formatting changes do not cause drift.
Pull imports only keys declared in the template, including nested keys.
Declare a new portable setting there before importing its live value.
Claude settings come from `config/claude/`. Missing required configuration
causes `just doctor` to fail and print the corresponding install command.

## Installation and synchronization

A clean machine needs Bash, `curl`, Git, CA certificates, `tar`, `unzip`, and
`rsync`.
Linux installation without sudo also needs a C compiler, `make`, XZ, and
ncurses headers for Zsh.
The installer bootstraps `jq`; `jq` is not a prerequisite.
Run `./install.sh` when `just` is not installed yet.

```bash
just install  # converge missing tools and local config
just sync     # pull and apply safe local and upstream changes
```

`just sync` prints the plan, applies settings, MCP, managed links, and the
Herdr hook, then refreshes inventory tools, Node, skills, and plugins.
A failed fetch, an unreadable plan, or an `EXPORT` row stops sync first.

Every network operation has a time limit (`scripts/operation.sh`). An expired
limit stops the operation and all its child processes. Tool output goes to
`${XDG_STATE_HOME:-~/.local/state}/dotfiles/sync.log`, which each sync run
replaces. A failure names the element, operation, cause, exit code, and next
step. Independent phases continue after a failure. A dependent phase prints
`NOT RUN` with its reason. The summary lists each problem and exits nonzero.

Cursor CLI, Grok Build, Herdr, Treehouse and no-mistakes use
official latest-release installers selected by the tool manifest.
Native commands use `~/.local/bin`;
no-mistakes keeps its binary in `~/.no-mistakes/bin` and restarts its daemon.
Installation and configuration application merge scalar `agent: codex` into
`~/.no-mistakes/config.yaml`, preserving other local settings and comments.
There is no automatic or Claude fallback in this global default; repository
agent overrides remain local. Configuration-only setup does not touch the
daemon. The merge uses `uv` with the pinned round-trip YAML parser in
`scripts/no-mistakes-config.py` (the CLI has no config-set command).

Herdr installation also installs its Claude hook
through the built-in integration command. The hook resolves its script
relative to `$HOME`.
Cursor's public command is `agent` in `~/.local/bin`.
Grok's binary stays in `~/.grok/bin` and is linked as `~/.local/bin/grok`.
Installation removes Grok's `agent` symlink, reserving that command for Cursor.
Grok completions join Zsh's search path before completion initialization.
Installers do not rewrite managed shell profiles. Both CLIs support macOS
and Linux through their official platform-aware installers.
Doctor checks that an enabled hook has a readable script; a disabled hook
is reported as SKIP.

## Verification

Use [.agents/skills/verify-dotfiles/SKILL.md](.agents/skills/verify-dotfiles/SKILL.md)
before changing or applying dotfiles and before commits. It reuses the existing
isolated-HOME install/sync smoke tests and `just check`, then compares the
read-only live `just doctor` result with the baseline. Doctor prints bounded
diagnostics rather than raw config diffs, which may contain credentials.
Evidence stays under ignored `.agent-runs/verify-dotfiles/`.
CI runs repository checks on macOS and Linux. Native amd64 and arm64 jobs also
run `install`, two `sync` commands, and `doctor` in a clean Ubuntu image as a
user without sudo. Accountless CI skips only remote Codex plugins because
their installation requires OAuth. CI mounts a read-only GitHub token only
during `sync`; Docker does not copy the token into the image. A separate job
resolves every current upstream skill on pushes, pull requests, and daily.
A local macOS run alone proves only macOS execution and the simulated Linux
cases.
Commit hooks run repository tests; live drift remains a separate check because
it depends on the machine's tools, credentials and installed configuration.

### Firstmate crew dispatch

Set `DOTFILES_FIRSTMATE_HOME` in the local `.env` to the absolute primary
Firstmate home containing `config/`. Full installation and the internal
config-only step write `config/firstmate/crew-dispatch.json` there as a regular
file. An unset target skips setup; an invalid target or differing existing
dispatch fails without replacing it. Equivalent JSON is left untouched. Other
Firstmate settings are never changed. There is no path guessing or
secondmate-home scan:
Firstmate's runtime `FM_HOME`/`FM_ROOT_OVERRIDE` can name an isolated home,
so dotfiles deliberately requires its own persistent, explicit target.

Profiles use the native `codex` harness: low for simple, well-understood
work, high for ambiguous diagnosis or complex investigation/data contracts,
and medium for ordinary implementation by default. Model is omitted so
Codex keeps its configured choice; no provider/model pin, quota arrays,
delivery policy, secondmate model, or no-mistakes effort is changed.
The schema owner is Firstmate's `docs/configuration.md`, section
"Crew dispatch profiles"; its `bin/fm-bootstrap.sh` validates the profiles.

After approval, apply only this configuration from the dotfiles checkout:

```bash
bash -c 'source ./install.sh; load_env; setup_firstmate'
```

This writes only the selected home's dispatch file. It does not restart
agents or propagate to secondmates. Main owns any later guarded
`fm-config-push.sh` inheritance. For a conflicting existing dispatch, review
and reconcile it explicitly before rerunning; setup never overwrites it.

### Herdr sidebar configuration

Full installation and the internal config-only step also merge
`config/herdr/config.toml` into `~/.config/herdr/config.toml` (or
`HERDR_CONFIG_PATH`). Agents retain their existing rows and gain a separate raw
`terminal_title` row, showing Pi's session name, spinner and final state even
while another tab is selected.
Other settings and comments stay local; agent-specific `rows_by_agent`
overrides remain untouched and take precedence over these shared rows.
Apply only this configuration, without installing tools or reloading sessions:

```bash
uv run --no-project --script scripts/herdr-config.py
```

Herdr 0.9.0 reads sidebar layouts from the client's local configuration.
Existing clients need a user-initiated config reload or a new attachment;
setup does neither. The outer window title and its spinner filter are unchanged.

## Synchronizing Git remotes

This checkout uses `origin` for `p-severin/dotfiles` and `work` for
`patrykseweryn-digica/dotfiles`. On a fresh clone, inspect `git remote -v`
and add whichever remote is missing, using the appropriate SSH identity:

```bash
git remote add origin git@github-personal:p-severin/dotfiles.git
git remote add work git@github-work:patrykseweryn-digica/dotfiles.git
```

Installation configures merges for pulls in this checkout. Other repositories
retain the global rebase preference.
With a clean working tree, combine both published histories, then push:

```bash
git switch master
git fetch origin
git fetch work
git merge origin/master
git merge work/master
git push origin HEAD:master
git push work HEAD:master
git rev-parse HEAD
git ls-remote origin refs/heads/master
git ls-remote work refs/heads/master
```

Resolve and commit any merge conflicts before continuing. All three SHAs
should match. If only one push succeeds, fix the connection and retry the
other. If a remote advanced, fetch it, merge its master, then push the new
HEAD to both again. These are ordinary fast-forward pushes; published
commits stay in history. Configuration application is separate from Git
publication.

## What is what

- `justfile`: command menu for humans.
- `install.sh`: full setup orchestrator.
- `bootstrap.d/*`: install modules sourced by `install.sh`.
- `sync-agents.sh`: sync Codex, Claude, Pi, OpenCode, MCP, plugins,
  skills.
- `ssh.sh`: SSH keys and `~/.ssh/config` setup.
- `scripts/smoke-*`: regression tests for installer behavior.
- `bin/*`: commands linked into `~/.local/bin`.
- `config/*`: files linked into `$HOME`.
- `.agents/*`: shared instructions, MCP servers, skill lock, plugin inventory.
  The plugin manifest covers Claude membership plus Codex remote and
  marketplace plugins.

## Rule of thumb

- New machine: `just install`.
- Daily synchronization: `just sync`.
- `EXPORT` result: `just export`.
- Diagnostics: `just doctor`.

CI and repository development use the hidden `just check` maintenance recipe.
Category-specific operations remain internal script subcommands for
implementation and tests.

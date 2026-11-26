# dotfiles

Personal machine setup and agent config.

Use `just` or GNU Make as the public interface. Both run the same scripts.

## Daily commands

```bash
just sync     # daily pull, local convergence, and managed updates
just install  # prepare or repair a machine
just export         # review and save portable local additions
just export skills  # choose global skill changes to save in the repository
just machine   # inspect local state offline and without writes
```

On a machine without `just`, use GNU Make from the checkout:

```bash
make install
make sync
make machine
make export
make export-skills
```

Run `make` to list the commands. The Make commands do not install or require
`just`. They work with the same no-sudo setup as `./install.sh`.
## Sync direction

Repository state is authoritative for `sync`. Portable runtime additions
enter the repository only through `export`.

`just export` requires a clean checkout and builds one plan for allowlisted
settings, normalized MCP, skills, plugin membership, and recognized tools.
It enforces plugin provider ownership before confirmation. A removed skill
stops export while its name remains in the current upstream source.
After confirmation, export validates every skill in a changed inventory
against current upstream before writing. Export never stages, commits,
pushes, or changes runtime files. If a write fails, export rolls the checkout
back. Environment values, HTTP headers, credentials, OAuth state, unsupported
transports, and local paths stay local.

Use `just export skills` to record intentional changes to global skills, such
as removals made with `npx skills remove -g`. Type to filter the `fzf` list.
Mark one change with `Tab` or all matching changes with `Ctrl+A`.
Clear the search to mark the entire list. Review with `Enter` or cancel with `Esc`.
Unmarked skills keep their repository entries. The command checks the resulting
inventory against current upstream before it writes only the repository lock.

`just sync` requires a clean checkout. It fetches upstream, fast-forwards,
applies repository settings and membership, then refreshes managed tools,
remote skills, and plugins. A local addition (`EXPORT`) stops sync before any
environment change and points to `just export`. The final result is `PASS`,
`EXPORT`, or `FAIL`. Sync never exports, commits, or pushes.
`SKIP` rows keep the final result at `PASS` and state why no action applies.
Remote skills remain unpinned and follow current upstream. Sync checks the
upstream revisions in parallel. If the revisions and local skills have not
changed since the last refresh, sync skips downloading skills.
A skill can link a support doc as `../../docs/<path>`, for example the pstack
Claude Code adapter. The skills CLI copies only skill folders, so sync
downloads each linked doc from the skill's upstream package into
`~/.agents/docs`. Downloads use GitHub's contents API with at most three
retries within a bounded fetch operation. Skill staging authenticates with
`GITHUB_TOKEN`, then `GH_TOKEN`, then the `gh` login; anonymous requests
share a 60 per hour limit that one sync exhausts.
Required document failures still stop staging before any runtime changes.
`~/.claude/docs`, `~/.config/opencode/docs` and
`~/.pi/agent/docs` link to it. A missing doc is a skills `UPDATE` in machine.
`~/.agents/skills` is the one shared skill set. Codex, Cursor and Grok Build
read it directly. Claude Code and OpenCode use per-skill symlinks. Pi uses
one symlink to the shared directory, so external removals leave no stale entries.
Every skill comes from an upstream lock entry through that same unpinned
skills CLI install; personal skills live in `p-severin/skills`. The
repository keeps no skill copies, except its own `verify-dotfiles`. Export and `skills-check` reject a live
skill without an upstream source.
pstack skills come from `harness/pstack/claude-code` in `cursor/plugins`:
its adapter line applies only in Claude Code, so every harness can share it.
Staging fails when the skills CLI resolves a skill from another upstream path
than its `skillPath`.
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
developer CLIs. Existing entries follow stable releases; explicitly reviewed
pins use `versionPolicy: "pinned"` with `version` for core mise tools.
Mise installs and updates portable core tools through
`scripts/core-tools.sh`. System-only entries retain package-manager names.
Entries without a user-local source declare `requires: "sudo"`.
Every entry declares its install group (see [Install groups](#install-groups)).
The generated `~/.config/mise/conf.d/10-core-tools.toml` keeps core tools
independent from system package versions. A core tool can declare
`zshCompletion`: a generator (`args`, for example `gh completion -s zsh`) or a
file in its mise install directory (`file`). Install and sync write each one to
`~/.zfunc/_<command>`; `.zshrc` puts `~/.zfunc` first in `fpath`. A failed
generator keeps the old file. Doctor reports missing or outdated completions.
Interactive zsh activates mise in `.zshrc`. Login shells that skip `.zshrc`,
such as `zsh -lc` from agents, find mise tools through mise shims: install and
sync keep a marked block at the end of `~/.zprofile`, after Homebrew, and
leave other lines unchanged. Doctor reports `UPDATE shell` when the block is
missing or a later line follows it.
Developer entries use `channel: "latest"` or an explicitly reviewed release
number in `channel`. Update preserves declared pins without rewriting the
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
Codex follows the best channel of each platform at latest. macOS uses the
Homebrew cask (`brew install` or `brew upgrade --cask codex`). Linux uses
OpenAI's official installer (`chatgpt.com/codex/install.sh`). It verifies
checksums, installs into `~/.local/bin`, and does nothing when the release
is current. Another `codex` on `PATH` stops the install, and machine reports
it. Sync removes a former mise npm Codex.
Configuration application never resolves channels or updates tool versions.

The digica-99 tool sync records explicit mise pins for ast-grep, typos,
hyperfine, watchexec, and Vale. Use `ast-grep`, not its deprecated `sg` alias.
The ast-grep npm entry approves `@ast-grep/cli` build scripts through
`allow_builds`, so mise's package manager can run its native postinstall.

Developer tools `rust-just`, `yt-dlp`, `cmakelang`, and `pylint` use uv.
Their executables belong in `~/.local/bin`; Pylint is not a default check.
Rust-just is the only source for `just`. Make skips it.
Remove any old mise just selection before applying this inventory elsewhere.
Do not add a pipx yt-dlp or TensorFlow installation.
Fallow uses the existing mise npm channel and declares all three executables.
The gh-dash extension uses GitHub CLI's extension installer with a release pin.

The [Vale template](config/vale/README.md) supplies a shared spelling
configuration, Firstmate vocabulary, and pre-commit hook pattern.

To add an npm CLI, add one entry to the manifest:

```json
{
  "name": "Example",
  "command": "example",
  "package": "example-cli",
  "installer": "npm",
  "channel": "latest",
  "group": "agents"
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
notices, and hook hashes stay local. The Codex settings check uses `uv` to
find an installed Python 3.11 or newer; it needs neither network access nor
cached packages. Applying or exporting settings still uses the `tomlkit`
dependency pinned in `scripts/codex-toml.py`. Comparison uses TOML values,
so formatting changes do not cause drift.
Pull imports only keys declared in the template, including nested keys.
Declare a new portable setting there before importing its live value.
Claude settings come from `config/claude/`. Missing required configuration
causes `just machine` to fail and print the corresponding install command.

## Installation and synchronization

A clean machine needs Bash, `curl`, Git, CA certificates, `tar`, `unzip`, and
`rsync`.
Linux installation without sudo also needs a C compiler, `make`, XZ, and
ncurses headers for Zsh.
The installer bootstraps `jq`; `jq` is not a prerequisite.
If `just` is unavailable, use `make install` and `make sync`.
If neither runner is available, start with `./install.sh`.

```bash
just install  # converge missing tools and local config
just sync     # pull and apply safe local and upstream changes
```

### Install groups

Each machine selects install groups in its local `.env`. `install` and `sync`
install and update only elements of the selected groups.

| Group | Contents |
|---|---|
| `core` | zsh, Oh My Zsh, CLI tools (gh, shellcheck, gnupg), Git, SSH, managed links |
| `agents` | Node, pnpm, agent CLIs and settings, MCP, skills, plugins, AXI |
| `desktop` | fonts, Ghostty and VS Code config, terminal colors, macOS apps (Brewfile casks) |

No setting, or an empty value, selects `core` only. Add or remove a group
with these commands:

```bash
just groups           # show the selected groups
just enable agents    # select agents, then run install
just disable desktop  # stop installing and updating desktop
```

The Make equivalents are `make groups`, `make enable group=agents`, and
`make disable group=desktop`.

The commands write `DOTFILES_GROUPS` in `.env`, for example
`DOTFILES_GROUPS=core,agents`. `core` is required and cannot be disabled.
An unknown group or a list without `core` stops `install`, `sync` and
`machine` before any change and names the valid groups.

A machine set up before `core` became the default keeps its other groups
installed. When managed links of an unselected group remain, `sync` and
`machine` print one row for each group:
`[SKIP] groups: Group agents is installed but not selected; ...
Run: just enable agents`.

Each element declares its group: tools in `.agents/tool-versions.json`, links
in `config/managed-links.tsv`, and install steps and sync phases in their
scripts. The plan reports an element of an unselected group as
`SKIP ... skipped: group <name> is not selected`. `sync` and `machine` pass when
only `SKIP` rows remain. `just disable` does not remove installed elements.

`just sync` prints the plan, applies settings, MCP, managed links, and the
Herdr hook, then refreshes inventory tools, Node, skills, and plugins.
A failed fetch, an unreadable plan, or an `EXPORT` row stops sync first.
For skills, sync uses the last applied inventory to distinguish repository
removals from local additions. Without that inventory or a locally available
Git copy recorded by an older sync, unknown skills still stop the run.

Every network operation has a time limit (`scripts/operation.sh`). An expired
limit stops the operation and all its child processes. Tool output goes to
`${XDG_STATE_HOME:-~/.local/state}/dotfiles/sync.log`, which each sync run
replaces. A failure names the element, operation, cause, exit code, and next
step. Independent phases continue after a failure. A dependent phase prints
`NOT RUN` with its reason. The summary lists each problem and exits nonzero.

Codex, Cursor CLI, Grok Build, Herdr, Treehouse and no-mistakes use
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
isolated-HOME install/sync smoke tests and `just test`, then compares the
read-only live `just machine` result with the baseline. Machine prints bounded
diagnostics rather than raw config diffs, which may contain credentials.
Evidence stays under ignored `.agent-runs/verify-dotfiles/`.
Pull requests and a manual run check the repository on macOS and Linux.
Pushes to master and the Monday 05:17 UTC schedule check Linux only.
Native amd64 and arm64 jobs run `install`, two `sync` commands, and `machine`
through Make in a clean Ubuntu image without sudo or `just`. Those jobs run on pull
requests, the Monday schedule, and a manual run. A push to master does not
run them. Accountless CI skips only remote Codex plugins because their
installation requires OAuth. CI mounts a read-only GitHub token only during
`sync`. Docker does not copy the token into the image. A separate job resolves
every current upstream skill when the workflow runs. A push that only changes
docs or Markdown does not start the workflow.
A local macOS run alone proves only macOS execution and the simulated Linux
cases.
prek runs the repository tests as commit hooks, independent hooks in parallel.
Live drift remains a separate check because
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

## Architecture map

The [SVG](docs/architecture.svg) shows how declarations, modules, and platforms
connect. The [JSON graph](docs/architecture.json) lists the corresponding
commands, inventories, and install groups.

Both files describe the current checkout, not the target [vision](STRATEGY.md).
The generator reads known declarations and shell entry points, not local `.env`
files or live machines. It does not resolve arbitrary shell calls.

After changing an architecture input, run `just architecture` to regenerate both
files. `just test` and CI reject stale output.

## Rule of thumb

- New machine: `just install`.
- Daily synchronization: `just sync`.
- `EXPORT` result: `just export`.
- Diagnostics: `just machine`.

CI and repository development use the hidden `just test` maintenance recipe.
Category-specific operations remain internal script subcommands for
implementation and tests.

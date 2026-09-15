# dotfiles

Personal machine setup and agent config.

Use `just` as the public interface. Treat raw scripts as implementation
details unless you are debugging them.

## Daily commands

```bash
just --list
just check
just doctor
just agent-versions
just push
just pull-codex-settings
just pull-mcp
just pull-skills
```

## Sync direction

Repository state is authoritative when pushing. Runtime state is only imported
through category-specific pull commands.

```bash
just pull-codex-settings # preview live Codex preferences, then confirm
just pull-mcp       # preview live MCP state, then confirm
just push-mcp       # repository MCP state -> runtimes
just pull-skills    # preview live skills, then confirm repository changes
just push-skills    # reconcile skills without version updates
just pull-plugins   # preview live plugins, then confirm repository changes
just push-plugins   # apply membership without upgrades
just push           # push MCP, skills, and plugins in order
```

There is no broad `just pull`. After saving a model or reasoning default in
Codex, run `just pull-codex-settings`. MCP pull merges identical definitions
and stops without writing on conflicts. Environment values, HTTP headers,
credentials, OAuth state, and unsupported transports are not imported.
Skill pull previews lock and custom-skill additions, removals, and replacements
before asking for confirmation. Doctor ignores Codex's active model and
reasoning selection; repository values remain install defaults. Skill push
removes unmanaged skills and stale links, then makes Codex, Claude Code,
OpenCode, and Pi match the repository inventory. Neither command updates
upstream skill versions.

Plugin pull combines supported Codex remote and Claude plugin membership,
shows the manifest diff, and writes only after confirmation. That explicit
pull makes the shared manifest authoritative. Plugin push uses Claude's CLI
for membership changes. Codex remote plugins still require `/plugins`; drift
stops with the plugin names, OAuth step, and verification command. Pull and
push never update marketplaces, plugins, or agent CLIs.

Claude marketplace plugins belong only in Claude. Codex uses OpenAI plugins
and third-party plugins with an upstream native `.codex-plugin/plugin.json`;
do not import Claude-only packages through Codex's compatibility conversion.
Keep each runtime's membership explicit in `.agents/plugin-manifest.json`.

Pi retains `pi-mcporter` for the existing MCP inventory and `pi-mcp-adapter`
for the used scripting/OAuth UI surface. See [Pi configuration](config/pi/README.md)
for the audit, theme, title lifecycle, compaction and live-test results.

## Developer tool versions

`.nvmrc` declares the exact Node version. Setup installs it before developer
CLIs and activates it for their installation. Repeated setup reuses that
version; `just doctor` checks the Node active in the current shell.

`.agents/tool-versions.json` declares developer CLIs. A `version` pins a
tool; without it, `channel: "latest"` explicitly opts into current releases.
Installation restores pins, while `just update-agent-tools` updates them.
Pi and the existing unpinned npm tools keep their `latest` policy. Reports
resolve npm `latest` and fail explicitly when the registry is unavailable.
Native latest installers resolve their own releases; their report checks
installed availability, not whether a newer release exists.

```bash
just agent-versions      # compare developer tools with their version policies
just update-agent-tools  # resolve channels, pin versions, install tools
```

Pi, Codex, OpenCode, and the skill manager use global npm packages. Claude
Code uses Anthropic's native installer with an exact version. Configuration
commands such as `just push` never resolve channels or update tool versions.

To add an npm CLI, add one entry to the manifest:

```json
{
  "name": "Example",
  "command": "example",
  "package": "example-cli",
  "installer": "npm",
  "channel": "latest",
  "version": "1.2.3"
}
```

Install, report, check and update discover the entry automatically. Omit
`version` only when you deliberately want `latest`. A tool needing a new
native installer uses a small bootstrap function and a corresponding
installer case and validation entry in the existing tool script.

`config/pi/settings.json` owns Pi's stable provider, model, thinking level, and
pinned package list. Install keeps `auth.json`, sessions, `trust.json`, and
changelog state local. Fast Mode remains off by default; its existing local
preference is untouched. No runtime state or credentials are imported.
Apply only Pi with `./sync-agents.sh pi-install`; check semantic JSON and
installed package versions with `./sync-agents.sh pi-check`.
Before repository checks, run `npm --prefix config/pi ci --ignore-scripts`
to install Pi's development-only typechecking and lint tools.
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

## Setup commands

```bash
just install          # new machine: tools, links, agents, SSH, hooks
just update-dotfiles  # existing machine: links + agents, no tools, no SSH
just setup-ssh        # explicit SSH key/config setup
```

Hermes Agent, Herdr, Treehouse and no-mistakes use official latest-release
installers selected by the tool manifest. Native commands use `~/.local/bin`;
no-mistakes keeps its binary in `~/.no-mistakes/bin` and restarts its daemon.
Both setup commands merge scalar `agent: codex` into
`~/.no-mistakes/config.yaml`, preserving other local settings and comments.
There is no automatic or Claude fallback in this global default; repository
agent overrides remain local. Configuration-only setup does not touch the
daemon. The merge uses `uv` with the pinned round-trip YAML parser in
`scripts/no-mistakes-config.py` (the CLI has no config-set command).

Hermes installation skips account setup and the optional Computer Use driver. Herdr installation also installs its Claude hook through
the built-in integration command. The hook resolves its script relative to `$HOME`.
Doctor checks that an enabled hook has a readable script; a disabled hook
is reported as SKIP.

## Synchronizing Git remotes

This checkout uses `origin` for `p-severin/dotfiles` and `work` for
`patrykseweryn-digica/dotfiles`. On a fresh clone, inspect `git remote -v`
and add whichever remote is missing, using the appropriate SSH identity:

```bash
git remote add origin git@github-personal:p-severin/dotfiles.git
git remote add work git@github-work:patrykseweryn-digica/dotfiles.git
```

`just install` and `just update-dotfiles` configure merges for pulls in
this checkout. Other repositories retain the global rebase preference.
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
commits stay in history. Configuration sync with `just push` is separate
from Git publication.

## What is what

- `justfile`: command menu for humans.
- `install.sh`: full setup orchestrator.
- `bootstrap.d/*`: install modules sourced by `install.sh`.
- `sync-agents.sh`: sync Codex, Claude, Pi, OpenCode, Kimi, MCP, plugins,
  skills.
- `ssh.sh`: SSH keys and `~/.ssh/config` setup.
- `scripts/smoke-*`: regression tests for installer behavior.
- `bin/*`: commands linked into `~/.local/bin`.
- `config/*`: files linked into `$HOME`.
- `.agents/*`: shared instructions, MCP servers, skill lock, plugin inventory.
  The plugin manifest covers Claude membership plus Codex remote and
  marketplace plugins.

## Rule of thumb

- Need to use repo: start with `just --list`.
- Need to verify repo: `just check`.
- Need to check this machine for drift: `just doctor`.
- Need to inspect agent versions: `just agent-versions`.
- Need to update agent tools: `just update-agent-tools`.
- Need to apply repository state: `just push`.
- Changed Codex model/preferences interactively: `just pull-codex-settings`.
- Need to inspect runtime MCP additions: `just pull-mcp`.
- Need to review live skill changes: `just pull-skills`.
- Need a new machine: `just install`.
- Need only dotfile links refreshed: `just update-dotfiles`.
- Need SSH changes: run `just setup-ssh` explicitly.

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
just pull-mcp
just pull-skills
```

## Sync direction

Repository state is authoritative when pushing. Runtime state is only imported
through category-specific pull commands.

```bash
just pull-mcp       # preview live MCP state, then confirm
just push-mcp       # repository MCP state -> runtimes
just pull-skills    # preview live skills, then confirm repository changes
just push-skills    # reconcile skills without version updates
just pull-plugins   # preview drift; inventory approval stays in issue #13
just push-plugins   # apply membership without upgrades
just push           # push MCP, skills, and plugins in order
```

There is no broad `just pull`. MCP pull merges identical definitions and stops
without writing on conflicts. Environment values, HTTP headers, credentials,
OAuth state, and unsupported transports are not imported. Skill pull previews
lock and custom-skill additions, removals, and replacements before asking for
confirmation. Skill push removes unmanaged skills and stale links, then makes
Codex, Claude Code, OpenCode, and Pi match the repository inventory. Neither
command updates upstream skill versions.

Pi receives stdio and HTTP servers through the pinned `pi-mcp-adapter` package.
Its local MCP state lives in `~/.agents/mcp.json`.

## Agent tool versions

`.agents/tool-versions.json` stores a moving channel and its exact resolved
version. Fresh installs use the committed version, so they stay reproducible.
Updating resolves each channel, writes new exact pins, then installs them.

```bash
just agent-versions      # compare installed tools with committed versions
just update-agent-tools  # resolve channels, pin versions, install tools
```

Pi, Codex, OpenCode, and the skill manager use global npm packages. Claude
Code uses Anthropic's native installer with an exact version. `just install`
installs the committed versions on a fresh machine. Configuration commands
such as `just push` never resolve channels or update tool versions.

`config/pi/settings.json` owns Pi's stable provider, model, thinking level, and
pinned package list. Install keeps `auth.json`, sessions, `trust.json`, and
changelog state local. Shared instructions are linked to
`~/.pi/agent/AGENTS.md`. Shared skills are linked into
`~/.pi/agent/skills/`.

## Setup commands

```bash
just install          # new machine: tools, links, agents, SSH, hooks
just update-dotfiles  # existing machine: links + agents, no tools, no SSH
just setup-ssh        # explicit SSH key/config setup
```

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
- `.agents/*`: shared agent instructions, MCP servers, skill lock.

## Rule of thumb

- Need to use repo: start with `just --list`.
- Need to verify repo: `just check`.
- Need to check this machine for drift: `just doctor`.
- Need to inspect agent versions: `just agent-versions`.
- Need to update agent tools: `just update-agent-tools`.
- Need to apply repository state: `just push`.
- Need to inspect runtime MCP additions: `just pull-mcp`.
- Need to review live skill changes: `just pull-skills`.
- Need a new machine: `just install`.
- Need only dotfile links refreshed: `just update-dotfiles`.
- Need SSH changes: run `just setup-ssh` explicitly.

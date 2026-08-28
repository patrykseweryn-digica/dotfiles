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
```

## Sync direction

Repository state is authoritative when pushing. Runtime state is only imported
through category-specific pull commands.

```bash
just pull-mcp       # preview live MCP state, then confirm
just push-mcp       # repository MCP state -> runtimes
just pull-skills    # preview drift; inventory approval stays in issue #10
just push-skills    # restore skills without version updates
just pull-plugins   # preview drift; inventory approval stays in issue #13
just push-plugins   # apply membership without upgrades
just push           # push MCP, skills, and plugins in order
```

There is no broad `just pull`. MCP pull merges identical definitions and stops
without writing on conflicts. Environment values, HTTP headers, credentials,
OAuth state, and unsupported transports are not imported. Pi has no built-in
MCP support, so its MCP adapter remains out of scope until issue `#12`.

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
- `sync-agents.sh`: sync Codex, Claude, OpenCode, Kimi, MCP, plugins, skills.
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
- Need a new machine: `just install`.
- Need only dotfile links refreshed: `just update-dotfiles`.
- Need SSH changes: run `just setup-ssh` explicitly.

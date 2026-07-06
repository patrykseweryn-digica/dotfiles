# dotfiles

Personal machine setup and agent config.

Use `just` as the public interface. Treat raw scripts as implementation
details unless you are debugging them.

## Daily commands

```bash
just --list
just check
just agents
just commit "chore: message" path/to/file
```

## Setup commands

```bash
just bootstrap       # new machine: tools, links, agents, SSH, hooks
just apply           # existing machine: links + agents, no tools, no SSH
just ssh             # explicit SSH key/config setup
```

## What is what

- `justfile`: command menu for humans.
- `install.sh`: full bootstrap orchestrator.
- `bootstrap.d/*`: install modules sourced by `install.sh`.
- `sync-agents.sh`: sync Codex, Claude, OpenCode, MCP, plugins, skills.
- `ssh.sh`: SSH keys and `~/.ssh/config` setup.
- `scripts/smoke-*`: regression tests for installer behavior.
- `bin/*`: commands linked into `~/.local/bin`.
- `config/*`: files linked into `$HOME`.
- `.agents/*`: shared agent instructions, MCP servers, skill lock.

## Rule of thumb

- Need to use repo: start with `just --list`.
- Need to verify repo: `just check`.
- Need to refresh agents: `just agents`.
- Need a new machine: `just bootstrap`.
- Need only dotfile links refreshed: `just apply`.
- Need SSH changes: run `just ssh` explicitly.

## Advanced agent commands

Usually use `just agents` and `just agents-check`.

Raw commands:

```bash
./sync-agents.sh codex-install
./sync-agents.sh opencode-install
./sync-agents.sh claude-install
./sync-agents.sh custom-skills-export
./sync-agents.sh skills-export
./sync-agents.sh claude-export
./sync-agents.sh claude-prune --check
```

# dotfiles

Personal machine setup and agent config.

Use `just` as the public interface. Treat raw scripts as implementation
details unless you are debugging them.

## Daily commands

```bash
just --list
just check
just update-agents
just update-skills
just update-plugins
```

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
- Need to refresh agents: `just update-agents`.
- Need to update shared skills: `just update-skills`.
- Need to update shared Codex/Claude plugins: `just update-plugins`.
- Need a new machine: `just install`.
- Need only dotfile links refreshed: `just update-dotfiles`.
- Need SSH changes: run `just setup-ssh` explicitly.

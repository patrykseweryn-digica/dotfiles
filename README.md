# dotfiles

Personal machine setup and agent config.

Use `just` as the public interface. Treat raw scripts as implementation
details unless you are debugging them.

## Daily commands

```bash
just --list
just check
just sync-agent-config
just commit "chore: message" path/to/file
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
- `sync-agents.sh`: sync Codex, Claude, OpenCode, MCP, plugins, skills.
- `ssh.sh`: SSH keys and `~/.ssh/config` setup.
- `scripts/smoke-*`: regression tests for installer behavior.
- `bin/*`: commands linked into `~/.local/bin`.
- `config/*`: files linked into `$HOME`.
- `.agents/*`: shared agent instructions, MCP servers, skill lock.

## Rule of thumb

- Need to use repo: start with `just --list`.
- Need to verify repo: `just check`.
- Need to refresh agents: `just sync-agent-config`.
- Need to verify agents: `just check-agent-config`.
- Need a new machine: `just install`.
- Need only dotfile links refreshed: `just update-dotfiles`.
- Need SSH changes: run `just setup-ssh` explicitly.

## Advanced agent commands

Usually use `just sync-agent-config` and `just check-agent-config`.

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

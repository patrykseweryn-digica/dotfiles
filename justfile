set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

sync_agents := env_var_or_default("SYNC_AGENTS", "./sync-agents.sh")
agent_tools := env_var_or_default("AGENT_TOOLS", "./scripts/agent-tools.sh")

# Show the public command menu.
[private]
default:
    just --list

# Full setup: tools, links, agent config, SSH, hooks.
install:
    ./install.sh

# Update dotfile links and agent config only. No tools, no SSH.
update-dotfiles:
    DOTFILES_SKIP_SSH=true bash -c 'source ./install.sh; load_env; setup_dotfiles'

# Run deterministic repository checks.
check:
    pre-commit run --all-files

# Check this machine against repository intent.
doctor:
    ./scripts/doctor.sh

# Report installed and expected agent tool versions.
agent-versions:
    "{{ agent_tools }}" report

# Resolve configured channels, update pins, and install agent tools.
update-agent-tools:
    "{{ agent_tools }}" update

# Preview runtime MCP state, then confirm the repository update.
pull-mcp:
    "{{ sync_agents }}" pull-mcp

# Render repository MCP state into supported runtimes.
push-mcp:
    "{{ sync_agents }}" push-mcp

# Preview runtime skills, then confirm the repository update.
pull-skills:
    "{{ sync_agents }}" pull-skills

# Reconcile repository skills without updating upstream versions.
push-skills:
    "{{ sync_agents }}" push-skills

# Preview runtime plugins, then confirm the repository update.
pull-plugins:
    "{{ sync_agents }}" pull-plugins

# Apply plugin membership without updating plugin versions.
push-plugins:
    "{{ sync_agents }}" push-plugins

# Push MCP, skill, and plugin repository state in order.
push:
    failed=false; for category in mcp skills plugins; do \
        "{{ sync_agents }}" "push-${category}" || failed=true; \
    done; [ "$failed" = false ]

# Set up SSH keys and ~/.ssh/config.
setup-ssh:
    set -a; . ./.env; set +a; ./ssh.sh "$EMAIL" "$WORK_EMAIL"

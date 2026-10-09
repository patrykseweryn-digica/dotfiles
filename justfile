set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

sync_agents := env_var_or_default("SYNC_AGENTS", "./sync-agents.sh")
agent_tools := env_var_or_default("AGENT_TOOLS", "./scripts/agent-tools.sh")

# Show the public command menu.
[private]
default:
    just --list

# Converge missing tools, links, agent config, SSH, and hooks.
install:
    ./install.sh

# Apply repository local state while preserving additions that need export.
update:
    ./scripts/update-local.sh

# Export all portable live state after one confirmation.
export:
    "{{ sync_agents }}" export

# Run deterministic repository checks.
[private]
check:
    pre-commit run --all-files

# Check this machine against repository intent.
doctor:
    ./scripts/doctor.sh

# List developer tools that need install or update without changes.
outdated:
    "{{ agent_tools }}" outdated

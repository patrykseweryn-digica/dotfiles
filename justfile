set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

sync_agents := env_var_or_default("SYNC_AGENTS", "./sync-agents.sh")

# Show the public command menu.
[private]
default:
    just --list

# Converge missing tools, links, agent config, SSH, and hooks.
install:
    ./install.sh

# Pull repository changes, then converge local and upstream state.
sync:
    ./scripts/sync-local.sh

# Apply repository local state while preserving additions that need export.
[private]
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

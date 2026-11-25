set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

sync_agents := env_var_or_default("SYNC_AGENTS", "./sync-agents.sh")

# Show the public command menu.
[private]
default:
    just --list

# Converge missing tools, links, agent config, SSH, and hooks.
install:
    ./install.sh

# Show the install groups of this machine.
groups:
    bash scripts/groups.sh show

# Select an install group, then install its elements.
enable group:
    bash scripts/groups.sh enable "{{ group }}"
    ./install.sh

# Stop installing and updating an install group; its elements stay.
disable group:
    bash scripts/groups.sh disable "{{ group }}"

# Pull repository changes, then converge local and upstream state.
sync:
    ./scripts/sync-local.sh

# Apply repository local state while preserving additions that need export.
[private]
update:
    ./scripts/update-local.sh

# Export portable live state, or select global skill changes with `export skills`.
[positional-arguments]
export *args:
    "{{ sync_agents }}" export "$@"

# Run deterministic repository checks.
[private]
test:
    pre-commit run --all-files

# Check this machine against repository intent.
machine:
    ./scripts/doctor.sh

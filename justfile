set shell := ["bash", "-eu", "-o", "pipefail", "-c"]
# Do not echo recipe lines; the scripts print their own progress.
set quiet

sync_agents := env_var_or_default("SYNC_AGENTS", "./sync-agents.sh")

# Show the install group status and the public commands. Keep Makefile help
# in the same order. scripts/menu.sh adds the colors: it follows NO_COLOR and
# JUST_COLOR, but cannot see the --color option of this just process.
[private]
default:
    "{{ just_executable() }}" --justfile "{{ justfile() }}" --list --unsorted \
        --list-heading '' --color never | bash scripts/menu.sh

# Install tools, links, agent config, SSH and hooks.
[group('start')]
install:
    ./install.sh

# Check this machine against the repo; read-only.
[group('start')]
machine:
    ./scripts/doctor.sh

# Pull repository changes, then update this machine.
[group('daily')]
sync:
    ./scripts/sync-local.sh

# Apply repository local state while preserving additions that need export.
[private]
update:
    ./scripts/update-local.sh

# Show the install groups of this machine.
[group('install groups')]
groups:
    bash scripts/groups.sh show

# Select an install group, then install its elements.
[group('install groups')]
enable group="":
    bash scripts/groups.sh enable "{{ group }}"

# Stop updating an install group; keep its elements.
[group('install groups')]
disable group="":
    bash scripts/groups.sh disable "{{ group }}"

# Save local additions; `export skills` picks skills.
[group('export')]
[positional-arguments]
export *args:
    "{{ sync_agents }}" export "$@"

# Run all repository checks; required before commits.
[group('dev')]
test:
    bash scripts/test.sh

# Regenerate the architecture SVG and JSON.
[group('dev')]
architecture:
    python3 scripts/build-architecture.py

set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

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

# Run the full repo verification suite.
check:
    pre-commit run --all-files

# Refresh Codex, OpenCode, and Claude configuration from repo state.
update-agents:
    ./sync-agents.sh install

# Update shared global skills, persist the lock, and sync all runtimes.
update-skills:
    ./sync-agents.sh skills-update
    ./sync-agents.sh skills-export
    ./sync-agents.sh install

# Set up SSH keys and ~/.ssh/config.
setup-ssh:
    set -a; . ./.env; set +a; ./ssh.sh "$EMAIL" "$WORK_EMAIL"

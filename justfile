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

# Test installer scripts without changing your real home config.
test-install:
    ./scripts/smoke-tool-plan.sh
    ./scripts/smoke-zsh-plan.sh
    ./scripts/smoke-zshrc-startup.sh
    ./scripts/smoke-agent-repo-layout.sh
    ./scripts/smoke-install-dotfiles.sh
    ./scripts/smoke-ssh-config.sh
    ./scripts/smoke-macos-apps.sh
    ./scripts/smoke-agent-skill-sync.sh
    ./scripts/smoke-web-scraping-skills.sh

# Refresh Codex, OpenCode, and Claude configuration from repo state.
update-agents:
    ./sync-agents.sh install

# Update shared global skills, persist the lock, and sync all runtimes.
update-skills:
    ./sync-agents.sh skills-update
    ./sync-agents.sh skills-export
    ./sync-agents.sh install

# Check whether live agent state matches repo files.
check-agents:
    ./sync-agents.sh codex-check
    ./sync-agents.sh opencode-check
    ./sync-agents.sh claude-prune --check
    ./sync-agents.sh claude-settings-check

# Set up SSH keys and ~/.ssh/config.
setup-ssh:
    set -a; . ./.env; set +a; ./ssh.sh "$EMAIL" "$WORK_EMAIL"

# Commit only the listed files.
commit-files message +files:
    committer "{{message}}" {{files}}

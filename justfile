set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

# Show the public command menu.
default:
    just --list

# Full first-machine setup: tools, links, agents, SSH, hooks.
bootstrap:
    ./install.sh

# Full setup with shell tracing.
bootstrap-debug:
    ./install.sh --debug

# Apply links + agents; no tool install, no SSH.
apply:
    DOTFILES_SKIP_SSH=true bash -c 'source ./install.sh; load_env; setup_dotfiles'

# Run the full repo verification suite.
check:
    pre-commit run --all-files

# Installer regression tests.
smoke:
    ./scripts/smoke-tool-plan.sh
    ./scripts/smoke-zsh-plan.sh
    ./scripts/smoke-zshrc-startup.sh
    ./scripts/smoke-agent-repo-layout.sh
    ./scripts/smoke-install-dotfiles.sh
    ./scripts/smoke-ssh-config.sh
    ./scripts/smoke-macos-apps.sh
    ./scripts/smoke-agent-skill-sync.sh
    ./scripts/smoke-web-scraping-skills.sh

# Sync shared agent config into Codex, OpenCode, and Claude.
agents:
    ./sync-agents.sh install

# Check live agent config drift.
agents-check:
    ./sync-agents.sh codex-check
    ./sync-agents.sh opencode-check
    ./sync-agents.sh claude-prune --check
    ./sync-agents.sh claude-settings-check

# Export live agent state back into repo-managed files.
agents-export:
    ./sync-agents.sh custom-skills-export
    ./sync-agents.sh skills-export
    ./sync-agents.sh claude-export

# Explicit SSH setup. This can edit ~/.ssh/config.
ssh:
    set -a; . ./.env; set +a; ./ssh.sh "$EMAIL" "$WORK_EMAIL"

# Path-limited commit helper.
commit message +files:
    committer "{{message}}" {{files}}

# Alias for `bootstrap`.
install:
    just bootstrap

# Alias for `agents`.
sync-agents:
    just agents

# Alias for `agents-check`.
check-agents:
    just agents-check

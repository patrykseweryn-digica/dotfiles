set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

default:
    just --list

install:
    ./install.sh

smoke:
    ./scripts/smoke-tool-plan.sh
    ./scripts/smoke-zsh-plan.sh
    ./scripts/smoke-agent-repo-layout.sh
    ./scripts/smoke-install-dotfiles.sh
    ./scripts/smoke-macos-apps.sh
    ./scripts/smoke-agent-skill-sync.sh

sync-agents:
    ./sync-agents.sh install

check-agents:
    ./sync-agents.sh codex-check
    ./sync-agents.sh opencode-check
    ./sync-agents.sh claude-prune --check
    ./sync-agents.sh claude-settings-check

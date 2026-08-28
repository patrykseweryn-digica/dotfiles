#!/bin/bash
set -uo pipefail

default_dotfiles_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$default_dotfiles_dir}"
SYNC_AGENTS="${SYNC_AGENTS:-${DOTFILES_DIR}/sync-agents.sh}"
AGENT_TOOLS="${AGENT_TOOLS:-${DOTFILES_DIR}/scripts/agent-tools.sh}"
failed=false

run_check() {
    local label="$1"
    shift

    echo "[INFO] Checking ${label}..."
    if "$@"; then
        echo "[PASS] ${label}"
    else
        echo "[FAIL] ${label}" >&2
        failed=true
    fi
}

check_agent_links() {
    local source target root link broken=false

    while IFS='|' read -r source target; do
        [ -n "$source" ] || continue
        if [ ! -L "$target" ] || [ "$(readlink "$target")" != "$source" ]; then
            echo "[ERROR] Link drift: $target -> $source" >&2
            broken=true
        fi
    done <<EOF
${DOTFILES_DIR}/config/codex/AGENTS.md|${HOME}/.codex/AGENTS.md
${DOTFILES_DIR}/config/claude/CLAUDE.md|${HOME}/.claude/CLAUDE.md
${DOTFILES_DIR}/config/opencode/AGENTS.md|${HOME}/.config/opencode/AGENTS.md
${DOTFILES_DIR}/config/pi/AGENTS.md|${HOME}/.pi/agent/AGENTS.md
EOF

    for root in \
        "${HOME}/.agents/skills" \
        "${HOME}/.claude/skills" \
        "${HOME}/.config/opencode/skills" \
        "${HOME}/.pi/agent/skills"; do
        [ -d "$root" ] || continue
        for link in "$root"/*; do
            [ -L "$link" ] && [ ! -e "$link" ] || continue
            echo "[ERROR] Broken skill link: $link" >&2
            echo "        -> $(readlink "$link")" >&2
            broken=true
        done
    done

    [ "$broken" = false ]
}

run_check "plugin drift" "$SYNC_AGENTS" plugins-check
run_check "Claude settings" "$SYNC_AGENTS" claude-settings-check
run_check "MCP drift" "$SYNC_AGENTS" mcp-check
run_check "Pi settings and packages" "$SYNC_AGENTS" pi-check
run_check "skill inventory" "$SYNC_AGENTS" skills-check
run_check "agent links" check_agent_links
run_check "agent tool versions" "$AGENT_TOOLS" check

if [ "$failed" = true ]; then
    echo "[ERROR] Live machine drift detected" >&2
    exit 1
fi

echo "[INFO] Live machine matches repository intent"

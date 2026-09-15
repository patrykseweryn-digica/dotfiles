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
${DOTFILES_DIR}/config/claude/settings.local.json|${HOME}/.claude/settings.local.json
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

    [ "$broken" = false ] || echo "Run: ./install.sh" >&2
    [ "$broken" = false ]
}

check_herdr_hook() {
    local settings="${CLAUDE_SETTINGS_FILE:-${HOME}/.claude/settings.json}"
    local hook="${HOME}/.claude/hooks/herdr-agent-state.sh"

    if [ ! -f "$settings" ]; then
        echo "[FAIL] Herdr Claude hook: settings missing: $settings" >&2
        echo "Run: ./sync-agents.sh claude-install" >&2
        return 1
    fi
    if ! jq -e -s 'length == 1 and (.[0] | type == "object")' "$settings" >/dev/null; then
        echo "[FAIL] Herdr Claude hook: invalid settings: $settings" >&2
        echo "Run: ./sync-agents.sh claude-install" >&2
        return 1
    fi
    if jq -e '.disableAllHooks == true' "$settings" >/dev/null; then
        echo "[SKIP] Herdr Claude hook: disableAllHooks is true"
    elif ! jq -e '[.hooks.SessionStart[]?.hooks[]? |
        select(.type == "command") | .command |
        select(contains("herdr-agent-state.sh"))] | length > 0' \
        "$settings" >/dev/null; then
        echo "[SKIP] Herdr Claude hook: no Herdr SessionStart hook configured"
    elif [ -f "$hook" ] && [ -r "$hook" ]; then
        echo "[PASS] Herdr Claude hook"
    else
        echo "[FAIL] Herdr Claude hook missing or unreadable: $hook" >&2
        echo "Run: herdr integration install claude && ./sync-agents.sh claude-install" >&2
        return 1
    fi
}

run_check "plugin drift" "$SYNC_AGENTS" plugins-check
run_check "Codex settings" "$SYNC_AGENTS" codex-check
run_check "Claude settings" "$SYNC_AGENTS" claude-settings-check
check_herdr_hook || failed=true
run_check "OpenCode settings" "$SYNC_AGENTS" opencode-check
run_check "Kimi settings" "$SYNC_AGENTS" kimi-check
run_check "MCP drift" "$SYNC_AGENTS" mcp-check
run_check "Pi settings and packages" "$SYNC_AGENTS" pi-check
run_check "skill inventory" "$SYNC_AGENTS" skills-check
run_check "agent links" check_agent_links
run_check "agent tool versions" "$AGENT_TOOLS" check
run_check "Node version" bash "$DOTFILES_DIR/bootstrap.d/07-node.sh" check

if [ "$failed" = true ]; then
    echo "[ERROR] Live machine drift detected" >&2
    exit 1
fi

echo "[INFO] Live machine matches repository intent"

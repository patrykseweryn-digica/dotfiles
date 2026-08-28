#!/bin/bash
set -uo pipefail

default_dotfiles_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$default_dotfiles_dir}"
SYNC_AGENTS="${SYNC_AGENTS:-${DOTFILES_DIR}/sync-agents.sh}"
AGENT_TOOLS="${AGENT_TOOLS:-${DOTFILES_DIR}/scripts/agent-tools.sh}"
REPO_SKILL_LOCK="${SKILL_LOCK_REPO:-${DOTFILES_DIR}/.agents/skill-lock.json}"
LIVE_SKILL_LOCK="${SKILL_LOCK_LIVE:-${HOME}/.agents/.skill-lock.json}"
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

normalize_skill_lock() {
    jq -S '{
        skills: (.skills | map_values(
            del(.skillFolderHash, .installedAt, .updatedAt)
        )),
        dismissed
    }' "$1" > "$2"
}

check_skill_lock() {
    if [ ! -f "$LIVE_SKILL_LOCK" ]; then
        echo "[ERROR] Missing live skill lock: $LIVE_SKILL_LOCK" >&2
        return 1
    fi

    local repo_lock live_lock
    repo_lock="$(mktemp)"
    live_lock="$(mktemp)"
    if ! normalize_skill_lock "$REPO_SKILL_LOCK" "$repo_lock" ||
        ! normalize_skill_lock "$LIVE_SKILL_LOCK" "$live_lock"; then
        rm -f "$repo_lock" "$live_lock"
        return 1
    fi

    if cmp -s "$repo_lock" "$live_lock"; then
        rm -f "$repo_lock" "$live_lock"
        return 0
    fi

    echo "[ERROR] Live skill lock differs from repository intent" >&2
    diff -u "$repo_lock" "$live_lock" >&2 || true
    rm -f "$repo_lock" "$live_lock"
    return 1
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
        if [ ! -d "$root" ]; then
            echo "[ERROR] Missing skill directory: $root" >&2
            broken=true
            continue
        fi
        for link in "$root"/*; do
            [ -L "$link" ] || continue
            if [ ! -e "$link" ]; then
                echo "[ERROR] Broken skill link: $link" >&2
                echo "        -> $(readlink "$link")" >&2
                broken=true
            fi
        done
    done

    [ "$broken" = false ]
}

run_check "plugin drift" "$SYNC_AGENTS" plugins-check
run_check "Claude settings" "$SYNC_AGENTS" claude-settings-check
run_check "MCP drift" "$SYNC_AGENTS" mcp-check
run_check "Pi settings and packages" "$SYNC_AGENTS" pi-check
run_check "custom skill drift" \
    "$SYNC_AGENTS" custom-skills-export --check
run_check "skill lock drift" check_skill_lock
run_check "agent links" check_agent_links
run_check "agent tool versions" "$AGENT_TOOLS" check

if [ "$failed" = true ]; then
    echo "[ERROR] Live machine drift detected" >&2
    exit 1
fi

echo "[INFO] Live machine matches repository intent"

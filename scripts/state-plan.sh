#!/bin/bash
set -uo pipefail

default_dotfiles_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$default_dotfiles_dir}"
AGENT_TOOLS="${AGENT_TOOLS:-${DOTFILES_DIR}/scripts/agent-tools.sh}"
SYNC_AGENTS="${SYNC_AGENTS:-${DOTFILES_DIR}/sync-agents.sh}"
NODE_CHECK="${NODE_CHECK:-${DOTFILES_DIR}/bootstrap.d/07-node.sh}"

validate_plan() {
    local status category action message extra failed=false

    while IFS=$'\t' read -r status category action message extra; do
        if [ -n "${extra:-}" ] || [ -z "$message" ]; then
            echo "[ERROR] Invalid state plan row" >&2
            failed=true
            continue
        fi
        case "$status" in
        PASS | UPDATE | EXPORT | FAIL) ;;
        *)
            echo "[ERROR] Invalid state plan status" >&2
            failed=true
            continue
            ;;
        esac
        case "$action" in
        none | update | export) ;;
        *)
            echo "[ERROR] Invalid state plan action" >&2
            failed=true
            continue
            ;;
        esac
        if [ -z "$category" ]; then
            echo "[ERROR] Invalid state plan content" >&2
            failed=true
            continue
        fi
        printf '%s\t%s\t%s\t%s\n' \
            "$status" "$category" "$action" "$message"
    done

    [ "$failed" = false ]
}

plan_sync() {
    "$SYNC_AGENTS" --quiet state-plan
}

plan_tools() {
    "$AGENT_TOOLS" plan
}

plan_links() {
    local source target root link broken=false

    while IFS='|' read -r source target; do
        [ -n "$source" ] || continue
        if [ ! -L "$target" ] || [ "$(readlink "$target")" != "$source" ]; then
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
            broken=true
        done
    done

    if [ "$broken" = true ]; then
        printf 'FAIL\tlinks\tupdate\tManaged links are missing or broken\n'
    else
        printf 'PASS\tlinks\tnone\tManaged links match repository intent\n'
    fi
}

plan_herdr_hook() {
    local settings="${CLAUDE_SETTINGS_FILE:-${HOME}/.claude/settings.json}"
    local hook="${HOME}/.claude/hooks/herdr-agent-state.sh"

    if [ ! -f "$settings" ] ||
        ! jq -e -s 'length == 1 and (.[0] | type == "object")' \
            "$settings" >/dev/null 2>&1; then
        printf 'FAIL\thooks\tupdate\tClaude hook settings are missing or invalid\n'
    elif jq -e '.disableAllHooks == true' "$settings" >/dev/null ||
        ! jq -e '[.hooks.SessionStart[]?.hooks[]? |
            select(.type == "command") | .command |
            select(contains("herdr-agent-state.sh"))] | length > 0' \
            "$settings" >/dev/null; then
        printf 'PASS\thooks\tnone\tHerdr hook is intentionally inactive\n'
    elif [ -f "$hook" ] && [ -r "$hook" ]; then
        printf 'PASS\thooks\tnone\tHerdr hook is available\n'
    else
        printf 'FAIL\thooks\tupdate\tEnabled Herdr hook is missing or unreadable\n'
    fi
}

plan_node() {
    local status=0

    bash "$NODE_CHECK" check >/dev/null 2>&1 || status=$?
    case "$status" in
    0) printf 'PASS\tnode\tnone\tNode matches the local version policy\n' ;;
    2) printf 'UPDATE\tnode\tupdate\tActive Node needs the local repository state\n' ;;
    *) printf 'FAIL\tnode\tupdate\tNode is missing, invalid, or unreadable\n' ;;
    esac
}

plan_platform() {
    local os arch
    os="$(uname -s)"
    arch="$(uname -m)"

    case "$os:$arch" in
    Darwin:arm64 | Darwin:x86_64 | Linux:arm64 | Linux:aarch64 | Linux:x86_64)
        printf 'PASS\tplatform\tnone\t%s %s is supported\n' "$os" "$arch"
        ;;
    *)
        printf 'FAIL\tplatform\tupdate\t%s %s is not supported\n' "$os" "$arch"
        ;;
    esac
}

plan_all() {
    plan_sync || return
    plan_tools || return
    plan_links || return
    plan_herdr_hook || return
    plan_node || return
    plan_platform
}

case "${1:-all}" in
all)
    plan_all 2>/dev/null | validate_plan
    ;;
tools)
    plan_tools 2>/dev/null | validate_plan
    ;;
*)
    echo "Usage: $0 [all|tools]" >&2
    exit 1
    ;;
esac

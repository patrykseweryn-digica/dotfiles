#!/bin/bash
set -uo pipefail

default_dotfiles_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$default_dotfiles_dir}"
AGENT_TOOLS="${AGENT_TOOLS:-${DOTFILES_DIR}/scripts/agent-tools.sh}"
CORE_TOOLS="${CORE_TOOLS:-${DOTFILES_DIR}/scripts/core-tools.sh}"
SYNC_AGENTS="${SYNC_AGENTS:-${DOTFILES_DIR}/sync-agents.sh}"
NODE_CHECK="${NODE_CHECK:-${DOTFILES_DIR}/bootstrap.d/07-node.sh}"

# shellcheck source=managed-links.sh
source "${DOTFILES_DIR}/scripts/managed-links.sh"
# shellcheck source=bootstrap.d/02-zsh.sh
source "${DOTFILES_DIR}/bootstrap.d/02-zsh.sh"

validate_plan() {
    local status category action message extra failed=false

    while IFS=$'\t' read -r status category action message extra; do
        if [ -n "${extra:-}" ] || [ -z "$message" ]; then
            echo "[ERROR] Invalid state plan row" >&2
            failed=true
            continue
        fi
        case "$status" in
        PASS | SKIP | UPDATE | EXPORT | FAIL) ;;
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
        if [ "$status" = SKIP ] && [ "$action" != none ]; then
            echo "[ERROR] SKIP cannot request an action" >&2
            failed=true
            continue
        fi
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
    "$CORE_TOOLS" plan || return
    "$AGENT_TOOLS" plan
}

plan_links() {
    local rows skipped source target group root link broken=false

    rows="$(managed_link_rows selected)" || return 1
    skipped="$(managed_link_rows skipped)" || return 1
    while IFS='|' read -r source target; do
        [ -n "$target" ] || continue
        if [ ! -L "$target" ] || [ "$(readlink "$target")" != "$source" ]; then
            broken=true
        fi
    done <<<"$rows"
    while IFS='|' read -r group target; do
        [ -z "$target" ] || group_skip_row links "$target" "$group"
    done <<<"$skipped"

    # Agent runtimes own these skill directories.
    local -a skill_roots=()
    if group_selected agents; then
        skill_roots=(
            "${HOME}/.agents/skills"
            "${HOME}/.claude/skills"
            "${HOME}/.config/opencode/skills"
            "${HOME}/.pi/agent/skills"
        )
    fi
    for root in ${skill_roots[@]+"${skill_roots[@]}"}; do
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

# Name each unselected group whose managed links are still installed.
# Without a setting only core is selected, so a machine set up before that
# default keeps its other groups installed but no longer updates them.
plan_groups() {
    local installed group

    installed="$(managed_link_rows installed)" || return 1
    for group in $DOTFILES_GROUP_NAMES; do
        grep -Fx "$group" <<<"$installed" >/dev/null || continue
        printf 'SKIP\tgroups\tnone\t%s %s\n' \
            "Group ${group} is installed but not selected;" \
            "dotfiles do not update it. Run: just enable ${group}"
    done
}

# Login shells that skip .zshrc find mise tools through ~/.zprofile.
plan_shell() {
    if mise_shims_profile_current; then
        printf 'PASS\tshell\tnone\tLogin shells find mise tools\n'
    else
        printf 'UPDATE\tshell\tupdate\t%s\n' \
            'Login shells do not find mise tools; ~/.zprofile needs the dotfiles block'
    fi
}

plan_node() {
    local status=0

    if ! group_selected agents; then
        group_skip_row node "Node" agents
        return 0
    fi
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
    plan_groups || return
    plan_shell || return
    plan_node || return
    plan_platform
}

# Reject an invalid group setting before planning any element.
groups_load || exit 1

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

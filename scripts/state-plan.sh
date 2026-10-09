#!/bin/bash
set -uo pipefail

default_dotfiles_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$default_dotfiles_dir}"
AGENT_TOOLS="${AGENT_TOOLS:-${DOTFILES_DIR}/scripts/agent-tools.sh}"

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
            echo "[ERROR] Invalid state plan status: $status" >&2
            failed=true
            continue
            ;;
        esac
        case "$action" in
        none | update | export) ;;
        *)
            echo "[ERROR] Invalid state plan action: $action" >&2
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

plan_tools() {
    "$AGENT_TOOLS" plan | validate_plan
}

case "${1:-all}" in
all | tools)
    plan_tools
    ;;
*)
    echo "Usage: $0 [all|tools]" >&2
    exit 1
    ;;
esac

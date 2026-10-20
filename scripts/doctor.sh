#!/bin/bash
set -uo pipefail

default_dotfiles_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$default_dotfiles_dir}"
STATE_PLAN="${STATE_PLAN:-${DOTFILES_DIR}/scripts/state-plan.sh}"
failed=false

run_plan() {
    local output status category action message

    output=$(mktemp) || return 1
    if ! "$STATE_PLAN" all >"$output" 2>&1; then
        sed -n -E '/^\[(ERROR|WARN|FAIL)\]/p' "$output" | sed -n '1,20p'
        echo "[FAIL] state plan" >&2
        rm -f "$output"
        failed=true
        return
    fi

    while IFS=$'\t' read -r status category action message; do
        echo "[$status] ${category}: ${message}"
        case "$action" in
        update) echo "Run: just sync" ;;
        export) echo "Run: just export" ;;
        esac
        [ "$status" != FAIL ] || failed=true
    done <"$output"
    rm -f "$output"
}
run_plan

if [ "$failed" = true ]; then
    echo "[ERROR] Live machine failures detected" >&2
    exit 1
fi

echo "[INFO] Live machine matches repository intent"

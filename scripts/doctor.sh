#!/bin/bash
set -uo pipefail

default_dotfiles_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$default_dotfiles_dir}"
STATE_PLAN="${STATE_PLAN:-${DOTFILES_DIR}/scripts/state-plan.sh}"
failed=false
unaligned=false

run_plan() {
    local output status category action message

    output=$(mktemp) || {
        echo "[FAIL] Could not create the state plan file" >&2
        return 1
    }
    if ! "$STATE_PLAN" all >"$output" 2>&1; then
        sed -n -E '/^\[(ERROR|WARN|FAIL)\]/p' "$output" | sed -n '1,20p'
        echo "[FAIL] state plan" >&2
        rm -f "$output"
        return 1
    fi

    while IFS=$'\t' read -r status category action message; do
        echo "[$status] ${category}: ${message}"
        case "$action" in
        update) echo "Run: just sync" ;;
        export) echo "Run: just export" ;;
        esac
        case "$status" in
        FAIL) failed=true ;;
        UPDATE | EXPORT) unaligned=true ;;
        esac
    done <"$output"
    rm -f "$output"
}
if ! run_plan || [ "$failed" = true ]; then
    echo "[ERROR] Live machine failures detected" >&2
    exit 1
fi

if [ "$unaligned" = true ]; then
    echo "[INFO] Live machine differs from repository intent"
else
    echo "[INFO] Live machine matches repository intent"
fi

#!/bin/bash
set -uo pipefail

default_dotfiles_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$default_dotfiles_dir}"
STATE_PLAN="${STATE_PLAN:-${DOTFILES_DIR}/scripts/state-plan.sh}"
SYNC_AGENTS="${SYNC_AGENTS:-${DOTFILES_DIR}/sync-agents.sh}"
INSTALL_SCRIPT="${INSTALL_SCRIPT:-${DOTFILES_DIR}/install.sh}"

# shellcheck source=/dev/null
source "$INSTALL_SCRIPT"

plan_file="$(mktemp)" || exit 1
final_file="$(mktemp)" || {
    rm -f "$plan_file"
    exit 1
}
trap 'rm -f "$plan_file" "$final_file"' EXIT

show_plan() {
    local label="$1" file="$2"
    local status category action message

    while IFS=$'\t' read -r status category action message; do
        printf '[%s] [%s] %s: %s\n' \
            "$label" "$status" "$category" "$message"
    done <"$file"
}

apply_category() {
    local category="$1"

    case "$category" in
    settings:*)
        "$SYNC_AGENTS" settings-install "${category#settings:}"
        ;;
    mcp)
        "$SYNC_AGENTS" push-mcp
        ;;
    links)
        update_managed_links
        ;;
    hooks)
        configure_herdr_hook
        ;;
    *)
        return 2
        ;;
    esac
}

if ! "$STATE_PLAN" all >"$plan_file"; then
    echo "[ERROR] Could not build local update plan" >&2
    exit 1
fi

echo "[INFO] Local update plan"
show_plan PLAN "$plan_file"

applied=0
unchanged=0
blocked=0
failed=0
skipped=0
while IFS=$'\t' read -r status category action message; do
    case "$status:$action" in
    PASS:none)
        unchanged=$((unchanged + 1))
        ;;
    EXPORT:export)
        echo "[BLOCKED] ${category}: export local additions first"
        blocked=$((blocked + 1))
        ;;
    UPDATE:update | FAIL:update)
        echo "[APPLY] ${category}"
        apply_category "$category"
        result=$?
        case "$result" in
        0) applied=$((applied + 1)) ;;
        2)
            echo "[SKIP] ${category}: outside local configuration update"
            skipped=$((skipped + 1))
            ;;
        *)
            echo "[ERROR] Failed to update ${category}" >&2
            failed=$((failed + 1))
            ;;
        esac
        ;;
    *)
        echo "[ERROR] Invalid plan action for ${category}" >&2
        failed=$((failed + 1))
        ;;
    esac
done <"$plan_file"

if ! "$STATE_PLAN" all >"$final_file"; then
    echo "[ERROR] Could not run final local check" >&2
    exit 1
fi

echo "[INFO] Final local state"
show_plan FINAL "$final_file"

remaining=0
while IFS=$'\t' read -r status category action message; do
    case "$status" in
    PASS) ;;
    *) remaining=$((remaining + 1)) ;;
    esac
done <"$final_file"

printf '[SUMMARY] applied=%s unchanged=%s blocked=%s skipped=%s failed=%s remaining=%s\n' \
    "$applied" "$unchanged" "$blocked" "$skipped" "$failed" "$remaining"

[ "$blocked" -eq 0 ] && [ "$failed" -eq 0 ] && [ "$remaining" -eq 0 ]

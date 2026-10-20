#!/bin/bash
set -uo pipefail

default_dotfiles_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$default_dotfiles_dir}"
STATE_PLAN="${STATE_PLAN:-${DOTFILES_DIR}/scripts/state-plan.sh}"
SYNC_AGENTS="${SYNC_AGENTS:-${DOTFILES_DIR}/sync-agents.sh}"
INSTALL_SCRIPT="${INSTALL_SCRIPT:-${DOTFILES_DIR}/install.sh}"
AGENT_TOOLS="${AGENT_TOOLS:-${DOTFILES_DIR}/scripts/agent-tools.sh}"

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

plan_status() {
    awk -F '\t' -v category="$1" '$2 == category { print $1; exit }' \
        "$plan_file"
}

refresh_phase() {
    local label="$1"
    shift

    echo "[REFRESH] $label"
    if "$@"; then
        refreshed=$((refreshed + 1))
    else
        echo "[ERROR] Failed to refresh $label" >&2
        failed=$((failed + 1))
    fi
}

refresh_core_tools() {
    ensure_install_dirs && install_declared_core_tools
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
refreshed=0
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
        result=0
        apply_category "$category" || result=$?
        case "$result" in
        0) applied=$((applied + 1)) ;;
        2)
            echo "[DEFER] ${category}: handled by upstream refresh"
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

refresh_phase "missing inventory tools" refresh_core_tools
refresh_phase "latest core tools" update_declared_latest_core_tools
refresh_phase "Node and agent tools" "$AGENT_TOOLS" update

skills_status="$(plan_status skills)"
if [ "$skills_status" = EXPORT ]; then
    echo "[BLOCKED] skills upstream refresh: export local additions first"
else
    refresh_phase "skills" "$SYNC_AGENTS" skills-update
fi

plugins_status="$(plan_status plugins)"
if [ "$plugins_status" = EXPORT ]; then
    echo "[BLOCKED] plugins upstream refresh: export local additions first"
else
    if [ "$plugins_status" = UPDATE ] || [ "$plugins_status" = FAIL ]; then
        refresh_phase "plugin membership" "$SYNC_AGENTS" push-plugins
    fi
    refresh_phase "plugin versions" "$SYNC_AGENTS" plugins-update
fi

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

printf '[SUMMARY] applied=%s refreshed=%s unchanged=%s blocked=%s skipped=%s failed=%s remaining=%s\n' \
    "$applied" "$refreshed" "$unchanged" "$blocked" "$skipped" \
    "$failed" "$remaining"

if [ "$failed" -ne 0 ]; then
    echo "[RESULT] FAIL"
    exit 1
fi
if [ "$blocked" -ne 0 ]; then
    echo "[RESULT] EXPORT"
    exit 1
fi
if [ "$remaining" -ne 0 ]; then
    echo "[RESULT] FAIL"
    exit 1
fi

echo "[RESULT] PASS"

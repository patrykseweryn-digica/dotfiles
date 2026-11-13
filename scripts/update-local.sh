#!/bin/bash
set -uo pipefail

default_dotfiles_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$default_dotfiles_dir}"
STATE_PLAN="${STATE_PLAN:-${DOTFILES_DIR}/scripts/state-plan.sh}"
SYNC_AGENTS="${SYNC_AGENTS:-${DOTFILES_DIR}/sync-agents.sh}"
INSTALL_SCRIPT="${INSTALL_SCRIPT:-${DOTFILES_DIR}/install.sh}"
AGENT_TOOLS="${AGENT_TOOLS:-${DOTFILES_DIR}/scripts/agent-tools.sh}"
CORE_TOOLS="${CORE_TOOLS:-${DOTFILES_DIR}/scripts/core-tools.sh}"

# shellcheck source=/dev/null
source "$INSTALL_SCRIPT"
# shellcheck source=scripts/operation.sh
source "${default_dotfiles_dir}/scripts/operation.sh"
# shellcheck source=scripts/groups.sh
source "${default_dotfiles_dir}/scripts/groups.sh"

plan_file="$(mktemp)" || exit 1
final_file="$(mktemp)" || {
    rm -f "$plan_file"
    exit 1
}
# Child phases append one row per failed external operation.
DOTFILES_OPERATION_FAILURES="$(mktemp)" || {
    rm -f "$plan_file" "$final_file"
    exit 1
}
DOTFILES_OPERATION_LOG="${DOTFILES_OPERATION_LOG:-$(operation_sync_log_path)}"
export DOTFILES_OPERATION_FAILURES DOTFILES_OPERATION_LOG
trap 'rm -f "$plan_file" "$final_file" "$DOTFILES_OPERATION_FAILURES"' EXIT

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
    shell)
        configure_mise_shims_profile
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

failure_count() {
    wc -l <"$DOTFILES_OPERATION_FAILURES" | tr -d ' '
}

# Record a failure that no external operation explained.
record_unexplained_failure() {
    local element="$1" operation="$2" status="$3" before="$4"
    [ "$(failure_count)" -eq "$before" ] || return 0
    operation_record_failure "$element" "$operation" "unknown cause" \
        "$status" "Read the output above and the log: ${DOTFILES_OPERATION_LOG}"
}

refresh_phase() {
    local label="$1" before status=0
    shift

    echo "[REFRESH] $label"
    before="$(failure_count)"
    "$@" || status=$?
    if [ "$status" -eq 0 ]; then
        refreshed=$((refreshed + 1))
        return 0
    fi
    echo "[ERROR] Failed to refresh $label" >&2
    failed=$((failed + 1))
    failed_phases+=("$label")
    record_unexplained_failure "$label" refresh "$status" "$before"
    return 1
}

# A phase of an unselected group does not run.
skip_phase() {
    echo "[SKIP] $2: $(group_skip_reason "$1")"
    skipped=$((skipped + 1))
}

# Refresh a phase only when its group is selected.
group_phase() {
    local group="$1" label="$2"
    shift 2

    if group_selected "$group"; then
        refresh_phase "$label" "$@"
    else
        skip_phase "$group" "$label"
    fi
}

# A dependent phase does not run after its prerequisite failed.
not_run_phase() {
    echo "[NOT RUN] $1: $2"
    not_run=$((not_run + 1))
}

# Reject an invalid group setting before any machine change.
if ! groups_load; then
    echo "[RESULT] FAIL"
    exit 1
fi

if ! "$STATE_PLAN" all >"$plan_file"; then
    echo "[ERROR] Could not build local update plan" >&2
    echo "Run: just doctor to see which check failed" >&2
    echo "[RESULT] FAIL"
    exit 1
fi

echo "[INFO] Local update plan"
show_plan PLAN "$plan_file"

# A local addition needs a decision before anything changes the environment.
blocked=0
while IFS=$'\t' read -r status category action message; do
    if [ "$status" = EXPORT ]; then
        echo "[BLOCKED] ${category}: ${message}"
        blocked=$((blocked + 1))
    fi
done <"$plan_file"
if [ "$blocked" -gt 0 ]; then
    echo "Run: just export to keep the additions, or remove them; then run: just sync"
    echo "[RESULT] EXPORT"
    exit 1
fi

applied=0
unchanged=0
failed=0
skipped=0
not_run=0
refreshed=0
failed_phases=()
while IFS=$'\t' read -r status category action message; do
    case "$status:$action" in
    PASS:none)
        unchanged=$((unchanged + 1))
        ;;
    SKIP:none)
        echo "[SKIP] ${category}: ${message}"
        skipped=$((skipped + 1))
        ;;
    UPDATE:update | FAIL:update)
        echo "[APPLY] ${category}"
        before="$(failure_count)"
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
            record_unexplained_failure "$category" apply "$result" "$before"
            ;;
        esac
        ;;
    *)
        echo "[ERROR] Invalid plan action for ${category}" >&2
        failed=$((failed + 1))
        operation_record_failure "$category" plan "invalid plan row" 1 \
            "Report the plan row as a dotfiles bug"
        ;;
    esac
done <"$plan_file"

group_phase core "core tools" env CORE_TOOLS_HAS_SUDO="${HAS_SUDO:-false}" \
    "$CORE_TOOLS" update
if group_selected agents; then
    refresh_phase "Node and agent tools" "$AGENT_TOOLS" update
    # The refresh activates Node only in its own process. Later phases and
    # the final check must use the same runtime and its global CLIs.
    node_ready=true
    if ! activate_node >/dev/null; then
        echo "[ERROR] Could not activate the installed Node LTS" >&2
        node_ready=false
        failed=$((failed + 1))
        failed_phases+=("Node activation")
        operation_record_failure Node activate "Node could not be activated" 1 \
            "Run: just install"
    fi

    if [ "$node_ready" = true ]; then
        refresh_phase "Pi packages" "$SYNC_AGENTS" pi-packages-update
        refresh_phase "skills" "$SYNC_AGENTS" skills-update
    else
        not_run_phase "Pi packages" "requires Node, which could not be activated"
        not_run_phase "skills" "requires Node, which could not be activated"
    fi

    membership_ok=true
    plugins_status="$(plan_status plugins)"
    if [ "$plugins_status" = UPDATE ] || [ "$plugins_status" = FAIL ]; then
        refresh_phase "plugin membership" "$SYNC_AGENTS" push-plugins ||
            membership_ok=false
    fi
    if [ "$membership_ok" = true ]; then
        refresh_phase "plugin versions" "$SYNC_AGENTS" plugins-update
    else
        not_run_phase "plugin versions" "requires plugin membership, which failed"
    fi
else
    for phase in "Node and agent tools" "Pi packages" skills \
        "plugin membership" "plugin versions"; do
        skip_phase agents "$phase"
    done
fi

remaining=0
before="$(failure_count)"
final_status=0
"$STATE_PLAN" all >"$final_file" || final_status=$?
if [ "$final_status" -eq 0 ]; then
    echo "[INFO] Final local state"
    show_plan FINAL "$final_file"
    while IFS=$'\t' read -r status category action message; do
        case "$status" in
        PASS | SKIP) ;;
        *) remaining=$((remaining + 1)) ;;
        esac
    done <"$final_file"
else
    echo "[ERROR] Could not run final local check" >&2
    failed=$((failed + 1))
    failed_phases+=("final check")
    record_unexplained_failure "final check" plan "$final_status" "$before"
fi

printf '[SUMMARY] applied=%s refreshed=%s unchanged=%s skipped=%s not_run=%s failed=%s remaining=%s\n' \
    "$applied" "$refreshed" "$unchanged" "$skipped" "$not_run" "$failed" \
    "$remaining"
if [ "${#failed_phases[@]}" -gt 0 ]; then
    printf '[FAILED] phases:'
    printf ' %s;' "${failed_phases[@]}"
    printf '\n'
fi
while IFS=$'\t' read -r element operation cause status next; do
    printf '[PROBLEM] %s: %s - %s (exit %s). Next: %s\n' \
        "$element" "$operation" "$cause" "$status" "$next"
done <"$DOTFILES_OPERATION_FAILURES"
if [ -s "$DOTFILES_OPERATION_FAILURES" ]; then
    echo "[LOG] ${DOTFILES_OPERATION_LOG}"
fi

if [ "$failed" -ne 0 ] || [ "$remaining" -ne 0 ]; then
    echo "[RESULT] FAIL"
    exit 1
fi

echo "[RESULT] PASS"

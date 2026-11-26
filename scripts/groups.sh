#!/bin/bash
# Install groups select which inventory elements a machine installs.
# The local environment file sets DOTFILES_GROUPS, for example:
#   DOTFILES_GROUPS=core,agents
# No setting selects core only. Core is always required.
# Run as a script to show or change the setting: see groups_main.

DOTFILES_GROUP_NAMES="core agents desktop"
DOTFILES_SELECTED_GROUPS=""

# Describe what each group installs in at most 36 characters, so that the
# groups table stays below 80 columns. The menu smoke test checks the width.
group_description() {
    case "$1" in
    core) echo "Shell, Git, SSH and CLI tools" ;;
    agents) echo "AI agents, skills, MCP and Node.js" ;;
    desktop) echo "Fonts, terminal colors and GUI apps" ;;
    esac
}

# jq filters for inventory entries; pass --arg groups and --arg names.
# shellcheck disable=SC2034
GROUP_SELECTED_JQ='(.group as $group |
    $groups | split(" ") | index($group) != null)'
# shellcheck disable=SC2034
GROUP_VALID_JQ='(.group as $group |
    $names | split(" ") | index($group) != null)'

groups_env_file() {
    printf '%s\n' "${DOTFILES_ENV_FILE:-${DOTFILES_DIR}/.env}"
}

# Read only the environment file, so every entry point uses one source.
# A file that cannot be sourced fails instead of selecting every group.
groups_setting() {
    local env_file
    env_file="$(groups_env_file)"
    [ -f "$env_file" ] || return 0
    (
        unset DOTFILES_GROUPS
        set +eu
        # shellcheck disable=SC1090
        . "$env_file" >/dev/null 2>&1 || exit 1
        printf '%s' "${DOTFILES_GROUPS-}"
    )
}

# Validate the setting and store the selected groups in canonical order.
groups_load() {
    local raw group known selected="" env_file
    local -a words=()

    env_file="$(groups_env_file)"
    raw="$(groups_setting)" || {
        echo "[ERROR] Could not read DOTFILES_GROUPS from ${env_file}" >&2
        return 1
    }
    read -r -a words <<<"${raw//,/ }"
    if [ "${#words[@]}" -eq 0 ]; then
        DOTFILES_SELECTED_GROUPS=core
        return 0
    fi
    for group in "${words[@]}"; do
        case " $DOTFILES_GROUP_NAMES " in
        *" $group "*) ;;
        *)
            printf '[ERROR] Unknown install group "%s" in %s (%s). %s\n' \
                "$group" DOTFILES_GROUPS "$env_file" \
                "Use: ${DOTFILES_GROUP_NAMES// /, }" >&2
            return 1
            ;;
        esac
    done
    for known in $DOTFILES_GROUP_NAMES; do
        case " ${words[*]} " in
        *" $known "*) selected="${selected:+$selected }$known" ;;
        esac
    done
    case " $selected " in
    *" core "*) ;;
    *)
        printf '[ERROR] DOTFILES_GROUPS must include core (%s): %s\n' \
            "$env_file" "$raw" >&2
        return 1
        ;;
    esac
    DOTFILES_SELECTED_GROUPS="$selected"
}

# An invalid setting stops the process; it never means "not selected".
group_selected() {
    [ -n "$DOTFILES_SELECTED_GROUPS" ] || groups_load || exit 1
    case " $DOTFILES_SELECTED_GROUPS " in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
    esac
}

group_skip_reason() {
    printf 'group %s is not selected\n' "$1"
}

# Print a state plan row for an element of an unselected group.
group_skip_row() {
    local category="$1" element="$2" group="$3"
    printf 'SKIP\t%s\tnone\t%s skipped: %s\n' \
        "$category" "$element" "$(group_skip_reason "$group")"
}

# Print a public command in the syntax of the runner that called us:
#   dotfiles_command enable desktop -> just enable desktop
#                                   -> make enable group=desktop
dotfiles_command() {
    local runner="${DOTFILES_RUNNER:-just}"
    if [ "$runner" = make ] && [ $# -gt 1 ]; then
        printf 'make %s group=%s\n' "$1" "$2"
    else
        printf '%s %s\n' "$runner" "$*"
    fi
}

# Set ANSI styles for stdout. NO_COLOR or JUST_COLOR=never turns them off,
# JUST_COLOR=always turns them on, and otherwise only a terminal gets them.
groups_colors() {
    GROUPS_BOLD="" GROUPS_GREEN="" GROUPS_DIM="" GROUPS_RESET=""
    [ -z "${NO_COLOR:-}" ] || return 0
    case "${JUST_COLOR:-auto}" in
    always) ;;
    never) return 0 ;;
    *) [ -t 1 ] || return 0 ;;
    esac
    GROUPS_BOLD=$'\033[1m' GROUPS_GREEN=$'\033[32m'
    GROUPS_DIM=$'\033[2m' GROUPS_RESET=$'\033[0m'
}

# Print "<selected> of <all>" for the loaded selection.
groups_count() {
    local -a known_groups=() selected_groups=()
    read -r -a known_groups <<<"$DOTFILES_GROUP_NAMES"
    read -r -a selected_groups <<<"$DOTFILES_SELECTED_GROUPS"
    printf '%s of %s\n' "${#selected_groups[@]}" "${#known_groups[@]}"
}

# Print one row per group: a mark, the name, the description and the command
# that changes the selection. Core is required, so it has no command.
# Call groups_load and groups_colors first.
groups_table() {
    local group mark hint description name_width=0 text_width=0
    for group in $DOTFILES_GROUP_NAMES; do
        description="$(group_description "$group")"
        [ "${#group}" -le "$name_width" ] || name_width="${#group}"
        [ "${#description}" -le "$text_width" ] || text_width="${#description}"
    done
    for group in $DOTFILES_GROUP_NAMES; do
        if ! group_selected "$group"; then
            mark="${GROUPS_DIM}○${GROUPS_RESET}"
            hint="$(dotfiles_command enable "$group")"
        elif [ "$group" = core ]; then
            mark="${GROUPS_GREEN}✓${GROUPS_RESET}"
            hint=required
        else
            mark="${GROUPS_GREEN}✓${GROUPS_RESET}"
            hint="$(dotfiles_command disable "$group")"
        fi
        printf '    %s %-*s  %-*s  %s\n' "$mark" "$name_width" "$group" \
            "$text_width" "$(group_description "$group")" \
            "${GROUPS_DIM}${hint}${GROUPS_RESET}"
    done
}

# Print the install groups of this machine as a table.
groups_show() {
    groups_load || return 1
    groups_colors
    printf '%sInstall groups - %s selected%s\n' \
        "$GROUPS_BOLD" "$(groups_count)" "$GROUPS_RESET"
    groups_table
}

# Write DOTFILES_GROUPS=<groups> into the env file. The first setting line
# keeps its position, other setting lines go, and other lines stay. With no
# setting line, the setting goes at the end.
groups_write() {
    local value="${1// /,}" env_file tmp
    env_file="$(groups_env_file)"
    tmp="$(mktemp "${env_file}.XXXXXX")" || return 1
    if ! awk -v line="DOTFILES_GROUPS=${value}" '
        /^[[:space:]]*(export[[:space:]]+)?DOTFILES_GROUPS=/ {
            if (!written) print line
            written = 1
            next
        }
        { print }
        END { if (!written) print line }
    ' "$env_file" >"$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    # Copy into the file so its mode and any symlink stay unchanged.
    cat "$tmp" >"$env_file" || {
        rm -f "$tmp"
        return 1
    }
    rm -f "$tmp"
    DOTFILES_SELECTED_GROUPS=""
    groups_load
}

# Add or remove one group in the env file.
groups_change() {
    local command="$1" group="$2" env_file known selected=""
    env_file="$(groups_env_file)"
    [ -f "$env_file" ] || {
        echo "[ERROR] ${env_file} does not exist. Run: ${DOTFILES_RUNNER:-just} install" >&2
        return 1
    }
    case " $DOTFILES_GROUP_NAMES " in
    *" $group "*) ;;
    *)
        printf '[ERROR] Unknown install group "%s". Use: %s\n' \
            "$group" "${DOTFILES_GROUP_NAMES// /, }" >&2
        return 1
        ;;
    esac
    groups_load || return 1
    if [ "$command:$group" = disable:core ]; then
        echo "[ERROR] Group core is required; it cannot be disabled" >&2
        return 1
    fi
    case "$command" in
    enable)
        if group_selected "$group"; then
            echo "[INFO] Group ${group} is already selected"
            return 0
        fi
        ;;
    disable)
        if ! group_selected "$group"; then
            echo "[INFO] Group ${group} is not selected"
            return 0
        fi
        ;;
    esac
    for known in $DOTFILES_GROUP_NAMES; do
        if [ "$known" = "$group" ]; then
            [ "$command" = disable ] && continue
        else
            group_selected "$known" || continue
        fi
        selected="${selected:+$selected }$known"
    done
    groups_write "$selected" || return 1
    echo "[INFO] Install groups: ${DOTFILES_SELECTED_GROUPS// /, }"
    if [ "$command" = disable ]; then
        echo "[INFO] Installed elements of group ${group} stay on this machine;" \
            "dotfiles no longer install or update them"
    fi
}

# Let the user pick the group for `enable` or `disable` from a numbered list,
# and store it in GROUPS_CHOICE. Enable offers unselected groups; disable
# offers selected groups but core. Nothing to choose, or an empty answer,
# leaves GROUPS_CHOICE empty and succeeds. Without a terminal on stdin, or
# with an answer outside the list, print the reason and fail.
groups_choose() {
    local command="$1" group answer range index=0 width=0 names=""
    local -a choices=()
    GROUPS_CHOICE=""
    groups_load || return 1
    for group in $DOTFILES_GROUP_NAMES; do
        if group_selected "$group"; then
            [ "$command" = disable ] && [ "$group" != core ] || continue
        else
            [ "$command" = enable ] || continue
        fi
        choices+=("$group")
        names="${names:+$names, }$group"
        [ "${#group}" -le "$width" ] || width="${#group}"
    done
    if [ "${#choices[@]}" -eq 0 ]; then
        if [ "$command" = enable ]; then
            echo "[INFO] All install groups are already selected"
        else
            echo "[INFO] Only core is selected, and core is required"
        fi
        return 0
    fi
    if [ ! -t 0 ]; then
        printf 'Usage: %s, where NAME is one of: %s\n' \
            "$(dotfiles_command "$command" NAME)" "$names" >&2
        return 1
    fi
    printf 'Install groups you can %s:\n' "$command" >&2
    for group in "${choices[@]}"; do
        index=$((index + 1))
        printf '    %s) %-*s  %s\n' "$index" "$width" "$group" \
            "$(group_description "$group")" >&2
    done
    range=1
    [ "$index" -eq 1 ] || range="1-${index}"
    printf 'Group number [%s, Enter cancels]: ' "$range" >&2
    IFS= read -r answer || echo >&2
    case "$answer" in
    "")
        echo "[INFO] No group chosen; nothing changed"
        return 0
        ;;
    *[!0-9]*) ;;
    *)
        if [ "$answer" -ge 1 ] && [ "$answer" -le "$index" ]; then
            GROUPS_CHOICE="${choices[answer - 1]}"
            return 0
        fi
        ;;
    esac
    printf '[ERROR] "%s" is not a group number: %s\n' "$answer" "$range" >&2
    return 1
}

# Change the selection. Enable then installs the elements of the selection.
groups_apply() {
    groups_change "$1" "$2" || return 1
    [ "$1" = disable ] || "$(dirname "${BASH_SOURCE[0]}")/../install.sh"
}

groups_main() {
    case "${1:-}:${2:-}" in
    show:) groups_show ;;
    enable: | disable:)
        groups_choose "$1" || return 1
        [ -z "$GROUPS_CHOICE" ] || groups_apply "$1" "$GROUPS_CHOICE"
        ;;
    enable:?* | disable:?*) groups_apply "$1" "$2" ;;
    *)
        if [ "${DOTFILES_RUNNER:-just}" = make ]; then
            echo "Usage: make groups | make enable [group=NAME] | make disable [group=NAME]" >&2
        else
            echo "Usage: $0 show | enable [group] | disable [group]" >&2
        fi
        return 1
        ;;
    esac
}


if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    set -uo pipefail
    DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
    groups_main "$@"
fi

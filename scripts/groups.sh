#!/bin/bash
# Install groups select which inventory elements a machine installs.
# The local environment file sets DOTFILES_GROUPS, for example:
#   DOTFILES_GROUPS=core,agents
# No setting selects core only. Core is always required.
# Run as a script to show or change the setting: see groups_main.

DOTFILES_GROUP_NAMES="core agents desktop"
DOTFILES_SELECTED_GROUPS=""

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

# Print the selected groups and the other groups.
groups_show() {
    local group others=""
    groups_load || return 1
    for group in $DOTFILES_GROUP_NAMES; do
        group_selected "$group" || others="${others:+$others, }$group"
    done
    echo "[INFO] Install groups: ${DOTFILES_SELECTED_GROUPS// /, }"
    [ -z "$others" ] ||
        echo "[INFO] Not selected: ${others}. Add one with: just enable <group>"
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
        echo "[ERROR] ${env_file} does not exist. Run: just install" >&2
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

groups_main() {
    case "${1:-}:${2:-}" in
    show:) groups_show ;;
    enable:?* | disable:?*) groups_change "$1" "$2" ;;
    *)
        echo "Usage: $0 show | enable <group> | disable <group>" >&2
        return 1
        ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    set -uo pipefail
    DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
    groups_main "$@"
fi

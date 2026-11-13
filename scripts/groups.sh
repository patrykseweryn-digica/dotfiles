#!/bin/bash
# Install groups select which inventory elements a machine installs.
# The local environment file sets DOTFILES_GROUPS, for example:
#   DOTFILES_GROUPS=core,agents
# No setting selects every group. Core is always required.

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
        DOTFILES_SELECTED_GROUPS="$DOTFILES_GROUP_NAMES"
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

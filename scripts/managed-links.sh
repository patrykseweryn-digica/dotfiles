#!/bin/bash

MANAGED_LINKS_FILE="${MANAGED_LINKS_FILE:-${DOTFILES_DIR}/config/managed-links.tsv}"

# shellcheck source=scripts/groups.sh
source "${DOTFILES_DIR}/scripts/groups.sh"

# Print source|target rows for selected groups, or group|target rows for
# rows that unselected groups skip.
managed_link_rows() {
    local mode="${1:-selected}" current_platform group platform source target
    local selected

    case "${OS:-$(uname -s)}" in
    Darwin) current_platform=darwin ;;
    Linux) current_platform=linux ;;
    *)
        echo "[ERROR] Unsupported managed-link platform" >&2
        return 1
        ;;
    esac
    [ -n "$DOTFILES_SELECTED_GROUPS" ] || groups_load || return 1

    while IFS='|' read -r group platform source target; do
        case "$group" in
        \#* | "") continue ;;
        esac
        case "$platform" in
        all | "$current_platform") ;;
        darwin | linux) continue ;;
        *)
            echo "[ERROR] Invalid managed-link platform: $platform" >&2
            return 1
            ;;
        esac
        case " $DOTFILES_GROUP_NAMES " in
        *" $group "*) ;;
        *)
            echo "[ERROR] Invalid managed-link group: $group" >&2
            return 1
            ;;
        esac
        if [ -z "$source" ] || [ -z "$target" ]; then
            echo "[ERROR] Invalid managed-link declaration" >&2
            return 1
        fi
        selected=false
        ! group_selected "$group" || selected=true
        case "$mode:$selected" in
        selected:true)
            printf '%s|%s\n' "${DOTFILES_DIR}/${source}" "${HOME}/${target}"
            ;;
        skipped:false) printf '%s|%s\n' "$group" "$target" ;;
        esac
    done <"$MANAGED_LINKS_FILE"
}

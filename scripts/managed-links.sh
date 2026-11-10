#!/bin/bash

MANAGED_LINKS_FILE="${MANAGED_LINKS_FILE:-${DOTFILES_DIR}/config/managed-links.tsv}"

managed_link_rows() {
    local current_platform platform source target

    case "${OS:-$(uname -s)}" in
    Darwin) current_platform=darwin ;;
    Linux) current_platform=linux ;;
    *)
        echo "[ERROR] Unsupported managed-link platform" >&2
        return 1
        ;;
    esac

    while IFS='|' read -r platform source target; do
        case "$platform" in
        \#* | "") continue ;;
        all | "$current_platform") ;;
        darwin | linux) continue ;;
        *)
            echo "[ERROR] Invalid managed-link platform: $platform" >&2
            return 1
            ;;
        esac
        if [ -z "$source" ] || [ -z "$target" ]; then
            echo "[ERROR] Invalid managed-link declaration" >&2
            return 1
        fi
        printf '%s|%s\n' "${DOTFILES_DIR}/${source}" "${HOME}/${target}"
    done <"$MANAGED_LINKS_FILE"
}

#!/bin/bash

# Explicit dotfiles target, never an inherited agent session's FM_HOME.
setup_firstmate() {
    local home="${DOTFILES_FIRSTMATE_HOME:-}"
    local source_path="$DOTFILES_DIR/config/firstmate/crew-dispatch.json"
    local target_path

    if [ -z "$home" ]; then
        echo "[INFO] Skipping Firstmate dispatch: DOTFILES_FIRSTMATE_HOME not set"
        return 0
    fi
    if [[ "$home" != /* ]] || [ ! -d "$home/config" ]; then
        echo "[ERROR] DOTFILES_FIRSTMATE_HOME must be an absolute Firstmate home with config/" >&2
        return 1
    fi
    target_path="$home/config/crew-dispatch.json"
    if ! command -v jq >/dev/null 2>&1; then
        echo "[ERROR] jq is required for Firstmate dispatch setup" >&2
        return 1
    fi
    local expected actual
    expected="$(jq -S . "$source_path")" || return 1
    if [ -e "$target_path" ] || [ -L "$target_path" ]; then
        if [ -f "$target_path" ] && [ ! -L "$target_path" ] &&
            actual="$(jq -S . "$target_path")" && [ "$actual" = "$expected" ]; then
            return 0
        fi
        echo "[ERROR] Conflicting Firstmate dispatch: $target_path; review against $source_path (left unchanged)" >&2
        return 1
    fi

    # Exclusive creation: never overwrite a config installed concurrently.
    (
        set -C
        cat "$source_path" >"$target_path"
    ) || return 1
    echo "[INFO] Installed Firstmate dispatch: $target_path"
}

#!/bin/bash

GOGH_THEME="base2tone-desert"
GOGH_RAW_URL="https://github.com/Gogh-Co/Gogh/raw/master"

install_terminal_colors() {
    echo "[INFO] Installing terminal color scheme..."

    if ! check_installed gnome-terminal; then
        echo "[INFO] GNOME Terminal not found, skipping color scheme"
        return
    fi

    local tmp_dir
    tmp_dir="$(mktemp -d)"

    echo "[INFO] Downloading Gogh apply script and ${GOGH_THEME} theme..."
    if ! curl -fsSL "${GOGH_RAW_URL}/apply-colors.sh" -o "${tmp_dir}/apply-colors.sh" ||
       ! curl -fsSL "${GOGH_RAW_URL}/installs/${GOGH_THEME}.sh" -o "${tmp_dir}/${GOGH_THEME}.sh"; then
        echo "[WARN] Failed to download Gogh theme files"
        rm -rf "$tmp_dir"
        return
    fi

    chmod +x "${tmp_dir}/${GOGH_THEME}.sh"

    export TERMINAL=gnome-terminal
    export GOGH_NONINTERACTIVE=true
    export GOGH_USE_NEW_THEME=true

    echo "[INFO] Applying ${GOGH_THEME} color scheme..."
    if GOGH_APPLY_SCRIPT="${tmp_dir}/apply-colors.sh" bash "${tmp_dir}/${GOGH_THEME}.sh"; then
        echo "[INFO] Terminal color scheme applied successfully"
    else
        echo "[WARN] Failed to apply terminal color scheme"
    fi

    rm -rf "$tmp_dir"
}

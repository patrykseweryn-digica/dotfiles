#!/bin/bash

install_pipx() {
    echo "[INFO] Installing pipx..."

    if pipx --version >/dev/null 2>&1; then
        echo "[INFO] pipx is already installed"
        pipx --version
        return 0
    fi

    # Prefer uv, fall back to pip
    if check_installed uv; then
        echo "[INFO] Installing pipx via uv..."
        uv tool install pipx
    elif python3 -m pip --version >/dev/null 2>&1; then
        echo "[INFO] Installing pipx via pip..."
        python3 -m pip install --user pipx
    else
        echo "[ERROR] Neither uv nor pip available to install pipx" >&2
        return 1
    fi

    # Ensure fresh install takes priority over broken system pipx
    export PATH="${HOME}/.local/bin:${PATH}"

    if pipx --version >/dev/null 2>&1; then
        pipx ensurepath
        pipx --version
        echo "[INFO] pipx installed successfully"
    else
        echo "[WARN] pipx installed but not found in PATH. Restart your shell."
    fi
}

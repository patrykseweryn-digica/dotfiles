#!/bin/bash

install_pipx() {
    echo "[INFO] Installing pipx..."

    if check_installed pipx; then
        echo "[INFO] pipx is already installed"
        pipx --version
        return 0
    fi

    # Install pipx using pip (user installation, no sudo needed)
    echo "[INFO] Installing pipx via pip..."

    if python3 -m pip install --user pipx; then
        echo "[INFO] pipx installed successfully"

        # Ensure pipx binaries are in PATH
        python3 -m pipx ensurepath

        # Add to PATH for current session
        export PATH="${HOME}/.local/bin:${PATH}"

        # Verify installation
        if command -v pipx >/dev/null 2>&1; then
            pipx --version
        else
            echo "[WARN] pipx installed but not found in PATH. Restart your shell or run: python3 -m pipx ensurepath"
        fi
    else
        echo "[ERROR] Failed to install pipx" >&2
        return 1
    fi
}

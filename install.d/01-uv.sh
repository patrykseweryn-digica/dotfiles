#!/bin/bash

install_uv() {
    echo "[INFO] Installing uv (Astral)..."

    if check_installed uv; then
        echo "[INFO] uv is already installed"
        uv --version
        return 0
    fi

    # Install uv using the official installer
    # This installs to ~/.cargo/bin by default (no sudo needed)
    echo "[INFO] Downloading and installing uv..."

    if curl -LsSf https://astral.sh/uv/install.sh | sh; then
        echo "[INFO] uv installed successfully"

        # Add cargo bin to PATH for current session
        export PATH="${HOME}/.cargo/bin:${PATH}"

        # Add to shell config if not already there
        RC_FILE="${HOME}/.zshrc"
        if [ -f "$RC_FILE" ] && ! grep -q 'export PATH="${HOME}/.cargo/bin:\$PATH"' "$RC_FILE"; then
            echo "" >>"$RC_FILE"
            echo "# Rust/uv binaries" >>"$RC_FILE"
            echo 'export PATH="${HOME}/.cargo/bin:$PATH"' >>"$RC_FILE"
        fi

        # Verify installation
        if command -v uv >/dev/null 2>&1; then
            uv --version
        else
            echo "[WARN] uv installed but not found in PATH. Restart your shell or source ~/.zshrc"
        fi
    else
        echo "[ERROR] Failed to install uv" >&2
        return 1
    fi
}

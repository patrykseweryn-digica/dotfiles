#!/bin/bash

install_claude_code() {
    echo "[INFO] Installing Claude Code..."

    if command -v claude >/dev/null 2>&1; then
        echo "[INFO] Claude Code is already installed"
        return
    fi

    if curl -fsSL https://claude.ai/install.sh | bash; then
        echo "[INFO] Claude Code installed successfully"
    else
        echo "[WARN] Failed to install Claude Code"
    fi
}

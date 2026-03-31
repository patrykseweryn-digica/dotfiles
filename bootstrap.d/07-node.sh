#!/bin/bash

NVM_VERSION="v0.40.1"

install_nvm() {
    echo "[INFO] Installing NVM and Node.js..."

    export NVM_DIR="${HOME}/.nvm"

    if [ -s "${NVM_DIR}/nvm.sh" ]; then
        echo "[INFO] NVM is already installed"
        # shellcheck source=/dev/null
        . "${NVM_DIR}/nvm.sh"
    else
        echo "[INFO] Installing NVM ${NVM_VERSION}..."
        if curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash; then
            # shellcheck source=/dev/null
            . "${NVM_DIR}/nvm.sh"
            echo "[INFO] NVM installed successfully"
        else
            echo "[WARN] Failed to install NVM"
            return
        fi
    fi

    # Install LTS Node if no version is installed
    if ! nvm ls default &>/dev/null || [ "$(nvm ls default 2>/dev/null)" = "N/A" ]; then
        echo "[INFO] Installing Node.js LTS..."
        nvm install --lts
        nvm alias default lts/*
        echo "[INFO] Node.js LTS installed"
    else
        echo "[INFO] Node.js default version already set: $(nvm version default)"
    fi

    # Install global npm packages
    echo "[INFO] Installing global npm packages..."
    npm i -g @steipete/summarize || echo "[WARN] Failed to install @steipete/summarize"
}

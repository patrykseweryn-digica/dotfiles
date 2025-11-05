#!/bin/bash

install_zsh() {
    echo "[INFO] Checking zsh installation..."

    if check_installed zsh; then
        echo "[INFO] zsh is already installed"
        zsh --version
        return 0
    fi

    if [ "$HAS_SUDO" = true ]; then
        echo "[INFO] Installing zsh via package manager..."

        # Detect package manager and install
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get update && sudo apt-get install -y zsh
        elif command -v yum >/dev/null 2>&1; then
            sudo yum install -y zsh
        elif command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y zsh
        elif command -v pacman >/dev/null 2>&1; then
            sudo pacman -S --noconfirm zsh
        elif command -v brew >/dev/null 2>&1; then
            brew install zsh
        else
            echo "[ERROR] No supported package manager found" >&2
            return 1
        fi
    else
        echo "[WARN] No sudo access. Installing zsh from source to ${OPT_DIR}/zsh..."

        # Download and build zsh from source
        ZSH_VERSION="5.9"
        ZSH_TMP="/tmp/zsh-${ZSH_VERSION}"

        cd /tmp
        curl -L "https://sourceforge.net/projects/zsh/files/zsh/${ZSH_VERSION}/zsh-${ZSH_VERSION}.tar.xz/download" -o "zsh-${ZSH_VERSION}.tar.xz"
        tar -xf "zsh-${ZSH_VERSION}.tar.xz"
        cd "zsh-${ZSH_VERSION}"

        ./configure --prefix="${OPT_DIR}/zsh"
        make
        make install

        # Create symlink in bin directory
        ln -sf "${OPT_DIR}/zsh/bin/zsh" "${BIN_DIR}/zsh"

        cd "${DOTFILES_DIR}"
        rm -rf "${ZSH_TMP}"

        echo "[INFO] zsh compiled and installed to ${OPT_DIR}/zsh"
    fi

    # Verify installation
    if check_installed zsh; then
        zsh --version
        echo "[INFO] zsh installed successfully"

        # Change default shell if possible
        if [ "$HAS_SUDO" = true ] && [ "$(basename "$SHELL")" != "zsh" ]; then
            echo "[INFO] Setting zsh as default shell..."
            chsh -s "$(which zsh)"
        else
            echo "[WARN] Cannot change default shell without sudo. You can manually change it or run 'zsh' to start it."
        fi
    else
        echo "[ERROR] Failed to install zsh" >&2
        return 1
    fi
}

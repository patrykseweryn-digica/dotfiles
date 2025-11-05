#!/bin/bash

install_zsh() {
    echo "[INFO] Checking zsh installation..."

    if check_installed zsh; then
        echo "[INFO] zsh is already installed"
        zsh --version
    else
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
    fi

    # Verify installation
    if check_installed zsh; then
        zsh --version
        echo "[INFO] zsh installed successfully"

        # Try to change default shell to zsh; allow password prompt if required
        CHSH_OK=0
        if [ "$(basename "$SHELL")" != "zsh" ]; then
            ZSH_PATH="$(command -v zsh || true)"
            if [ -n "$ZSH_PATH" ]; then
                echo "[INFO] Attempting to set default shell to zsh (you may be prompted for your password)..."
                if chsh -s "$ZSH_PATH" "$USER"; then
                    echo "[INFO] Default shell changed to zsh"
                    CHSH_OK=1
                elif chsh -s "$ZSH_PATH"; then
                    echo "[INFO] Default shell changed to zsh"
                    CHSH_OK=1
                else
                    echo "[WARN] Could not change default shell via chsh."
                fi
            fi
        fi

        # Ensure SSH sessions auto-start zsh if default shell wasn't changed
        if [ "${CHSH_OK}" -ne 1 ]; then
            AUTO_MARKER="# Auto-start zsh for SSH sessions (dotfiles)"
            AUTO_SNIPPET="${AUTO_MARKER}
if [ -n \"$SSH_CONNECTION\" ] && [ -z \"$ZSH_VERSION\" ] && command -v zsh >/dev/null 2>&1; then
  exec zsh -l
fi"

            for f in "$HOME/.profile" "$HOME/.bashrc"; do
                if [ -f "$f" ]; then
                    if ! grep -q "Auto-start zsh for SSH sessions (dotfiles)" "$f"; then
                        printf '\n%s\n' "$AUTO_SNIPPET" >>"$f"
                        echo "[INFO] Added auto-zsh SSH snippet to $f"
                    fi
                else
                    printf '%s\n' "$AUTO_SNIPPET" >>"$f"
                    echo "[INFO] Created $f with auto-zsh SSH snippet"
                fi
            done
        fi
    else
        echo "[ERROR] Failed to install zsh" >&2
        return 1
    fi
}

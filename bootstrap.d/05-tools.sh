#!/bin/bash

install_tools() {
    echo "[INFO] Installing CLI tools..."

    # fzf (required by fzf-tab zsh plugin)
    if check_installed fzf; then
        echo "[INFO] fzf is already installed"
    elif [ "$HAS_SUDO" = true ]; then
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get install -y fzf
        elif command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y fzf
        elif command -v pacman >/dev/null 2>&1; then
            sudo pacman -S --noconfirm fzf
        elif command -v brew >/dev/null 2>&1; then
            brew install fzf
        else
            echo "[WARN] Could not install fzf: no supported package manager"
        fi
    else
        echo "[WARN] Skipping fzf (no sudo). Install manually: https://github.com/junegunn/fzf#installation"
    fi

    # bat (required by zsh-bat plugin)
    if check_installed bat || check_installed batcat; then
        echo "[INFO] bat is already installed"
    elif [ "$HAS_SUDO" = true ]; then
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get install -y bat
            # Debian/Ubuntu installs as 'batcat' — create symlink
            if ! check_installed bat && check_installed batcat; then
                ln -sf "$(command -v batcat)" "${BIN_DIR}/bat"
            fi
        elif command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y bat
        elif command -v pacman >/dev/null 2>&1; then
            sudo pacman -S --noconfirm bat
        elif command -v brew >/dev/null 2>&1; then
            brew install bat
        else
            echo "[WARN] Could not install bat: no supported package manager"
        fi
    else
        echo "[WARN] Skipping bat (no sudo). Install manually: https://github.com/sharkdp/bat#installation"
    fi

    # pre-commit (via uv)
    if check_installed pre-commit; then
        echo "[INFO] pre-commit is already installed"
    elif check_installed uv; then
        echo "[INFO] Installing pre-commit via uv..."
        if uv tool install pre-commit; then
            echo "[INFO] pre-commit installed successfully"
        else
            echo "[WARN] Failed to install pre-commit" >&2
        fi
    else
        echo "[WARN] Skipping pre-commit (uv not available)"
    fi
}

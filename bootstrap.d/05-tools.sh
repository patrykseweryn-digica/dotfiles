#!/bin/bash

install_tools() {
    echo "[INFO] Installing CLI tools..."

    # fzf (required by fzf-tab zsh plugin)
    if check_installed fzf; then
        echo "[INFO] fzf is already installed"
    elif [ "$HAS_BREW" = true ]; then
        brew install fzf
    elif [ "$HAS_SUDO" = true ]; then
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get install -y fzf
        elif command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y fzf
        elif command -v pacman >/dev/null 2>&1; then
            sudo pacman -S --noconfirm fzf
        else
            echo "[WARN] Could not install fzf: no supported package manager"
        fi
    else
        install_github_binary "junegunn/fzf" "v0.67.0" \
            "$(github_binary_pattern fzf)" "fzf" || true
    fi

    # bat (required by zsh-bat plugin)
    if check_installed bat || check_installed batcat; then
        echo "[INFO] bat is already installed"
    elif [ "$HAS_BREW" = true ]; then
        brew install bat
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
        else
            echo "[WARN] Could not install bat: no supported package manager"
        fi
    else
        install_github_binary "sharkdp/bat" "v0.26.1" \
            "$(github_binary_pattern bat)" "bat" || true
    fi

    # ripgrep (fast grep replacement)
    if check_installed rg; then
        echo "[INFO] ripgrep is already installed"
    elif [ "$HAS_BREW" = true ]; then
        brew install ripgrep
    elif [ "$HAS_SUDO" = true ]; then
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get install -y ripgrep
        elif command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y ripgrep
        elif command -v pacman >/dev/null 2>&1; then
            sudo pacman -S --noconfirm ripgrep
        else
            echo "[WARN] Could not install ripgrep: no supported package manager"
        fi
    else
        install_github_binary "BurntSushi/ripgrep" "15.1.0" \
            "$(github_binary_pattern ripgrep)" "rg" || true
    fi

    # fd (fast find replacement)
    if check_installed fd || check_installed fdfind; then
        echo "[INFO] fd is already installed"
    elif [ "$HAS_BREW" = true ]; then
        brew install fd
    elif [ "$HAS_SUDO" = true ]; then
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get install -y fd-find
            # Debian/Ubuntu installs as 'fdfind' — create symlink
            if ! check_installed fd && check_installed fdfind; then
                ln -sf "$(command -v fdfind)" "${BIN_DIR}/fd"
            fi
        elif command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y fd-find
        elif command -v pacman >/dev/null 2>&1; then
            sudo pacman -S --noconfirm fd
        else
            echo "[WARN] Could not install fd: no supported package manager"
        fi
    else
        install_github_binary "sharkdp/fd" "v10.2.0" \
            "$(github_binary_pattern fd)" "fd" || true
    fi

    # eza (modern ls replacement — no macOS binary on GitHub, brew or package manager only)
    if check_installed eza; then
        echo "[INFO] eza is already installed"
    elif [ "$HAS_BREW" = true ]; then
        brew install eza
    elif [ "$HAS_SUDO" = true ]; then
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get install -y eza 2>/dev/null || true
        elif command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y eza 2>/dev/null || true
        elif command -v pacman >/dev/null 2>&1; then
            sudo pacman -S --noconfirm eza
        fi
    fi
    # Fallback to GitHub binary (Linux only — no macOS binary available)
    if ! check_installed eza && [ "$IS_LINUX" = true ]; then
        install_github_binary "eza-community/eza" "v0.20.14" \
            "$(github_binary_pattern eza)" "eza" || true
    fi

    # delta (syntax-highlighting git diff pager)
    if check_installed delta; then
        echo "[INFO] delta is already installed"
    elif [ "$HAS_BREW" = true ]; then
        brew install git-delta
    else
        install_github_binary "dandavison/delta" "0.18.2" \
            "$(github_binary_pattern delta)" "delta" || true
    fi

    # zoxide (smart cd replacement)
    if check_installed zoxide; then
        echo "[INFO] zoxide is already installed"
    elif [ "$HAS_BREW" = true ]; then
        brew install zoxide
    elif curl -sSf https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh 2>/dev/null; then
        echo "[INFO] zoxide installed successfully"
    elif check_installed cargo; then
        echo "[INFO] Installing zoxide via cargo..."
        cargo install zoxide --locked
    else
        echo "[WARN] Skipping zoxide. Install manually: https://github.com/ajeetdsouza/zoxide#installation"
    fi

    # tealdeer (tldr - practical command examples)
    if check_installed tldr; then
        echo "[INFO] tealdeer is already installed"
    elif [ "$HAS_BREW" = true ]; then
        brew install tealdeer
    elif [ "$HAS_SUDO" = true ]; then
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get install -y tealdeer
        elif command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y tealdeer
        elif command -v pacman >/dev/null 2>&1; then
            sudo pacman -S --noconfirm tealdeer
        else
            echo "[WARN] Could not install tealdeer: no supported package manager"
        fi
    else
        local pattern
        pattern="$(github_binary_pattern tealdeer)"
        install_github_binary "tealdeer-rs/tealdeer" "v1.8.1" \
            "$pattern" "$pattern" "tldr" || true
    fi
    # Update tldr cache if freshly installed
    if check_installed tldr; then
        tldr --update 2>/dev/null || true
    fi

    # lazygit (TUI for git)
    if check_installed lazygit; then
        echo "[INFO] lazygit is already installed"
    elif [ "$HAS_BREW" = true ]; then
        brew install lazygit
    elif [ "$HAS_SUDO" = true ] && command -v pacman >/dev/null 2>&1; then
        sudo pacman -S --noconfirm lazygit
    else
        install_github_binary "jesseduffield/lazygit" "v0.59.0" \
            "$(github_binary_pattern lazygit)" "lazygit" || true
    fi

    # jq (required by sync-claude.sh)
    if check_installed jq; then
        echo "[INFO] jq is already installed"
    elif [ "$HAS_BREW" = true ]; then
        brew install jq
    elif [ "$HAS_SUDO" = true ]; then
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get install -y jq
        elif command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y jq
        elif command -v pacman >/dev/null 2>&1; then
            sudo pacman -S --noconfirm jq
        else
            echo "[WARN] Could not install jq: no supported package manager"
        fi
    else
        local pattern
        pattern="$(github_binary_pattern jq)"
        install_github_binary "jqlang/jq" "jq-1.7.1" \
            "$pattern" "$pattern" "jq" || true
    fi

    # xclip (clipboard from terminal — Linux only, macOS has built-in pbcopy/pbpaste)
    if [ "$IS_MACOS" = true ]; then
        echo "[INFO] Skipping xclip (macOS uses built-in pbcopy/pbpaste)"
    elif check_installed xclip; then
        echo "[INFO] xclip is already installed"
    elif [ "$HAS_SUDO" = true ]; then
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get install -y xclip
        elif command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y xclip
        elif command -v pacman >/dev/null 2>&1; then
            sudo pacman -S --noconfirm xclip
        else
            echo "[WARN] Could not install xclip: no supported package manager"
        fi
    else
        echo "[WARN] Skipping xclip (no sudo available)"
    fi

    # tpm (tmux plugin manager)
    if [ -d "${HOME}/.tmux/plugins/tpm" ]; then
        echo "[INFO] tpm is already installed"
    else
        echo "[INFO] Installing tpm..."
        git clone https://github.com/tmux-plugins/tpm "${HOME}/.tmux/plugins/tpm" --depth=1 || echo "[WARN] Failed to install tpm"
    fi
    # Install tmux plugins via tpm
    if [ -x "${HOME}/.tmux/plugins/tpm/bin/install_plugins" ]; then
        echo "[INFO] Installing tmux plugins..."
        "${HOME}/.tmux/plugins/tpm/bin/install_plugins" || echo "[WARN] Failed to install tmux plugins"
    fi

    # Python dev tools (via uv)
    if check_installed uv; then
        for tool in pre-commit ruff pyright; do
            if "$tool" --version >/dev/null 2>&1; then
                echo "[INFO] $tool is already installed"
            else
                echo "[INFO] Installing $tool via uv..."
                if uv tool install "$tool"; then
                    echo "[INFO] $tool installed successfully"
                else
                    echo "[WARN] Failed to install $tool" >&2
                fi
            fi
        done
    else
        echo "[WARN] Skipping Python dev tools (uv not available)"
    fi
}

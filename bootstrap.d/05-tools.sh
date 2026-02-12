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

    # ripgrep (fast grep replacement)
    if check_installed rg; then
        echo "[INFO] ripgrep is already installed"
    elif [ "$HAS_SUDO" = true ]; then
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get install -y ripgrep
        elif command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y ripgrep
        elif command -v pacman >/dev/null 2>&1; then
            sudo pacman -S --noconfirm ripgrep
        elif command -v brew >/dev/null 2>&1; then
            brew install ripgrep
        else
            echo "[WARN] Could not install ripgrep: no supported package manager"
        fi
    else
        echo "[WARN] Skipping ripgrep (no sudo). Install manually: https://github.com/BurntSushi/ripgrep#installation"
    fi

    # fd (fast find replacement)
    if check_installed fd || check_installed fdfind; then
        echo "[INFO] fd is already installed"
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
        elif command -v brew >/dev/null 2>&1; then
            brew install fd
        else
            echo "[WARN] Could not install fd: no supported package manager"
        fi
    else
        install_github_binary "sharkdp/fd" "v10.2.0" "fd-{tag}-x86_64-unknown-linux-gnu.tar.gz" "fd" || true
    fi

    # eza (modern ls replacement)
    if check_installed eza; then
        echo "[INFO] eza is already installed"
    elif [ "$HAS_SUDO" = true ]; then
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get install -y eza 2>/dev/null || true
        elif command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y eza 2>/dev/null || true
        elif command -v pacman >/dev/null 2>&1; then
            sudo pacman -S --noconfirm eza
        elif command -v brew >/dev/null 2>&1; then
            brew install eza
        fi
    fi
    # Fallback to GitHub binary
    if ! check_installed eza; then
        install_github_binary "eza-community/eza" "v0.20.14" "eza_x86_64-unknown-linux-gnu.tar.gz" "eza" || true
    fi

    # delta (syntax-highlighting git diff pager)
    if check_installed delta; then
        echo "[INFO] delta is already installed"
    else
        install_github_binary "dandavison/delta" "0.18.2" "delta-0.18.2-x86_64-unknown-linux-gnu.tar.gz" "delta" || true
    fi

    # zoxide (smart cd replacement)
    if check_installed zoxide; then
        echo "[INFO] zoxide is already installed"
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
    elif [ "$HAS_SUDO" = true ]; then
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get install -y tealdeer
        elif command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y tealdeer
        elif command -v pacman >/dev/null 2>&1; then
            sudo pacman -S --noconfirm tealdeer
        elif command -v brew >/dev/null 2>&1; then
            brew install tealdeer
        else
            echo "[WARN] Could not install tealdeer: no supported package manager"
        fi
    else
        install_github_binary "tealdeer-rs/tealdeer" "v1.8.1" "tealdeer-linux-x86_64-musl" "tealdeer-linux-x86_64-musl" "tldr" || true
    fi
    # Update tldr cache if freshly installed
    if check_installed tldr; then
        tldr --update 2>/dev/null || true
    fi

    # lazygit (TUI for git)
    if check_installed lazygit; then
        echo "[INFO] lazygit is already installed"
    elif [ "$HAS_SUDO" = true ]; then
        if command -v pacman >/dev/null 2>&1; then
            sudo pacman -S --noconfirm lazygit
        elif command -v brew >/dev/null 2>&1; then
            brew install lazygit
        else
            install_github_binary "jesseduffield/lazygit" "v0.59.0" "lazygit_{tag_no_v}_Linux_x86_64.tar.gz" "lazygit" || true
        fi
    else
        install_github_binary "jesseduffield/lazygit" "v0.59.0" "lazygit_{tag_no_v}_Linux_x86_64.tar.gz" "lazygit" || true
    fi

    # tpm (tmux plugin manager)
    if [ -d "${HOME}/.tmux/plugins/tpm" ]; then
        echo "[INFO] tpm is already installed"
    else
        echo "[INFO] Installing tpm..."
        git clone https://github.com/tmux-plugins/tpm "${HOME}/.tmux/plugins/tpm" --depth=1 || echo "[WARN] Failed to install tpm"
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

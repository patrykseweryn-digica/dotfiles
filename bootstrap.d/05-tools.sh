#!/bin/bash

tool_plan_installed() {
    local check_command

    for check_command in $1; do
        if check_installed "$check_command"; then
            return 0
        fi
    done

    return 1
}

install_brew_package() {
    local tool_name="$1"
    local package_name="$2"

    if [ -z "$package_name" ]; then
        echo "[WARN] Could not install ${tool_name}: no Homebrew package configured"
        return 1
    fi

    brew install "$package_name"
}

configure_git_lfs() {
    if check_installed git && git lfs version >/dev/null 2>&1; then
        git lfs install --skip-repo || echo "[WARN] Failed to configure git-lfs"
    else
        echo "[WARN] git-lfs installed but git lfs is not available"
    fi
}

run_cli_tool_plan() {
    local tool_name="$1"
    local check_commands="$2"
    local apt_package="$3"
    local dnf_package="$4"
    local pacman_package="$5"
    local brew_package="$6"
    local github_repo="$7"
    local github_tag="$8"
    local github_archive="$9"
    local github_binary="${10}"
    local github_installed_name="${11:-}"
    local post_install="${12:-}"

    if tool_plan_installed "$check_commands"; then
        echo "[INFO] ${tool_name} is already installed"
    elif command -v brew >/dev/null 2>&1; then
        install_brew_package "$tool_name" "$brew_package" || true
        if [ -n "$post_install" ]; then
            "$post_install"
        fi
    elif [ "$HAS_SUDO" = true ]; then
        install_package_manager_package "$tool_name" "$apt_package" "$dnf_package" "$pacman_package" "$brew_package" || true
        if [ -n "$post_install" ]; then
            "$post_install"
        fi
    else
        if [ -z "$github_repo" ]; then
            echo "[WARN] Skipping ${tool_name}: no package manager or GitHub fallback available"
        elif [ -n "$github_installed_name" ]; then
            install_github_binary "$github_repo" "$github_tag" "$github_archive" "$github_binary" "$github_installed_name" || true
        else
            install_github_binary "$github_repo" "$github_tag" "$github_archive" "$github_binary" || true
        fi
    fi
}

link_bat_alias() {
    # Debian/Ubuntu installs as 'batcat' — create symlink
    if ! check_installed bat && check_installed batcat; then
        ln -sf "$(command -v batcat)" "${BIN_DIR}/bat"
    fi
}

link_fd_alias() {
    # Debian/Ubuntu installs as 'fdfind' — create symlink
    if ! check_installed fd && check_installed fdfind; then
        ln -sf "$(command -v fdfind)" "${BIN_DIR}/fd"
    fi
}

install_core_cli_tools() {
    # fzf (required by fzf-tab zsh plugin)
    run_cli_tool_plan "fzf" "fzf" \
        "fzf" "fzf" "fzf" "fzf" \
        "junegunn/fzf" "v0.67.0" "$(github_binary_pattern fzf)" "fzf"

    # bat (required by zsh-bat plugin)
    run_cli_tool_plan "bat" "bat batcat" \
        "bat" "bat" "bat" "bat" \
        "sharkdp/bat" "v0.26.1" "$(github_binary_pattern bat)" "bat" "" "link_bat_alias"

    # ripgrep (fast grep replacement)
    run_cli_tool_plan "ripgrep" "rg" \
        "ripgrep" "ripgrep" "ripgrep" "ripgrep" \
        "BurntSushi/ripgrep" "15.1.0" "$(github_binary_pattern ripgrep)" "rg"

    # fd (fast find replacement)
    run_cli_tool_plan "fd" "fd fdfind" \
        "fd-find" "fd-find" "fd" "fd" \
        "sharkdp/fd" "v10.2.0" "$(github_binary_pattern fd)" "fd" "" "link_fd_alias"

    # jq (required by sync-agents.sh)
    run_cli_tool_plan "jq" "jq" \
        "jq" "jq" "jq" "jq" \
        "jqlang/jq" "jq-1.7.1" "$(github_binary_pattern jq)" "$(github_binary_pattern jq)" "jq"

    # tmux (terminal multiplexer)
    run_cli_tool_plan "tmux" "tmux" \
        "tmux" "tmux" "tmux" "tmux" \
        "" "" "" ""

    # Neovim (modern Vim)
    run_cli_tool_plan "neovim" "nvim" \
        "neovim" "neovim" "neovim" "neovim" \
        "" "" "" ""

    # git-lfs (large file support for Git)
    run_cli_tool_plan "git-lfs" "git-lfs" \
        "git-lfs" "git-lfs" "git-lfs" "git-lfs" \
        "" "" "" "" "" "configure_git_lfs"

    # shfmt (shell formatter)
    run_cli_tool_plan "shfmt" "shfmt" \
        "shfmt" "shfmt" "shfmt" "shfmt" \
        "" "" "" ""

    # just (command runner)
    run_cli_tool_plan "just" "just" \
        "just" "just" "just" "just" \
        "" "" "" ""

    # hadolint (Dockerfile linter)
    run_cli_tool_plan "hadolint" "hadolint" \
        "" "hadolint" "hadolint" "hadolint" \
        "" "" "" ""

    # Bitwarden CLI (bw)
    run_cli_tool_plan "bitwarden-cli" "bw" \
        "" "" "bitwarden-cli" "bitwarden-cli" \
        "" "" "" ""
}

install_tools() {
    echo "[INFO] Installing CLI tools..."

    install_core_cli_tools

    # eza (modern ls replacement)
    if check_installed eza; then
        echo "[INFO] eza is already installed"
    elif command -v brew >/dev/null 2>&1; then
        brew install eza
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
    # Fallback to GitHub binary (Linux only — no macOS binary available)
    if ! check_installed eza && [ "${IS_LINUX:-false}" = true ]; then
        install_github_binary "eza-community/eza" "v0.20.14" "eza_x86_64-unknown-linux-gnu.tar.gz" "eza" || true
    fi

    # delta (syntax-highlighting git diff pager)
    if check_installed delta; then
        echo "[INFO] delta is already installed"
    elif command -v brew >/dev/null 2>&1; then
        brew install git-delta
    else
        install_github_binary "dandavison/delta" "0.18.2" "$(github_binary_pattern delta)" "delta" || true
    fi

    # zoxide (smart cd replacement)
    if check_installed zoxide; then
        echo "[INFO] zoxide is already installed"
    elif command -v brew >/dev/null 2>&1; then
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
    elif command -v brew >/dev/null 2>&1; then
        brew install tealdeer
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
        local pattern
        pattern="$(github_binary_pattern tealdeer)"
        install_github_binary "tealdeer-rs/tealdeer" "v1.8.1" "$pattern" "$pattern" "tldr" || true
    fi
    # Update tldr cache if freshly installed
    if check_installed tldr; then
        tldr --update 2>/dev/null || true
    fi

    # lazygit (TUI for git)
    if check_installed lazygit; then
        echo "[INFO] lazygit is already installed"
    elif command -v brew >/dev/null 2>&1; then
        brew install lazygit
    elif [ "$HAS_SUDO" = true ]; then
        if command -v pacman >/dev/null 2>&1; then
            sudo pacman -S --noconfirm lazygit
        else
            install_github_binary "jesseduffield/lazygit" "v0.59.0" "$(github_binary_pattern lazygit)" "lazygit" || true
        fi
    else
        install_github_binary "jesseduffield/lazygit" "v0.59.0" "$(github_binary_pattern lazygit)" "lazygit" || true
    fi

    # xclip (clipboard from terminal — Linux only, macOS has built-in pbcopy/pbpaste)
    if [ "${IS_MACOS:-false}" = true ]; then
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
        elif command -v brew >/dev/null 2>&1; then
            brew install xclip
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

    # pre-commit (via uv)
    if pre-commit --version >/dev/null 2>&1; then
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

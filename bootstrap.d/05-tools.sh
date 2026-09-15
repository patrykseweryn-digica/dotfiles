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

update_tldr_cache() {
    if check_installed tldr; then
        tldr --update 2>/dev/null || true
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
    local installed=false

    if tool_plan_installed "$check_commands"; then
        echo "[INFO] ${tool_name} is already installed"
    elif command -v brew >/dev/null 2>&1; then
        if install_brew_package "$tool_name" "$brew_package"; then
            installed=true
        fi
    elif [ "$HAS_SUDO" = true ]; then
        if install_package_manager_package "$tool_name" "$apt_package" "$dnf_package" "$pacman_package" "$brew_package"; then
            installed=true
        fi
    fi

    if ! tool_plan_installed "$check_commands" && [ "$installed" != true ]; then
        if [ -z "$github_repo" ]; then
            echo "[WARN] Skipping ${tool_name}: no package manager or GitHub fallback available"
        elif [ -n "$github_installed_name" ]; then
            install_github_binary "$github_repo" "$github_tag" "$github_archive" "$github_binary" "$github_installed_name" || true
        else
            install_github_binary "$github_repo" "$github_tag" "$github_archive" "$github_binary" || true
        fi
    fi

    if [ -n "$post_install" ]; then
        "$post_install"
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
        "casey/just" "1.56.0" "$(github_binary_pattern just)" "just"

    # hadolint (Dockerfile linter)
    run_cli_tool_plan "hadolint" "hadolint" \
        "" "hadolint" "hadolint" "hadolint" \
        "" "" "" ""

    # Bitwarden CLI (bw)
    run_cli_tool_plan "bitwarden-cli" "bw" \
        "" "" "bitwarden-cli" "bitwarden-cli" \
        "" "" "" ""
}

install_eza() {
    local github_repo=""
    local github_tag=""
    local github_archive=""
    local github_binary=""

    if [ "${IS_LINUX:-false}" = true ]; then
        github_repo="eza-community/eza"
        github_tag="v0.20.14"
        github_archive="eza_x86_64-unknown-linux-gnu.tar.gz"
        github_binary="eza"
    fi

    # eza (modern ls replacement)
    run_cli_tool_plan "eza" "eza" \
        "eza" "eza" "eza" "eza" \
        "$github_repo" "$github_tag" "$github_archive" "$github_binary"
}

install_delta() {
    # delta (syntax-highlighting git diff pager)
    run_cli_tool_plan "delta" "delta" \
        "" "" "" "git-delta" \
        "dandavison/delta" "0.18.2" "$(github_binary_pattern delta)" "delta"
}

install_tealdeer() {
    # tealdeer (tldr - practical command examples)
    run_cli_tool_plan "tealdeer" "tldr" \
        "tealdeer" "tealdeer" "tealdeer" "tealdeer" \
        "tealdeer-rs/tealdeer" "v1.8.1" "$(github_binary_pattern tealdeer)" "$(github_binary_pattern tealdeer)" "tldr" "update_tldr_cache"
}

install_lazygit() {
    # lazygit (TUI for git)
    run_cli_tool_plan "lazygit" "lazygit" \
        "" "" "lazygit" "lazygit" \
        "jesseduffield/lazygit" "v0.59.0" "$(github_binary_pattern lazygit)" "lazygit"
}

install_xclip() {
    # xclip (clipboard from terminal — Linux only, macOS has built-in pbcopy/pbpaste)
    if [ "${IS_MACOS:-false}" = true ]; then
        echo "[INFO] Skipping xclip (macOS uses built-in pbcopy/pbpaste)"
        return 0
    fi

    run_cli_tool_plan "xclip" "xclip" \
        "xclip" "xclip" "xclip" "xclip" \
        "" "" "" ""
}

install_tpm() {
    if [ -d "${HOME}/.tmux/plugins/tpm" ]; then
        echo "[INFO] tpm is already installed"
    else
        echo "[INFO] Installing tpm..."
        git clone https://github.com/tmux-plugins/tpm "${HOME}/.tmux/plugins/tpm" --depth=1 || echo "[WARN] Failed to install tpm"
    fi
}

install_tmux_plugins() {
    if [ -x "${HOME}/.tmux/plugins/tpm/bin/install_plugins" ]; then
        echo "[INFO] Installing tmux plugins..."
        "${HOME}/.tmux/plugins/tpm/bin/install_plugins" || echo "[WARN] Failed to install tmux plugins"
    else
        echo "[WARN] Skipping tmux plugins; tpm is not installed"
    fi
}

install_hermes() {
    local installer status browser_use

    installer="$(mktemp)" || return 1
    if ! curl -fsSL https://hermes-agent.nousresearch.com/install.sh -o "$installer"; then
        rm -f "$installer"
        return 1
    fi
    if ! bash "$installer" --skip-setup --skip-computer-use; then
        status=$?
        rm -f "$installer"
        return "$status"
    fi
    rm -f "$installer"

    browser_use="${HERMES_HOME:-$HOME/.hermes}/bin/browser-use"
    if [ ! -x "$browser_use" ]; then
        echo "[ERROR] Hermes Browser Use CLI not installed: $browser_use" >&2
        return 1
    fi
}

install_herdr() {
    local installer settings tmp

    settings="${HOME}/.claude/settings.json"
    if [ -L "$settings" ]; then
        if [ ! -f "$settings" ]; then
            echo "[ERROR] Broken or non-file Claude settings symlink: $settings" >&2
            echo "Restore its target before installing Herdr: $(readlink "$settings")" >&2
            return 1
        fi
        tmp="$(mktemp "${settings}.XXXXXX")" || return 1
        if ! cp -L "$settings" "$tmp" || ! mv -f "$tmp" "$settings"; then
            rm -f "$tmp"
            return 1
        fi
    fi

    installer="$(curl -fsSL https://herdr.dev/install.sh)" || return 1
    HERDR_INSTALL_DIR="$BIN_DIR" sh -c "$installer" || return 1
    mkdir -p "${HOME}/.claude" || return 1
    CLAUDE_CONFIG_DIR="${HOME}/.claude" \
        "$BIN_DIR/herdr" integration install claude || return 1
    if [ ! -s "${HOME}/.claude/hooks/herdr-agent-state.sh" ]; then
        echo "[ERROR] Herdr did not install ~/.claude/hooks/herdr-agent-state.sh" >&2
        return 1
    fi

    # Herdr writes an absolute path; keep its hook portable in managed settings.
    tmp="$(mktemp "${settings}.XXXXXX")" || return 1
    if jq -S '
        (.hooks.SessionStart[].hooks[] |
            select(.type == "command" and
                (.command | contains("herdr-agent-state.sh")))).command =
            "bash \"$HOME/.claude/hooks/herdr-agent-state.sh\" session" |
        .hooks.SessionStart |= reduce .[] as $entry ([];
            if ($entry.hooks | any(.command? // "" |
                    contains("herdr-agent-state.sh"))) and index($entry) != null
            then . else . + [$entry] end)
    ' "$settings" >"$tmp"; then
        mv "$tmp" "$settings"
    else
        rm -f "$tmp"
        return 1
    fi
}

install_treehouse() (
    local os arch release version archive task_dir
    os="$(uname -s)"
    arch="$(uname -m)"
    case "$os" in
    Linux) os=linux ;;
    Darwin) os=darwin ;;
    *) echo "[ERROR] Unsupported OS for Treehouse: $os" >&2; return 1 ;;
    esac
    case "$arch" in
    x86_64 | amd64) arch=amd64 ;;
    arm64 | aarch64) arch=arm64 ;;
    *) echo "[ERROR] Unsupported architecture for Treehouse: $arch" >&2; return 1 ;;
    esac

    # Public release redirects avoid GitHub's unauthenticated API quota.
    release=$(curl -fsSL -o /dev/null -w '%{url_effective}' \
        https://github.com/kunchenguid/treehouse/releases/latest) || {
        echo "[ERROR] Treehouse: failed to resolve latest release" >&2
        return 1
    }
    version="${release##*/}"
    if [[ ! "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "[ERROR] Treehouse: invalid release URL: $release" >&2
        return 1
    fi
    mkdir -p "$BIN_DIR" || return 1
    task_dir=$(mktemp -d "${BIN_DIR}/.treehouse.XXXXXX") || return 1
    trap 'rm -rf "$task_dir"' EXIT
    archive="treehouse-${version}-${os}-${arch}.tar.gz"
    if ! curl -fsSL "https://github.com/kunchenguid/treehouse/releases/download/${version}/${archive}" \
        -o "$task_dir/release.tar.gz" ||
        ! tar xzf "$task_dir/release.tar.gz" -C "$task_dir" treehouse ||
        ! "$task_dir/treehouse" --version; then
        echo "[ERROR] Treehouse: download or validation failed (${os}/${arch}, ${version})" >&2
        return 1
    fi
    mv "$task_dir/treehouse" "$BIN_DIR/treehouse" || return 1
    echo "[INFO] Treehouse $version installed to $BIN_DIR/treehouse"
)

install_no_mistakes() {
    local installer

    installer="$(curl -fsSL https://raw.githubusercontent.com/kunchenguid/no-mistakes/main/docs/install.sh)" || return 1
    NO_MISTAKES_LINK_DIR="$BIN_DIR" sh -c "$installer"
}

install_tools() {
    echo "[INFO] Installing CLI tools..."

    install_core_cli_tools
    install_eza
    install_delta

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

    install_tealdeer
    install_lazygit
    install_xclip

    install_tpm

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

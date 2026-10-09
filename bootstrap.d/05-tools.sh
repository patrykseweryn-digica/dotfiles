#!/bin/bash

TOOL_INVENTORY="${TOOL_INVENTORY:-${DOTFILES_DIR}/.agents/tool-versions.json}"
JQ_BIN="${JQ_BIN:-jq}"

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
        git lfs install --skip-repo || {
            echo "[ERROR] Failed to configure git-lfs" >&2
            return 1
        }
    else
        echo "[ERROR] git-lfs installed but git lfs is not available" >&2
        return 1
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
    local adapter="${13:-package}"
    local package_installed=false
    local post_installed=false

    if tool_plan_installed "$check_commands"; then
        echo "[INFO] ${tool_name} is already installed"
        return 0
    fi

    if command -v brew >/dev/null 2>&1; then
        install_brew_package "$tool_name" "$brew_package" &&
            package_installed=true
    elif [ "$HAS_SUDO" = true ]; then
        install_package_manager_package "$tool_name" "$apt_package" \
            "$dnf_package" "$pacman_package" "$brew_package" &&
            package_installed=true
    fi

    if [ "$package_installed" = true ] && [ -n "$post_install" ]; then
        "$post_install" || return 1
        post_installed=true
    fi

    if ! tool_plan_installed "$check_commands"; then
        case "$adapter" in
        zoxide-native) install_zoxide_native || return 1 ;;
        uv) install_uv_tool "$tool_name" || return 1 ;;
        package)
            if [ -z "$github_repo" ]; then
                echo "[ERROR] ${tool_name}: no supported install source" >&2
                return 1
            fi
            if [ -z "$github_archive" ] || [ -z "$github_binary" ]; then
                echo "[ERROR] ${tool_name}: no GitHub artifact for $(tool_platform)" >&2
                return 1
            fi
            if [ -n "$github_installed_name" ]; then
                install_github_binary "$github_repo" "$github_tag" \
                    "$github_archive" "$github_binary" "$github_installed_name" || return 1
            else
                install_github_binary "$github_repo" "$github_tag" \
                    "$github_archive" "$github_binary" || return 1
            fi
            ;;
        *)
            echo "[ERROR] ${tool_name}: unknown adapter ${adapter}" >&2
            return 1
            ;;
        esac
    fi

    if [ "$post_installed" = false ] && [ -n "$post_install" ]; then
        "$post_install" || return 1
    fi

    if ! tool_plan_installed "$check_commands"; then
        echo "[ERROR] ${tool_name}: installer finished but command is unavailable" >&2
        return 1
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

tool_platform() {
    local os="${OS:-$(uname -s)}"
    local arch="${ARCH:-$(uname -m)}"

    case "$os" in
    Darwin) os=darwin ;;
    Linux) os=linux ;;
    *) return 1 ;;
    esac
    case "$arch" in
    arm64 | aarch64) arch=arm64 ;;
    x86_64 | amd64) arch=x86_64 ;;
    *) return 1 ;;
    esac
    printf '%s-%s\n' "$os" "$arch"
}

core_tool_rows() {
    local platform
    platform="$(tool_platform)" || {
        echo "[ERROR] Unsupported tool platform: $(uname -s)/$(uname -m)" >&2
        return 1
    }
    "$JQ_BIN" -r --arg platform "$platform" '
        (.platforms // ["darwin-arm64", "darwin-x86_64",
            "linux-arm64", "linux-x86_64"]) as $defaults |
        .tools[] | select(.scope == "core") |
        select(((.platforms // $defaults) | index($platform)) != null) |
        (.github.artifacts[$platform] // {}) as $artifact |
        [.name, (.commands | join(" ")), (.packages.apt // "-"),
         (.packages.dnf // "-"), (.packages.pacman // "-"),
         (.packages.brew // "-"), (.github.repo // "-"),
         (.github.tag // "-"), ($artifact.archive // "-"),
         ($artifact.binary // "-"), ($artifact.installedName // "-"),
         (.postInstall // "-"), (.adapter // "package")] | @tsv
    ' "$TOOL_INVENTORY"
}

empty_if_dash() {
    [ "$1" = - ] || printf '%s' "$1"
}

install_zoxide_native() {
    if curl -sSf https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh |
        sh 2>/dev/null; then
        return 0
    fi
    if check_installed cargo; then
        cargo install zoxide --locked
        return $?
    fi
    echo "[ERROR] zoxide: native installer failed and cargo is unavailable" >&2
    return 1
}

install_uv_tool() {
    if ! check_installed uv; then
        echo "[ERROR] $1: uv is unavailable" >&2
        return 1
    fi
    uv tool install "$1"
}

install_declared_core_tools() {
    local failed=false
    local rows
    local name commands apt dnf pacman brew repo tag archive binary
    local installed_name post_install adapter

    rows="$(core_tool_rows)" || return 1
    while IFS=$'\t' read -r name commands apt dnf pacman brew repo tag \
        archive binary installed_name post_install adapter; do
        run_cli_tool_plan "$name" "$commands" \
            "$(empty_if_dash "$apt")" "$(empty_if_dash "$dnf")" \
            "$(empty_if_dash "$pacman")" "$(empty_if_dash "$brew")" \
            "$(empty_if_dash "$repo")" "$(empty_if_dash "$tag")" \
            "$(empty_if_dash "$archive")" "$(empty_if_dash "$binary")" \
            "$(empty_if_dash "$installed_name")" \
            "$(empty_if_dash "$post_install")" "$adapter" || failed=true
    done <<<"$rows"

    [ "$failed" = false ]
}

install_tpm() {
    if [ -d "${HOME}/.tmux/plugins/tpm" ]; then
        echo "[INFO] tpm is already installed"
    else
        echo "[INFO] Installing tpm..."
        git clone https://github.com/tmux-plugins/tpm \
            "${HOME}/.tmux/plugins/tpm" --depth=1 || {
            echo "[ERROR] Failed to install tpm" >&2
            return 1
        }
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
    bash "$installer" --skip-setup --skip-computer-use
    status=$?
    rm -f "$installer"
    if [ "$status" -ne 0 ]; then
        return "$status"
    fi

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

install_cursor_cli() {
    local installer

    installer="$(curl -fsSL https://cursor.com/install)" || return 1
    bash -c "$installer" || return 1
    "$HOME/.local/bin/agent" --version
}

install_grok() {
    local installer

    installer="$(curl -fsSL https://x.ai/cli/install.sh)" || return 1
    # Let dotfiles own shell initialization and reserve agent for Cursor.
    SHELL=/bin/false GROK_BIN_DIR="$HOME/.grok/bin" \
        PATH="$HOME/.grok/bin:$PATH" bash -c "$installer" || return 1
    if [ -L "$HOME/.grok/bin/agent" ]; then
        rm "$HOME/.grok/bin/agent" || return 1
    fi
    mkdir -p "$BIN_DIR" || return 1
    ln -sf "$HOME/.grok/bin/grok" "$BIN_DIR/grok" || return 1
    "$BIN_DIR/grok" --version
}

install_no_mistakes() {
    local installer

    installer="$(curl -fsSL https://raw.githubusercontent.com/kunchenguid/no-mistakes/main/docs/install.sh)" || return 1
    NO_MISTAKES_LINK_DIR="$BIN_DIR" sh -c "$installer"
}

install_tools() {
    echo "[INFO] Installing CLI tools..."

    "$DOTFILES_DIR/scripts/agent-tools.sh" plan >/dev/null
    install_declared_core_tools
    install_tpm
}

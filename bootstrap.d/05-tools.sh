#!/bin/bash

CORE_TOOLS="${CORE_TOOLS:-${DOTFILES_DIR}/scripts/core-tools.sh}"

github_latest_tag() {
    local repo="$1" release
    release="$(curl -fsSL -o /dev/null -w '%{url_effective}' \
        "https://github.com/${repo}/releases/latest")" || return 1
    [ "${release##*/}" != latest ] || return 1
    printf '%s\n' "${release##*/}"
}

github_latest_version() {
    local tag
    tag="$(github_latest_tag "$1")" || return 1
    [[ "$tag" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    printf '%s\n' "${tag#v}"
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
    local installer status

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
}

install_herdr() {
    local installer

    prepare_herdr_settings || return 1
    installer="$(curl -fsSL https://herdr.dev/install.sh)" || return 1
    HERDR_INSTALL_DIR="$BIN_DIR" sh -c "$installer" || return 1
    PATH="${BIN_DIR}:${PATH}" configure_herdr_hook
}

prepare_herdr_settings() {
    local settings tmp

    settings="${HOME}/.claude/settings.json"
    if [ -L "$settings" ]; then
        if [ ! -f "$settings" ]; then
            echo "[ERROR] Broken or non-file Claude settings symlink: $settings" >&2
            echo "Restore its target before configuring Herdr: $(readlink "$settings")" >&2
            return 1
        fi
        tmp="$(mktemp "${settings}.XXXXXX")" || return 1
        if ! cp -L "$settings" "$tmp" || ! mv -f "$tmp" "$settings"; then
            rm -f "$tmp"
            return 1
        fi
    fi
    if [ -f "$settings" ] &&
        ! jq -e -s 'length == 1 and (.[0] | type == "object")' \
            "$settings" >/dev/null 2>&1; then
        echo "[ERROR] Invalid Claude settings: $settings" >&2
        return 1
    fi
}

configure_herdr_hook() {
    local settings tmp herdr

    prepare_herdr_settings || return 1
    settings="${HOME}/.claude/settings.json"
    herdr="$(command -v herdr)" || {
        echo "[ERROR] Herdr is unavailable; install it before updating hooks" >&2
        return 1
    }
    mkdir -p "${HOME}/.claude" || return 1
    CLAUDE_CONFIG_DIR="${HOME}/.claude" \
        "$herdr" integration install claude || return 1
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
        .hooks.SessionStart |= (
            reduce .[] as $entry ({items: [], seen_herdr: false};
                ($entry.hooks | any(.command? // "" |
                    contains("herdr-agent-state.sh"))) as $is_herdr |
                if $is_herdr and .seen_herdr then
                    .
                else
                    .items += [$entry] |
                    if $is_herdr then .seen_herdr = true else . end
                end
            ) | .items
        )
    ' "$settings" >"$tmp"; then
        mv "$tmp" "$settings"
    else
        rm -f "$tmp"
        return 1
    fi
}

install_treehouse() (
    local os arch latest version archive task_dir output current
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

    latest="$(github_latest_version kunchenguid/treehouse)" || {
        echo "[ERROR] Treehouse: failed to resolve latest release" >&2
        return 1
    }
    version="v${latest}"
    if [ -x "$BIN_DIR/treehouse" ]; then
        output="$("$BIN_DIR/treehouse" --version 2>/dev/null || true)"
        if [[ "$output" =~ ([0-9]+\.[0-9]+\.[0-9]+) ]]; then
            current="${BASH_REMATCH[1]}"
        fi
        if [ "${current:-}" = "$latest" ]; then
            echo "[INFO] Treehouse $version already current"
            return 0
        fi
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

    CORE_TOOLS_HAS_SUDO="$HAS_SUDO" "$CORE_TOOLS" install
    install_tpm
}

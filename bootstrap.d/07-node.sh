#!/bin/bash

NODE_VERSION_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.nvmrc"

required_node_version() {
    local version
    version=$(cat "$NODE_VERSION_FILE") || return 1
    if [ "$version" != node ]; then
        echo "[ERROR] Expected latest Node policy (node) in $NODE_VERSION_FILE" >&2
        return 1
    fi
    printf '%s\n' "$version"
}

check_node() {
    local expected current installed
    expected=$(required_node_version) || return 1
    current=$(node --version 2>/dev/null) || current=missing
    if [[ ! "$current" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "[ERROR] Node missing or invalid: $current" >&2
        return 1
    fi
    if [ -s "${HOME}/.nvm/nvm.sh" ]; then
        export NVM_DIR="${HOME}/.nvm"
        # --no-use keeps this read-only check from switching the active runtime.
        # shellcheck source=/dev/null
        . "$NVM_DIR/nvm.sh" --no-use || return 1
        installed=$(nvm version "$expected") || return 1
        printf 'Node: policy=latest active=%s latest-installed=%s\n' "$current" "$installed"
        if [ "$current" != "$installed" ]; then
            echo "[ERROR] Active Node $current differs from latest installed $installed" >&2
            echo "Run: nvm use node" >&2
            return 1
        fi
    else
        printf 'Node: policy=latest active=%s (latest not checked)\n' "$current"
    fi
}

# Activate the newest installed Node in the caller's shell.
activate_node() {
    local expected
    expected=$(required_node_version) || return 1
    export NVM_DIR="${HOME}/.nvm"
    # shellcheck source=/dev/null
    . "${NVM_DIR}/nvm.sh" --no-use || return 1
    nvm use --silent "$expected" || return 1
    check_node
}

install_nvm() {
    local expected installer release version
    expected=$(required_node_version) || return 1
    export NVM_DIR="${HOME}/.nvm"

    if [ ! -s "${NVM_DIR}/nvm.sh" ]; then
        release=$(curl -fsSL -o /dev/null -w '%{url_effective}' \
            https://github.com/nvm-sh/nvm/releases/latest) || return 1
        version="${release##*/}"
        [[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
        echo "[INFO] Installing NVM $version..."
        installer=$(curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${version}/install.sh") || {
            echo "[ERROR] Failed to download NVM" >&2
            return 1
        }
        # Shell initialization is managed by dotfiles; do not edit profiles.
        PROFILE=/dev/null bash -c "$installer" || return 1
    fi

    # shellcheck source=/dev/null
    . "${NVM_DIR}/nvm.sh" --no-use || return 1
    echo "[INFO] Ensuring Node.js $expected..."
    # Never import globals or the user's nvm default-packages file.
    if ! nvm install --skip-default-packages "$expected"; then
        echo "[ERROR] Failed to install latest Node.js; previous Node retained" >&2
        return 1
    fi
    nvm use --silent "$expected" || return 1
    check_node || return 1
    nvm alias default "$expected"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    case "${1:-}" in
    check) check_node ;;
    *)
        echo "Usage: $0 check" >&2
        exit 1
        ;;
    esac
fi

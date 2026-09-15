#!/bin/bash

NVM_VERSION="v0.40.1"
NODE_VERSION_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.nvmrc"

required_node_version() {
    local version
    version=$(cat "$NODE_VERSION_FILE") || return 1
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "[ERROR] Invalid exact Node version in $NODE_VERSION_FILE" >&2
        return 1
    fi
    printf '%s\n' "$version"
}

check_node() {
    local expected current
    expected=$(required_node_version) || return 1
    current=$(node --version 2>/dev/null) || current=missing
    printf 'Node: required=v%s active=%s\n' "$expected" "$current"
    [ "$current" = "v$expected" ]
}

# Call in the parent shell after install_nvm succeeds in an optional step.
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
    local expected installer
    expected=$(required_node_version) || return 1
    export NVM_DIR="${HOME}/.nvm"

    if [ ! -s "${NVM_DIR}/nvm.sh" ]; then
        echo "[INFO] Installing NVM ${NVM_VERSION}..."
        installer=$(curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh") || {
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
    if [ "$(nvm version "$expected")" != "v$expected" ]; then
        if ! nvm install --skip-default-packages "$expected"; then
            echo "[ERROR] Failed to install Node.js $expected; previous Node retained" >&2
            return 1
        fi
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

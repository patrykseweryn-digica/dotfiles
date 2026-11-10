#!/bin/bash

DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NODE_POLICY_FILE="${NODE_POLICY_FILE:-${DOTFILES_ROOT}/config/mise/config.toml}"
MISE_INSTALL_URL="${MISE_INSTALL_URL:-https://mise.run}"

required_node_policy() {
    local policy
    policy=$(sed -n 's/^[[:space:]]*node[[:space:]]*=[[:space:]]*"\([^"]*\)"[[:space:]]*$/\1/p' \
        "$NODE_POLICY_FILE") || return 1
    if [ "$policy" != lts ]; then
        echo "[ERROR] Expected Node LTS policy in $NODE_POLICY_FILE" >&2
        return 1
    fi
    printf '%s\n' "$policy"
}

mise_bin() {
    printf '%s\n' "${MISE_BIN:-${HOME}/.local/bin/mise}"
}

run_mise() {
    local binary
    binary=$(mise_bin)
    env -u MISE_NODE_VERSION \
        MISE_GLOBAL_CONFIG_FILE="$NODE_POLICY_FILE" "$binary" "$@"
}

run_global_mise() {
    local binary
    binary=$(mise_bin)
    env -u MISE_NODE_VERSION "$binary" --cd "$HOME" "$@"
}

run_mise_offline() {
    local binary
    binary=$(mise_bin)
    env -u MISE_NODE_VERSION MISE_OFFLINE=1 \
        MISE_GLOBAL_CONFIG_FILE="$NODE_POLICY_FILE" "$binary" "$@"
}

check_node() {
    local current expected expected_bin binary
    required_node_policy >/dev/null || return 1
    binary=$(mise_bin)
    if [ ! -x "$binary" ]; then
        echo "[ERROR] mise is missing: $binary" >&2
        return 1
    fi
    expected_bin=$(run_mise_offline which node 2>/dev/null) || {
        echo "[ERROR] Node LTS is not installed through mise" >&2
        return 1
    }
    expected=$("$expected_bin" --version 2>/dev/null) || expected=missing
    current=$(node --version 2>/dev/null) || current=missing
    if [[ ! "$expected" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "[ERROR] mise selected an invalid Node version: $expected" >&2
        return 1
    fi
    if [[ ! "$current" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "[ERROR] Active Node is missing or invalid: $current" >&2
        return 1
    fi
    printf 'Node: policy=lts active=%s selected=%s\n' "$current" "$expected"
    if [ "$current" != "$expected" ]; then
        echo "[ERROR] Active Node $current differs from policy Node $expected" >&2
        echo "Run: eval \"\$(mise activate bash --shims)\"" >&2
        return 2
    fi
}

prepare_global_mise_config() {
    local config target

    config="${HOME}/.config/mise/config.toml"
    if [ -L "$config" ]; then
        target=$(readlink "$config")
        if [ "$target" != "$NODE_POLICY_FILE" ]; then
            echo "[ERROR] Refusing to replace unmanaged mise config: $config" >&2
            return 1
        fi
        rm "$config"
    fi
}

record_global_node_policy() {
    local binary policy

    policy=$(required_node_policy) || return 1
    prepare_global_mise_config || return 1
    binary=$(mise_bin)
    env -u MISE_NODE_VERSION -u MISE_GLOBAL_CONFIG_FILE \
        "$binary" config set --global tools.node "$policy" >/dev/null
}

activate_node() {
    local activation binary
    required_node_policy >/dev/null || return 1
    binary=$(mise_bin)
    [ -x "$binary" ] || return 1
    export MISE_TRUSTED_CONFIG_PATHS="${HOME}/.config/mise/conf.d\
${MISE_TRUSTED_CONFIG_PATHS:+:${MISE_TRUSTED_CONFIG_PATHS}}"
    unset MISE_GLOBAL_CONFIG_FILE
    unset MISE_NODE_VERSION
    activation=$("$binary" activate bash --shims) || return 1
    eval "$activation" || return 1
    check_node
}

install_mise() {
    local binary installer
    binary=$(mise_bin)
    if [ -x "$binary" ]; then
        return 0
    fi
    mkdir -p "$(dirname "$binary")"
    installer=$(mktemp "${TMPDIR:-/tmp}/mise-install.XXXXXX") || return 1
    if ! curl -fsSL "$MISE_INSTALL_URL" -o "$installer"; then
        rm -f "$installer"
        echo "[ERROR] Failed to download mise" >&2
        return 1
    fi
    echo "[INFO] Installing mise..."
    if ! MISE_INSTALL_PATH="$binary" sh "$installer"; then
        rm -f "$installer"
        echo "[ERROR] Failed to install mise" >&2
        return 1
    fi
    rm -f "$installer"
    [ -x "$binary" ] || {
        echo "[ERROR] mise installer did not create $binary" >&2
        return 1
    }
}

install_node() {
    local refresh="${1:-false}"
    required_node_policy >/dev/null || return 1
    install_mise || return 1
    if [ "$refresh" = true ] || ! run_mise which node >/dev/null 2>&1; then
        echo "[INFO] Installing current Node LTS..."
        if ! run_mise install node; then
            echo "[ERROR] Failed to install Node LTS; previous Node retained" >&2
            return 1
        fi
    else
        echo "[INFO] Node LTS is already installed"
    fi
    record_global_node_policy || return 1
    activate_node
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

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

select_latest_stable_node() {
    awk '
        $1 ~ /^v[0-9]+\.[0-9]+\.[0-9]+$/ {
            split(substr($1, 2), part, ".")
            if (!found || part[1] + 0 > major ||
                (part[1] + 0 == major && part[2] + 0 > minor) ||
                (part[1] + 0 == major && part[2] + 0 == minor &&
                 part[3] + 0 > patch)) {
                found = 1
                major = part[1] + 0
                minor = part[2] + 0
                patch = part[3] + 0
                version = $1
            }
        }
        END {
            if (!found) exit 1
            print version
        }
    '
}

latest_installed_stable_node() {
    local candidate
    for candidate in "$NVM_DIR"/versions/node/v*; do
        [ -x "$candidate/bin/node" ] || continue
        basename "$candidate"
    done | select_latest_stable_node
}

latest_remote_stable_node() {
    nvm ls-remote --no-colors | select_latest_stable_node
}

remove_nvm_node_paths() {
    local entry clean_path=""
    local IFS=:
    for entry in $PATH; do
        case "$entry" in
        "$NVM_DIR"/versions/node/*/bin) continue ;;
        esac
        clean_path="${clean_path:+${clean_path}:}${entry}"
    done
    export PATH="$clean_path"
}

check_node() {
    local current installed
    required_node_version >/dev/null || return 1
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
        installed=$(latest_installed_stable_node) || {
            echo "[ERROR] No stable Node version is installed" >&2
            return 1
        }
        printf 'Node: policy=latest active=%s latest-installed=%s\n' "$current" "$installed"
        if [ "$current" != "$installed" ]; then
            echo "[ERROR] Active Node $current differs from latest installed $installed" >&2
            echo "Run: nvm use $installed" >&2
            return 2
        fi
    else
        printf 'Node: policy=latest active=%s (latest not checked)\n' "$current"
    fi
}

# Activate the newest installed Node in the caller's shell.
activate_node() {
    local installed
    required_node_version >/dev/null || return 1
    export NVM_DIR="${HOME}/.nvm"
    # shellcheck source=/dev/null
    . "${NVM_DIR}/nvm.sh" --no-use || return 1
    installed=$(latest_installed_stable_node) || return 1
    remove_nvm_node_paths
    nvm use --silent "$installed" || return 1
    check_node
}

install_nvm() {
    local refresh="${1:-false}"
    local installer release version installed target
    required_node_version >/dev/null || return 1
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
    installed=$(latest_installed_stable_node 2>/dev/null || true)
    target="$installed"
    if [ "$refresh" = true ] || [ -z "$target" ]; then
        target=$(latest_remote_stable_node) || {
            echo "[ERROR] Failed to resolve latest stable Node.js" >&2
            return 1
        }
        echo "[INFO] Installing Node.js $target..."
        # Never import globals or the user's nvm default-packages file.
        if ! nvm install --skip-default-packages "$target"; then
            echo "[ERROR] Failed to install latest Node.js; previous Node retained" >&2
            return 1
        fi
    else
        echo "[INFO] Node.js $installed is already installed"
    fi
    remove_nvm_node_paths
    nvm use --silent "$target" || return 1
    check_node || return 1
    nvm alias default "$target"
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

#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$DOTFILES_DIR/bootstrap.d/07-node.sh"

fail() {
    echo "[ERROR] $*" >&2
    exit 1
}

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/stubs"

cat >"$scratch/mise" <<'STUB'
#!/bin/bash
set -eu
root="$HOME/.local/share/mise"
current="$root/current-node"
case "$1" in
which)
    [ "${MISE_GLOBAL_CONFIG_FILE:-}" = "$EXPECTED_POLICY_FILE" ] || exit 89
    [ "$2" = node ]
    printf 'which offline=%s\n' "${MISE_OFFLINE:-0}" >>"$NODE_TEST_LOG"
    version=$(cat "$current")
    binary="$root/installs/node/$version/bin/node"
    [ -x "$binary" ]
    printf '%s\n' "$binary"
    ;;
install)
    [ "${MISE_GLOBAL_CONFIG_FILE:-}" = "$EXPECTED_POLICY_FILE" ] || exit 89
    [ "$2" = node ]
    printf 'install node policy=lts target=%s\n' "$NODE_TEST_LTS" \
        >>"$NODE_TEST_LOG"
    [ "${NODE_TEST_INSTALL_FAIL:-false}" = false ] || exit 22
    binary="$root/installs/node/$NODE_TEST_LTS/bin/node"
    mkdir -p "$(dirname "$binary")"
    printf '#!/bin/sh\necho v%s\n' "$NODE_TEST_LTS" >"$binary"
    chmod +x "$binary"
    printf '%s\n' "$NODE_TEST_LTS" >"$current"
    ;;
config)
    [ -z "${MISE_GLOBAL_CONFIG_FILE+x}" ] || exit 91
    [ "$2" = set ]
    [ "$3" = --global ]
    [ "$4" = tools.node ]
    mkdir -p "$HOME/.config/mise"
    printf '[tools]\nnode = "%s"\n' "$5" \
        >"$HOME/.config/mise/config.toml"
    ;;
activate)
    [ -z "${MISE_GLOBAL_CONFIG_FILE+x}" ] || exit 92
    case ":${MISE_TRUSTED_CONFIG_PATHS:-}:" in
    *":$HOME/.config/mise/conf.d:"*) ;;
    *) exit 93 ;;
    esac
    [ "$2" = bash ]
    [ "$3" = --shims ]
    version=$(cat "$current")
    printf 'export PATH="%s/installs/node/%s/bin:$PATH"\n' \
        "$root" "$version"
    ;;
*) exit 90 ;;
esac
STUB
chmod +x "$scratch/mise"

cat >"$scratch/stubs/curl" <<'STUB'
#!/bin/bash
set -eu
[ "${NODE_TEST_DOWNLOAD_FAIL:-false}" = false ] || exit 22
output=""
while [ "$#" -gt 0 ]; do
    if [ "$1" = -o ]; then
        output="$2"
        shift 2
    else
        shift
    fi
done
[ -n "$output" ]
cat >"$output" <<'INSTALLER'
#!/bin/sh
mkdir -p "$(dirname "$MISE_INSTALL_PATH")"
cp "$NODE_TEST_MISE" "$MISE_INSTALL_PATH"
chmod +x "$MISE_INSTALL_PATH"
INSTALLER
STUB
printf '#!/bin/sh\nexit 127\n' >"$scratch/stubs/node"
chmod +x "$scratch/stubs/"*

export NODE_TEST_MISE="$scratch/mise"
export NODE_TEST_LOG="$scratch/actions.log"
export NODE_TEST_LTS=26.13.0
export EXPECTED_POLICY_FILE="$NODE_POLICY_FILE"
export PATH="$scratch/stubs:/usr/bin:/bin"
: >"$NODE_TEST_LOG"

install_fixture_node() {
    local version="$1" binary
    binary="$HOME/.local/share/mise/installs/node/$version/bin/node"
    mkdir -p "$(dirname "$binary")" "$HOME/.local/bin"
    printf '#!/bin/sh\necho v%s\n' "$version" >"$binary"
    chmod +x "$binary"
    printf '%s\n' "$version" >"$HOME/.local/share/mise/current-node"
    cp "$NODE_TEST_MISE" "$HOME/.local/bin/mise"
}

(
    export HOME="$scratch/fresh"
    if check_node >/dev/null 2>&1; then
        fail "Node check accepted a missing mise runtime"
    fi
    before_path="$PATH"
    (install_node)
    [ "$PATH" = "$before_path" ]
    activate_node
    [ "$(node --version)" = v26.13.0 ]
    grep -Fx 'node = "lts"' "$HOME/.config/mise/config.toml" >/dev/null
    NODE_TEST_DOWNLOAD_FAIL=true check_node >/dev/null
    grep -F 'which offline=1' "$NODE_TEST_LOG" >/dev/null
    NODE_TEST_LTS=26.14.0 install_node
    [ "$(node --version)" = v26.13.0 ]
    NODE_TEST_LTS=26.14.0 install_node true
    [ "$(node --version)" = v26.14.0 ]
    echo "[INFO] Node fresh passed"
)

(
    export HOME="$scratch/older"
    install_fixture_node 24.11.1
    export PATH="$HOME/.local/share/mise/installs/node/24.11.1/bin:$PATH"
    check_node >/dev/null
    NODE_TEST_LTS=26.13.0 install_node
    [ "$(node --version)" = v24.11.1 ]
    grep -Fx 'node = "lts"' "$HOME/.config/mise/config.toml" >/dev/null
    NODE_TEST_LTS=26.13.0 install_node true
    [ "$(node --version)" = v26.13.0 ]
    [ -x "$HOME/.local/share/mise/installs/node/24.11.1/bin/node" ]
    echo "[INFO] Node older passed"
)

(
    export HOME="$scratch/failure"
    install_fixture_node 24.11.1
    export PATH="$HOME/.local/share/mise/installs/node/24.11.1/bin:$PATH"
    if NODE_TEST_INSTALL_FAIL=true install_node true \
        >"$scratch/failure.log" 2>&1; then
        fail "Node bootstrap ignored a failed LTS install"
    fi
    grep -F 'previous Node retained' "$scratch/failure.log" >/dev/null
    [ "$(node --version)" = v24.11.1 ]
    [ "$(cat "$HOME/.local/share/mise/current-node")" = 24.11.1 ]
    check_node >/dev/null
    echo "[INFO] Node failure passed"
)

(
    export HOME="$scratch/download-failure"
    if NODE_TEST_DOWNLOAD_FAIL=true install_node >/dev/null 2>&1; then
        fail "Node bootstrap ignored a failed mise download"
    fi
    [ ! -e "$HOME/.local/bin/mise" ]
)

(
    export HOME="$scratch/managed-link"
    install_fixture_node 26.13.0
    mkdir -p "$HOME/.config/mise"
    ln -s "$NODE_POLICY_FILE" "$HOME/.config/mise/config.toml"
    install_node
    [ ! -L "$HOME/.config/mise/config.toml" ]
    grep -Fx 'node = "lts"' "$HOME/.config/mise/config.toml" >/dev/null
)

(
    export HOME="$scratch/unmanaged-link"
    install_fixture_node 26.13.0
    mkdir -p "$HOME/.config/mise"
    printf '[tools]\npython = "latest"\n' >"$HOME/foreign.toml"
    ln -s "$HOME/foreign.toml" "$HOME/.config/mise/config.toml"
    if install_node >/dev/null 2>&1; then
        fail "Node bootstrap replaced an unmanaged mise config"
    fi
    [ -L "$HOME/.config/mise/config.toml" ]
)

invalid_policy="$scratch/invalid.toml"
printf '[tools]\nnode = "latest"\n' >"$invalid_policy"
if NODE_POLICY_FILE="$invalid_policy" required_node_policy >/dev/null 2>&1; then
    fail "Node bootstrap accepted a non-LTS policy"
fi
[ "$(grep -c '^install node policy=lts ' "$NODE_TEST_LOG")" -eq 4 ]
echo "[INFO] Node LTS smoke test passed"

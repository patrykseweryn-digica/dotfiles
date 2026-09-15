#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$DOTFILES_DIR/bootstrap.d/07-node.sh"
expected=$(required_node_version)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/stubs"

# A controlled provider at the nvm boundary; no network or host Node needed.
cat >"$scratch/nvm.sh" <<'STUB'
nvm() {
    case "$1" in
    version)
        local version="$2"
        [ "$version" != default ] || version=$(cat "$NVM_DIR/alias/default")
        if [ -x "$NVM_DIR/versions/node/v$version/bin/node" ]; then
            echo "v$version"
        else
            echo N/A
            return 3
        fi
        ;;
    install)
        echo "$*" >> "$NODE_TEST_LOG"
        [ "$2" = --skip-default-packages ] || return 90
        [ "${NODE_TEST_INSTALL_FAIL:-false}" = false ] || return 22
        mkdir -p "$NVM_DIR/versions/node/v$3/bin"
        printf '#!/bin/sh\necho v%s\n' "$3" > "$NVM_DIR/versions/node/v$3/bin/node"
        chmod +x "$NVM_DIR/versions/node/v$3/bin/node"
        nvm use --silent "$3"
        ;;
    use)
        [ "$2" = --silent ] || return 90
        [ -x "$NVM_DIR/versions/node/v$3/bin/node" ] || return 3
        export PATH="$NVM_DIR/versions/node/v$3/bin:$PATH"
        ;;
    alias)
        [ "$2" = default ] || return 90
        mkdir -p "$NVM_DIR/alias"
        echo "$3" > "$NVM_DIR/alias/default"
        ;;
    *) return 90 ;;
    esac
}
if [ "${1:-}" != --no-use ]; then
    nvm use --silent "$(cat "$NVM_DIR/alias/default")"
fi
STUB
cat >"$scratch/stubs/curl" <<'STUB'
#!/bin/sh
printf '%s\n' 'mkdir -p "$NVM_DIR"; cp "$NODE_TEST_NVM" "$NVM_DIR/nvm.sh"'
[ "${NODE_TEST_DOWNLOAD_FAIL:-false}" = false ] || exit 22
STUB
printf '#!/bin/sh\nexit 127\n' >"$scratch/stubs/node"
# Any npm call by the runtime bootstrap is a failure, including imports.
printf '#!/bin/sh\necho unexpected-npm >> "$NODE_TEST_LOG"; exit 90\n' >"$scratch/stubs/npm"
chmod +x "$scratch/stubs/"*
export NODE_TEST_NVM="$scratch/nvm.sh" NODE_TEST_LOG="$scratch/actions.log"
export PATH="$scratch/stubs:/usr/bin:/bin"
: >"$NODE_TEST_LOG"

for scenario in fresh older failure; do
    (
        export HOME="$scratch/$scenario" NVM_DIR="$scratch/$scenario/.nvm"
        mkdir -p "$NVM_DIR"
        printf 'do-not-import\n' >"$NVM_DIR/default-packages"
        if [ "$scenario" != fresh ]; then
            cp "$NODE_TEST_NVM" "$NVM_DIR/nvm.sh"
            mkdir -p "$NVM_DIR/versions/node/v22.21.0/bin" "$NVM_DIR/alias"
            printf '#!/bin/sh\necho v22.21.0\n' >"$NVM_DIR/versions/node/v22.21.0/bin/node"
            chmod +x "$NVM_DIR/versions/node/v22.21.0/bin/node"
            echo 22.21.0 >"$NVM_DIR/alias/default"
            export PATH="$NVM_DIR/versions/node/v22.21.0/bin:$PATH"
        fi
        if bash "$DOTFILES_DIR/bootstrap.d/07-node.sh" check; then
            echo "[ERROR] Node check accepted missing/older runtime" >&2
            exit 1
        fi
        if [ "$scenario" = failure ]; then
            if NODE_TEST_INSTALL_FAIL=true install_nvm >"$scratch/failure.log" 2>&1; then
                echo "[ERROR] Node bootstrap ignored failed install" >&2
                exit 1
            fi
            grep -F 'previous Node retained' "$scratch/failure.log" >/dev/null
            [ "$(node --version)" = v22.21.0 ]
            [ "$(nvm version default)" = v22.21.0 ]
        else
            before_path="$PATH"
            (install_nvm)
            [ "$PATH" = "$before_path" ]
            activate_node
            bash "$DOTFILES_DIR/bootstrap.d/07-node.sh" check
            # A new shell loads the persisted default without inherited NVM PATH.
            PATH="$scratch/stubs:/usr/bin:/bin" bash -c \
                'source "$HOME/.nvm/nvm.sh"; test "$(node --version)" = "v$1"' -- "$expected"
            cp "$NODE_TEST_LOG" "$scratch/before-repeat.log"
            NODE_TEST_INSTALL_FAIL=true install_nvm
            cmp "$NODE_TEST_LOG" "$scratch/before-repeat.log"
            if [ "$scenario" = older ]; then
                [ "$("$NVM_DIR/versions/node/v22.21.0/bin/node" --version)" = v22.21.0 ]
            fi
        fi
        echo "[INFO] Node $scenario passed"
    )
done
(
    export HOME="$scratch/download-failure"
    if NODE_TEST_DOWNLOAD_FAIL=true install_nvm >/dev/null 2>&1; then
        echo "[ERROR] Node bootstrap ignored failed NVM download" >&2
        exit 1
    fi
    [ ! -e "$HOME/.nvm/nvm.sh" ]
)
[ "$(grep -c '^install --skip-default-packages ' "$NODE_TEST_LOG")" -eq 3 ]
if grep -F unexpected-npm "$NODE_TEST_LOG"; then exit 1; fi
echo "[INFO] Node smoke test passed"

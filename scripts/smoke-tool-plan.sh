#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
    echo "[ERROR] $*" >&2
    exit 1
}

assert_log_contains() {
    local log_file="$1"
    local expected="$2"

    if ! grep -F "$expected" "$log_file" >/dev/null 2>&1; then
        echo "[ERROR] Missing expected log line: $expected" >&2
        echo "[ERROR] Actual log:" >&2
        cat "$log_file" >&2
        exit 1
    fi
}

write_package_manager_stubs() {
    local stub_dir="$1"

    cat > "${stub_dir}/sudo" <<'STUB'
#!/bin/sh
"$@"
STUB

    cat > "${stub_dir}/apt-get" <<'STUB'
#!/bin/sh
echo "apt-get $*" >> "$SMOKE_LOG"

if [ "$1" = "install" ]; then
    shift
    for package_name in "$@"; do
        case "$package_name" in
            bat)
                printf '#!/bin/sh\n' > "${SMOKE_BIN}/batcat"
                chmod +x "${SMOKE_BIN}/batcat"
                ;;
            fd-find)
                printf '#!/bin/sh\n' > "${SMOKE_BIN}/fdfind"
                chmod +x "${SMOKE_BIN}/fdfind"
                ;;
        esac
    done
fi
STUB

    chmod +x "${stub_dir}/sudo" "${stub_dir}/apt-get"
}

smoke_package_manager_plan() {
    local tmp_dir
    local stub_dir
    local bin_dir
    local log_file

    tmp_dir="$(mktemp -d)"
    stub_dir="${tmp_dir}/stubs"
    bin_dir="${tmp_dir}/bin"
    log_file="${tmp_dir}/actions.log"

    mkdir -p "$stub_dir" "$bin_dir"
    : > "$log_file"
    write_package_manager_stubs "$stub_dir"

    (
        # shellcheck source=/dev/null
        source "${DOTFILES_DIR}/bootstrap.d/00-utils.sh"
        # shellcheck source=/dev/null
        source "${DOTFILES_DIR}/bootstrap.d/05-tools.sh"

        check_installed() {
            local found

            found="$(command -v "$1" 2>/dev/null || true)"
            case "$found" in
                "${BIN_DIR}"/* | "${stub_dir}"/*) return 0 ;;
                *) return 1 ;;
            esac
        }

        export SMOKE_LOG="$log_file"
        export SMOKE_BIN="$bin_dir"
        # shellcheck disable=SC2034
        HAS_SUDO=true
        BIN_DIR="$bin_dir"
        PATH="${bin_dir}:${stub_dir}:/usr/bin:/bin"

        install_core_cli_tools >/dev/null
    )

    assert_log_contains "$log_file" "apt-get install -y fzf"
    assert_log_contains "$log_file" "apt-get install -y bat"
    assert_log_contains "$log_file" "apt-get install -y ripgrep"
    assert_log_contains "$log_file" "apt-get install -y fd-find"
    assert_log_contains "$log_file" "apt-get install -y jq"
    [ -L "${bin_dir}/bat" ] || fail "bat alias symlink was not created"
    [ -L "${bin_dir}/fd" ] || fail "fd alias symlink was not created"

    rm -rf "$tmp_dir"
}

smoke_github_fallback_plan() {
    local tmp_dir
    local bin_dir
    local log_file

    tmp_dir="$(mktemp -d)"
    bin_dir="${tmp_dir}/bin"
    log_file="${tmp_dir}/actions.log"

    mkdir -p "$bin_dir"
    : > "$log_file"

    (
        # shellcheck source=/dev/null
        source "${DOTFILES_DIR}/bootstrap.d/00-utils.sh"
        # shellcheck source=/dev/null
        source "${DOTFILES_DIR}/bootstrap.d/05-tools.sh"

        check_installed() {
            return 1
        }

        install_github_binary() {
            echo "github $*" >> "$log_file"
        }

        # shellcheck disable=SC2034
        HAS_SUDO=false
        BIN_DIR="$bin_dir"
        PATH="${bin_dir}:/usr/bin:/bin"

        install_core_cli_tools >/dev/null
    )

    assert_log_contains "$log_file" "github junegunn/fzf v0.67.0 fzf-{tag_no_v}-linux_amd64.tar.gz fzf"
    assert_log_contains "$log_file" "github sharkdp/bat v0.26.1 bat-{tag}-x86_64-unknown-linux-gnu.tar.gz bat"
    assert_log_contains "$log_file" "github BurntSushi/ripgrep 15.1.0 ripgrep-{tag}-x86_64-unknown-linux-musl.tar.gz rg"
    assert_log_contains "$log_file" "github sharkdp/fd v10.2.0 fd-{tag}-x86_64-unknown-linux-gnu.tar.gz fd"
    assert_log_contains "$log_file" "github jqlang/jq jq-1.7.1 jq-linux-amd64 jq-linux-amd64 jq"

    rm -rf "$tmp_dir"
}

smoke_package_manager_plan
smoke_github_fallback_plan

echo "[INFO] tool plan smoke test passed"

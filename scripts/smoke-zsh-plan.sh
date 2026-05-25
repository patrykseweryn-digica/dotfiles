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
        cat "$log_file" >&2
        exit 1
    fi
}

tmp_dir="$(mktemp -d)"
cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

stub_dir="${tmp_dir}/stubs"
bin_dir="${tmp_dir}/bin"
opt_dir="${tmp_dir}/opt"
home_dir="${tmp_dir}/home"
log_file="${tmp_dir}/actions.log"

mkdir -p "$stub_dir" "$bin_dir" "$opt_dir" "$home_dir"
: > "$log_file"

cat > "${stub_dir}/brew" <<'STUB'
#!/bin/sh
echo "brew $*" >> "$SMOKE_LOG"

if [ "$1" = "install" ] && [ "$2" = "zsh" ]; then
    printf '#!/bin/sh\necho zsh 5.9\n' > "${SMOKE_BIN}/zsh"
    chmod +x "${SMOKE_BIN}/zsh"
fi
STUB

cat > "${stub_dir}/sudo" <<'STUB'
#!/bin/sh
echo "sudo $*" >> "$SMOKE_LOG"
exit 1
STUB

cat > "${stub_dir}/curl" <<'STUB'
#!/bin/sh
echo "curl $*" >> "$SMOKE_LOG"
exit 1
STUB

cat > "${stub_dir}/make" <<'STUB'
#!/bin/sh
echo "make $*" >> "$SMOKE_LOG"
exit 1
STUB

cat > "${stub_dir}/chsh" <<'STUB'
#!/bin/sh
echo "chsh $*" >> "$SMOKE_LOG"
STUB

chmod +x "${stub_dir}/brew" "${stub_dir}/sudo" "${stub_dir}/curl" "${stub_dir}/make" "${stub_dir}/chsh"

(
    # shellcheck source=/dev/null
    source "${DOTFILES_DIR}/bootstrap.d/00-utils.sh"
    # shellcheck source=/dev/null
    source "${DOTFILES_DIR}/bootstrap.d/02-zsh.sh"

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
    export HOME="$home_dir"
    export SHELL="/bin/bash"
    # shellcheck disable=SC2034
    HAS_SUDO=false
    # shellcheck disable=SC2034
    BIN_DIR="$bin_dir"
    # shellcheck disable=SC2034
    OPT_DIR="$opt_dir"
    PATH="${bin_dir}:${stub_dir}:/usr/bin:/bin"

    install_zsh >/dev/null
)

assert_log_contains "$log_file" "brew install zsh"
assert_log_contains "$log_file" "chsh -s ${bin_dir}/zsh"

if grep -E '^(sudo|curl|make) ' "$log_file" >/dev/null 2>&1; then
    echo "[ERROR] zsh Homebrew plan should not use sudo/source fallback" >&2
    cat "$log_file" >&2
    exit 1
fi

[ -x "${bin_dir}/zsh" ] || fail "zsh binary was not installed via Homebrew stub"

echo "[INFO] zsh plan smoke test passed"

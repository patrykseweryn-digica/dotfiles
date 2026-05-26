#!/bin/bash
# shellcheck disable=SC2030,SC2031,SC2329
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

assert_log_not_contains() {
    local log_file="$1"
    local unexpected="$2"

    if grep -F "$unexpected" "$log_file" >/dev/null 2>&1; then
        echo "[ERROR] Unexpected log line: $unexpected" >&2
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
            git-lfs)
                printf '#!/bin/sh\n' > "${SMOKE_BIN}/git-lfs"
                chmod +x "${SMOKE_BIN}/git-lfs"
                ;;
            eza)
                printf '#!/bin/sh\n' > "${SMOKE_BIN}/eza"
                chmod +x "${SMOKE_BIN}/eza"
                ;;
            tealdeer)
                printf '#!/bin/sh\necho "tldr $*" >> "$SMOKE_LOG"\n' > "${SMOKE_BIN}/tldr"
                chmod +x "${SMOKE_BIN}/tldr"
                ;;
            xclip)
                printf '#!/bin/sh\n' > "${SMOKE_BIN}/xclip"
                chmod +x "${SMOKE_BIN}/xclip"
                ;;
        esac
    done
fi
STUB

    chmod +x "${stub_dir}/sudo" "${stub_dir}/apt-get"
}

write_linuxbrew_stubs() {
    local stub_dir="$1"

    cat > "${stub_dir}/apt-get" <<'STUB'
#!/bin/sh
echo "apt-get $*" >> "$SMOKE_LOG"
exit 1
STUB

    cat > "${stub_dir}/brew" <<'STUB'
#!/bin/sh
echo "brew $*" >> "$SMOKE_LOG"

if [ "$1" = "install" ]; then
    shift
    for package_name in "$@"; do
        case "$package_name" in
            bat)
                printf '#!/bin/sh\n' > "${SMOKE_BIN}/bat"
                chmod +x "${SMOKE_BIN}/bat"
                ;;
            fd)
                printf '#!/bin/sh\n' > "${SMOKE_BIN}/fd"
                chmod +x "${SMOKE_BIN}/fd"
                ;;
            git-lfs)
                printf '#!/bin/sh\n' > "${SMOKE_BIN}/git-lfs"
                chmod +x "${SMOKE_BIN}/git-lfs"
                ;;
            eza)
                printf '#!/bin/sh\n' > "${SMOKE_BIN}/eza"
                chmod +x "${SMOKE_BIN}/eza"
                ;;
            git-delta)
                printf '#!/bin/sh\n' > "${SMOKE_BIN}/delta"
                chmod +x "${SMOKE_BIN}/delta"
                ;;
            tealdeer)
                printf '#!/bin/sh\necho "tldr $*" >> "$SMOKE_LOG"\n' > "${SMOKE_BIN}/tldr"
                chmod +x "${SMOKE_BIN}/tldr"
                ;;
            lazygit)
                printf '#!/bin/sh\n' > "${SMOKE_BIN}/lazygit"
                chmod +x "${SMOKE_BIN}/lazygit"
                ;;
            xclip)
                printf '#!/bin/sh\n' > "${SMOKE_BIN}/xclip"
                chmod +x "${SMOKE_BIN}/xclip"
                ;;
        esac
    done
fi
STUB

    cat > "${stub_dir}/sudo" <<'STUB'
#!/bin/sh
echo "sudo $*" >> "$SMOKE_LOG"
exit 1
STUB

    chmod +x "${stub_dir}/apt-get" "${stub_dir}/brew" "${stub_dir}/sudo"
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
    assert_log_contains "$log_file" "apt-get install -y tmux"
    assert_log_contains "$log_file" "apt-get install -y neovim"
    assert_log_contains "$log_file" "apt-get install -y git-lfs"
    assert_log_contains "$log_file" "apt-get install -y shfmt"
    assert_log_contains "$log_file" "apt-get install -y just"
    [ -L "${bin_dir}/bat" ] || fail "bat alias symlink was not created"
    [ -L "${bin_dir}/fd" ] || fail "fd alias symlink was not created"

    rm -rf "$tmp_dir"
}

smoke_linuxbrew_without_sudo_plan() {
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
    write_linuxbrew_stubs "$stub_dir"

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
        HAS_SUDO=false
        BIN_DIR="$bin_dir"
        PATH="${bin_dir}:${stub_dir}:/usr/bin:/bin"

        install_core_cli_tools >/dev/null
    )

    assert_log_contains "$log_file" "brew install fzf"
    assert_log_contains "$log_file" "brew install bat"
    assert_log_contains "$log_file" "brew install ripgrep"
    assert_log_contains "$log_file" "brew install fd"
    assert_log_contains "$log_file" "brew install jq"
    assert_log_contains "$log_file" "brew install tmux"
    assert_log_contains "$log_file" "brew install neovim"
    assert_log_contains "$log_file" "brew install git-lfs"
    assert_log_contains "$log_file" "brew install shfmt"
    assert_log_contains "$log_file" "brew install just"
    assert_log_contains "$log_file" "brew install hadolint"
    assert_log_contains "$log_file" "brew install bitwarden-cli"
    if grep -F "sudo " "$log_file" >/dev/null 2>&1 || grep -F "apt-get " "$log_file" >/dev/null 2>&1; then
        echo "[ERROR] Linuxbrew plan should not fall back to sudo or apt-get when HAS_SUDO=false" >&2
        cat "$log_file" >&2
        exit 1
    fi

    rm -rf "$tmp_dir"
}

smoke_remaining_tool_plan() {
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

        install_github_binary() {
            echo "github $*" >> "$log_file"
        }

        export SMOKE_LOG="$log_file"
        export SMOKE_BIN="$bin_dir"
        # shellcheck disable=SC2034
        HAS_SUDO=true
        # shellcheck disable=SC2034
        IS_LINUX=true
        # shellcheck disable=SC2034
        IS_MACOS=false
        BIN_DIR="$bin_dir"
        PATH="${bin_dir}:${stub_dir}:/usr/bin:/bin"

        install_eza >/dev/null
        install_delta >/dev/null
        install_tealdeer >/dev/null
        install_lazygit >/dev/null
        install_xclip >/dev/null
    )

    assert_log_contains "$log_file" "apt-get install -y eza"
    assert_log_contains "$log_file" "apt-get install -y tealdeer"
    assert_log_contains "$log_file" "apt-get install -y xclip"
    assert_log_contains "$log_file" "github dandavison/delta 0.18.2 delta-{tag}-x86_64-unknown-linux-gnu.tar.gz delta"
    assert_log_contains "$log_file" "github jesseduffield/lazygit v0.59.0 lazygit_{tag_no_v}_Linux_x86_64.tar.gz lazygit"
    assert_log_contains "$log_file" "tldr --update"

    rm -rf "$tmp_dir"
}

smoke_installed_tools_are_skipped() {
    local tmp_dir
    local stub_dir
    local bin_dir
    local log_file
    local installed_tool

    tmp_dir="$(mktemp -d)"
    stub_dir="${tmp_dir}/stubs"
    bin_dir="${tmp_dir}/bin"
    log_file="${tmp_dir}/actions.log"

    mkdir -p "$stub_dir" "$bin_dir"
    : > "$log_file"

    for installed_tool in fzf bat rg fd jq tmux nvim git-lfs shfmt just hadolint bw eza delta tldr lazygit xclip; do
        printf '#!/bin/sh\n' > "${bin_dir}/${installed_tool}"
        chmod +x "${bin_dir}/${installed_tool}"
    done

    cat > "${stub_dir}/brew" <<'STUB'
#!/bin/sh
echo "brew $*" >> "$SMOKE_LOG"
STUB

    cat > "${stub_dir}/apt-get" <<'STUB'
#!/bin/sh
echo "apt-get $*" >> "$SMOKE_LOG"
STUB

    chmod +x "${stub_dir}/brew" "${stub_dir}/apt-get"

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

        install_github_binary() {
            echo "github $*" >> "$log_file"
        }

        export SMOKE_LOG="$log_file"
        # shellcheck disable=SC2034
        HAS_SUDO=true
        # shellcheck disable=SC2034
        IS_LINUX=true
        # shellcheck disable=SC2034
        IS_MACOS=false
        BIN_DIR="$bin_dir"
        PATH="${bin_dir}:${stub_dir}:/usr/bin:/bin"

        install_core_cli_tools >/dev/null
        install_eza >/dev/null
        install_delta >/dev/null
        install_tealdeer >/dev/null
        install_lazygit >/dev/null
        install_xclip >/dev/null
    )

    assert_log_not_contains "$log_file" "brew install"
    assert_log_not_contains "$log_file" "apt-get install"
    assert_log_not_contains "$log_file" "github "

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
        # shellcheck disable=SC2034
        IS_LINUX=true
        BIN_DIR="$bin_dir"
        PATH="${bin_dir}:/usr/bin:/bin"

        install_core_cli_tools >/dev/null
        install_eza >/dev/null
        install_delta >/dev/null
        install_tealdeer >/dev/null
        install_lazygit >/dev/null
    )

    assert_log_contains "$log_file" "github junegunn/fzf v0.67.0 fzf-{tag_no_v}-linux_amd64.tar.gz fzf"
    assert_log_contains "$log_file" "github sharkdp/bat v0.26.1 bat-{tag}-x86_64-unknown-linux-gnu.tar.gz bat"
    assert_log_contains "$log_file" "github BurntSushi/ripgrep 15.1.0 ripgrep-{tag}-x86_64-unknown-linux-musl.tar.gz rg"
    assert_log_contains "$log_file" "github sharkdp/fd v10.2.0 fd-{tag}-x86_64-unknown-linux-gnu.tar.gz fd"
    assert_log_contains "$log_file" "github jqlang/jq jq-1.7.1 jq-linux-amd64 jq-linux-amd64 jq"
    assert_log_contains "$log_file" "github eza-community/eza v0.20.14 eza_x86_64-unknown-linux-gnu.tar.gz eza"
    assert_log_contains "$log_file" "github dandavison/delta 0.18.2 delta-{tag}-x86_64-unknown-linux-gnu.tar.gz delta"
    assert_log_contains "$log_file" "github tealdeer-rs/tealdeer v1.8.1 tealdeer-linux-x86_64-musl tealdeer-linux-x86_64-musl tldr"
    assert_log_contains "$log_file" "github jesseduffield/lazygit v0.59.0 lazygit_{tag_no_v}_Linux_x86_64.tar.gz lazygit"

    rm -rf "$tmp_dir"
}

smoke_macos_github_patterns() {
    (
        # shellcheck source=/dev/null
        source "${DOTFILES_DIR}/bootstrap.d/00-utils.sh"

        # shellcheck disable=SC2034
        OS="Darwin"
        # shellcheck disable=SC2034
        ARCH="arm64"

        [ "$(github_binary_pattern fzf)" = "fzf-{tag_no_v}-darwin_arm64.tar.gz" ] || fail "bad macOS fzf archive pattern"
        [ "$(github_binary_pattern bat)" = "bat-{tag}-aarch64-apple-darwin.tar.gz" ] || fail "bad macOS bat archive pattern"
        [ "$(github_binary_pattern ripgrep)" = "ripgrep-{tag}-aarch64-apple-darwin.tar.gz" ] || fail "bad macOS ripgrep archive pattern"
        [ "$(github_binary_pattern fd)" = "fd-{tag}-aarch64-apple-darwin.tar.gz" ] || fail "bad macOS fd archive pattern"
        [ "$(github_binary_pattern delta)" = "delta-{tag}-aarch64-apple-darwin.tar.gz" ] || fail "bad macOS delta archive pattern"
        [ "$(github_binary_pattern lazygit)" = "lazygit_{tag_no_v}_darwin_arm64.tar.gz" ] || fail "bad macOS lazygit archive pattern"
        [ "$(github_binary_pattern jq)" = "jq-macos-arm64" ] || fail "bad macOS jq archive pattern"
        [ "$(github_binary_pattern tealdeer)" = "tealdeer-macos-aarch64" ] || fail "bad macOS tealdeer archive pattern"
    )
}

smoke_direct_binary_install() {
    local tmp_dir
    local bin_dir

    tmp_dir="$(mktemp -d)"
    bin_dir="${tmp_dir}/bin"
    mkdir -p "$bin_dir"

    (
        # shellcheck source=/dev/null
        source "${DOTFILES_DIR}/bootstrap.d/00-utils.sh"

        curl() {
            local output_path=""

            while [ "$#" -gt 0 ]; do
                case "$1" in
                    -o)
                        shift
                        output_path="$1"
                        ;;
                esac
                shift
            done

            [ -n "$output_path" ] || return 1
            printf '#!/bin/sh\n' > "$output_path"
        }

        # shellcheck disable=SC2034
        BIN_DIR="$bin_dir"

        install_github_binary "jqlang/jq" "jq-1.7.1" "jq-linux-amd64" "jq-linux-amd64" "jq" >/dev/null
    )

    [ -x "${bin_dir}/jq" ] || fail "direct GitHub binary asset was not installed"

    rm -rf "$tmp_dir"
}

smoke_package_manager_plan
smoke_linuxbrew_without_sudo_plan
smoke_remaining_tool_plan
smoke_installed_tools_are_skipped
smoke_github_fallback_plan
smoke_macos_github_patterns
smoke_direct_binary_install

echo "[INFO] tool plan smoke test passed"

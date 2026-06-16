#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
    echo "[ERROR] $*" >&2
    exit 1
}

JQ_BIN="$(command -v jq 2>/dev/null || true)"
[ -n "$JQ_BIN" ] || fail "jq is required"

smoke_source_has_no_home_side_effect() {
    local tmp_dir
    local home_dir
    local env_file

    tmp_dir="$(mktemp -d)"
    home_dir="${tmp_dir}/home"
    env_file="${tmp_dir}/dotfiles.env"

    mkdir -p "$home_dir"

    (
        export HOME="$home_dir"
        export DOTFILES_ENV_FILE="$env_file"
        # shellcheck source=/dev/null
        source "${DOTFILES_DIR}/install.sh"
    )

    [ ! -e "${home_dir}/.local" ] || fail "sourcing install.sh should not create ~/.local"
    [ ! -e "$env_file" ] || fail "sourcing install.sh should not create env file"

    rm -rf "$tmp_dir"
}

smoke_codex_npm_install_on_linux_only() {
    local tmp_dir
    local stub_dir
    local npm_log

    tmp_dir="$(mktemp -d)"
    stub_dir="${tmp_dir}/stubs"
    npm_log="${tmp_dir}/npm.log"

    mkdir -p "${tmp_dir}/linux-home/.nvm" "${tmp_dir}/macos-home/.nvm" "$stub_dir"
    : > "$npm_log"

    cat > "${stub_dir}/npm" <<'STUB'
#!/bin/sh
echo "npm $*" >> "$NPM_LOG"
STUB
    chmod +x "${stub_dir}/npm"

    cat > "${tmp_dir}/linux-home/.nvm/nvm.sh" <<'STUB'
nvm() {
    case "$1 $2" in
        "ls default") echo "v22.0.0" ;;
        "version default") echo "v22.0.0" ;;
        *) return 0 ;;
    esac
}
STUB
    cp "${tmp_dir}/linux-home/.nvm/nvm.sh" "${tmp_dir}/macos-home/.nvm/nvm.sh"

    (
        export HOME="${tmp_dir}/linux-home"
        export PATH="${stub_dir}:/usr/bin:/bin"
        export NPM_LOG="$npm_log"
        # shellcheck source=/dev/null
        source "${DOTFILES_DIR}/install.sh"
        export IS_LINUX=true
        export IS_MACOS=false
        install_nvm >/dev/null
    )

    grep -q "npm i -g @openai/codex@latest" "$npm_log" || fail "Linux: missing Codex npm install"

    : > "$npm_log"
    (
        export HOME="${tmp_dir}/macos-home"
        export PATH="${stub_dir}:/usr/bin:/bin"
        export NPM_LOG="$npm_log"
        # shellcheck source=/dev/null
        source "${DOTFILES_DIR}/install.sh"
        export IS_LINUX=false
        export IS_MACOS=true
        install_nvm >/dev/null
    )

    if grep -q "@openai/codex" "$npm_log"; then
        fail "Darwin: Codex should stay managed by Homebrew cask"
    fi

    rm -rf "$tmp_dir"
}

smoke_tmux_plugins_install_after_setup_dotfiles() {
    local tmp_dir
    local home_dir
    local stub_dir
    local env_file
    local npx_log
    local tmux_log

    tmp_dir="$(mktemp -d)"
    home_dir="${tmp_dir}/home"
    stub_dir="${tmp_dir}/stubs"
    env_file="${tmp_dir}/dotfiles.env"
    npx_log="${tmp_dir}/npx.log"
    tmux_log="${tmp_dir}/tmux.log"

    mkdir -p "${home_dir}/.tmux/plugins/tpm/bin" "$stub_dir"
    ln -s "$JQ_BIN" "${stub_dir}/jq"
    : > "$npx_log"
    : > "$tmux_log"

    cat > "${stub_dir}/npx" <<'STUB'
#!/bin/sh
echo "npx $*" >> "$NPX_LOG"
exit 127
STUB
    chmod +x "${stub_dir}/npx"

    cat > "${home_dir}/.tmux/plugins/tpm/bin/install_plugins" <<'STUB'
#!/bin/sh
if [ ! -L "$HOME/.tmux.conf" ]; then
    echo "missing linked tmux config" >> "$TMUX_LOG"
    exit 42
fi
echo "tmux plugins installed with $(readlink "$HOME/.tmux.conf")" >> "$TMUX_LOG"
STUB
    chmod +x "${home_dir}/.tmux/plugins/tpm/bin/install_plugins"

    (
        export HOME="$home_dir"
        export PATH="${stub_dir}:/usr/bin:/bin"
        export EMAIL="test@example.com"
        export WORK_EMAIL="work@example.com"
        export EDITOR="vim"
        export CODEX_HOME="${HOME}/.codex"
        export OPENCODE_CONFIG_DIR="${HOME}/.config/opencode"
        export OPENCODE_CONFIG="${OPENCODE_CONFIG_DIR}/opencode.json"
        export DOTFILES_SKIP_SSH=true
        export DOTFILES_ENV_FILE="$env_file"
        export NPX_LOG="$npx_log"
        export TMUX_LOG="$tmux_log"

        # shellcheck source=/dev/null
        source "${DOTFILES_DIR}/install.sh"

        export OS="Linux"
        export ARCH="x86_64"
        export IS_MACOS=false
        export IS_LINUX=true

        setup_dotfiles >/dev/null 2>&1
        install_tmux_plugins >/dev/null 2>&1
    )

    grep -q "tmux plugins installed with ${DOTFILES_DIR}/.tmux.conf" "$tmux_log" ||
        fail "tmux plugins were not installed after .tmux.conf was linked"

    rm -rf "$tmp_dir"
}

run_case() {
    local os_name="$1"
    local expected_code_dir="$2"
    local expected_ghostty_config="$3"
    local tmp_dir
    local home_dir
    local stub_dir
    local sync_log
    local env_file
    local npx_log

    tmp_dir="$(mktemp -d)"
    home_dir="${tmp_dir}/home"
    stub_dir="${tmp_dir}/stubs"
    sync_log="${tmp_dir}/sync.log"
    env_file="${tmp_dir}/dotfiles.env"
    npx_log="${tmp_dir}/npx.log"

    mkdir -p "$home_dir" "$stub_dir"
    ln -s "$JQ_BIN" "${stub_dir}/jq"
    : > "$npx_log"

    cat > "${stub_dir}/npx" <<'STUB'
#!/bin/sh
echo "npx $*" >> "$NPX_LOG"
exit 127
STUB
    chmod +x "${stub_dir}/npx"

    (
        export HOME="$home_dir"
        export PATH="${stub_dir}:/usr/bin:/bin"
        export EMAIL="test@example.com"
        export WORK_EMAIL="work@example.com"
        export EDITOR="vim"
        export CODEX_HOME="${HOME}/.codex"
        export OPENCODE_CONFIG_DIR="${HOME}/.config/opencode"
        export OPENCODE_CONFIG="${OPENCODE_CONFIG_DIR}/opencode.json"
        export DOTFILES_SKIP_SSH=true
        export DOTFILES_ENV_FILE="$env_file"
        export NPX_LOG="$npx_log"

        # shellcheck source=/dev/null
        source "${DOTFILES_DIR}/install.sh"

        export OS="$os_name"
        export ARCH="arm64"
        export IS_MACOS=false
        export IS_LINUX=false
        if [ "$OS" = "Darwin" ]; then
            export IS_MACOS=true
        else
            export IS_LINUX=true
        fi

        setup_dotfiles > "$sync_log" 2>&1
    )

    [ -L "${home_dir}/.zshrc" ] || fail "$os_name: missing .zshrc symlink"
    [ ! -e "$env_file" ] || fail "$os_name: setup_dotfiles should not create env file when sourced"
    [ -L "${home_dir}/${expected_code_dir}/settings.json" ] || fail "$os_name: missing VS Code settings symlink"
    [ -L "${home_dir}/${expected_ghostty_config}" ] || fail "$os_name: missing Ghostty config symlink"
    [ -L "${home_dir}/.claude/CLAUDE.md" ] || fail "$os_name: missing Claude instructions symlink"
    [ -L "${home_dir}/.summarize/config.json" ] || fail "$os_name: missing summarize config symlink"
    [ -L "${home_dir}/.codex/AGENTS.md" ] || fail "$os_name: missing Codex instructions symlink"
    [ -L "${home_dir}/.config/opencode/AGENTS.md" ] || fail "$os_name: missing OpenCode instructions symlink"
    [ -f "${home_dir}/.codex/config.toml" ] || fail "$os_name: missing Codex config"
    [ -f "${home_dir}/.config/opencode/opencode.json" ] || fail "$os_name: missing OpenCode config"

    if [ -L "${home_dir}/.claude/settings.json" ]; then
        fail "$os_name: Claude settings must be generated as a plain file, not symlinked"
    fi
    [ -f "${home_dir}/.claude/settings.json" ] || fail "$os_name: missing generated Claude settings"
    [ -s "$npx_log" ] || fail "$os_name: sync should attempt lock-managed skill install and degrade cleanly when npx fails"

    rm -rf "$tmp_dir"
}

smoke_source_has_no_home_side_effect
smoke_codex_npm_install_on_linux_only
smoke_tmux_plugins_install_after_setup_dotfiles
run_case "Linux" ".config/Code/User" ".config/ghostty/config"
run_case "Darwin" "Library/Application Support/Code/User" "Library/Application Support/com.mitchellh.ghostty/config.ghostty"

echo "[INFO] install dotfiles smoke test passed"

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
run_case "Linux" ".config/Code/User" ".config/ghostty/config"
run_case "Darwin" "Library/Application Support/Code/User" "Library/Application Support/com.mitchellh.ghostty/config.ghostty"

echo "[INFO] install dotfiles smoke test passed"

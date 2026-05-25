#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
    echo "[ERROR] $*" >&2
    exit 1
}

tmp_dir="$(mktemp -d)"
cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

stub_dir="${tmp_dir}/stubs"
brew_prefix="${tmp_dir}/brew-prefix"
vscode_cli="${tmp_dir}/Visual Studio Code.app/Contents/Resources/app/bin/code"
brew_log="${tmp_dir}/brew.log"
code_log="${tmp_dir}/code.log"
defaults_log="${tmp_dir}/defaults.log"

mkdir -p "$stub_dir" "$(dirname "$vscode_cli")"
: > "$brew_log"
: > "$code_log"
: > "$defaults_log"

ln -s "$(command -v mkdir)" "${stub_dir}/mkdir"
ln -s "$(command -v ln)" "${stub_dir}/ln"

cat > "${stub_dir}/brew" <<'STUB'
#!/bin/sh
if [ "$1" = "--prefix" ]; then
    printf '%s\n' "$BREW_PREFIX"
    exit 0
fi
echo "brew $*" >> "$BREW_LOG"
exit 0
STUB
chmod +x "${stub_dir}/brew"

cat > "$vscode_cli" <<'STUB'
#!/bin/sh
echo "code $*" >> "$CODE_LOG"
exit 0
STUB
chmod +x "$vscode_cli"

cat > "${stub_dir}/defaults" <<'STUB'
#!/bin/sh
echo "defaults $*" >> "$DEFAULTS_LOG"
exit 0
STUB
chmod +x "${stub_dir}/defaults"

run_macos_apps_case() {
    local is_macos="$1"

    (
        export DOTFILES_DIR
        export IS_MACOS="$is_macos"
        export PATH="${stub_dir}:${brew_prefix}/bin"
        export BREW_PREFIX="$brew_prefix"
        export VSCODE_CLI_PATH="$vscode_cli"
        export BREW_LOG="$brew_log"
        export CODE_LOG="$code_log"
        export DEFAULTS_LOG="$defaults_log"

        # shellcheck source=/dev/null
        source "${DOTFILES_DIR}/bootstrap.d/10-macos-apps.sh"
        install_macos_apps
    )
}

run_macos_apps_case false

[ ! -s "$brew_log" ] || fail "non-macOS path should not run brew"
[ ! -s "$code_log" ] || fail "non-macOS path should not install VS Code extensions"
[ ! -s "$defaults_log" ] || fail "non-macOS path should not write Rectangle defaults"

run_macos_apps_case true

grep -F "brew bundle install --file ${DOTFILES_DIR}/Brewfile" "$brew_log" >/dev/null 2>&1 || fail "Brewfile was not installed on macOS"
[ -L "${brew_prefix}/bin/code" ] || fail "VS Code CLI symlink was not created"
[ "$(readlink "${brew_prefix}/bin/code")" = "$vscode_cli" ] || fail "VS Code CLI symlink points at wrong target"
grep -F "code --install-extension " "$code_log" >/dev/null 2>&1 || fail "VS Code extensions were not installed on macOS"
grep -F "defaults write com.knollsoft.Rectangle" "$defaults_log" >/dev/null 2>&1 || fail "Rectangle defaults were not applied on macOS"

echo "[INFO] macOS apps smoke test passed"

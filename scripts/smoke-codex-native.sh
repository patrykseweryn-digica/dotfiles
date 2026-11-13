#!/bin/bash
# Codex follows each platform's best channel at latest:
# the Homebrew cask on macOS and OpenAI's official installer on Linux.
# The network, both installers and mise are simulated.
set -eu
repo="$(cd "$(dirname "$0")/.." && pwd)"
source "${repo}/scripts/host-tools.sh"
task_dir="$(mktemp -d)"
trap 'rm -rf "$task_dir"' EXIT

fail() {
    echo "[ERROR] $*" >&2
    exit 1
}

mkdir -p "$task_dir/stubs" "$task_dir/other" "$task_dir/brew/bin" \
    "$task_dir/brew/Caskroom"
cat >"$task_dir/stubs/uname" <<'STUB'
#!/bin/sh
if [ "$1" = -s ]; then echo "$TEST_OS"; else echo arm64; fi
STUB
cat >"$task_dir/stubs/curl" <<'STUB'
#!/bin/bash
set -eu
case "$*" in
*chatgpt.com/codex/install.sh*)
    [ "${FAIL_DOWNLOAD:-false}" = false ] ||
        { echo 'download interrupted' >&2; exit 22; }
    cat <<'INSTALLER'
set -eu
# The real installer edits a shell profile unless the bin dir is on PATH.
[ "${CODEX_NON_INTERACTIVE:-}" = 1 ] || exit 41
case ":$PATH:" in *":$CODEX_INSTALL_DIR:"*) ;; *) exit 42 ;; esac
echo installer >>"$CODEX_LOG"
mkdir -p "$CODEX_INSTALL_DIR"
printf '#!/bin/sh\necho "codex-cli %s"\n' "$CODEX_TEST_VERSION" \
    >"$CODEX_INSTALL_DIR/codex"
chmod +x "$CODEX_INSTALL_DIR/codex"
INSTALLER
    ;;
*) echo "unexpected URL: $*" >&2; exit 1 ;;
esac
STUB
# Homebrew keeps the cask record in Caskroom and links bin/codex.
cat >"$task_dir/brew/bin/brew" <<'STUB'
#!/bin/bash
set -eu
prefix="$(cd "$(dirname "$0")/.." && pwd)"
echo "brew $*" >>"$CODEX_LOG"
case "$*" in
--prefix) echo "$prefix" ;;
'list --cask codex') [ -d "$prefix/Caskroom/codex" ] ;;
'install --cask codex' | 'upgrade --cask codex')
    [ "${FAIL_DOWNLOAD:-false}" = false ] ||
        { echo 'download interrupted' >&2; exit 1; }
    mkdir -p "$prefix/Caskroom/codex"
    printf '#!/bin/sh\necho "codex-cli %s"\n' "$CODEX_TEST_VERSION" \
        >"$prefix/bin/codex"
    chmod +x "$prefix/bin/codex"
    ;;
*) exit 1 ;;
esac
STUB
cat >"$task_dir/stubs/mise" <<'STUB'
#!/bin/bash
set -eu
printf 'mise %s\n' "$*" >>"$CODEX_LOG"
[ "$*" = 'uninstall --all npm:@openai/codex' ] || exit 1
rm -f "$HOME/.local/share/mise/shims/codex"
STUB
chmod +x "$task_dir/stubs/"* "$task_dir/brew/bin/brew"

export DOTFILES_DIR="$repo" CODEX_LOG="$task_dir/calls"
export CODEX_TEST_VERSION=0.169.0
# shellcheck source=bootstrap.d/05-tools.sh
source "$repo/bootstrap.d/05-tools.sh"

use_home() {
    HOME="$task_dir/$1"
    BIN_DIR="$HOME/.local/bin"
    mkdir -p "$HOME"
    export HOME BIN_DIR
    : >"$CODEX_LOG"
}
base_path="$task_dir/stubs:/usr/bin:/bin"
brew_path="$task_dir/brew/bin"
export TEST_OS=Linux

use_home fresh
PATH="$base_path" install_codex >"$task_dir/output" 2>&1 ||
    { cat "$task_dir/output" >&2; fail "fresh Codex install failed"; }
[ "$("$BIN_DIR/codex" --version)" = 'codex-cli 0.169.0' ] ||
    fail "Codex was not installed into ~/.local/bin"
grep -Fx installer "$CODEX_LOG" >/dev/null || fail "official installer did not run"
echo "[INFO] Linux: fresh install uses the official installer"

cp "$BIN_DIR/codex" "$task_dir/before"
: >"$CODEX_LOG"
if CODEX_TEST_VERSION=0.170.0 FAIL_DOWNLOAD=true PATH="$base_path" \
    install_codex >"$task_dir/output" 2>&1; then
    fail "failed installer download passed"
fi
cmp -s "$task_dir/before" "$BIN_DIR/codex" ||
    fail "failed download changed the installed Codex"
[ ! -s "$CODEX_LOG" ] || fail "installer ran after a failed download"
CODEX_TEST_VERSION=0.170.0 PATH="$BIN_DIR:$base_path" install_codex \
    >"$task_dir/output" 2>&1 || fail "Codex update failed"
[ "$("$BIN_DIR/codex" --version)" = 'codex-cli 0.170.0' ] ||
    fail "Codex update was not applied"
echo "[INFO] Linux: a failed download keeps Codex; a new release replaces it"

# Another Codex on PATH makes the installer edit shell profiles.
use_home foreign
printf '#!/bin/sh\necho "codex-cli 0.1.0"\n' >"$task_dir/other/codex"
chmod +x "$task_dir/other/codex"
if PATH="$task_dir/other:$base_path" install_codex \
    >"$task_dir/output" 2>&1; then
    fail "install passed with another Codex on PATH"
fi
grep -F "Codex: another install is on PATH: $task_dir/other/codex" \
    "$task_dir/output" >/dev/null || fail "foreign Codex was not named"
[ ! -s "$CODEX_LOG" ] || fail "installer ran beside a foreign Codex"
[ ! -e "$BIN_DIR/codex" ] || fail "foreign Codex install was changed"
echo "[INFO] Linux: a foreign Codex stops the install before any change"

# Dotfiles installed Codex with mise npm before; it removes that install.
use_home migrate
shims="$HOME/.local/share/mise/shims"
mkdir -p "$shims"
printf '#!/bin/sh\necho "codex-cli 0.1.0"\n' >"$shims/codex"
chmod +x "$shims/codex"
PATH="$shims:$base_path" install_codex >"$task_dir/output" 2>&1 ||
    { cat "$task_dir/output" >&2; fail "mise Codex migration failed"; }
grep -Fx 'mise uninstall --all npm:@openai/codex' "$CODEX_LOG" >/dev/null ||
    fail "mise npm Codex was not uninstalled"
[ ! -e "$shims/codex" ] || fail "mise Codex shim remained"
[ "$("$BIN_DIR/codex" --version)" = 'codex-cli 0.169.0' ] ||
    fail "Codex was not installed after migration"
echo "[INFO] Linux: a former mise npm Codex is replaced"

# Doctor requires the Codex that the platform channel manages.
printf 'DOTFILES_GROUPS=core,agents,desktop\n' >"$task_dir/all-groups.env"
manifest="$task_dir/tools.json"
printf '%s\n' '{"tools":[{"name":"Codex","command":"codex",' \
    '"installer":"codex-native","channel":"latest","group":"agents"}]}' \
    >"$manifest"
codex_plan() {
    env AGENT_TOOL_VERSIONS="$manifest" PATH="$1" \
        DOTFILES_ENV_FILE="$task_dir/all-groups.env" \
        bash "$repo/scripts/agent-tools.sh" plan 2>&1 |
        awk -F '\t' '$2 == "tools" { print $1 "\t" $4 }'
}
[ "$(codex_plan "$BIN_DIR:$base_path")" = "$(printf 'PASS\tCodex is available')" ] ||
    fail "managed Codex did not pass the plan"
expected_row="$(printf 'FAIL\tCodex resolves to %s; expected %s' \
    "$task_dir/other/codex" "$BIN_DIR/codex")"
[ "$(codex_plan "$task_dir/other:$BIN_DIR:$base_path")" = "$expected_row" ] ||
    fail "plan accepted a foreign Codex first on PATH"
echo "[INFO] Linux: the plan requires the official installer's Codex"

export TEST_OS=Darwin
use_home mac
PATH="$brew_path:$base_path" install_codex >"$task_dir/output" 2>&1 ||
    { cat "$task_dir/output" >&2; fail "macOS cask install failed"; }
grep -Fx 'brew install --cask codex' "$CODEX_LOG" >/dev/null ||
    fail "macOS did not install the Codex cask"
! grep -Fx installer "$CODEX_LOG" >/dev/null ||
    fail "macOS ran OpenAI's installer instead of the cask"
[ ! -e "$BIN_DIR/codex" ] || fail "macOS wrote Codex into ~/.local/bin"
: >"$CODEX_LOG"
CODEX_TEST_VERSION=0.170.0 PATH="$brew_path:$base_path" install_codex \
    >"$task_dir/output" 2>&1 || fail "macOS cask update failed"
grep -Fx 'brew upgrade --cask codex' "$CODEX_LOG" >/dev/null ||
    fail "macOS did not upgrade the Codex cask to latest"
[ "$("$brew_path/codex" --version)" = 'codex-cli 0.170.0' ] ||
    fail "macOS cask update was not applied"
[ "$(codex_plan "$brew_path:$base_path")" = \
    "$(printf 'PASS\tCodex is available')" ] ||
    fail "cask Codex did not pass the macOS plan"
expected_row="$(printf 'FAIL\tCodex resolves to %s; expected %s' \
    "$task_dir/other/codex" "$brew_path/codex")"
[ "$(codex_plan "$task_dir/other:$brew_path:$base_path")" = \
    "$expected_row" ] || fail "macOS plan accepted a foreign Codex"
if PATH="$base_path" install_codex >"$task_dir/output" 2>&1; then
    fail "macOS install passed without Homebrew"
fi
grep -F 'Codex: Homebrew is required on macOS' "$task_dir/output" \
    >/dev/null || fail "missing Homebrew was not explained"
echo "[INFO] Codex smoke test passed (installers simulated)"

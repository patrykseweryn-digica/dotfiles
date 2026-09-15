#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HERDR_BIN="${HERDR_BIN:-$(command -v herdr || true)}"
[ -x "$HERDR_BIN" ] || {
    echo '[ERROR] Herdr required; install it or set HERDR_BIN' >&2
    exit 1
}
export HERDR_BIN

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

(
    export HOME="${tmp_dir}/another user home"
    BIN_DIR="${HOME}/local bin"
    mkdir -p "$HOME/.claude"
    jq '.localPreference = "preserve me"' \
        "$DOTFILES_DIR/config/claude/settings.json" >"$tmp_dir/settings-target.json"
    cp "$tmp_dir/settings-target.json" "$tmp_dir/settings-target.before.json"
    ln -s "$tmp_dir/settings-target.json" "$HOME/.claude/settings.json"
    # Exercise the installed integration, replacing only its network download.
    curl() {
        [ "$*" = '-fsSL https://herdr.dev/install.sh' ] || return 1
        printf 'download\n' >>"$tmp_dir/downloads.log"
        cat <<'INSTALLER'
mkdir -p "$HERDR_INSTALL_DIR"
ln -sf "$HERDR_BIN" "$HERDR_INSTALL_DIR/herdr"
INSTALLER
    }
    # shellcheck source=bootstrap.d/05-tools.sh
    source "$DOTFILES_DIR/bootstrap.d/05-tools.sh"
    install_herdr
    cmp "$tmp_dir/settings-target.before.json" "$tmp_dir/settings-target.json"
    test ! -L "$HOME/.claude/settings.json"
    jq -e '.localPreference == "preserve me"' "$HOME/.claude/settings.json" >/dev/null
    hook="$HOME/.claude/hooks/herdr-agent-state.sh"
    test -s "$hook"
    grep -F 'HERDR_INTEGRATION_VERSION=' "$hook" >/dev/null
    cp "$HOME/.claude/settings.json" "$tmp_dir/settings.before.json"
    cp "$hook" "$tmp_dir/hook.before.sh"
    install_herdr
    cmp "$tmp_dir/settings.before.json" "$HOME/.claude/settings.json"
    cmp "$tmp_dir/hook.before.sh" "$hook"
    jq -e '[.hooks.SessionStart[].hooks[].command] |
        map(select(. == "gh-axi" or . == "chrome-devtools-axi")) |
        sort == ["chrome-devtools-axi", "gh-axi"]' \
        "$HOME/.claude/settings.json" >/dev/null

    # Record which script and argument the actual configured command invokes.
    cat >"$hook" <<'HOOK'
#!/bin/bash
printf '%s\n' "$0" "$@" >"$HOME/hook-called"
HOOK
    command=$(jq -r '.hooks.SessionStart[].hooks[].command |
        select(contains("herdr-agent-state.sh"))' "$HOME/.claude/settings.json")
    bash -c "$command" </dev/null
    printf '%s\nsession\n' "$hook" >"$tmp_dir/expected-call"
    cmp "$tmp_dir/expected-call" "$HOME/hook-called"
    rm "$HOME/hook-called"
    command=$(jq -r '.hooks.SessionStart[].hooks[].command |
        select(contains("herdr-agent-state.sh"))' "$DOTFILES_DIR/config/claude/settings.json")
    bash -c "$command" </dev/null
    cmp "$tmp_dir/expected-call" "$HOME/hook-called"

    # A dangling settings link must fail before any external installer runs.
    rm "$HOME/.claude/settings.json"
    ln -s "$tmp_dir/missing-settings.json" "$HOME/.claude/settings.json"
    cp "$tmp_dir/downloads.log" "$tmp_dir/downloads.before.log"
    if install_herdr >"$tmp_dir/broken.log" 2>&1; then
        echo '[ERROR] Herdr accepted a broken settings symlink' >&2
        exit 1
    fi
    grep -F 'Broken or non-file Claude settings symlink' "$tmp_dir/broken.log" >/dev/null
    test -L "$HOME/.claude/settings.json"
    test ! -e "$tmp_dir/missing-settings.json"
    cmp "$tmp_dir/downloads.before.log" "$tmp_dir/downloads.log"
)

echo '[INFO] Herdr hook smoke test passed'

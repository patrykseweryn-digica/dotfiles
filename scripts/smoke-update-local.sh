#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JUST_BIN="$(command -v just)"

fail() {
    echo "[ERROR] $*" >&2
    exit 1
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
home_dir="${tmp_dir}/home"
state_dir="${home_dir}/.state"
action_log="${tmp_dir}/actions.log"
mkdir -p "$state_dir"
: >"$action_log"

cat >"${tmp_dir}/state-plan.sh" <<'STUB'
#!/bin/bash
set -eu
[ "$1" = all ]
state="$HOME/.state"
row() { printf '%s\t%s\t%s\t%s\n' "$@"; }
[ -f "$state/settings" ] &&
    row PASS settings:codex none "Codex settings match" ||
    row UPDATE settings:codex update "Codex settings drift"
row PASS settings:claude none "Claude settings match"
row PASS settings:opencode none "OpenCode settings match"
row PASS settings:pi none "Pi settings match"
if [ -f "$state/export" ]; then
    row EXPORT mcp export "MCP has a local addition"
elif [ -f "$state/mcp" ]; then
    row PASS mcp none "MCP matches"
else
    row UPDATE mcp update "MCP drift"
fi
[ -f "$state/links" ] && row PASS links none "Links match" ||
    row FAIL links update "Links missing"
[ -f "$state/hooks" ] && row PASS hooks none "Hooks match" ||
    row UPDATE hooks update "Hooks drift"
row PASS tools none "Tools match"
row PASS node none "Node matches"
row PASS platform none "Platform supported"
STUB

cat >"${tmp_dir}/sync-agents.sh" <<'STUB'
#!/bin/bash
set -eu
printf '%s\n' "$*" >>"$ACTION_LOG"
case "$1" in
settings-install)
    [ "$2" = codex ]
    touch "$HOME/.state/settings"
    ;;
push-mcp)
    touch "$HOME/.state/mcp"
    ;;
*) exit 1 ;;
esac
STUB

cat >"${tmp_dir}/install.sh" <<'STUB'
#!/bin/bash
update_managed_links() {
    printf '%s\n' links >>"$ACTION_LOG"
    touch "$HOME/.state/links"
}
configure_herdr_hook() {
    printf '%s\n' hooks >>"$ACTION_LOG"
    touch "$HOME/.state/hooks"
}
STUB
chmod +x "${tmp_dir}/state-plan.sh" "${tmp_dir}/sync-agents.sh"
touch "${state_dir}/export"

run_update() {
    HOME="$home_dir" ACTION_LOG="$action_log" \
        STATE_PLAN="${tmp_dir}/state-plan.sh" \
        SYNC_AGENTS="${tmp_dir}/sync-agents.sh" \
        INSTALL_SCRIPT="${tmp_dir}/install.sh" \
        "$JUST_BIN" --justfile "${DOTFILES_DIR}/justfile" update \
        >"${tmp_dir}/update.log" 2>&1
}

if run_update; then
    fail "update accepted an unexported local addition"
fi
for marker in settings links hooks; do
    [ -f "${state_dir}/${marker}" ] ||
        fail "independent category was not applied: $marker"
done
[ ! -f "${state_dir}/mcp" ] || fail "EXPORT category was changed"
grep -Fx 'settings-install codex' "$action_log" >/dev/null ||
    fail "settings adapter was not used"
grep -Fx '[BLOCKED] mcp: export local additions first' \
    "${tmp_dir}/update.log" >/dev/null || fail "EXPORT was not reported"
grep -F '[SUMMARY]' "${tmp_dir}/update.log" >/dev/null ||
    fail "update omitted its summary"

rm "${state_dir}/export"
: >"$action_log"
run_update || fail "compatible update failed"
[ -f "${state_dir}/mcp" ] || fail "MCP adapter was not applied"
grep -Fx 'push-mcp' "$action_log" >/dev/null ||
    fail "MCP adapter was not used"

find "$home_dir" -type f -exec cksum {} \; | sort \
    >"${tmp_dir}/home.before"
git -C "$DOTFILES_DIR" diff --no-ext-diff HEAD >"${tmp_dir}/repo.before"
: >"$action_log"
run_update || fail "idempotent update failed"
[ ! -s "$action_log" ] || fail "second update repeated apply actions"
find "$home_dir" -type f -exec cksum {} \; | sort \
    >"${tmp_dir}/home.after"
git -C "$DOTFILES_DIR" diff --no-ext-diff HEAD >"${tmp_dir}/repo.after"
cmp "${tmp_dir}/home.before" "${tmp_dir}/home.after" ||
    fail "second update changed HOME"
cmp "${tmp_dir}/repo.before" "${tmp_dir}/repo.after" ||
    fail "second update changed checkout"
grep -F '[FINAL] [PASS] mcp:' "${tmp_dir}/update.log" >/dev/null ||
    fail "update omitted its final check"

echo "[INFO] local update smoke test passed"

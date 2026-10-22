#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JUST_BIN="$(command -v just)"
JUSTFILE="${DOTFILES_DIR}/justfile"
UPDATE_SCRIPT="${DOTFILES_DIR}/scripts/update-local.sh"

# Hook-local Git state must not affect fixture repositories.
# shellcheck disable=SC2046
unset $(git -C "$DOTFILES_DIR" rev-parse --local-env-vars)

fail() {
    echo "[ERROR] $*" >&2
    exit 1
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
home_dir="${tmp_dir}/home"
state_dir="${home_dir}/.state"
action_log="${tmp_dir}/actions.log"
mutation_log="${tmp_dir}/mutations.log"
remote_dir="${tmp_dir}/remote.git"
sync_repo="${tmp_dir}/sync-repo"
publisher_repo="${tmp_dir}/publisher"
mkdir -p "$state_dir"
: >"$action_log"
: >"$mutation_log"

git init --bare --quiet --initial-branch=master "$remote_dir"
git init --quiet --initial-branch=master "$sync_repo"
git -C "$sync_repo" config user.name "Smoke Test"
git -C "$sync_repo" config user.email "smoke@example.com"
touch "${sync_repo}/base"
git -C "$sync_repo" add base
git -C "$sync_repo" commit --quiet -m "test: initialize fixture"
git -C "$sync_repo" remote add origin "$remote_dir"
git -C "$sync_repo" push --quiet --set-upstream origin master

git clone --quiet "$remote_dir" "$publisher_repo"
git -C "$publisher_repo" config user.name "Smoke Test"
git -C "$publisher_repo" config user.email "smoke@example.com"
touch "${publisher_repo}/upstream"
git -C "$publisher_repo" add upstream
git -C "$publisher_repo" commit --quiet -m "test: add upstream change"
git -C "$publisher_repo" push --quiet

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
if [ -f "$state/export-skills" ]; then
    row EXPORT skills export "Skills have a local addition"
elif [ -f "$state/skills" ]; then
    row PASS skills none "Skills match"
else
    row UPDATE skills update "Skills drift"
fi
if [ -f "$state/export-plugins" ]; then
    row EXPORT plugins export "Plugins have a local addition"
elif [ -f "$state/plugins" ]; then
    row PASS plugins none "Plugins match"
else
    row UPDATE plugins update "Plugins drift"
fi
command -v smoke-npm-tool >/dev/null &&
    row PASS tools none "Tools match" ||
    row FAIL tools update "smoke-npm-tool is missing"
latest=""
for candidate in "$HOME"/.nvm/versions/node/v*; do
    latest="${candidate##*/}"
done
[ "$(node --version)" = "$latest" ] &&
    row PASS node none "Node matches" ||
    row UPDATE node update "Active Node differs from latest installed"
row PASS platform none "Platform supported"
STUB

# The caller's shell starts with an older Node, as on a long-lived session.
nvm_dir="${home_dir}/.nvm"
mkdir -p "${nvm_dir}/versions/node/v24.0.0/bin"
printf '#!/bin/sh\necho v24.0.0\n' >"${nvm_dir}/versions/node/v24.0.0/bin/node"
chmod +x "${nvm_dir}/versions/node/v24.0.0/bin/node"
cat >"${nvm_dir}/nvm.sh" <<'STUB'
nvm() {
    local latest="" candidate
    for candidate in "$NVM_DIR"/versions/node/v*; do
        latest="${candidate##*/}"
    done
    case "$1" in
    version) echo "$latest" ;;
    use) export PATH="$NVM_DIR/versions/node/$latest/bin:$PATH" ;;
    *) return 90 ;;
    esac
}
STUB

cat >"${tmp_dir}/sync-agents.sh" <<'STUB'
#!/bin/bash
set -eu
printf '%s\n' "$*" >>"$ACTION_LOG"
case "$1" in
settings-install)
    [ "$2" = codex ]
    touch "$HOME/.state/settings"
    echo settings >>"$MUTATION_LOG"
    ;;
push-mcp)
    touch "$HOME/.state/mcp"
    echo mcp >>"$MUTATION_LOG"
    ;;
skills-update)
    if [ ! -f "$HOME/.state/skills" ]; then
        touch "$HOME/.state/skills"
        echo skills >>"$MUTATION_LOG"
    fi
    ;;
push-plugins)
    touch "$HOME/.state/plugins"
    echo plugin-membership >>"$MUTATION_LOG"
    ;;
plugins-update)
    [ -f "$HOME/.state/plugins" ]
    ;;
*) exit 1 ;;
esac
STUB

cat >"${tmp_dir}/install.sh" <<'STUB'
#!/bin/bash
ensure_install_dirs() { mkdir -p "$HOME/.local/bin"; }
install_declared_core_tools() {
    if [ ! -f "$HOME/.state/core-tools" ]; then
        touch "$HOME/.state/core-tools"
        echo core-tools >>"$MUTATION_LOG"
    fi
}
update_declared_latest_core_tools() {
    printf '%s\n' latest-core-tools >>"$ACTION_LOG"
}
update_managed_links() {
    printf '%s\n' links >>"$ACTION_LOG"
    touch "$HOME/.state/links"
    echo links >>"$MUTATION_LOG"
}
configure_herdr_hook() {
    printf '%s\n' hooks >>"$ACTION_LOG"
    touch "$HOME/.state/hooks"
    echo hooks >>"$MUTATION_LOG"
}
STUB
printf 'source %q\n' "${DOTFILES_DIR}/bootstrap.d/07-node.sh" \
    >>"${tmp_dir}/install.sh"
# The tool refresh installs a newer Node and an npm CLI in a child process.
cat >"${tmp_dir}/agent-tools.sh" <<'STUB'
#!/bin/bash
set -eu
printf 'agent-tools %s\n' "$*" >>"$ACTION_LOG"
[ "$1" = update ]
[ "${FAIL_AGENT_UPDATE:-false}" = false ] || exit 1
if [ ! -f "$HOME/.state/agent-tools" ]; then
    node_bin="$HOME/.nvm/versions/node/v26.0.0/bin"
    mkdir -p "$node_bin"
    printf '#!/bin/sh\necho v26.0.0\n' >"$node_bin/node"
    printf '#!/bin/sh\n' >"$node_bin/smoke-npm-tool"
    chmod +x "$node_bin/node" "$node_bin/smoke-npm-tool"
    touch "$HOME/.state/agent-tools"
    echo agent-tools >>"$MUTATION_LOG"
fi
STUB
chmod +x "${tmp_dir}/state-plan.sh" "${tmp_dir}/sync-agents.sh" \
    "${tmp_dir}/agent-tools.sh"
touch "${state_dir}/export" "${state_dir}/export-skills" \
    "${state_dir}/export-plugins"

run_sync() {
    HOME="$home_dir" ACTION_LOG="$action_log" MUTATION_LOG="$mutation_log" \
        PATH="${nvm_dir}/versions/node/v24.0.0/bin:$PATH" \
        DOTFILES_DIR="$sync_repo" \
        UPDATE_SCRIPT="$UPDATE_SCRIPT" \
        FAIL_AGENT_UPDATE="${1:-false}" \
        STATE_PLAN="${tmp_dir}/state-plan.sh" \
        SYNC_AGENTS="${tmp_dir}/sync-agents.sh" \
        AGENT_TOOLS="${tmp_dir}/agent-tools.sh" \
        INSTALL_SCRIPT="${tmp_dir}/install.sh" \
        "$JUST_BIN" --justfile "$JUSTFILE" sync \
        >"${tmp_dir}/update.log" 2>&1
}

touch "${sync_repo}/dirty"
if run_sync; then
    fail "sync accepted a dirty checkout"
fi
[ ! -e "${sync_repo}/upstream" ] || fail "dirty sync pulled changes"
[ ! -s "$action_log" ] || fail "dirty sync started the update"
grep -Fx '[RESULT] FAIL' "${tmp_dir}/update.log" >/dev/null ||
    fail "dirty sync omitted its result"
rm "${sync_repo}/dirty"

if run_sync true; then
    fail "sync accepted a failed upstream update"
fi
[ -e "${sync_repo}/upstream" ] || fail "sync did not pull upstream changes"
grep -Fx '[RESULT] FAIL' "${tmp_dir}/update.log" >/dev/null ||
    fail "failed sync omitted its result"
for marker in settings links hooks; do
    [ -f "${state_dir}/${marker}" ] ||
        fail "independent category was not applied: $marker"
done
[ ! -f "${state_dir}/mcp" ] || fail "EXPORT category was changed"
grep -Fx 'settings-install codex' "$action_log" >/dev/null ||
    fail "settings adapter was not used"
for action in latest-core-tools 'agent-tools update'; do
    grep -Fx "$action" "$action_log" >/dev/null ||
        fail "independent upstream phase was not attempted: $action"
done
for action in skills-update push-plugins plugins-update; do
    if grep -Fx "$action" "$action_log" >/dev/null; then
        fail "EXPORT category was mutated: $action"
    fi
done
grep -Fx '[BLOCKED] mcp: export local additions first' \
    "${tmp_dir}/update.log" >/dev/null || fail "EXPORT was not reported"
grep -Fx '[BLOCKED] skills upstream refresh: export local additions first' \
    "${tmp_dir}/update.log" >/dev/null || fail "skill EXPORT was not reported"
grep -Fx '[BLOCKED] plugins upstream refresh: export local additions first' \
    "${tmp_dir}/update.log" >/dev/null || fail "plugin EXPORT was not reported"
grep -F '[SUMMARY]' "${tmp_dir}/update.log" >/dev/null ||
    fail "sync omitted its summary"
grep -Fx '[FAILED] phases: Node and agent tools;' \
    "${tmp_dir}/update.log" >/dev/null ||
    fail "sync summary omitted the failed phase"

: >"$action_log"
: >"$mutation_log"
if run_sync; then
    fail "sync accepted an unexported local addition"
fi
grep -Fx '[RESULT] EXPORT' "${tmp_dir}/update.log" >/dev/null ||
    fail "sync omitted its export result"

rm "${state_dir}/export" "${state_dir}/export-skills" \
    "${state_dir}/export-plugins"
: >"$action_log"
: >"$mutation_log"
run_sync || fail "compatible sync failed"
[ -f "${state_dir}/mcp" ] || fail "MCP adapter was not applied"
grep -Fx 'push-mcp' "$action_log" >/dev/null ||
    fail "MCP adapter was not used"
grep -Fx '[RESULT] PASS' "${tmp_dir}/update.log" >/dev/null ||
    fail "compatible sync omitted its result"
for category in node tools; do
    grep -F "[FINAL] [PASS] ${category}:" "${tmp_dir}/update.log" >/dev/null ||
        fail "final check missed the refreshed Node: $category"
done

find "$home_dir" -type f -exec cksum {} \; | sort \
    >"${tmp_dir}/home.before"
git -C "$sync_repo" diff --no-ext-diff HEAD >"${tmp_dir}/repo.before"
: >"$action_log"
: >"$mutation_log"
run_sync || fail "idempotent sync failed"
[ ! -s "$mutation_log" ] || fail "second sync repeated mutations"
for action in latest-core-tools 'agent-tools update' skills-update \
    plugins-update; do
    grep -Fx "$action" "$action_log" >/dev/null ||
        fail "second sync omitted upstream query: $action"
done
if grep -Fx push-plugins "$action_log" >/dev/null; then
    fail "second sync repeated plugin membership install"
fi
find "$home_dir" -type f -exec cksum {} \; | sort \
    >"${tmp_dir}/home.after"
git -C "$sync_repo" diff --no-ext-diff HEAD >"${tmp_dir}/repo.after"
cmp "${tmp_dir}/home.before" "${tmp_dir}/home.after" ||
    fail "second sync changed HOME"
cmp "${tmp_dir}/repo.before" "${tmp_dir}/repo.after" ||
    fail "second sync changed checkout"
grep -F '[FINAL] [PASS] mcp:' "${tmp_dir}/update.log" >/dev/null ||
    fail "sync omitted its final check"
grep -Fx '[RESULT] PASS' "${tmp_dir}/update.log" >/dev/null ||
    fail "idempotent sync omitted its result"

echo "[INFO] local sync smoke test passed"

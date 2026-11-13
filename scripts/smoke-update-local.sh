#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${DOTFILES_DIR}/scripts/host-tools.sh"
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
# The machine group setting must not change fixture results.
export DOTFILES_ENV_FILE="${tmp_dir}/all-groups.env"
printf 'DOTFILES_GROUPS=core,agents,desktop\n' >"$DOTFILES_ENV_FILE"
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
[ -f "$state/shell" ] && row PASS shell none "Login shells find mise tools" ||
    row UPDATE shell update "Login shells do not find mise tools"
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
row SKIP system-tools none "xclip requires sudo on linux-arm64"
selected=$(cat "$HOME/.local/share/mise/current-node")
[ "$(node --version)" = "v$selected" ] &&
    row PASS node none "Node matches" ||
    row UPDATE node update "Active Node differs from LTS policy"
row PASS platform none "Platform supported"
STUB

# The caller's shell starts with an older Node, as on a long-lived session.
mise_root="${home_dir}/.local/share/mise"
old_node_bin="${mise_root}/installs/node/24.0.0/bin"
mkdir -p "$old_node_bin" "${home_dir}/.local/bin"
printf '#!/bin/sh\necho v24.0.0\n' >"${old_node_bin}/node"
chmod +x "${old_node_bin}/node"
printf '24.0.0\n' >"${mise_root}/current-node"
cat >"${home_dir}/.local/bin/mise" <<'STUB'
#!/bin/bash
set -eu
root="$HOME/.local/share/mise"
version=$(cat "$root/current-node")
case "$1" in
which) printf '%s/installs/node/%s/bin/node\n' "$root" "$version" ;;
activate)
    printf 'export PATH="%s/installs/node/%s/bin:$PATH"\n' "$root" "$version"
    ;;
*) exit 90 ;;
esac
STUB
chmod +x "${home_dir}/.local/bin/mise"

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
    if [ "${HANG_PLUGIN_MEMBERSHIP:-false}" = true ]; then
        # shellcheck source=/dev/null
        source "$OPERATION_LIB"
        operation_run "claude plugin smoke@market" "install plugin" install -- \
            bash -c 'echo $$ >"$1/plugin.pid"
                     sleep 300 &
                     echo $! >"$1/plugin-child.pid"
                     echo "Cloning marketplace" >&2
                     wait' hang "$SCENARIO_DIR"
        exit
    fi
    touch "$HOME/.state/plugins"
    echo plugin-membership >>"$MUTATION_LOG"
    ;;
plugins-update)
    :
    ;;
pi-packages-update)
    printf '%s\n' pi-packages-update >>"$ACTION_LOG"
    ;;
*) exit 1 ;;
esac
STUB

cat >"${tmp_dir}/install.sh" <<'STUB'
#!/bin/bash
ensure_install_dirs() { mkdir -p "$HOME/.local/bin"; }
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
configure_mise_shims_profile() {
    printf '%s\n' shell >>"$ACTION_LOG"
    touch "$HOME/.state/shell"
    echo shell >>"$MUTATION_LOG"
}
STUB
printf 'source %q\n' "${DOTFILES_DIR}/bootstrap.d/07-node.sh" \
    >>"${tmp_dir}/install.sh"
cat >"${tmp_dir}/core-tools.sh" <<'STUB'
#!/bin/bash
set -eu
printf 'core-tools %s\n' "$*" >>"$ACTION_LOG"
[ "$1" = update ]
if [ ! -f "$HOME/.state/core-tools" ]; then
    touch "$HOME/.state/core-tools"
    echo core-tools >>"$MUTATION_LOG"
fi
STUB
# The tool refresh installs a newer Node and an npm CLI in a child process.
cat >"${tmp_dir}/agent-tools.sh" <<'STUB'
#!/bin/bash
set -eu
printf 'agent-tools %s\n' "$*" >>"$ACTION_LOG"
[ "$1" = update ]
[ "${FAIL_AGENT_UPDATE:-false}" = false ] || exit 1
if [ ! -f "$HOME/.state/agent-tools" ]; then
    node_bin="$HOME/.local/share/mise/installs/node/26.0.0/bin"
    mkdir -p "$node_bin"
    printf '#!/bin/sh\necho v26.0.0\n' >"$node_bin/node"
    printf '#!/bin/sh\n' >"$node_bin/smoke-npm-tool"
    chmod +x "$node_bin/node" "$node_bin/smoke-npm-tool"
    printf '26.0.0\n' >"$HOME/.local/share/mise/current-node"
    touch "$HOME/.state/agent-tools"
    echo agent-tools >>"$MUTATION_LOG"
fi
STUB
chmod +x "${tmp_dir}/state-plan.sh" "${tmp_dir}/sync-agents.sh" \
    "${tmp_dir}/agent-tools.sh" "${tmp_dir}/core-tools.sh"
touch "${state_dir}/export" "${state_dir}/export-skills" \
    "${state_dir}/export-plugins"

export OPERATION_LIB="${DOTFILES_DIR}/scripts/operation.sh"
export SCENARIO_DIR="$tmp_dir"
export HANG_PLUGIN_MEMBERSHIP=false
operation_log="${home_dir}/.local/state/dotfiles/sync.log"

assert_stopped() {
    local pid_file="$1" pid
    [ -s "$pid_file" ] || fail "fixture did not record $pid_file"
    pid="$(cat "$pid_file")"
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        kill -0 "$pid" 2>/dev/null || return 0
        sleep 0.2
    done
    kill -9 "$pid" 2>/dev/null || true
    fail "process $pid survived the time limit"
}

expect_log() {
    grep -F -- "$1" "${tmp_dir}/update.log" >/dev/null || fail "$2"
}

run_sync() {
    HOME="$home_dir" ACTION_LOG="$action_log" MUTATION_LOG="$mutation_log" \
        PATH="${old_node_bin}:$PATH" \
        DOTFILES_DIR="$sync_repo" \
        UPDATE_SCRIPT="$UPDATE_SCRIPT" \
        FAIL_AGENT_UPDATE="${1:-false}" \
        STATE_PLAN="${tmp_dir}/state-plan.sh" \
        SYNC_AGENTS="${tmp_dir}/sync-agents.sh" \
        AGENT_TOOLS="${tmp_dir}/agent-tools.sh" \
        CORE_TOOLS="${tmp_dir}/core-tools.sh" \
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

# A stalled repository fetch stops sync before any environment change.
origin_url="$(git -C "$sync_repo" remote get-url origin)"
stall="sh -c echo% \$\$% >${tmp_dir}/fetch.pid;% sleep% 300% &% echo% \$!% >${tmp_dir}/fetch-child.pid;% wait"
git -C "$sync_repo" remote set-url origin "ext::${stall}"
if GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=protocol.ext.allow \
    GIT_CONFIG_VALUE_0=always DOTFILES_OPERATION_TIMEOUT=1 run_sync; then
    fail "sync accepted a stalled repository fetch"
fi
git -C "$sync_repo" remote set-url origin "$origin_url"
assert_stopped "${tmp_dir}/fetch.pid"
assert_stopped "${tmp_dir}/fetch-child.pid"
[ ! -e "${sync_repo}/upstream" ] || fail "stalled fetch changed the checkout"
[ ! -s "$action_log" ] || fail "stalled fetch started the update"
expect_log '[ERROR] dotfiles repo: fetch upstream failed' \
    "stalled fetch omitted its element and operation"
expect_log 'cause: timed out after 1 s' "stalled fetch omitted its cause"
grep -Fx '[RESULT] FAIL' "${tmp_dir}/update.log" >/dev/null ||
    fail "stalled fetch omitted its result"

# A local addition stops sync before any environment change.
if run_sync; then
    fail "sync accepted an unexported local addition"
fi
[ -e "${sync_repo}/upstream" ] || fail "sync did not pull upstream changes"
[ ! -s "$action_log" ] || fail "EXPORT sync started changes"
[ ! -s "$mutation_log" ] || fail "EXPORT sync changed the environment"
expect_log '[BLOCKED] mcp: MCP has a local addition' \
    "EXPORT omitted the MCP addition"
expect_log '[BLOCKED] skills: Skills have a local addition' \
    "EXPORT omitted the skill addition"
expect_log 'Run: just export' "EXPORT omitted the next step"
grep -Fx '[RESULT] EXPORT' "${tmp_dir}/update.log" >/dev/null ||
    fail "sync omitted its export result"
rm "${state_dir}/export" "${state_dir}/export-skills" \
    "${state_dir}/export-plugins"

# A stalled operation and a failed phase do not stop independent phases.
: >"$action_log"
: >"$mutation_log"
if HANG_PLUGIN_MEMBERSHIP=true DOTFILES_OPERATION_TIMEOUT=1 run_sync true; then
    fail "sync accepted failed upstream updates"
fi
assert_stopped "${tmp_dir}/plugin.pid"
assert_stopped "${tmp_dir}/plugin-child.pid"
for marker in settings mcp links hooks shell skills; do
    [ -f "${state_dir}/${marker}" ] ||
        fail "independent category was not applied: $marker"
done
for action in 'core-tools update' 'agent-tools update' pi-packages-update \
    skills-update push-plugins; do
    grep -Fx "$action" "$action_log" >/dev/null ||
        fail "independent phase was not attempted: $action"
done
if grep -Fx plugins-update "$action_log" >/dev/null; then
    fail "dependent plugin versions ran after failed membership"
fi
expect_log '[NOT RUN] plugin versions: requires plugin membership, which failed' \
    "dependent phase omitted its reason"
expect_log '[ERROR] claude plugin smoke@market: install plugin failed' \
    "stalled operation omitted its element and operation"
expect_log 'Cloning marketplace' "stalled operation omitted tool output"
expect_log '[PROBLEM] claude plugin smoke@market: install plugin - timed out after 1 s' \
    "summary omitted the stalled operation"
expect_log '[PROBLEM] Node and agent tools: refresh - unknown cause (exit 1)' \
    "summary omitted the unknown phase failure"
expect_log "[LOG] ${operation_log}" "summary omitted the log"
grep -Fx '[FAILED] phases: Node and agent tools; plugin membership;' \
    "${tmp_dir}/update.log" >/dev/null ||
    fail "sync summary omitted the failed phases"
grep -Fx '[RESULT] FAIL' "${tmp_dir}/update.log" >/dev/null ||
    fail "failed sync omitted its result"
grep -F 'Cloning marketplace' "$operation_log" >/dev/null ||
    fail "operation log omitted tool output"

: >"$action_log"
: >"$mutation_log"
run_sync || fail "compatible sync failed"
[ -f "${state_dir}/mcp" ] || fail "MCP adapter was not applied"
if grep -Fx 'push-mcp' "$action_log" >/dev/null; then
    fail "compatible sync repeated the MCP apply"
fi
grep -Fx '[RESULT] PASS' "${tmp_dir}/update.log" >/dev/null ||
    fail "compatible sync omitted its result"
for phase in PLAN FINAL; do
    grep -Fx "[${phase}] [SKIP] system-tools: xclip requires sudo on linux-arm64" \
        "${tmp_dir}/update.log" >/dev/null ||
        fail "sync omitted SKIP reason from $phase"
done
for category in node tools; do
    grep -F "[FINAL] [PASS] ${category}:" "${tmp_dir}/update.log" >/dev/null ||
        fail "final check missed the refreshed Node: $category"
done

find "$home_dir" -path "${home_dir}/.local/state" -prune -o \
    -type f -exec cksum {} \; | sort \
    >"${tmp_dir}/home.before"
git -C "$sync_repo" diff --no-ext-diff HEAD >"${tmp_dir}/repo.before"
: >"$action_log"
: >"$mutation_log"
run_sync || fail "idempotent sync failed"
[ ! -s "$mutation_log" ] || fail "second sync repeated mutations"
for action in 'core-tools update' 'agent-tools update' pi-packages-update skills-update \
    plugins-update; do
    grep -Fx "$action" "$action_log" >/dev/null ||
        fail "second sync omitted upstream query: $action"
done
if grep -Fx push-plugins "$action_log" >/dev/null; then
    fail "second sync repeated plugin membership install"
fi
find "$home_dir" -path "${home_dir}/.local/state" -prune -o \
    -type f -exec cksum {} \; | sort \
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

#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${DOTFILES_DIR}/scripts/host-tools.sh"
public_recipe_command "$DOTFILES_DIR"
STATE_PLAN="${DOTFILES_DIR}/scripts/state-plan.sh"
UV_BIN="$(command -v uv)"
export UV_CACHE_DIR="${UV_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/uv}"
export UV_PYTHON_INSTALL_DIR="${UV_PYTHON_INSTALL_DIR:-$("$UV_BIN" python dir)}"
unset XDG_CONFIG_HOME

fail() {
    echo "[ERROR] $*" >&2
    exit 1
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
set_smoke_base_path "$tmp_dir"
# The machine group setting must not change fixture results.
export DOTFILES_ENV_FILE="${tmp_dir}/all-groups.env"
printf 'DOTFILES_GROUPS=core,agents,desktop\n' >"$DOTFILES_ENV_FILE"
home_dir="${tmp_dir}/home with spaces"
stub_dir="${tmp_dir}/stubs"
check_log="${tmp_dir}/checks.log"
network_log="${tmp_dir}/network.log"
export DOCTOR_UV_LOG="${tmp_dir}/uv.log"
export DOCTOR_UV_BIN="$UV_BIN"

export CODEX_CONFIG="${home_dir}/.codex/config.toml"
export CODEX_SETTINGS_TEMPLATE="${tmp_dir}/codex-settings.toml"
export CODEX_REMOTE_PLUGIN_CACHE="${home_dir}/.codex/plugins/cache/openai-curated-remote"
export CLAUDE_SETTINGS_FILE="${home_dir}/.claude/settings.json"
export CLAUDE_USER_CONFIG="${home_dir}/.claude.json"
export CLAUDE_TEMPLATE_FILE="${tmp_dir}/claude-settings.json"
export CLAUDE_CONFIG_DIR="${home_dir}/.claude"
export OPENCODE_CONFIG_DIR="${home_dir}/.config/opencode"
export OPENCODE_CONFIG="${OPENCODE_CONFIG_DIR}/opencode.json"
export PI_CODING_AGENT_DIR="${home_dir}/.pi/agent"
export PI_SETTINGS_FILE="${PI_CODING_AGENT_DIR}/settings.json"
export PI_SKILLS_DIR="${PI_CODING_AGENT_DIR}/skills"
export PI_MCP_CONFIG="${home_dir}/.agents/mcp.json"
export PI_AGENTS_SOURCE="${DOTFILES_DIR}/config/pi/AGENTS.md"
export PI_SETTINGS_TEMPLATE="${DOTFILES_DIR}/config/pi/settings.json"
export MCP_SERVERS="${tmp_dir}/mcp.json"
export PLUGIN_MANIFEST="${tmp_dir}/plugins.json"
export CLAUDE_MANIFEST="$PLUGIN_MANIFEST"
export CODEX_PLUGIN_MANIFEST="$PLUGIN_MANIFEST"
export SKILL_LOCK_REPO="${tmp_dir}/skills.json"
export SKILL_LOCK_LIVE="${home_dir}/.agents/.skill-lock.json"
export SKILLS_CLI="${stub_dir}/skills"
unset CODEX_PLUGIN_LIST_FILE CODEX_MARKETPLACE_LIST_FILE

mkdir -p \
    "${home_dir}/.agents/skills" \
    "${home_dir}/.claude/skills" \
    "${home_dir}/.codex" \
    "${home_dir}/.config/opencode/skills" \
    "$PI_CODING_AGENT_DIR" \
    "$stub_dir"
ln -s "${home_dir}/.agents/skills" "$PI_SKILLS_DIR"
cat >"${stub_dir}/uv" <<'STUB'
#!/bin/bash
printf '%s %s\n' "${1:-}" "${2:-}" >>"$DOCTOR_UV_LOG"
exec "$DOCTOR_UV_BIN" "$@"
STUB
chmod +x "${stub_dir}/uv"
cp "${DOTFILES_DIR}/config/claude/settings.json" "$CLAUDE_TEMPLATE_FILE"
cp "${DOTFILES_DIR}/config/codex/settings.toml" "$CODEX_SETTINGS_TEMPLATE"
cp "${DOTFILES_DIR}/.agents/skill-lock.json" "$SKILL_LOCK_LIVE"

repair_managed_links() {
    (
        export HOME="$home_dir"
        # shellcheck source=/dev/null
        source "${DOTFILES_DIR}/install.sh"
        update_managed_links >/dev/null
        configure_mise_shims_profile >/dev/null
    )
}

repair_managed_links

cat >"${stub_dir}/sync-agents" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$DOCTOR_CHECK_LOG"
[ "$*" = '--quiet state-plan' ] || exit 1
if [ "${PLAN_SCENARIO:-normal}" = planner-fail ]; then
    printf '%s\n' '+ "PASSWORD": "private-doctor-sentinel"'
    for ((i=0; i<100; i++)); do echo "[ERROR] Test diagnostic $i"; done
    exit 1
fi
case "${PLAN_SCENARIO:-normal}" in
normal) printf 'PASS\tsettings:codex\tnone\tCodex settings match\n' ;;
update) printf 'UPDATE\tsettings:codex\tupdate\tCodex settings need repository state\n' ;;
export) printf 'EXPORT\tsettings:codex\texport\tCodex settings have portable changes\n' ;;
fail) printf 'FAIL\tsettings:codex\tupdate\tCodex settings are invalid\n' ;;
esac
printf 'PASS\tsettings:claude\tnone\tClaude settings match\n'
printf 'PASS\tsettings:opencode\tnone\tOpenCode settings match\n'
printf 'PASS\tsettings:pi\tnone\tPi settings match\n'
printf 'PASS\tmcp\tnone\tMCP matches\n'
printf 'PASS\tskills\tnone\tSkills match\n'
printf 'PASS\tplugins\tnone\tPlugins match\n'
STUB

cat >"${stub_dir}/agent-tools" <<'STUB'
#!/bin/bash
[ "$1" = plan ] || exit 1
case "${PLAN_MODE:-normal}" in
contract)
    printf 'PASS\ttools\tnone\thealthy\n'
    printf 'UPDATE\tsettings\tupdate\tdrift\n'
    printf 'EXPORT\tskills\texport\tlocal addition\n'
    printf 'FAIL\ttools\tupdate\tmissing\n'
    ;;
invalid) printf 'BROKEN\ttools\tnone\tbad status\n' ;;
invalid-skip) printf 'SKIP\ttools\tupdate\tbad action\n' ;;
skip) printf 'PASS\ttools\tnone\tAgent tool is available\n' ;;
normal)
    if [ "${TOOL_DRIFT:-false}" = false ]; then
        printf 'PASS\ttools\tnone\tTool 1.2.3 is available\n'
    else
        printf 'FAIL\ttools\tupdate\tTool is missing or not runnable\n'
    fi
    ;;
esac
STUB

cat >"${stub_dir}/core-tools" <<'STUB'
#!/bin/bash
[ "$1" = plan ] || exit 1
case "${PLAN_MODE:-normal}" in
contract) printf 'SKIP\ttools\tnone\tsystem tool requires sudo\n' ;;
skip)
    printf 'SKIP\ttools\tnone\txclip requires sudo on linux-arm64\n'
    printf 'SKIP\ttools\tnone\tdemo requires a system package\n'
    ;;
*) printf 'PASS\ttools\tnone\tCore tool is available\n' ;;
esac
STUB

cat >"${stub_dir}/node" <<'STUB'
#!/bin/bash
[ "$*" = --version ] || exit 1
printf 'v%s\n' "${NODE_TEST_VERSION:-99.0.0}"
STUB

mkdir -p "${home_dir}/.local/bin"
cat >"${home_dir}/.local/bin/mise" <<'STUB'
#!/bin/bash
[ "$1" = which ] && [ "$2" = node ] || exit 1
printf '%s\n' "$DOCTOR_NODE_BIN"
STUB

chmod +x "${stub_dir}/sync-agents" "${stub_dir}/agent-tools" \
    "${stub_dir}/core-tools" \
    "${stub_dir}/node" "${home_dir}/.local/bin/mise"
for command_name in npm curl gh; do
    cat >"${stub_dir}/${command_name}" <<'STUB'
#!/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"$NETWORK_LOG"
exit 99
STUB
    chmod +x "${stub_dir}/${command_name}"
done
cp "${DOTFILES_DIR}/config/claude/settings.json" "$CLAUDE_SETTINGS_FILE"
mkdir -p "${home_dir}/.claude/hooks"
printf '#!/bin/bash\n' >"${home_dir}/.claude/hooks/herdr-agent-state.sh"

run_doctor() {
    HOME="$home_dir" \
        PATH="${stub_dir}:${SMOKE_BASE_PATH}" \
        SYNC_AGENTS="${1:-${stub_dir}/sync-agents}" \
        AGENT_TOOLS="${stub_dir}/agent-tools" \
        CORE_TOOLS="${stub_dir}/core-tools" \
        NETWORK_LOG="$network_log" \
        DOCTOR_NODE_BIN="${stub_dir}/node" \
        DOCTOR_CHECK_LOG="$check_log" \
        PLAN_SCENARIO="${PLAN_SCENARIO:-normal}" \
        PLAN_MODE="${PLAN_MODE:-normal}" \
        NODE_TEST_VERSION="${NODE_TEST_VERSION:-}" \
        TOOL_DRIFT="${TOOL_DRIFT:-false}" \
        env -u CODEX_HOME DOTFILES_DIR="$DOTFILES_DIR" \
        "${PUBLIC_RECIPE[@]}" machine \
        >"${tmp_dir}/doctor.log" 2>&1
}

snapshot_state() {
    local output="$1"
    {
        find "$home_dir" -print | LC_ALL=C sort
        find "$home_dir" -type f -exec cksum {} \; | LC_ALL=C sort
        git -C "$DOTFILES_DIR" status --short --untracked-files=all
    } >"$output"
}

PLAN_MODE=contract AGENT_TOOLS="${stub_dir}/agent-tools" \
    CORE_TOOLS="${stub_dir}/core-tools" \
    "$STATE_PLAN" tools >"${tmp_dir}/contract-plan"
[ "$(wc -l <"${tmp_dir}/contract-plan" | tr -d ' ')" -eq 5 ] ||
    fail "state plan does not support every status"
if PLAN_MODE=invalid AGENT_TOOLS="${stub_dir}/agent-tools" \
    CORE_TOOLS="${stub_dir}/core-tools" \
    "$STATE_PLAN" tools >/dev/null 2>&1; then
    fail "state plan accepted an invalid status"
fi
if PLAN_MODE=invalid-skip AGENT_TOOLS="${stub_dir}/agent-tools" \
    CORE_TOOLS="${stub_dir}/core-tools" \
    "$STATE_PLAN" tools >/dev/null 2>&1; then
    fail "state plan accepted an actionable SKIP"
fi

: >"$check_log"
: >"$network_log"
snapshot_state "${tmp_dir}/before"
run_doctor || fail "doctor rejected a healthy plan"
grep -Fxq '[INFO] Live machine matches repository intent' "${tmp_dir}/doctor.log" ||
    fail "doctor did not confirm a healthy machine"
snapshot_state "${tmp_dir}/after"
cmp "${tmp_dir}/before" "${tmp_dir}/after" ||
    fail "doctor changed HOME or checkout"
[ ! -s "$network_log" ] || fail "doctor attempted network access"
grep -Fx -- '--quiet state-plan' "$check_log" >/dev/null ||
    fail "doctor skipped the shared state plan"

rm "${home_dir}/.zshrc"
if run_doctor; then fail "doctor passed with a missing managed link"; fi
grep -F '[FAIL] links:' "${tmp_dir}/doctor.log" >/dev/null ||
    fail "doctor omitted the missing managed link"
repair_managed_links
run_doctor || fail "doctor rejected a repaired managed link"
[ -L "${home_dir}/.zshrc" ] || fail "sync adapter did not restore .zshrc"

grep -Fx '[PASS] shell: Login shells find mise tools' \
    "${tmp_dir}/doctor.log" >/dev/null ||
    fail "doctor did not pass the mise shims profile"
printf 'export LOCAL=1\n' >"${home_dir}/.zprofile"
run_doctor || fail "doctor failed for a profile without mise shims"
grep -Fx '[UPDATE] shell: Login shells do not find mise tools; ~/.zprofile needs the dotfiles block' \
    "${tmp_dir}/doctor.log" >/dev/null ||
    fail "doctor omitted the missing mise shims block"
repair_managed_links
[ "$(head -n 1 "${home_dir}/.zprofile")" = 'export LOCAL=1' ] ||
    fail "repair dropped a local profile line"
run_doctor || fail "doctor rejected a repaired profile"

PLAN_SCENARIO=update
run_doctor || fail "doctor rejected UPDATE"
grep -F '[UPDATE] settings:codex:' "${tmp_dir}/doctor.log" >/dev/null ||
    fail "doctor omitted UPDATE"
grep -F "Run: ${SMOKE_RUNNER} sync" "${tmp_dir}/doctor.log" >/dev/null ||
    fail "doctor omitted update action"
grep -Fxq '[INFO] Live machine differs from repository intent' "${tmp_dir}/doctor.log" ||
    fail "doctor did not report an unaligned machine for UPDATE"

PLAN_SCENARIO="export"
run_doctor || fail "doctor rejected EXPORT"
grep -F '[EXPORT] settings:codex:' "${tmp_dir}/doctor.log" >/dev/null ||
    fail "doctor omitted EXPORT"
grep -F "Run: ${SMOKE_RUNNER} export" "${tmp_dir}/doctor.log" >/dev/null ||
    fail "doctor omitted export action"
grep -Fxq '[INFO] Live machine differs from repository intent' "${tmp_dir}/doctor.log" ||
    fail "doctor did not report an unaligned machine for EXPORT"
unset PLAN_SCENARIO

PLAN_MODE=skip
run_doctor || fail "doctor rejected SKIP-only tool rows"
for reason in \
    'xclip requires sudo on linux-arm64' \
    'demo requires a system package'; do
    grep -F "[SKIP] tools: ${reason}" "${tmp_dir}/doctor.log" >/dev/null ||
        fail "doctor omitted SKIP reason: $reason"
done
unset PLAN_MODE

PLAN_SCENARIO=fail
if run_doctor; then fail "doctor passed with FAIL"; fi
grep -F '[FAIL] settings:codex:' "${tmp_dir}/doctor.log" >/dev/null ||
    fail "doctor omitted FAIL"

PLAN_SCENARIO=planner-fail
if run_doctor; then fail "doctor passed when planning failed"; fi
unset PLAN_SCENARIO
if grep -F 'private-doctor-sentinel' "${tmp_dir}/doctor.log"; then
    fail "doctor exposed raw configuration values"
fi
[ "$(grep -c '^\[ERROR\] Invalid state plan' "${tmp_dir}/doctor.log")" -eq 20 ] ||
    fail "doctor did not bound diagnostics"

ln -s "${home_dir}/missing" "${home_dir}/.agents/skills/broken-link"
if run_doctor; then fail "doctor passed with a broken skill link"; fi
rm "${home_dir}/.agents/skills/broken-link"

TOOL_DRIFT=true
if run_doctor; then fail "doctor passed with a missing tool"; fi
unset TOOL_DRIFT

NODE_TEST_VERSION=invalid
if run_doctor; then fail "doctor passed with invalid Node"; fi
grep -F '[FAIL] node:' "${tmp_dir}/doctor.log" >/dev/null ||
    fail "doctor omitted Node failure"
unset NODE_TEST_VERSION

# Real planner: local adapters, isolated HOME, and stubbed external CLIs.
printf '{}\n' >"$MCP_SERVERS"
printf '%s\n' \
    '{"plugins":{},"marketplaces":{},"codexPlugins":[],"codexMarketplaces":{}}' \
    >"$PLUGIN_MANIFEST"
printf '{"skills":{},"dismissed":{}}\n' >"$SKILL_LOCK_REPO"
cp "$SKILL_LOCK_REPO" "$SKILL_LOCK_LIVE"
cp "${stub_dir}/curl" "${stub_dir}/codex"

sync_real() {
    HOME="$home_dir" PATH="${stub_dir}:${SMOKE_BASE_PATH}" \
        env -u CODEX_HOME "$DOTFILES_DIR/sync-agents.sh" "$@" \
        >"${tmp_dir}/sync.log" 2>&1
}

for component in codex opencode pi claude; do
    sync_real "${component}-install" || {
        cat "${tmp_dir}/sync.log"
        fail "install $component"
    }
done
sync_real push-mcp || fail "prepare MCP fixture"

# Do not reuse the mutation cache for the real read-only checks.
check_cache="${tmp_dir}/empty-uv-cache"
mkdir "$check_cache"
real_plan() {
    HOME="$home_dir" PATH="${stub_dir}:${SMOKE_BASE_PATH}" \
        UV_CACHE_DIR="$check_cache" UV_OFFLINE=1 UV_PYTHON_DOWNLOADS=never \
        NETWORK_LOG="$network_log" \
        env -u CODEX_HOME "$DOTFILES_DIR/sync-agents.sh" --quiet state-plan \
        >"${tmp_dir}/real-plan" 2>"${tmp_dir}/real-plan.err"
}

machine_offline() {
    UV_CACHE_DIR="$check_cache" UV_OFFLINE=1 UV_PYTHON_DOWNLOADS=never \
        run_doctor "$DOTFILES_DIR/sync-agents.sh"
}

: >"$network_log"
# Count file arguments in the real plan, without logging their contents.
plugin_dir="${home_dir}/.claude/plugins"
mkdir -p "$plugin_dir"
printf '{"plugins":{}}\n' >"$plugin_dir/installed_plugins.json"
printf '{}\n' >"$plugin_dir/known_marketplaces.json"
for tool in jq cat cmp; do
    {
        printf '#!/bin/bash\n'
        printf '%s\n' 'if [ -n "${DOCTOR_READ_LOG:-}" ]; then
    for path in "$@"; do
        case "$path" in
        "$HOME"/*) printf "%s\n" "$path" >>"$DOCTOR_READ_LOG" ;;
        esac
    done
fi'
        printf 'exec %q "$@"\n' "$(command -v "$tool")"
    } >"${stub_dir}/${tool}"
    chmod +x "${stub_dir}/${tool}"
done
snapshot_state "${tmp_dir}/real-before"
read_log="${tmp_dir}/provider-reads"
: >"$read_log"
DOCTOR_READ_LOG="$read_log" machine_offline || {
    cat "${tmp_dir}/doctor.log"
    fail "offline machine check failed"
}
for config in "$CLAUDE_SETTINGS_FILE" "$CLAUDE_USER_CONFIG" \
    "$plugin_dir/installed_plugins.json" "$plugin_dir/known_marketplaces.json" \
    "$OPENCODE_CONFIG" "$PI_SETTINGS_FILE" "$PI_MCP_CONFIG" "$SKILL_LOCK_LIVE"; do
    reads="$(grep -Fxc -- "$config" "$read_log" || true)"
    [ "$reads" = 1 ] || fail "expected one read of ${config#"$home_dir"/}; got $reads"
done
grep -E '^\[PASS\] settings:codex:' "${tmp_dir}/doctor.log" ||
    fail "offline machine did not pass matching Codex settings"
real_plan || fail "real state plan failed"
for category in settings:codex settings:claude settings:opencode hooks mcp skills plugins; do
    grep -E "^PASS[[:space:]]+${category}[[:space:]]" \
        "${tmp_dir}/real-plan" >/dev/null || fail "real plan omitted PASS: $category"
done
snapshot_state "${tmp_dir}/real-after"
cmp "${tmp_dir}/real-before" "${tmp_dir}/real-after" ||
    fail "real state plan changed HOME or checkout"

rm "${home_dir}/.claude/hooks/herdr-agent-state.sh"
if machine_offline; then fail "doctor passed with a missing enabled hook"; fi
grep -Fq '[FAIL] hooks:' "${tmp_dir}/doctor.log" || fail "doctor omitted hook failure"
cp "$CLAUDE_SETTINGS_FILE" "${tmp_dir}/claude.hook-before"
jq '.disableAllHooks = true' "$CLAUDE_SETTINGS_FILE" >"${tmp_dir}/disabled.json"
mv "${tmp_dir}/disabled.json" "$CLAUDE_SETTINGS_FILE"
machine_offline || fail "doctor rejected intentionally disabled hooks"
grep -Fq '[SKIP] hooks: Herdr hook is intentionally inactive' \
    "${tmp_dir}/doctor.log" || fail "doctor omitted inactive hook reason"
mv "${tmp_dir}/claude.hook-before" "$CLAUDE_SETTINGS_FILE"
printf '#!/bin/bash\n' >"${home_dir}/.claude/hooks/herdr-agent-state.sh"

cp "$CODEX_CONFIG" "${tmp_dir}/codex.before"
printf 'service_tier = "changed"\n' >"$CODEX_CONFIG"
snapshot_state "${tmp_dir}/real-before"
machine_offline || { cat "${tmp_dir}/doctor.log"; fail "offline machine rejected Codex drift"; }
grep -E '^\[UPDATE\] settings:codex:' "${tmp_dir}/doctor.log" ||
    fail "offline machine did not report Codex drift"
real_plan
grep -E '^UPDATE[[:space:]]+settings:codex[[:space:]]' "${tmp_dir}/real-plan" >/dev/null ||
    fail "offline sync plan did not report Codex drift"

# Constrain real uv discovery to a directory with no installed interpreters.
if UV_MANAGED_PYTHON=1 UV_PYTHON_INSTALL_DIR="${tmp_dir}/no-python" machine_offline; then
    fail "machine passed without a Codex check interpreter"
fi
grep -E '^\[FAIL\] settings:codex: .*Python 3\.11' "${tmp_dir}/doctor.log" ||
    fail "machine did not report the missing Codex check interpreter"
snapshot_state "${tmp_dir}/real-after"
cmp "${tmp_dir}/real-before" "${tmp_dir}/real-after" ||
    fail "offline Codex checks changed HOME or checkout"
[ -z "$(ls -A "$check_cache")" ] || fail "offline Codex checks changed the uv cache"
[ ! -s "$network_log" ] || fail "real state plan attempted network access"
mv "${tmp_dir}/codex.before" "$CODEX_CONFIG"

cat >"$MCP_SERVERS" <<'JSON'
{"shared":{"type":"http","url":"https://repo.test/mcp"}}
JSON
cp "$CODEX_CONFIG" "${tmp_dir}/codex.before-mcp"
cat >>"$CODEX_CONFIG" <<'TOML'
[mcp_servers.shared]
url = "https://codex-old.test/mcp"
TOML
cp "$CLAUDE_USER_CONFIG" "${tmp_dir}/claude-user.before-mcp-drift"
jq '.mcpServers.shared = {
      type: "http", url: "https://claude-old.test/mcp"
    }' "$CLAUDE_USER_CONFIG" >"${tmp_dir}/claude-managed-drift.json"
mv "${tmp_dir}/claude-managed-drift.json" "$CLAUDE_USER_CONFIG"
real_plan
grep -E '^UPDATE[[:space:]]+mcp[[:space:]]' \
    "${tmp_dir}/real-plan" >/dev/null ||
    fail "managed MCP drift is not UPDATE"
printf '{}\n' >"$MCP_SERVERS"
cp "${tmp_dir}/codex.before-mcp" "$CODEX_CONFIG"
mv "${tmp_dir}/claude-user.before-mcp-drift" "$CLAUDE_USER_CONFIG"

cat >>"$CODEX_CONFIG" <<'TOML'
[mcp_servers.codex-local]
command = "/Users/local/bin/server"
[mcp_servers.disabled]
command = "disabled-server"
enabled = false
TOML
real_plan
grep -E '^PASS[[:space:]]+mcp[[:space:]]' \
    "${tmp_dir}/real-plan" >/dev/null ||
    fail "Codex-only local MCP state was not ignored"
cat >>"$CODEX_CONFIG" <<'TOML'
[mcp_servers.codex-portable]
command = "portable-server"
args = ["--stdio"]
TOML
real_plan
grep -E '^EXPORT[[:space:]]+mcp[[:space:]]' \
    "${tmp_dir}/real-plan" >/dev/null ||
    fail "portable Codex-only MCP state is not exportable"
machine_offline || fail "machine rejected a portable MCP addition"
grep -Eq '^\[EXPORT\] mcp: .*codex-portable' "${tmp_dir}/doctor.log" ||
    fail "machine did not name the portable MCP addition"
cp "${tmp_dir}/codex.before-mcp" "$CODEX_CONFIG"

cp "$CLAUDE_SETTINGS_FILE" "${tmp_dir}/claude-settings.before"
jq '.model = "changed"' "$CLAUDE_SETTINGS_FILE" >"${tmp_dir}/changed.json"
mv "${tmp_dir}/changed.json" "$CLAUDE_SETTINGS_FILE"
real_plan
grep -E '^UPDATE[[:space:]]+settings:claude[[:space:]]' \
    "${tmp_dir}/real-plan" >/dev/null || fail "settings drift is not UPDATE"
mv "${tmp_dir}/claude-settings.before" "$CLAUDE_SETTINGS_FILE"

mv "$CLAUDE_SETTINGS_FILE" "${tmp_dir}/claude-settings.saved"
real_plan
grep -E '^FAIL[[:space:]]+settings:claude[[:space:]]' \
    "${tmp_dir}/real-plan" >/dev/null || fail "missing settings are not FAIL"
mv "${tmp_dir}/claude-settings.saved" "$CLAUDE_SETTINGS_FILE"

cp "$PI_MCP_CONFIG" "${tmp_dir}/pi-mcp.before"
printf '[]\n' >"$PI_MCP_CONFIG"
if machine_offline; then fail "machine accepted invalid Pi MCP state"; fi
grep -Fxq '[FAIL] mcp: Pi MCP config is unreadable or invalid' \
    "${tmp_dir}/doctor.log" || fail "machine did not identify invalid Pi MCP state"
mv "${tmp_dir}/pi-mcp.before" "$PI_MCP_CONFIG"

jq '.mcpServers.extra = {type: "http", url: "https://extra.test/mcp"}' \
    "$CLAUDE_USER_CONFIG" >"${tmp_dir}/claude-extra.json"
mv "${tmp_dir}/claude-extra.json" "$CLAUDE_USER_CONFIG"
real_plan
grep -E '^EXPORT[[:space:]]+mcp[[:space:]]' \
    "${tmp_dir}/real-plan" >/dev/null || fail "portable MCP addition is not EXPORT"
sync_real push-mcp || fail "restore MCP fixture"

mkdir -p "${home_dir}/.agents/skills/local-skill"
printf '%s\n' '# local' >"${home_dir}/.agents/skills/local-skill/SKILL.md"
real_plan
grep -E '^EXPORT[[:space:]]+skills[[:space:]]' \
    "${tmp_dir}/real-plan" >/dev/null || fail "local skill addition is not EXPORT"
grep -E '^EXPORT[[:space:]]+skills[[:space:]].*local-skill' \
    "${tmp_dir}/real-plan" >/dev/null || fail "plan did not name the local skill"
rm -rf "${home_dir}/.agents/skills/local-skill"

market="${home_dir}/.codex/.tmp/marketplaces/third/.agents/plugins"
cache="${home_dir}/.codex/plugins/cache/third"
mkdir -p "$market" "$cache/demo/1.0.0" "$cache/disabled/1.0.0"
printf '%s\n' '{"name":"third","plugins":[{"name":"demo"},{"name":"disabled"}]}' >"$market/marketplace.json"
cat >>"$CODEX_CONFIG" <<'TOML'
[marketplaces.third]
source_type = "git"
source = "https://github.com/example/plugins"
[plugins."demo@third"]
enabled = true
[plugins."disabled@third"]
enabled = false
TOML
snapshot_state "${tmp_dir}/plugins-before"
: >"$DOCTOR_UV_LOG"
machine_offline || fail "machine rejected an offline plugin addition"
[ "$(cat "$DOCTOR_UV_LOG")" = 'python find' ] ||
    fail "machine did not build settings, MCP and plugin state in one Codex read"
snapshot_state "${tmp_dir}/plugins-after"
cmp "${tmp_dir}/plugins-before" "${tmp_dir}/plugins-after" ||
    fail "plugin plan changed HOME or checkout"
real_plan
grep -E '^EXPORT[[:space:]]+plugins[[:space:]]' \
    "${tmp_dir}/real-plan" >/dev/null || fail "portable plugin addition is not EXPORT"
grep -E '^EXPORT[[:space:]]+plugins[[:space:]].*demo@third' \
    "${tmp_dir}/real-plan" >/dev/null || fail "plan did not name the local plugin"
if grep -Eq 'https://github.com/example/plugins|disabled@third' "${tmp_dir}/real-plan"; then
    fail "plan exposed a marketplace URL or listed a disabled plugin"
fi
[ ! -s "$network_log" ] || fail "machine called a network-capable CLI"

# Use a real fetch and planner without allowing sync to touch the source checkout.
(
    # shellcheck disable=SC2046
    unset $(git -C "$DOTFILES_DIR" rev-parse --local-env-vars)
    upstream="${tmp_dir}/sync-upstream"
    checkout="${tmp_dir}/sync-checkout"
    git init -q --initial-branch=master "$upstream"
    git -C "$upstream" -c user.name=Smoke -c user.email=smoke@example.test \
        commit -q --allow-empty -m 'Initialize fixture'
    git clone -q "$upstream" "$checkout"

    # The Git fixture only supplies the checkout; the real planner uses this tree.
    plan="${tmp_dir}/sync-plan"
    printf '#!/bin/bash\nDOTFILES_DIR=%q exec %q "$@"\n' "$DOTFILES_DIR" "$STATE_PLAN" >"$plan"
    chmod +x "$plan"

    rm "${home_dir}/.zshrc"  # Independent repair would write to HOME.
    snapshot_state "${tmp_dir}/sync-before"
    if env -u CODEX_HOME HOME="$home_dir" XDG_STATE_HOME="${tmp_dir}/sync-state" \
        PATH="${stub_dir}:${SMOKE_BASE_PATH}" NETWORK_LOG="$network_log" \
        UV_CACHE_DIR="$check_cache" UV_OFFLINE=1 UV_PYTHON_DOWNLOADS=never \
        DOTFILES_DIR="$checkout" STATE_PLAN="$plan" \
        UPDATE_SCRIPT="${DOTFILES_DIR}/scripts/update-local.sh" \
        INSTALL_SCRIPT="${DOTFILES_DIR}/install.sh" \
        SYNC_AGENTS="${DOTFILES_DIR}/sync-agents.sh" \
        AGENT_TOOLS="${stub_dir}/agent-tools" CORE_TOOLS="${stub_dir}/core-tools" \
        DOCTOR_NODE_BIN="${stub_dir}/node" \
        "${PUBLIC_RECIPE[@]}" sync \
        >"${tmp_dir}/blocked-sync.log" 2>&1; then
        fail "sync accepted an unexported Codex plugin"
    fi
    if ! grep -Eq '^\[BLOCKED\] plugins: .*demo@third' "${tmp_dir}/blocked-sync.log" ||
        ! grep -Fxq '[RESULT] EXPORT' "${tmp_dir}/blocked-sync.log"; then
        cat "${tmp_dir}/blocked-sync.log" >&2
        fail "sync did not block on the named Codex plugin"
    fi
    grep -Fq '[PLAN] [FAIL] links:' "${tmp_dir}/blocked-sync.log" ||
        fail "sync fixture did not plan the independent repair"
    grep -Fq "Run: ${SMOKE_RUNNER} export" "${tmp_dir}/blocked-sync.log" ||
        fail "sync omitted the next step"
    if grep -Eq '^\[(APPLY|REFRESH)\]' "${tmp_dir}/blocked-sync.log"; then
        fail "sync attempted a change before export"
    fi
    snapshot_state "${tmp_dir}/sync-after"
    cmp "${tmp_dir}/sync-before" "${tmp_dir}/sync-after" ||
        fail "blocked sync changed HOME or the source checkout"
    [ ! -s "$network_log" ] || fail "blocked sync called a network-capable CLI"
)
repair_managed_links
rm "$market/marketplace.json"
if machine_offline; then fail "machine accepted a missing marketplace snapshot"; fi
grep -Eq '^\[FAIL\] plugins: .*marketplace.*third' "${tmp_dir}/doctor.log" ||
    fail "machine did not name the missing marketplace snapshot"

cp "$SKILL_LOCK_REPO" "${tmp_dir}/skills.before"
printf 'not JSON\n' >"$SKILL_LOCK_REPO"
if machine_offline; then fail "machine accepted an incomplete plan"; fi
grep -Fq '[FAIL] state plan' "${tmp_dir}/doctor.log" ||
    fail "machine omitted the planner failure"
mv "${tmp_dir}/skills.before" "$SKILL_LOCK_REPO"

if grep -Eq \
    'agent-plugin-check|claude-settings-check|mcp-config-check' \
    "${DOTFILES_DIR}/.pre-commit-config.yaml"; then
    fail "prek hooks still contain live machine checks"
fi

echo "[INFO] doctor smoke test passed"

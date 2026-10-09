#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_PLAN="${DOTFILES_DIR}/scripts/state-plan.sh"
JUST_BIN="$(command -v just)"
UV_BIN="$(command -v uv)"
export UV_CACHE_DIR="${UV_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/uv}"

fail() {
    echo "[ERROR] $*" >&2
    exit 1
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
home_dir="${tmp_dir}/home with spaces"
stub_dir="${tmp_dir}/stubs"
check_log="${tmp_dir}/checks.log"
network_log="${tmp_dir}/network.log"

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
export SHARED_SKILLS_CUSTOM_DIR="${tmp_dir}/custom-skills"
export SKILLS_CLI="${stub_dir}/skills"
export CODEX_MCP_STATE_FILE="${tmp_dir}/codex-mcp.json"

mkdir -p \
    "${home_dir}/.agents/skills" \
    "${home_dir}/.claude/skills" \
    "${home_dir}/.codex" \
    "${home_dir}/.config/opencode/skills" \
    "${home_dir}/.pi/agent/skills" \
    "$stub_dir" "$SHARED_SKILLS_CUSTOM_DIR"
ln -s "$UV_BIN" "${stub_dir}/uv"
cp "${DOTFILES_DIR}/config/claude/settings.json" "$CLAUDE_TEMPLATE_FILE"
cp "${DOTFILES_DIR}/config/codex/settings.toml" "$CODEX_SETTINGS_TEMPLATE"
cp "${DOTFILES_DIR}/.agents/skill-lock.json" "$SKILL_LOCK_LIVE"
ln -s "${DOTFILES_DIR}/config/codex/AGENTS.md" \
    "${home_dir}/.codex/AGENTS.md"
ln -s "${DOTFILES_DIR}/config/claude/CLAUDE.md" \
    "${home_dir}/.claude/CLAUDE.md"
ln -s "${DOTFILES_DIR}/config/claude/settings.local.json" \
    "${home_dir}/.claude/settings.local.json"
ln -s "${DOTFILES_DIR}/config/opencode/AGENTS.md" \
    "${home_dir}/.config/opencode/AGENTS.md"
ln -s "${DOTFILES_DIR}/config/pi/AGENTS.md" \
    "${home_dir}/.pi/agent/AGENTS.md"

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
normal)
    if [ "${TOOL_DRIFT:-false}" = false ]; then
        printf 'PASS\ttools\tnone\tTool 1.2.3 is available\n'
    else
        printf 'FAIL\ttools\tupdate\tTool is missing or not runnable\n'
    fi
    ;;
esac
STUB

cat >"${stub_dir}/node" <<'STUB'
#!/bin/bash
[ "$*" = --version ] || exit 1
printf 'v%s\n' "${NODE_TEST_VERSION:-99.0.0}"
STUB

chmod +x "${stub_dir}/sync-agents" "${stub_dir}/agent-tools" \
    "${stub_dir}/node"
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
        PATH="${stub_dir}:/usr/bin:/bin" \
        SYNC_AGENTS="${stub_dir}/sync-agents" \
        AGENT_TOOLS="${stub_dir}/agent-tools" \
        NETWORK_LOG="$network_log" \
        DOCTOR_CHECK_LOG="$check_log" \
        PLAN_SCENARIO="${PLAN_SCENARIO:-normal}" \
        NODE_TEST_VERSION="${NODE_TEST_VERSION:-}" \
        TOOL_DRIFT="${TOOL_DRIFT:-false}" \
        env -u CODEX_HOME DOTFILES_DIR="$DOTFILES_DIR" \
        "$JUST_BIN" --justfile "${DOTFILES_DIR}/justfile" doctor \
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
    "$STATE_PLAN" tools >"${tmp_dir}/contract-plan"
[ "$(wc -l <"${tmp_dir}/contract-plan" | tr -d ' ')" -eq 4 ] ||
    fail "state plan does not support every status"
if PLAN_MODE=invalid AGENT_TOOLS="${stub_dir}/agent-tools" \
    "$STATE_PLAN" tools >/dev/null 2>&1; then
    fail "state plan accepted an invalid status"
fi

: >"$check_log"
: >"$network_log"
snapshot_state "${tmp_dir}/before"
run_doctor || fail "doctor rejected a healthy plan"
snapshot_state "${tmp_dir}/after"
cmp "${tmp_dir}/before" "${tmp_dir}/after" ||
    fail "doctor changed HOME or checkout"
[ ! -s "$network_log" ] || fail "doctor attempted network access"
grep -Fx -- '--quiet state-plan' "$check_log" >/dev/null ||
    fail "doctor skipped the shared state plan"

PLAN_SCENARIO=update
run_doctor || fail "doctor rejected UPDATE"
grep -F '[UPDATE] settings:codex:' "${tmp_dir}/doctor.log" >/dev/null ||
    fail "doctor omitted UPDATE"
grep -F 'Run: just update' "${tmp_dir}/doctor.log" >/dev/null ||
    fail "doctor omitted update action"

PLAN_SCENARIO="export"
run_doctor || fail "doctor rejected EXPORT"
grep -F '[EXPORT] settings:codex:' "${tmp_dir}/doctor.log" >/dev/null ||
    fail "doctor omitted EXPORT"
grep -F 'Run: just export' "${tmp_dir}/doctor.log" >/dev/null ||
    fail "doctor omitted export action"

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

rm "${home_dir}/.claude/hooks/herdr-agent-state.sh"
if run_doctor; then fail "doctor passed with a missing enabled hook"; fi
grep -F '[FAIL] hooks:' "${tmp_dir}/doctor.log" >/dev/null ||
    fail "doctor omitted hook failure"
jq '.disableAllHooks = true' "$CLAUDE_SETTINGS_FILE" \
    >"${tmp_dir}/disabled.json"
mv "${tmp_dir}/disabled.json" "$CLAUDE_SETTINGS_FILE"
run_doctor || fail "doctor rejected intentionally disabled hooks"
grep -F '[PASS] hooks: Herdr hook is intentionally inactive' \
    "${tmp_dir}/doctor.log" >/dev/null || fail "doctor omitted inactive hook reason"
printf '#!/bin/bash\n' >"${home_dir}/.claude/hooks/herdr-agent-state.sh"

# Real planner: local adapters, isolated HOME, and stubbed external CLIs.
printf '{}\n' >"$MCP_SERVERS"
printf '%s\n' \
    '{"plugins":{},"marketplaces":{},"codexPlugins":[],"codexMarketplaces":{}}' \
    >"$PLUGIN_MANIFEST"
printf '{"skills":{},"dismissed":{}}\n' >"$SKILL_LOCK_REPO"
cp "$SKILL_LOCK_REPO" "$SKILL_LOCK_LIVE"
export CODEX_PLUGIN_LIST_FILE="${tmp_dir}/codex-plugins.json"
export CODEX_MARKETPLACE_LIST_FILE="${tmp_dir}/codex-marketplaces.json"
printf '{"installed":[]}\n' >"$CODEX_PLUGIN_LIST_FILE"
printf '{"marketplaces":[]}\n' >"$CODEX_MARKETPLACE_LIST_FILE"
cat >"${stub_dir}/codex" <<'STUB'
#!/bin/bash
[ "$*" = 'mcp list --json' ] || exit 1
cat "$CODEX_MCP_STATE_FILE"
STUB
chmod +x "${stub_dir}/codex"
printf '[]\n' >"$CODEX_MCP_STATE_FILE"

sync_real() {
    HOME="$home_dir" PATH="${stub_dir}:/usr/bin:/bin" \
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

real_plan() {
    HOME="$home_dir" PATH="${stub_dir}:/usr/bin:/bin" \
        NETWORK_LOG="$network_log" \
        env -u CODEX_HOME "$DOTFILES_DIR/sync-agents.sh" --quiet state-plan \
        >"${tmp_dir}/real-plan" 2>"${tmp_dir}/real-plan.err"
}

: >"$network_log"
snapshot_state "${tmp_dir}/real-before"
real_plan || fail "real state plan failed"
for category in settings:codex settings:claude settings:opencode mcp skills plugins; do
    grep -E "^PASS[[:space:]]+${category}[[:space:]]" \
        "${tmp_dir}/real-plan" >/dev/null || fail "real plan omitted PASS: $category"
done
snapshot_state "${tmp_dir}/real-after"
cmp "${tmp_dir}/real-before" "${tmp_dir}/real-after" ||
    fail "real state plan changed HOME or checkout"
[ ! -s "$network_log" ] || fail "real state plan attempted network access"

cat >"$CODEX_MCP_STATE_FILE" <<'JSON'
[{"enabled":true,"name":"codex-local","transport":{
  "type":"stdio","command":"/Users/local/bin/server","args":[]}}]
JSON
real_plan
grep -E '^PASS[[:space:]]+mcp[[:space:]]' \
    "${tmp_dir}/real-plan" >/dev/null ||
    fail "Codex-only local MCP state was not ignored"
printf '[]\n' >"$CODEX_MCP_STATE_FILE"

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
    "${tmp_dir}/real-plan" >/dev/null || fail "portable skill addition is not EXPORT"
rm -rf "${home_dir}/.agents/skills/local-skill"

cat >"$CODEX_PLUGIN_LIST_FILE" <<'JSON'
{"installed":[{"installed":true,"enabled":true,"pluginId":"demo@third",
"marketplaceName":"third","marketplaceSource":{"sourceType":"git",
"source":"https://github.com/example/plugins"}}]}
JSON
cat >"$CODEX_MARKETPLACE_LIST_FILE" <<'JSON'
{"marketplaces":[{"name":"third","marketplaceSource":{"sourceType":"git",
"source":"https://github.com/example/plugins"}}]}
JSON
real_plan
grep -E '^EXPORT[[:space:]]+plugins[[:space:]]' \
    "${tmp_dir}/real-plan" >/dev/null || fail "portable plugin addition is not EXPORT"

if grep -Eq \
    'agent-plugin-check|claude-settings-check|mcp-config-check' \
    "${DOTFILES_DIR}/.pre-commit-config.yaml"; then
    fail "pre-commit still contains live machine checks"
fi

echo "[INFO] doctor smoke test passed"

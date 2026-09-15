#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCTOR="${DOTFILES_DIR}/scripts/doctor.sh"
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

# Pin every sync input/output instead of inheriting the caller's live overrides.
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
export KIMI_CODE_HOME="${home_dir}/.kimi-code"
export KIMI_MCP_CONFIG="${KIMI_CODE_HOME}/mcp.json"
export MCP_SERVERS="${tmp_dir}/mcp.json"
export PLUGIN_MANIFEST="${tmp_dir}/plugins.json"
export CLAUDE_MANIFEST="$PLUGIN_MANIFEST"
export CODEX_PLUGIN_MANIFEST="$PLUGIN_MANIFEST"
export SKILL_LOCK_REPO="${tmp_dir}/skills.json"
export SKILL_LOCK_LIVE="${home_dir}/.agents/.skill-lock.json"
export SHARED_SKILLS_CUSTOM_DIR="${tmp_dir}/custom-skills"
export SKILLS_CLI="${stub_dir}/skills"

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

cp "${DOTFILES_DIR}/.agents/skill-lock.json" \
    "${home_dir}/.agents/.skill-lock.json"
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
printf '%s\n' "$*" >> "$DOCTOR_CHECK_LOG"
if [ "$*" = "${REAL_CHECK:-}" ]; then
    exec "$DOTFILES_DIR/sync-agents.sh" "$@"
fi
[ "$*" != "${FAIL_CHECK:-}" ]
STUB

cat >"${stub_dir}/agent-tools" <<'STUB'
#!/bin/bash
[ "${TOOL_DRIFT:-false}" = false ]
STUB
cat >"${stub_dir}/node" <<'STUB'
#!/bin/bash
[ "$*" = --version ] || exit 1
printf 'v%s\n' "${NODE_TEST_VERSION:-$(cat "$DOTFILES_DIR/.nvmrc")}"
STUB
chmod +x "${stub_dir}/sync-agents" "${stub_dir}/agent-tools" "${stub_dir}/node"
cp "${DOTFILES_DIR}/config/claude/settings.json" "${home_dir}/.claude/settings.json"
mkdir -p "${home_dir}/.claude/hooks"
printf '#!/bin/bash\n' >"${home_dir}/.claude/hooks/herdr-agent-state.sh"

run_doctor() {
    HOME="$home_dir" \
        PATH="${stub_dir}:/usr/bin:/bin" \
        DOTFILES_DIR="$DOTFILES_DIR" \
        SYNC_AGENTS="${stub_dir}/sync-agents" \
        AGENT_TOOLS="${stub_dir}/agent-tools" \
        DOCTOR_CHECK_LOG="$check_log" \
        FAIL_CHECK="${FAIL_CHECK:-}" \
        REAL_CHECK="${REAL_CHECK:-}" \
        NODE_TEST_VERSION="${NODE_TEST_VERSION:-}" \
        TOOL_DRIFT="${TOOL_DRIFT:-false}" \
        env -u CODEX_HOME "$DOCTOR" >"${tmp_dir}/doctor.log" 2>&1
}

: >"$check_log"
run_doctor || {
    cat "${tmp_dir}/doctor.log" >&2
    fail "doctor failed"
}

for expected in \
    plugins-check \
    codex-check \
    claude-settings-check \
    opencode-check \
    kimi-check \
    mcp-check \
    pi-check \
    skills-check; do
    grep -Fx "$expected" "$check_log" >/dev/null ||
        fail "doctor skipped: $expected"
done

FAIL_CHECK=plugins-check
if run_doctor; then
    fail "doctor passed with plugin drift"
fi
unset FAIL_CHECK

ln -s "${home_dir}/missing" "${home_dir}/.agents/skills/broken-link"
if run_doctor; then
    fail "doctor passed with a broken skill link"
fi
rm "${home_dir}/.agents/skills/broken-link"

TOOL_DRIFT=true
if run_doctor; then
    fail "doctor passed with version drift"
fi
unset TOOL_DRIFT

NODE_TEST_VERSION=0.0.0
if run_doctor; then
    fail "doctor passed with Node drift"
fi
grep -F '[FAIL] Node version' "${tmp_dir}/doctor.log" >/dev/null ||
    fail "doctor did not identify Node drift"
unset NODE_TEST_VERSION

rm "${home_dir}/.claude/hooks/herdr-agent-state.sh"
if run_doctor; then
    fail "doctor passed with missing enabled Herdr hook"
fi
grep -F 'herdr integration install claude' "${tmp_dir}/doctor.log" >/dev/null ||
    fail "doctor omitted Herdr repair command"
jq '.disableAllHooks = true' "${home_dir}/.claude/settings.json" >"${tmp_dir}/disabled.json"
mv "${tmp_dir}/disabled.json" "${home_dir}/.claude/settings.json"
run_doctor || fail "doctor rejected explicitly disabled hooks"
grep -F '[SKIP] Herdr Claude hook: disableAllHooks is true' \
    "${tmp_dir}/doctor.log" >/dev/null || fail "doctor omitted SKIP reason"
printf '#!/bin/bash\n' >"${home_dir}/.claude/hooks/herdr-agent-state.sh"

jq '.skills.extra = {source: "example/skills"}' \
    "${home_dir}/.agents/.skill-lock.json" >"${tmp_dir}/lock.json"
mv "${tmp_dir}/lock.json" "${home_dir}/.agents/.skill-lock.json"
FAIL_CHECK=skills-check
if run_doctor; then
    fail "doctor passed with skill lock drift"
fi
unset FAIL_CHECK

# Exercise the real settings commands through doctor; other subsystems remain
# isolated so their installed CLIs and network access cannot affect this test.
printf '{}\n' >"$MCP_SERVERS"
printf '{"plugins":{},"marketplaces":{}}\n' >"$CLAUDE_MANIFEST"
printf '{"skills":{},"dismissed":{}}\n' >"$SKILL_LOCK_REPO"

sync_real() {
    HOME="$home_dir" PATH="${stub_dir}:/usr/bin:/bin" \
        env -u CODEX_HOME "$DOTFILES_DIR/sync-agents.sh" "$@" >"${tmp_dir}/sync.log" 2>&1
}

for component in claude opencode kimi; do
    case "$component" in
    claude)
        REAL_CHECK=claude-settings-check
        config="${home_dir}/.claude/settings.json"
        drift='.model = "changed"'
        ;;
    opencode)
        REAL_CHECK=opencode-check
        config="${home_dir}/.config/opencode/opencode.json"
        drift='.instructions = []'
        ;;
    kimi)
        REAL_CHECK=kimi-check
        config="${home_dir}/.kimi-code/mcp.json"
        drift='.mcpServers.extra = {command: "changed"}'
        ;;
    esac
    sync_real "${component}-install" || {
        cat "${tmp_dir}/sync.log"
        fail "install $component"
    }
    cp "$config" "${tmp_dir}/expected.json"
    run_doctor || {
        cat "${tmp_dir}/doctor.log"
        fail "valid $component settings rejected"
    }
    cmp -s "$config" "${tmp_dir}/expected.json" || fail "doctor wrote settings"

    rm "$config"
    if run_doctor; then fail "doctor passed with missing $component settings"; fi
    [ ! -e "$config" ] || fail "doctor recreated missing settings"
    grep -F "$config" "${tmp_dir}/doctor.log" >/dev/null || fail "missing path omitted"
    grep -F "./sync-agents.sh ${component}-install" "${tmp_dir}/doctor.log" \
        >/dev/null || fail "repair command omitted"

    for invalid in '' '{' '{} {}' '[]' 'null'; do
        printf '%s' "$invalid" >"$config"
        if run_doctor; then fail "doctor passed with invalid $component JSON: $invalid"; fi
        grep -F "expected exactly one object: $config" "${tmp_dir}/doctor.log" \
            >/dev/null || fail "invalid JSON diagnostic omitted"
        grep -F "./sync-agents.sh ${component}-install" "${tmp_dir}/doctor.log" \
            >/dev/null || fail "invalid JSON repair command omitted"
        [ "$(cat "$config")" = "$invalid" ] || fail "doctor modified invalid JSON"
    done

    jq "$drift" "${tmp_dir}/expected.json" >"$config"
    if run_doctor; then fail "doctor passed with changed $component settings"; fi
    cp "${tmp_dir}/expected.json" "$config"
done
unset REAL_CHECK

# Codex uses TOML; exercise its real install/check through the same doctor.
printf 'approval_policy = "never"\n' >"$CODEX_SETTINGS_TEMPLATE"
REAL_CHECK=codex-check
sync_real codex-install || {
    cat "${tmp_dir}/sync.log"
    fail 'install Codex'
}
config="${home_dir}/.codex/config.toml"
cp "$config" "${tmp_dir}/expected.toml"
run_doctor || {
    cat "${tmp_dir}/doctor.log"
    fail 'valid Codex settings rejected'
}
cmp -s "$config" "${tmp_dir}/expected.toml" || fail 'doctor wrote Codex settings'
rm "$config"
if run_doctor; then fail 'doctor passed with missing Codex settings'; fi
[ ! -e "$config" ] || fail 'doctor recreated Codex settings'
grep -F './sync-agents.sh codex-install' "${tmp_dir}/doctor.log" >/dev/null ||
    fail 'missing Codex repair command'
sed 's/never/on-request/' "${tmp_dir}/expected.toml" >"$config"
if cmp -s "$config" "${tmp_dir}/expected.toml"; then
    fail 'Codex drift fixture did not change approval_policy'
fi
if run_doctor; then fail 'doctor passed with changed Codex settings'; fi
cp "${tmp_dir}/expected.toml" "$config"
unset REAL_CHECK

# Empty shared MCP inventory still requires each managed runtime's config.
mkdir -p "${home_dir}/.codex"
printf '\n' >"${home_dir}/.codex/config.toml"
printf '{"mcpServers":{}}\n' >"${home_dir}/.agents/mcp.json"
cat >"${stub_dir}/codex" <<'STUB'
#!/bin/bash
[ "$*" = 'mcp list --json' ] || exit 1
printf '[]\n'
STUB
chmod +x "${stub_dir}/codex"
REAL_CHECK=mcp-check
run_doctor || {
    cat "${tmp_dir}/doctor.log"
    fail "valid MCP settings rejected"
}
for config in \
    "${home_dir}/.codex/config.toml" \
    "${home_dir}/.claude.json" \
    "${home_dir}/.config/opencode/opencode.json" \
    "${home_dir}/.kimi-code/mcp.json" \
    "${home_dir}/.agents/mcp.json"; do
    mv "$config" "${tmp_dir}/saved-config"
    if run_doctor; then fail "doctor passed with missing MCP file: $config"; fi
    grep -F "$config" "${tmp_dir}/doctor.log" >/dev/null || fail "missing MCP path omitted"
    grep -F './sync-agents.sh push-mcp' "${tmp_dir}/doctor.log" >/dev/null ||
        fail "missing MCP repair command"
    if [[ "$config" == *.json ]]; then
        for invalid in '' '{'; do
            printf '%s' "$invalid" >"$config"
            if run_doctor; then fail "doctor passed with invalid MCP JSON: $config"; fi
            grep -F "expected exactly one object: $config" "${tmp_dir}/doctor.log" \
                >/dev/null || fail "invalid MCP JSON diagnostic omitted"
        done
    fi
    mv "${tmp_dir}/saved-config" "$config"
done
unset REAL_CHECK

REAL_CHECK=pi-check
for invalid in '' '{'; do
    printf '%s' "$invalid" >"$PI_SETTINGS_FILE"
    if run_doctor; then fail 'doctor passed with invalid Pi JSON'; fi
    grep -F "expected exactly one object: $PI_SETTINGS_FILE" "${tmp_dir}/doctor.log" \
        >/dev/null || fail 'invalid Pi JSON diagnostic omitted'
done
unset REAL_CHECK

# A manifest declaring plugins makes their installed state required.
printf '{"plugins":{"example":{"claude":"example@market"}},"marketplaces":{}}\n' \
    >"$CLAUDE_MANIFEST"
if sync_real claude-export --check; then fail "missing Claude plugin state passed"; fi
grep -F 'installed_plugins.json' "${tmp_dir}/sync.log" >/dev/null ||
    fail "missing Claude plugin path omitted"
mkdir -p "${home_dir}/.claude/plugins"
printf '{"plugins":{"example@market":[{"scope":"user"}]}}\n' \
    >"${home_dir}/.claude/plugins/installed_plugins.json"
jq '.marketplaces.market = {source: "github", repo: "example/plugins"}' \
    "$CLAUDE_MANIFEST" >"${tmp_dir}/manifest.json"
mv "${tmp_dir}/manifest.json" "$CLAUDE_MANIFEST"
if sync_real claude-export --check; then fail "missing Claude marketplaces passed"; fi
grep -F 'known_marketplaces.json' "${tmp_dir}/sync.log" >/dev/null ||
    fail "missing Claude marketplace path omitted"

if grep -Eq \
    'agent-plugin-check|claude-settings-check|mcp-config-check' \
    "${DOTFILES_DIR}/.pre-commit-config.yaml"; then
    fail "pre-commit still contains live machine checks"
fi

echo "[INFO] doctor smoke test passed"

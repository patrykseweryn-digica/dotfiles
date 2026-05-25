#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK_FILE="${DOTFILES_DIR}/.agents/skill-lock.json"
MCP_SERVERS_FILE="${DOTFILES_DIR}/.agents/mcp-servers.json"
CUSTOM_SKILLS_DIR="${DOTFILES_DIR}/.agents/skills-custom"
CLAUDE_MANIFEST_FILE="${DOTFILES_DIR}/config/claude/claude-manifest.json"

fail() {
    echo "[ERROR] $*" >&2
    exit 1
}

JQ_BIN="$(command -v jq 2>/dev/null || true)"
[ -n "$JQ_BIN" ] || fail "jq is required"

tmp_dir="$(mktemp -d)"
cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

home_dir="${tmp_dir}/home"
stub_dir="${tmp_dir}/stubs"
lock_names="${tmp_dir}/lock-skill-names.txt"
sync_log="${tmp_dir}/sync.log"
npx_home="${tmp_dir}/npx-home"
npx_stub_dir="${tmp_dir}/npx-stubs"
npx_log="${tmp_dir}/npx.log"
legacy_home="${tmp_dir}/legacy-home"
env_home="${tmp_dir}/env-home"
env_mcp_file="${tmp_dir}/mcp-with-env.json"
repo_lock_copy="${tmp_dir}/skill-lock.json"
manifest_copy="${tmp_dir}/claude-manifest.json"

mkdir -p "$home_dir/.agents/skills" "$stub_dir"
ln -s "$JQ_BIN" "${stub_dir}/jq"
cp "$LOCK_FILE" "$repo_lock_copy"
cp "$CLAUDE_MANIFEST_FILE" "$manifest_copy"
jq -r '.skills | keys[]' "$LOCK_FILE" > "$lock_names"

# Pretend lock-managed skills already exist in the shared Codex-compatible runtime.
# The smoke test should prove sync links them into Claude/OpenCode without needing npx.
while IFS= read -r skill_name; do
    [ -n "$skill_name" ] || continue
    mkdir -p "${home_dir}/.agents/skills/${skill_name}"
    printf '# %s\n' "$skill_name" > "${home_dir}/.agents/skills/${skill_name}/SKILL.md"
done < "$lock_names"

export HOME="$home_dir"
export CODEX_HOME="${HOME}/.codex"
export OPENCODE_CONFIG_DIR="${HOME}/.config/opencode"
export OPENCODE_CONFIG="${OPENCODE_CONFIG_DIR}/opencode.json"
export SKILL_LOCK_REPO="$repo_lock_copy"
export CLAUDE_MANIFEST="$manifest_copy"
export PATH="${stub_dir}:/usr/bin:/bin"

if ! "${DOTFILES_DIR}/sync-agents.sh" --quiet codex-check > "$sync_log" 2>&1; then
    cat "$sync_log" >&2
    fail "codex-check should skip missing fresh config"
fi

if ! "${DOTFILES_DIR}/sync-agents.sh" --quiet opencode-check > "$sync_log" 2>&1; then
    cat "$sync_log" >&2
    fail "opencode-check should skip missing fresh config"
fi

if ! "${DOTFILES_DIR}/sync-agents.sh" --quiet install > "$sync_log" 2>&1; then
    cat "$sync_log" >&2
    fail "sync-agents.sh install failed"
fi

if ! "${DOTFILES_DIR}/sync-agents.sh" --quiet claude-settings-check > "$sync_log" 2>&1; then
    cat "$sync_log" >&2
    fail "claude-settings-check failed after install"
fi

if ! "${DOTFILES_DIR}/sync-agents.sh" --quiet claude-export --check > "$sync_log" 2>&1; then
    cat "$sync_log" >&2
    fail "claude-export --check should tolerate fresh installs without live plugin state"
fi

if ! "${DOTFILES_DIR}/sync-agents.sh" --quiet skills-export > "$sync_log" 2>&1; then
    cat "$sync_log" >&2
    fail "skills-export failed with isolated repo lock"
fi

cmp -s "$repo_lock_copy" "$LOCK_FILE" || fail "skills-export changed isolated repo lock intent unexpectedly"

if grep -F "Installing skill:" "$sync_log" >/dev/null 2>&1; then
    cat "$sync_log" >&2
    fail "sync tried to install lock-managed skills instead of linking existing shared copies"
fi

while IFS= read -r skill_name; do
    [ -n "$skill_name" ] || continue
    [ -e "${HOME}/.agents/skills/${skill_name}/SKILL.md" ] || fail "missing shared skill: $skill_name"
    [ -e "${HOME}/.claude/skills/${skill_name}/SKILL.md" ] || fail "missing Claude skill: $skill_name"
    [ -e "${OPENCODE_CONFIG_DIR}/skills/${skill_name}/SKILL.md" ] || fail "missing OpenCode skill: $skill_name"
done < "$lock_names"

for skill_dir in "$CUSTOM_SKILLS_DIR"/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name="$(basename "$skill_dir")"
    [ -e "${HOME}/.agents/skills/${skill_name}/SKILL.md" ] || fail "missing shared custom skill: $skill_name"
    [ -e "${HOME}/.claude/skills/${skill_name}/SKILL.md" ] || fail "missing Claude custom skill: $skill_name"
    [ -e "${OPENCODE_CONFIG_DIR}/skills/${skill_name}/SKILL.md" ] || fail "missing OpenCode custom skill: $skill_name"
done

for skill_file in "$CUSTOM_SKILLS_DIR"/*.skill; do
    [ -f "$skill_file" ] || continue
    skill_name="$(basename "$skill_file")"
    [ -e "${HOME}/.agents/skills/${skill_name}" ] || fail "missing shared custom skill file: $skill_name"
    [ -e "${HOME}/.claude/skills/${skill_name}" ] || fail "missing Claude custom skill file: $skill_name"
    [ -e "${OPENCODE_CONFIG_DIR}/skills/${skill_name}" ] || fail "missing OpenCode custom skill file: $skill_name"
done

[ -e "${CODEX_HOME}/AGENTS.md" ] || fail "missing Codex AGENTS.md"
[ -e "${HOME}/.claude/CLAUDE.md" ] || fail "missing Claude CLAUDE.md"
[ -e "${OPENCODE_CONFIG_DIR}/AGENTS.md" ] || fail "missing OpenCode AGENTS.md"

while IFS= read -r server_name; do
    [ -n "$server_name" ] || continue
    grep -F "[mcp_servers.${server_name}]" "${CODEX_HOME}/config.toml" >/dev/null 2>&1 || fail "missing Codex MCP server: $server_name"
done < <(jq -r 'keys[]' "$MCP_SERVERS_FILE")

jq -e '
    (.instructions | index("AGENTS.md")) and
    (.mcp | keys | sort) == ($mcp[0] | keys | sort)
' --slurpfile mcp "$MCP_SERVERS_FILE" "$OPENCODE_CONFIG" >/dev/null || fail "OpenCode config does not reflect shared instructions and MCP servers"

jq -e '
    (.mcpServers | keys | sort) == ($mcp[0] | keys | sort)
' --slurpfile mcp "$MCP_SERVERS_FILE" "${HOME}/.claude/settings.json" >/dev/null || fail "Claude settings do not reflect shared MCP servers"

while IFS= read -r server_name; do
    [ -n "$server_name" ] || continue
    server_type="$(jq -r --arg name "$server_name" '.[$name].type' "$MCP_SERVERS_FILE")"
    server_command="$(jq -r --arg name "$server_name" '.[$name].command // ""' "$MCP_SERVERS_FILE")"
    server_url="$(jq -r --arg name "$server_name" '.[$name].url // ""' "$MCP_SERVERS_FILE")"

    if [ "$server_type" = "http" ]; then
        grep -F "[mcp_servers.${server_name}]" "${CODEX_HOME}/config.toml" >/dev/null 2>&1 || fail "missing Codex HTTP MCP header: $server_name"
        grep -F "url = \"${server_url}\"" "${CODEX_HOME}/config.toml" >/dev/null 2>&1 || fail "missing Codex HTTP MCP url: $server_name"
        jq -e --arg name "$server_name" --arg url "$server_url" '
            .mcp[$name].type == "remote" and .mcp[$name].url == $url
        ' "$OPENCODE_CONFIG" >/dev/null || fail "OpenCode HTTP MCP mapping is wrong: $server_name"
    else
        grep -F "[mcp_servers.${server_name}]" "${CODEX_HOME}/config.toml" >/dev/null 2>&1 || fail "missing Codex stdio MCP header: $server_name"
        grep -F "command = \"${server_command}\"" "${CODEX_HOME}/config.toml" >/dev/null 2>&1 || fail "missing Codex stdio MCP command: $server_name"
        jq -e --arg name "$server_name" --arg command "$server_command" '
            .mcp[$name].type == "local" and .mcp[$name].command[0] == $command
        ' "$OPENCODE_CONFIG" >/dev/null || fail "OpenCode stdio MCP mapping is wrong: $server_name"
    fi
done < <(jq -r 'keys[]' "$MCP_SERVERS_FILE")

mkdir -p "$npx_home" "$npx_stub_dir"
ln -s "$JQ_BIN" "${npx_stub_dir}/jq"
: > "$npx_log"

cat > "${npx_stub_dir}/npx" <<'STUB'
#!/bin/sh
skill_name=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --skill)
            shift
            skill_name="$1"
            ;;
    esac
    shift
done

[ -n "$skill_name" ] || exit 1
echo "npx install ${skill_name}" >> "$NPX_LOG"
mkdir -p "${HOME}/.claude/skills/${skill_name}"
printf '# %s\n' "$skill_name" > "${HOME}/.claude/skills/${skill_name}/SKILL.md"
STUB
chmod +x "${npx_stub_dir}/npx"

export HOME="$npx_home"
export CODEX_HOME="${HOME}/.codex"
export OPENCODE_CONFIG_DIR="${HOME}/.config/opencode"
export OPENCODE_CONFIG="${OPENCODE_CONFIG_DIR}/opencode.json"
export NPX_LOG="$npx_log"
export SKILL_LOCK_REPO="$repo_lock_copy"
export CLAUDE_MANIFEST="$manifest_copy"
export PATH="${npx_stub_dir}:/usr/bin:/bin"

if ! "${DOTFILES_DIR}/sync-agents.sh" --quiet install > "$sync_log" 2>&1; then
    cat "$sync_log" >&2
    fail "sync-agents.sh install with npx stub failed"
fi

while IFS= read -r skill_name; do
    [ -n "$skill_name" ] || continue
    [ -e "${HOME}/.agents/skills/${skill_name}/SKILL.md" ] || fail "npx-installed skill missing shared runtime: $skill_name"
    [ -e "${HOME}/.claude/skills/${skill_name}/SKILL.md" ] || fail "npx-installed skill missing Claude runtime: $skill_name"
    [ -e "${OPENCODE_CONFIG_DIR}/skills/${skill_name}/SKILL.md" ] || fail "npx-installed skill missing OpenCode runtime: $skill_name"
done < "$lock_names"

if [ "$(wc -l < "$npx_log" | tr -d ' ')" != "$(wc -l < "$lock_names" | tr -d ' ')" ]; then
    cat "$npx_log" >&2
    fail "npx stub was not called once per missing lock-managed skill"
fi

mkdir -p "${legacy_home}/.agents/skills" "${legacy_home}/.claude/skills"
ln -s "$repo_lock_copy" "${legacy_home}/.agents/.skill-lock.json"

while IFS= read -r skill_name; do
    [ -n "$skill_name" ] || continue
    mkdir -p "${legacy_home}/.agents/skills/${skill_name}"
    printf '# %s\n' "$skill_name" > "${legacy_home}/.agents/skills/${skill_name}/SKILL.md"
done < "$lock_names"

export HOME="$legacy_home"
export CODEX_HOME="${HOME}/.codex"
export OPENCODE_CONFIG_DIR="${HOME}/.config/opencode"
export OPENCODE_CONFIG="${OPENCODE_CONFIG_DIR}/opencode.json"
export SKILL_LOCK_REPO="$repo_lock_copy"
export CLAUDE_MANIFEST="$manifest_copy"
export PATH="${stub_dir}:/usr/bin:/bin"

if ! "${DOTFILES_DIR}/sync-agents.sh" --quiet install > "$sync_log" 2>&1; then
    cat "$sync_log" >&2
    fail "sync-agents.sh install with legacy lock symlink failed"
fi

[ ! -L "${legacy_home}/.agents/.skill-lock.json" ] || fail "legacy live skill-lock symlink was not migrated to plain file"
[ -f "${legacy_home}/.agents/.skill-lock.json" ] || fail "legacy live skill-lock migration did not create plain file"
jq -e --slurpfile repo "$repo_lock_copy" '.skills | keys == ($repo[0].skills | keys)' "${legacy_home}/.agents/.skill-lock.json" >/dev/null || fail "migrated live skill-lock lost repo skill intent"

cat > "$env_mcp_file" <<'JSON'
{
  "env-stdio": {
    "type": "stdio",
    "command": "env-server",
    "args": ["--stdio"],
    "env": {
      "ENV_TOKEN": "literal-token"
    }
  },
  "env-http": {
    "type": "http",
    "url": "https://example.test/mcp"
  }
}
JSON

mkdir -p "$env_home" "$npx_stub_dir"
export HOME="$env_home"
export CODEX_HOME="${HOME}/.codex"
export OPENCODE_CONFIG_DIR="${HOME}/.config/opencode"
export OPENCODE_CONFIG="${OPENCODE_CONFIG_DIR}/opencode.json"
export MCP_SERVERS="$env_mcp_file"
export NPX_LOG="$npx_log"
export SKILL_LOCK_REPO="$repo_lock_copy"
export CLAUDE_MANIFEST="$manifest_copy"
export PATH="${npx_stub_dir}:/usr/bin:/bin"

mkdir -p "$CODEX_HOME"
cat > "${CODEX_HOME}/config.toml" <<'TOML'
[unrelated]
keep = true

[mcp_servers.env-stdio]
command = "old-env-server"
args = ["old"]

[mcp_servers.env-stdio.env]
ENV_TOKEN = "old-token"
TOML

if ! "${DOTFILES_DIR}/sync-agents.sh" --quiet install > "$sync_log" 2>&1; then
    cat "$sync_log" >&2
    fail "sync-agents.sh install with MCP env fixture failed"
fi

grep -F "[unrelated]" "${CODEX_HOME}/config.toml" >/dev/null 2>&1 || fail "Codex config stripping removed unrelated config"
if grep -F "old-env-server" "${CODEX_HOME}/config.toml" >/dev/null 2>&1 || grep -F "old-token" "${CODEX_HOME}/config.toml" >/dev/null 2>&1; then
    cat "${CODEX_HOME}/config.toml" >&2
    fail "Codex config stripping did not remove legacy MCP table/env"
fi
grep -F "[mcp_servers.env-stdio.env]" "${CODEX_HOME}/config.toml" >/dev/null 2>&1 || fail "Codex MCP env table missing"
grep -F "ENV_TOKEN = \"literal-token\"" "${CODEX_HOME}/config.toml" >/dev/null 2>&1 || fail "Codex MCP env value missing"
jq -e '.mcp["env-stdio"].environment.ENV_TOKEN == "literal-token"' "$OPENCODE_CONFIG" >/dev/null || fail "OpenCode MCP env value missing"
jq -e '.mcpServers["env-stdio"].env.ENV_TOKEN == "literal-token"' "${HOME}/.claude/settings.json" >/dev/null || fail "Claude MCP env value missing"

echo "[INFO] agent skill sync smoke test passed"

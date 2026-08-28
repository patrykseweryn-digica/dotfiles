#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYNC="${DOTFILES_DIR}/sync-agents.sh"
JUST_BIN="$(command -v just)"

fail() {
    echo "[ERROR] $*" >&2
    exit 1
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

home_dir="${tmp_dir}/home"
stub_dir="${tmp_dir}/stubs"
repo_mcp="${tmp_dir}/mcp-servers.json"
codex_mcp="${tmp_dir}/codex-mcp.json"
claude_config="${home_dir}/.claude.json"
claude_settings="${home_dir}/.claude/settings.json"
opencode_config="${home_dir}/.config/opencode/opencode.json"
kimi_config="${home_dir}/.kimi-code/mcp.json"
pi_mcp="${home_dir}/.agents/mcp.json"
mkdir -p \
    "${home_dir}/.codex" \
    "$(dirname "$opencode_config")" \
    "$(dirname "$kimi_config")" \
    "$(dirname "$pi_mcp")" \
    "$stub_dir"

cat > "$repo_mcp" <<'JSON'
{
  "shared": {
    "type": "http",
    "url": "https://shared.test/mcp"
  }
}
JSON

cat > "$codex_mcp" <<'JSON'
[
  {
    "name": "shared",
    "enabled": true,
    "transport": {
      "type": "streamable_http",
      "url": "https://shared.test/mcp"
    }
  },
  {
    "name": "codex-only",
    "enabled": true,
    "transport": {
      "type": "stdio",
      "command": "codex-server",
      "args": ["--stdio"]
    }
  }
]
JSON

cat > "$claude_config" <<'JSON'
{
  "keep": true,
  "mcpServers": {
    "shared": {
      "type": "http",
      "url": "https://shared.test/mcp"
    },
    "claude-only": {
      "type": "stdio",
      "command": "claude-server",
      "args": [],
      "env": {"SECRET_TOKEN": "must-not-enter-repo"}
    }
  }
}
JSON

cat > "$opencode_config" <<'JSON'
{
  "keep": true,
  "mcp": {
    "shared": {
      "type": "remote",
      "url": "https://shared.test/mcp",
      "enabled": true
    },
    "opencode-only": {
      "type": "local",
      "command": ["opencode-server", "--stdio"],
      "enabled": true
    }
  }
}
JSON

cat > "$kimi_config" <<'JSON'
{
  "keep": true,
  "mcpServers": {
    "shared": {"url": "https://shared.test/mcp"},
    "kimi-only": {"command": "kimi-server", "args": []}
  }
}
JSON

cat > "$pi_mcp" <<'JSON'
{
  "keep": true,
  "mcpServers": {
    "shared": {"url": "https://shared.test/mcp"},
    "pi-only": {
      "command": "pi-server",
      "args": [],
      "env": {"SECRET_TOKEN": "must-not-enter-repo"}
    }
  }
}
JSON

cat > "${stub_dir}/codex" <<'STUB'
#!/bin/bash
[ "$*" = "mcp list --json" ] || exit 1
cat "$CODEX_MCP_LIST"
STUB
chmod +x "${stub_dir}/codex"

export HOME="$home_dir"
export CODEX_HOME="${home_dir}/.codex"
export CODEX_MCP_LIST="$codex_mcp"
export CLAUDE_USER_CONFIG="$claude_config"
export CLAUDE_SETTINGS_FILE="$claude_settings"
OPENCODE_CONFIG_DIR="$(dirname "$opencode_config")"
export OPENCODE_CONFIG_DIR
export OPENCODE_CONFIG="$opencode_config"
export KIMI_MCP_CONFIG="$kimi_config"
export PI_MCP_CONFIG="$pi_mcp"
export MCP_SERVERS="$repo_mcp"
export PATH="${stub_dir}:/usr/bin:/bin"

cp "$repo_mcp" "${tmp_dir}/before-cancel.json"
if printf 'n\n' | "$SYNC" --quiet pull-mcp \
    > "${tmp_dir}/cancel.log" 2>&1; then
    fail "pull-mcp ignored cancelled confirmation"
fi
cmp -s "$repo_mcp" "${tmp_dir}/before-cancel.json" || \
    fail "pull-mcp wrote after cancelled confirmation"
grep -F 'codex-only' "${tmp_dir}/cancel.log" >/dev/null || \
    fail "pull-mcp did not preview the repository diff"

printf 'y\n' | "$SYNC" --quiet pull-mcp > "${tmp_dir}/pull.log"

jq -e '
  keys == ["claude-only", "codex-only", "kimi-only", "opencode-only", "pi-only", "shared"] and
  .["claude-only"] == {
    type: "stdio", command: "claude-server", args: []
  }
' "$repo_mcp" >/dev/null || fail "pull-mcp did not merge normalized runtimes"
if grep -F 'must-not-enter-repo' "$repo_mcp" >/dev/null; then
    fail "pull-mcp imported a credential"
fi

cp "$repo_mcp" "${tmp_dir}/before-conflict.json"
jq '.mcpServers.shared.url = "https://conflict.test/mcp"' \
    "$kimi_config" > "${tmp_dir}/kimi-conflict.json"
mv "${tmp_dir}/kimi-conflict.json" "$kimi_config"
if printf 'y\n' | "$SYNC" --quiet pull-mcp > "${tmp_dir}/conflict.log" 2>&1; then
    fail "pull-mcp accepted conflicting definitions"
fi
cmp -s "$repo_mcp" "${tmp_dir}/before-conflict.json" || \
    fail "pull-mcp wrote after a conflict"

cat > "$repo_mcp" <<'JSON'
{
  "local": {
    "type": "stdio",
    "command": "local-server",
    "args": ["--stdio"]
  },
  "remote": {
    "type": "http",
    "url": "https://remote.test/mcp"
  }
}
JSON
cat > "${CODEX_HOME}/config.toml" <<'TOML'
[unrelated]
keep = true
TOML
cat > "$claude_config" <<'JSON'
{
  "keep": true,
  "mcpServers": {
    "local": {
      "type": "stdio",
      "command": "local-server",
      "args": ["--stdio"],
      "env": {"LOCAL_TOKEN": "keep-local"}
    }
  }
}
JSON
mkdir -p "$(dirname "$claude_settings")"
cat > "$claude_settings" <<'JSON'
{
  "keep": true,
  "mcpServers": {"legacy": {"url": "https://legacy.test/mcp"}},
  "permissions": {"allow": ["Read", "mcp__legacy__*"]}
}
JSON
echo '{"keep":true}' > "$opencode_config"
echo '{"keep":true}' > "$kimi_config"
cat > "$pi_mcp" <<'JSON'
{
  "keep": true,
  "mcpServers": {
    "local": {
      "command": "local-server",
      "args": ["--stdio"],
      "disabled": true,
      "env": {"LOCAL_TOKEN": "keep-local"}
    }
  }
}
JSON

"$SYNC" --quiet push-mcp

grep -F '[unrelated]' "${CODEX_HOME}/config.toml" >/dev/null || \
    fail "push-mcp removed unrelated Codex config"
grep -F '[mcp_servers.local]' "${CODEX_HOME}/config.toml" >/dev/null || \
    fail "push-mcp omitted Codex MCP config"
jq -e '
  .keep and
  (.mcpServers | keys) == ["local", "remote"] and
  .mcpServers.local.env.LOCAL_TOKEN == "keep-local"
' "$claude_config" >/dev/null || \
    fail "push-mcp omitted Claude MCP config or local credentials"
jq -e '
  .keep and
  (.mcpServers == null) and
  .permissions.allow == ["Read", "mcp__local__*", "mcp__remote__*"]
' "$claude_settings" >/dev/null || \
    fail "push-mcp did not reconcile Claude MCP permissions"
jq -e '.keep and (.mcp | keys) == ["local", "remote"]' \
    "$opencode_config" >/dev/null || fail "push-mcp omitted OpenCode MCP config"
jq -e '.keep and (.mcpServers | keys) == ["local", "remote"]' \
    "$kimi_config" >/dev/null || fail "push-mcp omitted Kimi MCP config"
jq -e '
  .keep and
  (.mcpServers | keys) == ["local", "remote"] and
  .mcpServers.local.disabled == null and
  .mcpServers.local.env.LOCAL_TOKEN == "keep-local"
' "$pi_mcp" >/dev/null || \
    fail "push-mcp omitted Pi MCP config or local credentials"

pushed_hashes="$(sha256sum \
    "${CODEX_HOME}/config.toml" \
    "$claude_config" \
    "$claude_settings" \
    "$opencode_config" \
    "$kimi_config" \
    "$pi_mcp")"
"$SYNC" --quiet push-mcp
[ "$pushed_hashes" = "$(sha256sum \
    "${CODEX_HOME}/config.toml" \
    "$claude_config" \
    "$claude_settings" \
    "$opencode_config" \
    "$kimi_config" \
    "$pi_mcp")" ] || fail "push-mcp is not idempotent"

cat > "$codex_mcp" <<'JSON'
[
  {
    "name": "remote",
    "enabled": true,
    "transport": {
      "url": "https://remote.test/mcp",
      "type": "streamable_http"
    }
  },
  {
    "name": "local",
    "enabled": true,
    "transport": {
      "args": ["--stdio"],
      "command": "local-server",
      "type": "stdio"
    }
  }
]
JSON
"$SYNC" --quiet mcp-check
jq '.mcpServers.extra = {url: "https://extra.test/mcp"}' \
    "$kimi_config" > "${tmp_dir}/kimi-extra.json"
mv "${tmp_dir}/kimi-extra.json" "$kimi_config"
if "$SYNC" --quiet mcp-check > "${tmp_dir}/check.log" 2>&1; then
    fail "mcp-check ignored semantic drift"
fi

cat > "${stub_dir}/sync-agents" <<'STUB'
#!/bin/bash
printf '%s\n' "$1" >> "$SYNC_LOG"
[ "$1" != "${FAIL_SYNC:-}" ]
STUB
chmod +x "${stub_dir}/sync-agents"

sync_log="${tmp_dir}/push.log"
if SYNC_AGENTS="${stub_dir}/sync-agents" \
    SYNC_LOG="$sync_log" \
    FAIL_SYNC=push-skills \
    "$JUST_BIN" --justfile "${DOTFILES_DIR}/justfile" push \
    > "${tmp_dir}/just-push.log" 2>&1; then
    fail "just push passed when a category failed"
fi
[ "$(cat "$sync_log")" = $'push-mcp\npush-skills\npush-plugins' ] || \
    fail "just push did not invoke every category in order"

"$JUST_BIN" --justfile "${DOTFILES_DIR}/justfile" --list | \
    grep -Eq '^    (pull|push)-(mcp|skills|plugins)' || \
    fail "symmetric sync commands missing from just"
if "$JUST_BIN" --justfile "${DOTFILES_DIR}/justfile" --list | \
    grep -Eq '^    pull[[:space:]]'; then
    fail "broad pull command must not exist"
fi

echo "[INFO] agent sync interface smoke test passed"

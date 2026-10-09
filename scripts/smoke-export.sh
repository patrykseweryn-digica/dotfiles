#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYNC="${DOTFILES_DIR}/sync-agents.sh"
JUST_BIN="$(command -v just)"
UV_BIN="$(command -v uv)"
UV_CACHE_REAL="${UV_CACHE_DIR:-$("$UV_BIN" cache dir)}"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

fail() {
    echo "[ERROR] $*" >&2
    exit 1
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
checkout="${tmp_dir}/checkout"
home_dir="${tmp_dir}/home"
stub_dir="${tmp_dir}/stubs"
mkdir -p \
    "${checkout}/config/codex" \
    "${checkout}/config/claude" \
    "${checkout}/config/opencode" \
    "${checkout}/config/pi" \
    "${checkout}/.agents" \
    "${home_dir}/.codex" \
    "${home_dir}/.claude" \
    "${home_dir}/.config/opencode" \
    "${home_dir}/.pi/agent" \
    "${home_dir}/.agents" \
    "$stub_dir"

codex_template="${checkout}/config/codex/settings.toml"
claude_template="${checkout}/config/claude/settings.json"
opencode_template="${checkout}/config/opencode/opencode.json"
pi_template="${checkout}/config/pi/settings.json"
repo_mcp="${checkout}/.agents/mcp-servers.json"
codex_live="${home_dir}/.codex/config.toml"
claude_live="${home_dir}/.claude/settings.json"
claude_user="${home_dir}/.claude.json"
opencode_live="${home_dir}/.config/opencode/opencode.json"
pi_live="${home_dir}/.pi/agent/settings.json"
pi_mcp="${home_dir}/.agents/mcp.json"
codex_mcp="${tmp_dir}/codex-mcp.json"

cat >"$codex_template" <<'TOML'
model = "repo-codex"
[tui]
status_line = ["model"]
TOML
cat >"$claude_template" <<'JSON'
{
  "env": {"SAFE": "repo"},
  "model": "repo-claude",
  "permissions": {"allow": ["Read"]}
}
JSON
cat >"$opencode_template" <<'JSON'
{
  "model": "repo-opencode",
  "provider": {"ollama": {"options": {"baseURL": "http://repo.test"}}}
}
JSON
cat >"$pi_template" <<'JSON'
{
  "packages": ["npm:example@1"],
  "terminal": {"trueColor": false},
  "theme": "repo-theme"
}
JSON
printf '{}\n' >"$repo_mcp"
printf 'clean\n' >"${checkout}/marker"

cat >"$codex_live" <<'TOML'
model = "live-codex"
oauth_token = "must-not-enter-repo"
[tui]
status_line = ["git-branch", "model"]
[projects."/Users/local/project"]
trust_level = "trusted"
TOML
cat >"$claude_live" <<'JSON'
{
  "cacheDir": "/Users/local/cache",
  "env": {"SAFE": "live", "SECRET_TOKEN": "must-not-enter-repo"},
  "model": "live-claude",
  "oauthToken": "must-not-enter-repo",
  "permissions": {"allow": ["Read", "mcp__shared__*"]}
}
JSON
cat >"$claude_user" <<'JSON'
{
  "mcpServers": {
    "claude-only": {
      "args": [],
      "command": "claude-server",
      "env": {"SECRET_TOKEN": "must-not-enter-repo"},
      "type": "stdio"
    },
    "shared": {"type": "http", "url": "https://shared.test/mcp"}
  },
  "oauthAccount": {"token": "must-not-enter-repo"}
}
JSON
cat >"$opencode_live" <<'JSON'
{
  "mcp": {
    "opencode-only": {
      "command": ["opencode-server", "--stdio"],
      "enabled": true,
      "type": "local"
    },
    "shared": {
      "enabled": true,
      "type": "remote",
      "url": "https://shared.test/mcp"
    }
  },
  "model": "live-opencode",
  "provider": {"ollama": {"options": {"baseURL": "http://live.test"}}},
  "session": {"token": "must-not-enter-repo"}
}
JSON
cat >"$pi_live" <<'JSON'
{
  "authToken": "must-not-enter-repo",
  "packages": ["npm:example@2"],
  "terminal": {"trueColor": true},
  "theme": "live-theme"
}
JSON
cat >"$pi_mcp" <<'JSON'
{
  "mcpServers": {
    "pi-only": {
      "args": [],
      "command": "pi-server",
      "env": {"SECRET_TOKEN": "must-not-enter-repo"}
    },
    "shared": {"url": "https://shared.test/mcp"}
  }
}
JSON
cat >"$codex_mcp" <<'JSON'
[
  {
    "enabled": true,
    "name": "codex-only",
    "transport": {"args": [], "command": "codex-server", "type": "stdio"}
  },
  {
    "enabled": true,
    "name": "shared",
    "transport": {"type": "http", "url": "https://shared.test/mcp"}
  }
]
JSON

cat >"${stub_dir}/codex" <<'STUB'
#!/bin/bash
set -eu
[ "$*" = "mcp list --json" ]
cat "$CODEX_MCP_LIST"
STUB
cat >"${stub_dir}/cp" <<'STUB'
#!/bin/bash
set -eu
destination=""
for argument in "$@"; do destination="$argument"; done
if [ -n "${FAIL_COPY_TARGET:-}" ] && [ "$destination" = "$FAIL_COPY_TARGET" ] &&
    [ ! -e "$FAIL_COPY_MARKER" ]; then
    : >"$FAIL_COPY_MARKER"
    exit 1
fi
exec /bin/cp "$@"
STUB
chmod +x "${stub_dir}/codex" "${stub_dir}/cp"

git -C "$checkout" init -q
git -C "$checkout" config user.name smoke
git -C "$checkout" config user.email smoke@example.test
git -C "$checkout" add .
git -C "$checkout" commit -qm initial
initial_head="$(git -C "$checkout" rev-parse HEAD)"

export HOME="$home_dir"
export UV_CACHE_DIR="$UV_CACHE_REAL"
export PATH="${stub_dir}:$PATH"
export SYNC_AGENTS="$SYNC"
export EXPORT_GIT_DIR="$checkout"
export CODEX_HOME="${home_dir}/.codex"
export CODEX_CONFIG="$codex_live"
export CODEX_SETTINGS_TEMPLATE="$codex_template"
export CODEX_MCP_LIST="$codex_mcp"
export CLAUDE_SETTINGS_FILE="$claude_live"
export CLAUDE_USER_CONFIG="$claude_user"
export CLAUDE_TEMPLATE_FILE="$claude_template"
export OPENCODE_CONFIG_DIR="${home_dir}/.config/opencode"
export OPENCODE_CONFIG="$opencode_live"
export OPENCODE_TEMPLATE="$opencode_template"
export PI_CODING_AGENT_DIR="${home_dir}/.pi/agent"
export PI_SETTINGS_FILE="$pi_live"
export PI_SETTINGS_TEMPLATE="$pi_template"
export PI_MCP_CONFIG="$pi_mcp"
export MCP_SERVERS="$repo_mcp"

run_export() {
    local answer="$1" output="$2"
    shift 2
    printf '%s\n' "$answer" | env "$@" \
        "$JUST_BIN" --justfile "${DOTFILES_DIR}/justfile" export \
        >"$output" 2>&1
}

# Dirty checkout wins before any live candidate is parsed.
printf 'dirty\n' >"${checkout}/marker"
printf 'not valid toml\n' >"$codex_live"
if run_export y "${tmp_dir}/dirty.log"; then
    fail "export accepted a dirty checkout"
fi
grep -F 'clean checkout' "${tmp_dir}/dirty.log" >/dev/null ||
    fail "dirty checkout error missing"
printf 'clean\n' >"${checkout}/marker"
cat >"$codex_live" <<'TOML'
model = "live-codex"
oauth_token = "must-not-enter-repo"
[tui]
status_line = ["git-branch", "model"]
[projects."/Users/local/project"]
trust_level = "trusted"
TOML

# One refusal changes neither the checkout nor live state.
find "$home_dir" -type f -exec cksum {} \; | sort >"${tmp_dir}/live.before"
if run_export n "${tmp_dir}/cancel.log"; then
    fail "export ignored cancelled confirmation"
fi
[ -z "$(git -C "$checkout" status --porcelain --untracked-files=all)" ] ||
    fail "cancelled export changed checkout"
for label in 'Codex settings' 'Claude settings' 'OpenCode settings' \
    'Pi settings' 'MCP inventory'; do
    grep -F "[PLAN] $label:" "${tmp_dir}/cancel.log" >/dev/null ||
        { cat "${tmp_dir}/cancel.log" >&2; fail "export plan omitted: $label"; }
done
find "$home_dir" -type f -exec cksum {} \; | sort >"${tmp_dir}/live.after"
cmp "${tmp_dir}/live.before" "${tmp_dir}/live.after" ||
    fail "cancelled export changed live state"

# Conflicting runtime MCP definitions stop the whole transaction.
jq '.mcpServers.shared.url = "https://conflict.test/mcp"' "$claude_user" \
    >"${tmp_dir}/claude-conflict.json"
mv "${tmp_dir}/claude-conflict.json" "$claude_user"
if run_export y "${tmp_dir}/conflict.log"; then
    fail "export accepted conflicting MCP definitions"
fi
grep -F 'Conflicting MCP definitions' "${tmp_dir}/conflict.log" >/dev/null ||
    fail "MCP conflict was not reported"
[ -z "$(git -C "$checkout" status --porcelain --untracked-files=all)" ] ||
    fail "MCP conflict changed checkout"
jq '.mcpServers.shared.url = "https://shared.test/mcp"' "$claude_user" \
    >"${tmp_dir}/claude-restored.json"
mv "${tmp_dir}/claude-restored.json" "$claude_user"

# Local filesystem paths are never portable MCP state.
jq --arg command "$HOME/bin/pi-server" \
    '.mcpServers["pi-only"].command = $command' "$pi_mcp" \
    >"${tmp_dir}/pi-local.json"
mv "${tmp_dir}/pi-local.json" "$pi_mcp"
if run_export y "${tmp_dir}/local-path.log"; then
    fail "export accepted a local MCP path"
fi
grep -F 'local path or secret' "${tmp_dir}/local-path.log" >/dev/null ||
    fail "local MCP path was not reported"
jq '.mcpServers["pi-only"].command = "pi-server"' "$pi_mcp" \
    >"${tmp_dir}/pi-restored.json"
mv "${tmp_dir}/pi-restored.json" "$pi_mcp"
find "$home_dir" -type f -exec cksum {} \; | sort \
    >"${tmp_dir}/live.apply-before"

# An apply failure restores every checkout target.
if run_export y "${tmp_dir}/rollback.log" \
    FAIL_COPY_TARGET="$claude_template" \
    FAIL_COPY_MARKER="${tmp_dir}/copy-failed"; then
    fail "export ignored an apply failure"
fi
grep -F 'rolling back checkout' "${tmp_dir}/rollback.log" >/dev/null ||
    fail "export did not report rollback"
[ -z "$(git -C "$checkout" status --porcelain --untracked-files=all)" ] ||
    fail "failed export did not restore checkout"

# Approval updates only the checkout and leaves Git index/history untouched.
run_export y "${tmp_dir}/apply.log" || {
    cat "${tmp_dir}/apply.log" >&2
    fail "approved export failed"
}
jq -e '
    .model == "live-claude" and
    .env == {SAFE: "live"} and
    .permissions.allow == ["Read"] and
    (has("oauthToken") | not)
' "$claude_template" >/dev/null || fail "Claude allowlist export failed"
jq -e '
    .model == "live-opencode" and
    .provider.ollama.options.baseURL == "http://live.test" and
    (has("session") | not) and (has("mcp") | not)
' "$opencode_template" >/dev/null || fail "OpenCode allowlist export failed"
jq -e '
    .theme == "live-theme" and .terminal.trueColor == true and
    .packages == ["npm:example@2"] and (has("authToken") | not)
' "$pi_template" >/dev/null || fail "Pi allowlist export failed"
grep -F 'model = "live-codex"' "$codex_template" >/dev/null ||
    fail "Codex allowlist export failed"
if grep -F 'must-not-enter-repo' \
    "$codex_template" "$claude_template" "$opencode_template" \
    "$pi_template" "$repo_mcp" >/dev/null; then
    fail "export wrote a credential"
fi
if grep -F "$HOME/" \
    "$codex_template" "$claude_template" "$opencode_template" \
    "$pi_template" "$repo_mcp" >/dev/null; then
    fail "export wrote a local path"
fi
jq -e '
    keys == ["claude-only", "codex-only", "opencode-only", "pi-only", "shared"] and
    .["claude-only"] == {
      type: "stdio", command: "claude-server", args: []
    }
' "$repo_mcp" >/dev/null || fail "MCP export was not normalized"
git -C "$checkout" diff --cached --quiet || fail "export staged changes"
[ "$(git -C "$checkout" rev-parse HEAD)" = "$initial_head" ] ||
    fail "export created a commit"
git -C "$checkout" status --porcelain | awk '{print $2}' | sort \
    >"${tmp_dir}/changed"
printf '%s\n' \
    .agents/mcp-servers.json \
    config/claude/settings.json \
    config/codex/settings.toml \
    config/opencode/opencode.json \
    config/pi/settings.json | sort >"${tmp_dir}/expected-changed"
cmp "${tmp_dir}/expected-changed" "${tmp_dir}/changed" ||
    fail "export changed files outside its plan"
find "$home_dir" -type f -exec cksum {} \; | sort >"${tmp_dir}/live.final"
cmp "${tmp_dir}/live.apply-before" "${tmp_dir}/live.final" ||
    fail "approved export changed live state"

echo "[INFO] transactional export smoke test passed"

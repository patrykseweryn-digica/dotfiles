#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${DOTFILES_DIR}/scripts/host-tools.sh"
SYNC="${DOTFILES_DIR}/sync-agents.sh"
JUST_BIN="$(command -v just)"
UV_BIN="$(command -v uv)"
REAL_GIT="$(command -v git)"
UV_CACHE_REAL="${UV_CACHE_DIR:-$("$UV_BIN" cache dir)}"
UV_PYTHON_REAL="${UV_PYTHON_INSTALL_DIR:-$("$UV_BIN" python dir)}"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

fail() {
    echo "[ERROR] $*" >&2
    exit 1
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
# The machine group setting must not change fixture results.
export DOTFILES_ENV_FILE="${tmp_dir}/all-groups.env"
printf 'DOTFILES_GROUPS=core,agents,desktop\n' >"$DOTFILES_ENV_FILE"
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
    "${home_dir}/.claude/plugins" \
    "${home_dir}/.config/opencode" \
    "${home_dir}/.pi/agent" \
    "${home_dir}/.agents/skills" \
    "${home_dir}/tool-bin" \
    "${home_dir}/lib/node_modules/portable-cli/bin" \
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
skill_lock_repo="${checkout}/.agents/skill-lock.json"
skill_lock_live="${home_dir}/.agents/.skill-lock.json"
plugin_manifest="${checkout}/.agents/plugin-manifest.json"
tool_manifest="${checkout}/.agents/tool-versions.json"
tool_bin="${home_dir}/tool-bin"
codex_cache="${home_dir}/.codex/plugins/cache"
codex_plugins="${tmp_dir}/codex-plugins.json"
codex_marketplaces="${tmp_dir}/codex-marketplaces.json"
claude_plugins="${home_dir}/.claude/plugins/installed_plugins.json"
claude_marketplaces="${home_dir}/.claude/plugins/known_marketplaces.json"
skill_test_log="${tmp_dir}/skill-calls.log"

cat >"$codex_template" <<'TOML'
model = "repo-codex"
[tui]
status_line = ["model"]
TOML
cat >"$claude_template" <<'JSON'
{
  "env": {"SAFE": "repo"},
  "hooks": {"SessionStart": [{"hooks": [{
    "command": "bash \"$HOME/.claude/hooks/herdr-agent-state.sh\" session",
    "timeout": 10, "type": "command"}], "matcher": "*"}]},
  "model": "repo-claude",
  "permissions": {"allow": ["Read"]}
}
JSON
cat >"$opencode_template" <<'JSON'
{
  "model": "repo-opencode",
  "preserveWhenMissing": "repo",
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
cat >"$repo_mcp" <<'JSON'
{
  "shared": {"type": "http", "url": "https://repo.test/mcp"}
}
JSON
printf 'clean\n' >"${checkout}/marker"

cat >"$skill_lock_repo" <<'JSON'
{
  "dismissed": {},
  "skills": {
    "managed-skill": {
      "skillPath": "package/skills/managed-skill/SKILL.md",
      "source": "example/skills",
      "sourceType": "github",
      "sourceUrl": "https://github.com/example/skills.git"
    }
  }
}
JSON
# Live records an older upstream path; the repository decides how to install.
cat >"$skill_lock_live" <<'JSON'
{
  "dismissed": {},
  "skills": {
    "managed-skill": {
      "installedAt": "local",
      "skillFolderHash": "local",
      "skillPath": "old/managed-skill/SKILL.md",
      "source": "example/skills",
      "sourceType": "github",
      "sourceUrl": "https://github.com/example/skills.git"
    },
    "new-managed": {
      "commit": "0123456789abcdef0123456789abcdef01234567",
      "installedAt": "local",
      "skillFolderHash": "local",
      "skillPath": "package/skills/new-managed/SKILL.md",
      "source": "example/skills",
      "sourceType": "github",
      "sourceUrl": "https://github.com/example/skills.git"
    }
  }
}
JSON
for skill in managed-skill new-managed; do
    mkdir -p "${home_dir}/.agents/skills/${skill}"
    printf '%s\n' '---' "name: $skill" '---' \
        >"${home_dir}/.agents/skills/${skill}/SKILL.md"
done

cat >"$plugin_manifest" <<'JSON'
{
  "codexMarketplaces": {
    "third": "https://github.com/example/plugins.git"
  },
  "codexPlugins": ["keep-market@third"],
  "marketplaces": {
    "third": {"repo": "example/plugins", "source": "github"}
  },
  "plugins": {
    "keep": {"claude": "keep@third", "codex": "plugin_keep"}
  }
}
JSON
cat >"$tool_manifest" <<'JSON'
{
  "tools": [
    {
      "channel": "latest",
      "command": "known-cli",
      "group": "agents",
      "installer": "npm",
      "name": "known-cli",
      "package": "known-cli"
    }
  ]
}
JSON
cat >"${home_dir}/lib/node_modules/portable-cli/package.json" <<'JSON'
{
  "name": "portable-cli",
  "bin": {"portable-cli": "bin/portable-cli.js"}
}
JSON
printf '#!/bin/sh\nexit 0\n' \
    >"${home_dir}/lib/node_modules/portable-cli/bin/portable-cli.js"
chmod +x "${home_dir}/lib/node_modules/portable-cli/bin/portable-cli.js"
ln -s ../lib/node_modules/portable-cli/bin/portable-cli.js \
    "${tool_bin}/portable-cli"
printf '#!/bin/sh\nexit 0\n' >"${tool_bin}/manual-tool"
chmod +x "${tool_bin}/manual-tool"
mkdir -p "$codex_cache/keep" "$codex_cache/new-codex"
printf '%s\n' '{"schema_version":1,"remote_plugin_id":"plugin_keep"}' \
    >"$codex_cache/keep/.codex-remote-plugin-install.json"
printf '%s\n' '{"schema_version":1,"remote_plugin_id":"plugin_new"}' \
    >"$codex_cache/new-codex/.codex-remote-plugin-install.json"
cat >"$codex_plugins" <<'JSON'
{"installed":[
  {"enabled":true,"installed":true,"pluginId":"keep-market@third",
   "marketplaceName":"third",
   "marketplaceSource":{"source":"https://github.com/example/plugins.git",
                        "sourceType":"git"}},
  {"enabled":true,"installed":true,"pluginId":"new-market@third",
   "marketplaceName":"third",
   "marketplaceSource":{"source":"https://github.com/example/plugins.git",
                        "sourceType":"git"}}
]}
JSON
cat >"$codex_marketplaces" <<'JSON'
{"marketplaces":[
  {"name":"third","marketplaceSource":{
    "source":"https://github.com/example/plugins.git","sourceType":"git"}}
]}
JSON
cat >"$claude_plugins" <<'JSON'
{"plugins":{
  "keep@third":[{"scope":"user"}],
  "new-claude@third":[{"scope":"user"}]
}}
JSON
cat >"$claude_marketplaces" <<'JSON'
{"third":{"source":{"repo":"example/plugins","source":"github"}}}
JSON

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
# Herdr appends its own absolute-path hook next to the portable one.
jq --slurpfile repo "$claude_template" \
    --arg hook "${home_dir}/.claude/hooks/herdr-agent-state.sh" '
    .hooks.SessionStart = $repo[0].hooks.SessionStart + [{
        hooks: [{command: "bash '"'"'\($hook)'"'"' session",
            timeout: 10, type: "command"}],
        matcher: "^(startup|resume|clear|compact|fork)$"}]
' "$claude_live" >"${claude_live}.tmp"
mv "${claude_live}.tmp" "$claude_live"
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
  "apiKeys": {"fixture": "must-not-enter-repo"},
  "authToken": "must-not-enter-repo",
  "deviceId": "local-device",
  "packages": ["npm:example@2"],
  "terminal": {"trueColor": true},
  "theme": "live-theme",
  "trackingId": "local-tracking"
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
    "transport": {
      "args": [],
      "command": "/Users/local/bin/codex-server",
      "type": "stdio"
    }
  },
  {
    "enabled": true,
    "name": "codex-portable",
    "transport": {
      "args": ["--stdio"],
      "command": "codex-server",
      "type": "stdio"
    }
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
cat >"${stub_dir}/skills" <<'STUB'
#!/bin/bash
set -eu
printf '%s\n' "$*" >>"$SKILL_TEST_LOG"
[ "${SKILL_STAGE_FAIL:-false}" = false ] || exit 1
skills=()
collect=false
for argument in "$@"; do
    if [ "$argument" = --skill ]; then
        collect=true
        continue
    fi
    if [ "$argument" = --agent ]; then
        collect=false
    fi
    [ "$collect" = true ] && skills+=("$argument")
done
for skill in "${skills[@]}"; do
    mkdir -p "$HOME/.agents/skills/$skill"
    printf '%s\n' '---' "name: $skill" '---' \
        >"$HOME/.agents/skills/$skill/SKILL.md"
done
STUB
cat >"${stub_dir}/git" <<'STUB'
#!/bin/bash
set -eu
if [ "$1" = clone ]; then
    checkout="${*: -1}"
    mkdir -p "$checkout/moved/new-managed"
    printf '%s\n' '---' 'name: new-managed' '---' \
        >"$checkout/moved/new-managed/SKILL.md"
    if [ "${SKILL_UPSTREAM_REMOVED:-false}" != true ]; then
        mkdir -p "$checkout/moved/managed-skill"
        printf '%s\n' '---' 'name: managed-skill' '---' \
            >"$checkout/moved/managed-skill/SKILL.md"
    fi
    exit 0
fi
exec "$REAL_GIT" "$@"
STUB
# The real GitHub CLI writes state into HOME; export must not change HOME.
printf '#!/bin/sh\necho "not logged in" >&2\nexit 1\n' >"${stub_dir}/gh"
chmod +x "${stub_dir}/codex" "${stub_dir}/cp" "${stub_dir}/skills" \
    "${stub_dir}/git" "${stub_dir}/gh"

git -C "$checkout" init -q
git -C "$checkout" config user.name smoke
git -C "$checkout" config user.email smoke@example.test
git -C "$checkout" add .
git -C "$checkout" commit -qm initial
initial_head="$(git -C "$checkout" rev-parse HEAD)"

export HOME="$home_dir"
export UV_CACHE_DIR="$UV_CACHE_REAL"
export UV_PYTHON_INSTALL_DIR="$UV_PYTHON_REAL"
export REAL_GIT
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
export SKILL_LOCK_REPO="$skill_lock_repo"
export SKILL_LOCK_LIVE="$skill_lock_live"
export SKILLS_CLI="${stub_dir}/skills"
export SKILL_TEST_LOG="$skill_test_log"
export PLUGIN_MANIFEST="$plugin_manifest"
export CLAUDE_MANIFEST="$plugin_manifest"
export CODEX_PLUGIN_MANIFEST="$plugin_manifest"
export CODEX_REMOTE_PLUGIN_CACHE="$codex_cache"
export CODEX_PLUGIN_LIST_FILE="$codex_plugins"
export CODEX_MARKETPLACE_LIST_FILE="$codex_marketplaces"
export TOOL_INVENTORY="$tool_manifest"
export TOOL_EXPORT_BIN_DIRS="$tool_bin"

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
    'Pi settings' 'MCP inventory' 'Skill inventory' \
    'Plugin membership' 'Tool inventory'; do
    grep -F "[PLAN] $label:" "${tmp_dir}/cancel.log" >/dev/null ||
        { cat "${tmp_dir}/cancel.log" >&2; fail "export plan omitted: $label"; }
done
grep -F '[CANDIDATE] Tool manual-tool needs a source and installer' \
    "${tmp_dir}/cancel.log" >/dev/null ||
    fail "unknown binary was not reported for manual description"
find "$home_dir" -type f -exec cksum {} \; | sort >"${tmp_dir}/live.after"
cmp "${tmp_dir}/live.before" "${tmp_dir}/live.after" ||
    fail "cancelled export changed live state"

# Conflicting unmanaged MCP definitions stop the whole transaction.
jq '.mcpServers["runtime-conflict"] = {
      type: "http", url: "https://claude-conflict.test/mcp"
    }' "$claude_user" \
    >"${tmp_dir}/claude-conflict.json"
mv "${tmp_dir}/claude-conflict.json" "$claude_user"
jq '.mcpServers["runtime-conflict"] = {
      url: "https://pi-conflict.test/mcp"
    }' "$pi_mcp" >"${tmp_dir}/pi-conflict.json"
mv "${tmp_dir}/pi-conflict.json" "$pi_mcp"
if run_export y "${tmp_dir}/conflict.log"; then
    fail "export accepted conflicting MCP definitions"
fi
grep -F 'Conflicting MCP definitions' "${tmp_dir}/conflict.log" >/dev/null ||
    fail "MCP conflict was not reported"
[ -z "$(git -C "$checkout" status --porcelain --untracked-files=all)" ] ||
    fail "MCP conflict changed checkout"
jq 'del(.mcpServers["runtime-conflict"])' "$claude_user" \
    >"${tmp_dir}/claude-restored.json"
mv "${tmp_dir}/claude-restored.json" "$claude_user"
jq 'del(.mcpServers["runtime-conflict"])' "$pi_mcp" \
    >"${tmp_dir}/pi-conflict-restored.json"
mv "${tmp_dir}/pi-conflict-restored.json" "$pi_mcp"

# Unmanaged local MCP paths stay local and do not block the export plan.
jq --arg command "$HOME/bin/pi-server" \
    '.mcpServers["pi-only"].command = $command' "$pi_mcp" \
    >"${tmp_dir}/pi-local.json"
mv "${tmp_dir}/pi-local.json" "$pi_mcp"
if run_export n "${tmp_dir}/local-path.log"; then
    fail "cancelled export with local MCP state succeeded"
fi
grep -F '[PLAN] MCP inventory:' "${tmp_dir}/local-path.log" >/dev/null ||
    fail "local MCP state blocked the export plan"
if grep -F 'local path or secret' "${tmp_dir}/local-path.log" >/dev/null; then
    fail "unmanaged local MCP state was treated as export data"
fi
jq '.mcpServers["pi-only"].command = "pi-server"' "$pi_mcp" \
    >"${tmp_dir}/pi-restored.json"
mv "${tmp_dir}/pi-restored.json" "$pi_mcp"

# Removing or renaming a managed skill cannot become an accidental export.
mv "${home_dir}/.agents/skills/managed-skill" \
    "${tmp_dir}/managed-skill.saved"
if run_export y "${tmp_dir}/removed-skill.log"; then
    fail "export accepted a removed managed skill"
fi
grep -F 'Removed or renamed managed skills' \
    "${tmp_dir}/removed-skill.log" >/dev/null ||
    fail "removed managed skill was not reported"
mv "${tmp_dir}/managed-skill.saved" \
    "${home_dir}/.agents/skills/managed-skill"
[ -z "$(git -C "$checkout" status --porcelain --untracked-files=all)" ] ||
    fail "removed skill check changed checkout"

# A live skill without an upstream source has nowhere to be exported to.
mkdir -p "${home_dir}/.agents/skills/local-only"
printf '%s\n' '---' 'name: local-only' '---' \
    >"${home_dir}/.agents/skills/local-only/SKILL.md"
if run_export y "${tmp_dir}/unmanaged-skill.log"; then
    fail "export accepted a skill without an upstream source"
fi
grep -F 'Live skills without an upstream source' \
    "${tmp_dir}/unmanaged-skill.log" >/dev/null ||
    fail "skill without an upstream source was not reported"
grep -F -- '  - local-only' "${tmp_dir}/unmanaged-skill.log" >/dev/null ||
    fail "skill without an upstream source was not named"
rm -rf "${home_dir}/.agents/skills/local-only"
[ -z "$(git -C "$checkout" status --porcelain --untracked-files=all)" ] ||
    fail "unmanaged skill check changed checkout"

# Export accepts a removal only when the name is absent from current upstream.
mv "${home_dir}/.agents/skills/managed-skill" \
    "${tmp_dir}/managed-skill.saved"
export SKILL_UPSTREAM_REMOVED=true
if run_export n "${tmp_dir}/upstream-removed-skill.log"; then
    fail "cancelled upstream skill export succeeded"
fi
unset SKILL_UPSTREAM_REMOVED
grep -F 'Accepting upstream-removed or renamed skill: managed-skill' \
    "${tmp_dir}/upstream-removed-skill.log" >/dev/null ||
    fail "verified upstream skill removal was not accepted"
grep -F '[PLAN] Skill inventory:' \
    "${tmp_dir}/upstream-removed-skill.log" >/dev/null ||
    fail "verified upstream skill removal omitted the export plan"
mv "${tmp_dir}/managed-skill.saved" \
    "${home_dir}/.agents/skills/managed-skill"

# Plugin provider ownership is checked before the transaction can write.
cp "$claude_plugins" "${tmp_dir}/claude-plugins.saved"
jq '.plugins["foreign@openai-bundled"] = [{"scope":"user"}]' \
    "$claude_plugins" >"${tmp_dir}/foreign-plugin.json"
mv "${tmp_dir}/foreign-plugin.json" "$claude_plugins"
if run_export y "${tmp_dir}/provider.log"; then
    fail "export accepted a plugin from the wrong provider"
fi
grep -F 'Provider-specific marketplaces' "${tmp_dir}/provider.log" \
    >/dev/null || fail "plugin provider error was not reported"
mv "${tmp_dir}/claude-plugins.saved" "$claude_plugins"
[ -z "$(git -C "$checkout" status --porcelain --untracked-files=all)" ] ||
    fail "plugin provider check changed checkout"

[ ! -s "$skill_test_log" ] ||
    fail "export staged skills before approval"

if run_export y "${tmp_dir}/failed-preflight.log" SKILL_STAGE_FAIL=true; then
    fail "export accepted an unavailable skill source"
fi
[ -z "$(git -C "$checkout" status --porcelain --untracked-files=all)" ] ||
    fail "failed skill preflight changed checkout"
grep -E -- '--skill managed-skill new-managed --agent codex' \
    "$skill_test_log" >/dev/null ||
    fail "approved export did not preflight every managed skill"
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
    [.hooks.SessionStart[].hooks[].command] ==
        ["bash \"$HOME/.claude/hooks/herdr-agent-state.sh\" session"]
' "$claude_template" >/dev/null ||
    fail "Claude export kept a Herdr absolute-path hook"
jq -e '
    .model == "live-opencode" and
    .preserveWhenMissing == "repo" and
    .provider.ollama.options.baseURL == "http://live.test" and
    (has("session") | not) and (has("mcp") | not)
' "$opencode_template" >/dev/null || fail "OpenCode allowlist export failed"
jq -e '
    . as $settings |
    $settings.theme == "live-theme" and
    $settings.terminal.trueColor == true and
    $settings.packages == ["npm:example"] and
    (["apiKeys", "authToken", "deviceId", "trackingId"] |
        all(. as $key | $settings | has($key) | not))
' "$pi_template" >/dev/null || fail "Pi allowlist export failed"
grep -F 'model = "live-codex"' "$codex_template" >/dev/null ||
    fail "Codex allowlist export failed"
jq -e '
    (.skills | keys) == ["managed-skill", "new-managed"] and
    .skills["managed-skill"].skillPath ==
        "package/skills/managed-skill/SKILL.md" and
    (.skills | all(has("commit") | not))
' "$skill_lock_repo" >/dev/null || fail "managed skill export failed"
jq -e '
    .plugins.keep == {claude: "keep@third", codex: "plugin_keep"} and
    .plugins["new-codex"].codex == "plugin_new" and
    .plugins["new-claude"].claude == "new-claude@third" and
    .codexPlugins == ["keep-market@third", "new-market@third"] and
    (.marketplaces | keys) == ["third"] and
    (.codexMarketplaces | keys) == ["third"]
' "$plugin_manifest" >/dev/null || fail "plugin membership export failed"
jq -e '
    [.tools[] | select(.package == "portable-cli")] == [{
      channel: "latest", command: "portable-cli", group: "agents",
      installer: "npm", name: "portable-cli", package: "portable-cli"
    }] and
    ([.tools[].command] | index("manual-tool")) == null
' "$tool_manifest" >/dev/null || fail "portable tool export failed"
if grep -F 'must-not-enter-repo' \
    "$codex_template" "$claude_template" "$opencode_template" \
    "$pi_template" "$repo_mcp" "$skill_lock_repo" "$plugin_manifest" \
    "$tool_manifest" \
    >/dev/null; then
    fail "export wrote a credential"
fi
if grep -F "$HOME/" \
    "$codex_template" "$claude_template" "$opencode_template" \
    "$pi_template" "$repo_mcp" >/dev/null; then
    fail "export wrote a local path"
fi
jq -e '
    keys == [
      "claude-only", "codex-portable", "opencode-only", "pi-only", "shared"
    ] and
    .["claude-only"] == {
      type: "stdio", command: "claude-server", args: []
    } and
    .["codex-portable"] == {
      type: "stdio", command: "codex-server", args: ["--stdio"]
    } and
    .shared == {type: "http", url: "https://repo.test/mcp"}
' "$repo_mcp" >/dev/null ||
    fail "MCP export mishandled portable or local-only state"
git -C "$checkout" diff --cached --quiet || fail "export staged changes"
[ "$(git -C "$checkout" rev-parse HEAD)" = "$initial_head" ] ||
    fail "export created a commit"
git -C "$checkout" status --porcelain --untracked-files=all |
    awk '{print $2}' | sort \
    >"${tmp_dir}/changed"
printf '%s\n' \
    .agents/mcp-servers.json \
    .agents/plugin-manifest.json \
    .agents/skill-lock.json \
    .agents/tool-versions.json \
    config/claude/settings.json \
    config/codex/settings.toml \
    config/opencode/opencode.json \
    config/pi/settings.json | sort >"${tmp_dir}/expected-changed"
cmp "${tmp_dir}/expected-changed" "${tmp_dir}/changed" ||
    fail "export changed files outside its plan"
find "$home_dir" -type f -exec cksum {} \; | sort >"${tmp_dir}/live.final"
cmp "${tmp_dir}/live.apply-before" "${tmp_dir}/live.final" ||
    fail "approved export changed live state"

git -C "$checkout" add -A
git -C "$checkout" commit -qm 'fixture: exported state'
: >"$skill_test_log"
run_export n "${tmp_dir}/unchanged.log" SKILL_STAGE_FAIL=true ||
    fail "unchanged export did not finish without approval"
[ ! -s "$skill_test_log" ] || fail "unchanged export staged skills"
[ -z "$(git -C "$checkout" status --porcelain --untracked-files=all)" ] ||
    fail "unchanged export changed checkout"

# Run the public selector from a terminal; stub only the fzf selection.
cat >"${stub_dir}/fzf" <<'STUB'
#!/bin/bash
[ "${SKILL_SELECTION:-}" != cancel ] || exit 130
tee "$SKILL_MENU_LOG" | awk -F '\t' -v names="${SKILL_SELECTION:-}" '
    BEGIN { split(names, selected, ",") }
    { for (i in selected) if ($1 == selected[i]) print }
'
STUB
chmod +x "${stub_dir}/fzf"
run_skill_export() {
    local answer="$1" output="$2"
    shift 2
    env "$@" python3 - "$answer" "$JUST_BIN" --justfile "${DOTFILES_DIR}/justfile" export skills >"$output" 2>&1 <<'PY'
import errno
import os
import pty
import select
import signal
import sys
import time

answer, *command = sys.argv[1:]
pid, terminal = pty.fork()
if pid == 0:
    os.execv(command[0], command)

deadline = time.monotonic() + 30
output = bytearray()
while time.monotonic() < deadline:
    if not select.select([terminal], [], [], 0.25)[0]:
        continue
    try:
        chunk = os.read(terminal, 4096)
    except OSError as exc:
        if exc.errno != errno.EIO:
            raise
        break
    if not chunk:
        break
    sys.stdout.buffer.write(chunk)
    output.extend(chunk)
    if answer and b"Apply selected skill changes" in output:
        os.write(terminal, (answer + "\n").encode())
        answer = ""
else:
    os.kill(pid, signal.SIGKILL)
    os.waitpid(pid, 0)
    sys.exit("interactive skill export timed out")
_, status = os.waitpid(pid, 0)
sys.exit(os.waitstatus_to_exitcode(status))
PY
}

export SKILL_MENU_LOG="${tmp_dir}/menu"
jq '.skills["keep-missing"] = (.skills["managed-skill"] |
    .skillPath = "package/skills/keep-missing/SKILL.md")' \
    "$skill_lock_repo" >"${tmp_dir}/baseline-lock"
mv "${tmp_dir}/baseline-lock" "$skill_lock_repo"
git -C "$checkout" add -A
git -C "$checkout" commit -qm 'fixture: baseline for interactive export'
interactive_head=$(git -C "$checkout" rev-parse HEAD)
rm -r "${home_dir}/.agents/skills/managed-skill"
for skill in added local-only; do
    mkdir -p "${home_dir}/.agents/skills/$skill"
    printf '%s\n' '---' "name: $skill" '---' >"${home_dir}/.agents/skills/$skill/SKILL.md"
done
jq '.skills["added"] = (.skills["new-managed"] |
    .skillPath = "package/skills/added/SKILL.md" | .deviceId = "local") |
    .skills["new-managed"] |= (.source = "example/replacement" |
        .sourceUrl = "https://github.com/example/replacement.git" |
        .runtimeName = "New Managed")' \
    "$skill_lock_live" >"${tmp_dir}/modified-lock"
mv "${tmp_dir}/modified-lock" "$skill_lock_live"
find "$home_dir" -type f -exec cksum {} \; | sort >"${tmp_dir}/interactive.before"
assert_clean_skill_export() {
    [ -z "$(git -C "$checkout" status --porcelain --untracked-files=all)" ] ||
        fail "unapproved skill export changed checkout"
}

if "$JUST_BIN" --justfile "${DOTFILES_DIR}/justfile" export skills \
        </dev/null >"${tmp_dir}/no-terminal.log" 2>&1; then
    fail "export unexpectedly succeeded without terminal approval"
fi
grep -F 'interactive terminal' "${tmp_dir}/no-terminal.log" >/dev/null
run_skill_export '' "${tmp_dir}/no-selection.log" SKILL_SELECTION='' ||
    fail "interactive export failed with no selection"
assert_clean_skill_export
run_skill_export '' "${tmp_dir}/escape.log" SKILL_SELECTION=cancel ||
    fail "interactive export failed on Escape"
assert_clean_skill_export
run_skill_export n "${tmp_dir}/declined.log" SKILL_SELECTION=managed-skill ||
    fail "interactive export failed on refusal"
assert_clean_skill_export
if run_skill_export y "${tmp_dir}/stage-failure.log" \
    SKILL_SELECTION=managed-skill SKILL_STAGE_FAIL=true; then
    fail "interactive export ignored staging failure"
fi
grep -F 'Failed to stage current skills' "${tmp_dir}/stage-failure.log" >/dev/null
assert_clean_skill_export

mv "$skill_lock_live" "${tmp_dir}/saved-live-lock"
printf 'broken JSON\n' >"$skill_lock_live"
if run_skill_export y "${tmp_dir}/broken.log" SKILL_SELECTION=managed-skill; then
    fail "interactive export accepted a malformed global lock"
fi
grep -F 'Invalid live skill lock' "${tmp_dir}/broken.log" >/dev/null
jq '.skills["new-managed"].source = 123' "${tmp_dir}/saved-live-lock" >"$skill_lock_live"
if run_skill_export y "${tmp_dir}/bad-source.log" SKILL_SELECTION=managed-skill; then
    fail "interactive export accepted a global lock with invalid source metadata"
fi
grep -F 'Invalid live skill lock' "${tmp_dir}/bad-source.log" >/dev/null
mv "${tmp_dir}/saved-live-lock" "$skill_lock_live"
assert_clean_skill_export

run_skill_export y "${tmp_dir}/interactive.log" \
    SKILL_SELECTION=managed-skill,new-managed,added || {
    cat "${tmp_dir}/interactive.log" >&2
    fail "interactive skill export failed"
}
grep -F 'Not exportable: local skills without an upstream source' \
    "${tmp_dir}/interactive.log" >/dev/null
grep -F 'local-only' "${tmp_dir}/interactive.log" >/dev/null
grep -Fx $'managed-skill\tREMOVE\thttps://github.com/example/skills.git' "$SKILL_MENU_LOG"
grep -Fx $'added\tADD\thttps://github.com/example/skills.git' "$SKILL_MENU_LOG"
grep -Fx $'new-managed\tCHANGE SOURCE\thttps://github.com/example/skills.git -> https://github.com/example/replacement.git' "$SKILL_MENU_LOG"
jq -e --slurpfile before <(git -C "$checkout" show HEAD:.agents/skill-lock.json) '
    (.skills | keys) == ["added", "keep-missing", "new-managed"] and
    .skills["keep-missing"] == $before[0].skills["keep-missing"] and
    .skills["new-managed"].source == "example/replacement" and
    .skills["new-managed"].runtimeName == "New Managed" and
    .skills.added == {skillPath: "package/skills/added/SKILL.md",
        source: "example/skills", sourceType: "github",
        sourceUrl: "https://github.com/example/skills.git"}
' "$skill_lock_repo" >/dev/null || fail "interactive export applied the wrong selection"
[ "$(git -C "$checkout" status --porcelain --untracked-files=all)" = ' M .agents/skill-lock.json' ] ||
    fail "interactive export changed something besides the unstaged lock"
[ "$(git -C "$checkout" rev-parse HEAD)" = "$interactive_head" ] ||
    fail "interactive export created a commit"
find "$home_dir" -type f -exec cksum {} \; | sort >"${tmp_dir}/interactive.after"
cmp "${tmp_dir}/interactive.before" "${tmp_dir}/interactive.after" ||
    fail "interactive export changed live state"

echo "[INFO] transactional export smoke test passed"

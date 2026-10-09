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
    "${checkout}/.agents/skills-custom/existing-custom" \
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
custom_skills="${checkout}/.agents/skills-custom"
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
printf '{}\n' >"$repo_mcp"
printf 'clean\n' >"${checkout}/marker"
printf '%s\n' '---' 'name: existing-custom' '---' \
    >"${custom_skills}/existing-custom/SKILL.md"

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
cat >"$skill_lock_live" <<'JSON'
{
  "dismissed": {},
  "skills": {
    "managed-skill": {
      "installedAt": "local",
      "skillFolderHash": "local",
      "skillPath": "package/skills/managed-skill/SKILL.md",
      "source": "example/skills",
      "sourceType": "github",
      "sourceUrl": "https://github.com/example/skills.git"
    },
    "new-managed": {
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
for skill in managed-skill new-managed existing-custom new-custom; do
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
    "transport": {
      "args": [],
      "command": "/Users/local/bin/codex-server",
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
chmod +x "${stub_dir}/codex" "${stub_dir}/cp" "${stub_dir}/skills"

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
export SKILL_LOCK_REPO="$skill_lock_repo"
export SKILL_LOCK_LIVE="$skill_lock_live"
export SHARED_SKILLS_CUSTOM_DIR="$custom_skills"
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
    'Pi settings' 'MCP inventory' 'Skill inventory' 'Portable skills' \
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

grep -E -- '--skill managed-skill new-managed --agent codex' \
    "$skill_test_log" >/dev/null ||
    fail "export did not preflight every managed skill"
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
    .preserveWhenMissing == "repo" and
    .provider.ollama.options.baseURL == "http://live.test" and
    (has("session") | not) and (has("mcp") | not)
' "$opencode_template" >/dev/null || fail "OpenCode allowlist export failed"
jq -e '
    .theme == "live-theme" and .terminal.trueColor == true and
    .packages == ["npm:example@2"] and (has("authToken") | not)
' "$pi_template" >/dev/null || fail "Pi allowlist export failed"
grep -F 'model = "live-codex"' "$codex_template" >/dev/null ||
    fail "Codex allowlist export failed"
jq -e '
    (.skills | keys) == ["managed-skill", "new-managed"]
' "$skill_lock_repo" >/dev/null || fail "managed skill export failed"
[ -f "${custom_skills}/new-custom/SKILL.md" ] ||
    fail "portable skill was not exported"
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
      channel: "latest", command: "portable-cli", installer: "npm",
      name: "portable-cli", package: "portable-cli"
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
    keys == ["claude-only", "opencode-only", "pi-only", "shared"] and
    .["claude-only"] == {
      type: "stdio", command: "claude-server", args: []
    }
' "$repo_mcp" >/dev/null ||
    fail "MCP export included Codex-only local state"
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
    .agents/skills-custom/new-custom/SKILL.md \
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

echo "[INFO] transactional export smoke test passed"

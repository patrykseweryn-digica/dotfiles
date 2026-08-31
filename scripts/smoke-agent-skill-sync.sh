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
prune_home="${tmp_dir}/prune-home"
prune_stub_dir="${tmp_dir}/prune-stubs"
prune_project="${tmp_dir}/prune-project"
prune_manifest="${tmp_dir}/prune-manifest.json"
prune_log="${tmp_dir}/prune.log"
env_home="${tmp_dir}/env-home"
env_mcp_file="${tmp_dir}/mcp-with-env.json"
repo_lock_copy="${tmp_dir}/skill-lock.json"
manifest_copy="${tmp_dir}/claude-manifest.json"
custom_export_home="${tmp_dir}/custom-export-home"
custom_export_repo="${tmp_dir}/custom-export-repo"
custom_export_lock="${tmp_dir}/custom-export-lock.json"
custom_export_log="${tmp_dir}/custom-export.log"
skills_update_stub_dir="${tmp_dir}/skills-update-stubs"
skills_update_log="${tmp_dir}/skills-update.log"
pull_home="${tmp_dir}/pull-home"
pull_repo="${tmp_dir}/pull-repo"
pull_lock="${tmp_dir}/pull-skill-lock.json"
pull_live_lock="${pull_home}/.agents/.skill-lock.json"
pull_log="${tmp_dir}/pull.log"

mkdir -p "$home_dir/.agents/skills" "$stub_dir" "$skills_update_stub_dir"
ln -s "$JQ_BIN" "${stub_dir}/jq"
cp "$LOCK_FILE" "$repo_lock_copy"
cp "$CLAUDE_MANIFEST_FILE" "$manifest_copy"
jq -r '.skills | keys[]' "$LOCK_FILE" > "$lock_names"

cat > "${skills_update_stub_dir}/skills" <<'STUB'
#!/bin/bash
set -eu
printf '%s\n' "$*" >> "$SKILLS_UPDATE_LOG"
STUB
chmod +x "${skills_update_stub_dir}/skills"

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

cat > "${stub_dir}/claude" <<'STUB'
#!/bin/bash
set -eu
printf '%s\n' "$*" >> "$CLAUDE_INSTALL_LOG"
STUB
chmod +x "${stub_dir}/claude"
claude_install_log="${tmp_dir}/claude-install.log"
: > "$claude_install_log"
if ! CLAUDE_INSTALL_LOG="$claude_install_log" \
    "${DOTFILES_DIR}/sync-agents.sh" --quiet install \
    > "$sync_log" 2>&1; then
    cat "$sync_log" >&2
    fail "install did not repair missing Claude plugin state"
fi
grep -F 'plugin install ' "$claude_install_log" >/dev/null || \
    fail "install did not push missing Claude plugins"
rm "${stub_dir}/claude"

cat > "${stub_dir}/codex" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "${stub_dir}/codex"
if "${DOTFILES_DIR}/sync-agents.sh" --quiet install \
    > "$sync_log" 2>&1; then
    fail "install ignored missing Codex remote plugins"
fi
grep -F 'Open Codex and enter: /plugins' "$sync_log" >/dev/null || \
    fail "install omitted manual Codex plugin steps"
rm "${stub_dir}/codex"

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

if ! PATH="${skills_update_stub_dir}:${stub_dir}:/usr/bin:/bin" \
    SKILLS_UPDATE_LOG="$skills_update_log" \
    "${DOTFILES_DIR}/sync-agents.sh" --quiet skills-update diagnosing-bugs > "$sync_log" 2>&1; then
    cat "$sync_log" >&2
    fail "skills-update failed"
fi

grep -Fx -- 'update -g diagnosing-bugs' "$skills_update_log" >/dev/null || \
    fail "skills-update did not update shared global skills"

: > "$skills_update_log"
for skill_root in \
    "${HOME}/.agents/skills" \
    "${HOME}/.claude/skills" \
    "${OPENCODE_CONFIG_DIR}/skills" \
    "${HOME}/.pi/agent/skills"; do
    mkdir -p "${skill_root}/outside-inventory"
    printf '# Outside inventory\n' > \
        "${skill_root}/outside-inventory/SKILL.md"
    ln -s "${HOME}/missing-skill" "${skill_root}/stale-skill"
done

if ! PATH="${skills_update_stub_dir}:${stub_dir}:/usr/bin:/bin" \
    SKILLS_UPDATE_LOG="$skills_update_log" \
    "${DOTFILES_DIR}/sync-agents.sh" --quiet push-skills \
    > "$sync_log" 2>&1; then
    cat "$sync_log" >&2
    fail "push-skills failed"
fi
[ ! -s "$skills_update_log" ] || \
    fail "push-skills updated the skill manager or upstream skills"
for skill_root in \
    "${HOME}/.agents/skills" \
    "${HOME}/.claude/skills" \
    "${OPENCODE_CONFIG_DIR}/skills" \
    "${HOME}/.pi/agent/skills"; do
    [ ! -e "${skill_root}/outside-inventory" ] || \
        fail "push-skills kept an unmanaged skill in ${skill_root}"
    [ ! -L "${skill_root}/stale-skill" ] || \
        fail "push-skills kept a stale link in ${skill_root}"
done

if ! "${DOTFILES_DIR}/sync-agents.sh" --quiet skills-check \
    > "$sync_log" 2>&1; then
    cat "$sync_log" >&2
    fail "skills-check failed after push"
fi

cp "${HOME}/.agents/.skill-lock.json" \
    "${tmp_dir}/live-lock-backup.json"
mkdir -p "${HOME}/.agents/skills/extra"
printf '# Extra\n' > "${HOME}/.agents/skills/extra/SKILL.md"
jq '.skills.extra = {source: "example/skills"}' \
    "${HOME}/.agents/.skill-lock.json" > \
    "${tmp_dir}/live-lock-drift.json"
mv "${tmp_dir}/live-lock-drift.json" \
    "${HOME}/.agents/.skill-lock.json"
if "${DOTFILES_DIR}/sync-agents.sh" --quiet skills-check \
    > "$sync_log" 2>&1; then
    fail "skills-check ignored live lock drift"
fi
mv "${tmp_dir}/live-lock-backup.json" \
    "${HOME}/.agents/.skill-lock.json"
rm -rf "${HOME}/.agents/skills/extra"

mkdir -p "${OPENCODE_CONFIG_DIR}/skills/unmanaged"
printf '# Unmanaged\n' > \
    "${OPENCODE_CONFIG_DIR}/skills/unmanaged/SKILL.md"
if "${DOTFILES_DIR}/sync-agents.sh" --quiet skills-check \
    > "$sync_log" 2>&1; then
    fail "skills-check ignored an unmanaged runtime skill"
fi
rm -rf "${OPENCODE_CONFIG_DIR}/skills/unmanaged"

rm "${HOME}/.pi/agent/skills/$(head -n 1 "$lock_names")"
if "${DOTFILES_DIR}/sync-agents.sh" --quiet skills-check \
    > "$sync_log" 2>&1; then
    fail "skills-check ignored a missing runtime skill"
fi
if ! PATH="${skills_update_stub_dir}:${stub_dir}:/usr/bin:/bin" \
    SKILLS_UPDATE_LOG="$skills_update_log" \
    "${DOTFILES_DIR}/sync-agents.sh" --quiet push-skills \
    > "$sync_log" 2>&1; then
    cat "$sync_log" >&2
    fail "push-skills did not restore runtime drift"
fi

if PATH="${skills_update_stub_dir}:${stub_dir}:/usr/bin:/bin" \
    SKILLS_UPDATE_LOG="$skills_update_log" \
    "${DOTFILES_DIR}/sync-agents.sh" --quiet claude-update > "$sync_log" 2>&1; then
    fail "removed claude-update command should fail"
fi

if grep -F 'claude-update' "$sync_log" >/dev/null 2>&1; then
    fail "removed claude-update command remains in help"
fi

if grep -F "Installing skill:" "$sync_log" >/dev/null 2>&1; then
    cat "$sync_log" >&2
    fail "sync tried to install lock-managed skills instead of linking existing shared copies"
fi

while IFS= read -r skill_name; do
    [ -n "$skill_name" ] || continue
    [ -e "${HOME}/.agents/skills/${skill_name}/SKILL.md" ] || fail "missing shared skill: $skill_name"
    [ -e "${HOME}/.claude/skills/${skill_name}/SKILL.md" ] || fail "missing Claude skill: $skill_name"
    [ -e "${OPENCODE_CONFIG_DIR}/skills/${skill_name}/SKILL.md" ] || fail "missing OpenCode skill: $skill_name"
    [ -e "${HOME}/.pi/agent/skills/${skill_name}/SKILL.md" ] || fail "missing Pi skill: $skill_name"
done < "$lock_names"

for skill_dir in "$CUSTOM_SKILLS_DIR"/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name="$(basename "$skill_dir")"
    [ -e "${HOME}/.agents/skills/${skill_name}/SKILL.md" ] || fail "missing shared custom skill: $skill_name"
    [ -e "${HOME}/.claude/skills/${skill_name}/SKILL.md" ] || fail "missing Claude custom skill: $skill_name"
    [ -e "${OPENCODE_CONFIG_DIR}/skills/${skill_name}/SKILL.md" ] || fail "missing OpenCode custom skill: $skill_name"
    [ -e "${HOME}/.pi/agent/skills/${skill_name}/SKILL.md" ] || fail "missing Pi custom skill: $skill_name"
done

for skill_file in "$CUSTOM_SKILLS_DIR"/*.skill; do
    [ -f "$skill_file" ] || continue
    skill_name="$(basename "$skill_file")"
    [ -e "${HOME}/.agents/skills/${skill_name}" ] || fail "missing shared custom skill file: $skill_name"
    [ -e "${HOME}/.claude/skills/${skill_name}" ] || fail "missing Claude custom skill file: $skill_name"
    [ -e "${OPENCODE_CONFIG_DIR}/skills/${skill_name}" ] || fail "missing OpenCode custom skill file: $skill_name"
    [ -e "${HOME}/.pi/agent/skills/${skill_name}" ] || fail "missing Pi custom skill file: $skill_name"
done

[ -e "${CODEX_HOME}/AGENTS.md" ] || fail "missing Codex AGENTS.md"
[ -e "${HOME}/.claude/CLAUDE.md" ] || fail "missing Claude CLAUDE.md"
[ -e "${OPENCODE_CONFIG_DIR}/AGENTS.md" ] || fail "missing OpenCode AGENTS.md"
[ -e "${HOME}/.pi/agent/AGENTS.md" ] || fail "missing Pi AGENTS.md"

mkdir -p \
    "${custom_export_home}/.agents/skills/live-custom" \
    "${custom_export_home}/.agents/skills/locked-skill" \
    "${custom_export_repo}/repo-linked"
printf '# Live custom\n' > "${custom_export_home}/.agents/skills/live-custom/SKILL.md"
printf '# Locked skill\n' > "${custom_export_home}/.agents/skills/locked-skill/SKILL.md"
printf '# Repo linked\n' > "${custom_export_repo}/repo-linked/SKILL.md"
ln -s "${custom_export_repo}/repo-linked" "${custom_export_home}/.agents/skills/repo-linked"
cat > "$custom_export_lock" <<'JSON'
{
  "dismissed": {},
  "skills": {
    "locked-skill": {
      "source": "example/skills"
    }
  }
}
JSON

if HOME="$custom_export_home" SHARED_SKILLS_CUSTOM_DIR="$custom_export_repo" SKILL_LOCK_REPO="$custom_export_lock" PATH="${stub_dir}:/usr/bin:/bin" "${DOTFILES_DIR}/sync-agents.sh" --quiet custom-skills-export --check > "$custom_export_log" 2>&1; then
    cat "$custom_export_log" >&2
    fail "custom-skills-export --check should detect missing repo custom skill"
fi
grep -F "live-custom" "$custom_export_log" >/dev/null 2>&1 || fail "custom-skills-export --check did not report missing live custom skill"

if ! HOME="$custom_export_home" SHARED_SKILLS_CUSTOM_DIR="$custom_export_repo" SKILL_LOCK_REPO="$custom_export_lock" PATH="${stub_dir}:/usr/bin:/bin" "${DOTFILES_DIR}/sync-agents.sh" --quiet custom-skills-export --dry-run > "$custom_export_log" 2>&1; then
    cat "$custom_export_log" >&2
    fail "custom-skills-export --dry-run failed"
fi
[ ! -e "${custom_export_repo}/live-custom/SKILL.md" ] || fail "custom-skills-export --dry-run wrote live custom skill"

if ! HOME="$custom_export_home" SHARED_SKILLS_CUSTOM_DIR="$custom_export_repo" SKILL_LOCK_REPO="$custom_export_lock" PATH="${stub_dir}:/usr/bin:/bin" "${DOTFILES_DIR}/sync-agents.sh" --quiet custom-skills-export > "$custom_export_log" 2>&1; then
    cat "$custom_export_log" >&2
    fail "custom-skills-export failed"
fi
[ -e "${custom_export_repo}/live-custom/SKILL.md" ] || fail "custom-skills-export did not copy live custom skill"
[ ! -e "${custom_export_repo}/locked-skill/SKILL.md" ] || fail "custom-skills-export copied lock-managed skill"

printf '# Live custom v2\n' > "${custom_export_home}/.agents/skills/live-custom/SKILL.md"
if HOME="$custom_export_home" SHARED_SKILLS_CUSTOM_DIR="$custom_export_repo" SKILL_LOCK_REPO="$custom_export_lock" PATH="${stub_dir}:/usr/bin:/bin" "${DOTFILES_DIR}/sync-agents.sh" --quiet custom-skills-export --check > "$custom_export_log" 2>&1; then
    cat "$custom_export_log" >&2
    fail "custom-skills-export --check should detect changed repo custom skill"
fi
if ! HOME="$custom_export_home" SHARED_SKILLS_CUSTOM_DIR="$custom_export_repo" SKILL_LOCK_REPO="$custom_export_lock" PATH="${stub_dir}:/usr/bin:/bin" "${DOTFILES_DIR}/sync-agents.sh" --quiet custom-skills-export live-custom > "$custom_export_log" 2>&1; then
    cat "$custom_export_log" >&2
    fail "custom-skills-export live-custom update failed"
fi
grep -F '# Live custom v2' "${custom_export_repo}/live-custom/SKILL.md" >/dev/null 2>&1 || fail "custom-skills-export did not update live custom skill"
if ! HOME="$custom_export_home" SHARED_SKILLS_CUSTOM_DIR="$custom_export_repo" SKILL_LOCK_REPO="$custom_export_lock" PATH="${stub_dir}:/usr/bin:/bin" "${DOTFILES_DIR}/sync-agents.sh" --quiet custom-skills-export --check > "$custom_export_log" 2>&1; then
    cat "$custom_export_log" >&2
    fail "custom-skills-export --check failed after export"
fi

mkdir -p \
    "${pull_home}/.agents/skills/new-locked" \
    "${pull_home}/.agents/skills/live-custom" \
    "${pull_home}/.agents/skills/changed-custom" \
    "${pull_repo}/old-custom" \
    "${pull_repo}/changed-custom"
printf '# New locked\n' > \
    "${pull_home}/.agents/skills/new-locked/SKILL.md"
printf '# Live custom\n' > \
    "${pull_home}/.agents/skills/live-custom/SKILL.md"
printf '# Changed custom, live\n' > \
    "${pull_home}/.agents/skills/changed-custom/SKILL.md"
printf '# Old custom\n' > "${pull_repo}/old-custom/SKILL.md"
printf '# Changed custom, repo\n' > \
    "${pull_repo}/changed-custom/SKILL.md"
cat > "$pull_lock" <<'JSON'
{
  "dismissed": {},
  "skills": {
    "old-locked": {
      "source": "example/old",
      "sourceType": "github"
    }
  }
}
JSON
cat > "$pull_live_lock" <<'JSON'
{
  "dismissed": {"findSkillsPrompt": true},
  "skills": {
    "deleted-upstream": {
      "source": "example/deleted",
      "sourceType": "github"
    },
    "new-locked": {
      "installedAt": "runtime-only",
      "skillFolderHash": "runtime-only",
      "source": "example/new",
      "sourceType": "github",
      "updatedAt": "runtime-only"
    }
  }
}
JSON

if printf 'n\n' | HOME="$pull_home" \
    SHARED_SKILLS_CUSTOM_DIR="$pull_repo" \
    SKILL_LOCK_REPO="$pull_lock" \
    PATH="${skills_update_stub_dir}:${stub_dir}:/usr/bin:/bin" \
    SKILLS_UPDATE_LOG="$skills_update_log" \
    "${DOTFILES_DIR}/sync-agents.sh" pull-skills \
    > "$pull_log" 2>&1; then
    fail "pull-skills should return non-zero when cancelled"
fi
grep -F 'old-locked' "$pull_log" >/dev/null || \
    fail "pull-skills preview omitted a removed locked skill"
grep -F 'new-locked' "$pull_log" >/dev/null || \
    fail "pull-skills preview omitted an added locked skill"
grep -F 'Changed custom, live' "$pull_log" >/dev/null || \
    fail "pull-skills preview omitted changed custom content"
jq -e '.skills | keys == ["old-locked"]' "$pull_lock" >/dev/null || \
    fail "cancelled pull-skills changed the repository lock"
[ -e "${pull_repo}/old-custom/SKILL.md" ] || \
    fail "cancelled pull-skills removed a repository custom skill"

if ! printf 'y\n' | HOME="$pull_home" \
    SHARED_SKILLS_CUSTOM_DIR="$pull_repo" \
    SKILL_LOCK_REPO="$pull_lock" \
    PATH="${skills_update_stub_dir}:${stub_dir}:/usr/bin:/bin" \
    SKILLS_UPDATE_LOG="$skills_update_log" \
    "${DOTFILES_DIR}/sync-agents.sh" pull-skills \
    > "$pull_log" 2>&1; then
    cat "$pull_log" >&2
    fail "confirmed pull-skills failed"
fi
jq -e '
    (.skills | keys) == ["new-locked"] and
    .skills["deleted-upstream"] == null and
    .skills["new-locked"].installedAt == null and
    .skills["new-locked"].skillFolderHash == null and
    .skills["new-locked"].updatedAt == null
' "$pull_lock" >/dev/null || \
    fail "pull-skills did not normalize the live lock"
[ -e "${pull_repo}/live-custom/SKILL.md" ] || \
    fail "pull-skills did not import a custom skill"
grep -F '# Changed custom, live' \
    "${pull_repo}/changed-custom/SKILL.md" >/dev/null || \
    fail "pull-skills did not replace changed custom content"
[ ! -e "${pull_repo}/old-custom" ] || \
    fail "pull-skills did not remove an absent custom skill"
[ ! -s "$skills_update_log" ] || \
    fail "pull-skills updated the skill manager or upstream skills"

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
' --slurpfile mcp "$MCP_SERVERS_FILE" "${HOME}/.claude.json" \
    >/dev/null || fail "Claude user config does not reflect shared MCP servers"
jq -e '
    (.mcpServers | keys | sort) == ($mcp[0] | keys | sort)
' --slurpfile mcp "$MCP_SERVERS_FILE" "${HOME}/.agents/mcp.json" \
    >/dev/null || fail "Pi config does not reflect shared MCP servers"
jq -e '
    (.permissions.allow // []) as $allow |
    ($allow | index("mcp__*") | not) and
    (([$mcp[0] | keys[] | "mcp__\(.)__*"] - $allow) | length == 0)
' --slurpfile mcp "$MCP_SERVERS_FILE" "${HOME}/.claude/settings.json" \
    >/dev/null || fail "Claude settings do not reflect MCP permissions"

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

cat > "${npx_stub_dir}/skills" <<'STUB'
#!/bin/sh
source=""
skill_name=""
accept_openclaw=false

while [ "$#" -gt 0 ]; do
    case "$1" in
        add)
            ;;
        -g)
            shift
            source="$1"
            ;;
        --skill)
            shift
            skill_name="$1"
            ;;
        --dangerously-accept-openclaw-risks)
            accept_openclaw=true
            ;;
    esac
    shift
done

[ -n "$skill_name" ] || exit 1
[ -n "$source" ] || exit 1
if [ "$source" = "openclaw/agent-skills" ] && [ "$accept_openclaw" != true ]; then
    exit 1
fi

echo "npx install ${source} ${skill_name}" >> "$NPX_LOG"
mkdir -p "${HOME}/.claude/skills/${skill_name}"
printf '# %s\n' "$skill_name" > "${HOME}/.claude/skills/${skill_name}/SKILL.md"
STUB
chmod +x "${npx_stub_dir}/skills"

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
    [ -e "${HOME}/.pi/agent/skills/${skill_name}/SKILL.md" ] || fail "npx-installed skill missing Pi runtime: $skill_name"
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


mkdir -p "$prune_home/.claude/plugins" "$prune_stub_dir" "$prune_project"
ln -s "$JQ_BIN" "${prune_stub_dir}/jq"
: > "$prune_log"

cat > "$prune_manifest" <<JSON
{
  "marketplaces": {
    "official": {
      "source": "github",
      "repo": "example/official"
    }
  },
  "plugins": {
    "kept": {
      "claude": "kept@official"
    }
  }
}
JSON

cat > "${prune_home}/.claude/plugins/installed_plugins.json" <<JSON
{
  "plugins": {
    "kept@official": [
      {"scope": "user"}
    ],
    "extra@extra-mp": [
      {"scope": "project", "projectPath": "$prune_project"}
    ],
    "orphan@official": [
      {"scope": "user"}
    ]
  }
}
JSON

cat > "${prune_home}/.claude/plugins/known_marketplaces.json" <<'JSON'
{
  "extra-mp": {"source": {"source": "github", "repo": "example/extra"}},
  "official": {"source": {"source": "github", "repo": "example/official"}},
  "unused-mp": {"source": {"source": "github", "repo": "example/unused"}}
}
JSON

cat > "${prune_stub_dir}/claude" <<'STUB'
#!/bin/sh
printf '%s\t%s\n' "$PWD" "$*" >> "$CLAUDE_LOG"
if [ "$*" = "plugin uninstall extra@extra-mp --scope project --keep-data -y" ]; then
    echo 'Plugin "extra@extra-mp" is installed in user scope, not project. Use --scope user to uninstall.' >&2
    exit 1
fi
STUB
chmod +x "${prune_stub_dir}/claude"

export HOME="$prune_home"
export CLAUDE_MANIFEST="$prune_manifest"
export CLAUDE_LOG="$prune_log"
export PATH="${prune_stub_dir}:/usr/bin:/bin"

if "${DOTFILES_DIR}/sync-agents.sh" --quiet claude-prune --check > "$sync_log" 2>&1; then
    cat "$sync_log" >&2
    fail "claude-prune --check should fail when live plugins or marketplaces are outside manifest"
fi
[ ! -s "$prune_log" ] || fail "claude-prune --check should not invoke claude CLI"
grep -F "extra@extra-mp" "$sync_log" >/dev/null 2>&1 || fail "claude-prune --check did not report extra plugin"
grep -F "unused-mp" "$sync_log" >/dev/null 2>&1 || fail "claude-prune --check did not report extra marketplace"

if ! "${DOTFILES_DIR}/sync-agents.sh" --quiet claude-prune > "$sync_log" 2>&1; then
    cat "$sync_log" >&2
    fail "claude-prune failed with claude stub"
fi

grep -F "${prune_project}	plugin uninstall extra@extra-mp --scope project --keep-data -y" "$prune_log" >/dev/null 2>&1 || fail "claude-prune did not try project-scoped uninstall from its project path"
grep -F "plugin uninstall extra@extra-mp --scope user --keep-data -y" "$prune_log" >/dev/null 2>&1 || fail "claude-prune did not fall back to user scope after project-scope mismatch"
grep -F "plugin uninstall orphan@official --scope user --keep-data -y" "$prune_log" >/dev/null 2>&1 || fail "claude-prune did not uninstall user-scoped extra"
grep -F "plugin marketplace remove extra-mp" "$prune_log" >/dev/null 2>&1 || fail "claude-prune did not remove extra marketplace"
grep -F "plugin marketplace remove unused-mp" "$prune_log" >/dev/null 2>&1 || fail "claude-prune did not remove unused marketplace"

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
jq -e '.mcpServers["env-stdio"].env.ENV_TOKEN == "literal-token"' \
    "${HOME}/.claude.json" >/dev/null || fail "Claude MCP env value missing"
jq -e '
    (.permissions.allow | index("mcp__env-stdio__*")) and
    (.permissions.allow | index("mcp__env-http__*"))
' "${HOME}/.claude/settings.json" \
    >/dev/null || fail "Claude MCP permission missing"

echo "[INFO] agent skill sync smoke test passed"

#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
    echo "[ERROR] $*" >&2
    exit 1
}

tmp_dir="$(mktemp -d)"
cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

home_dir="${tmp_dir}/home"
manifest="${tmp_dir}/plugin-manifest.json"
sync_log="${tmp_dir}/sync.log"
stub_dir="${tmp_dir}/stubs"
update_log="${tmp_dir}/update.log"
project_dir="${tmp_dir}/project"
codex_cache="${tmp_dir}/codex-cache"

mkdir -p \
    "${home_dir}/.claude/plugins" \
    "${codex_cache}/keep" \
    "${codex_cache}/codex-new" \
    "$stub_dir" \
    "$project_dir"

cat > "$manifest" <<'JSON'
{
  "marketplaces": {
    "keep-mp": {
      "repo": "example/keep",
      "source": "github"
    },
    "stale-mp": {
      "repo": "example/stale",
      "source": "github"
    }
  },
  "plugins": {
    "keep": {
      "claude": "keep@keep-mp",
      "codex": "plugin_connector_keep"
    },
    "removed-only": {
      "claude": "removed-only@stale-mp"
    },
    "removed-shared": {
      "claude": "removed-shared@stale-mp",
      "codex": "plugin_connector_removed_shared"
    }
  }
}
JSON

cat > "${home_dir}/.claude/plugins/installed_plugins.json" <<'JSON'
{
  "plugins": {
    "keep@keep-mp": [
      {"scope": "user"}
    ],
    "new@new-mp": [
      {"scope": "user"}
    ]
  }
}
JSON

cat > "${home_dir}/.claude/plugins/known_marketplaces.json" <<'JSON'
{
  "keep-mp": {
    "source": {
      "repo": "example/keep",
      "source": "github"
    }
  },
  "new-mp": {
    "source": {
      "repo": "example/new",
      "source": "github"
    }
  }
}
JSON

cat > "${codex_cache}/keep/.codex-remote-plugin-install.json" <<'JSON'
{
  "schema_version": 1,
  "remote_plugin_id": "plugin_connector_keep"
}
JSON

cat > "${codex_cache}/codex-new/.codex-remote-plugin-install.json" <<'JSON'
{
  "schema_version": 1,
  "remote_plugin_id": "plugin_connector_new"
}
JSON

export HOME="$home_dir"
export PLUGIN_MANIFEST="$manifest"
export CLAUDE_MANIFEST="$manifest"
export CODEX_PLUGIN_MANIFEST="$manifest"
export CODEX_REMOTE_PLUGIN_CACHE="$codex_cache"

cp "$manifest" "${tmp_dir}/before-cancel.json"
if printf 'n\n' | "$DOTFILES_DIR/sync-agents.sh" --quiet pull-plugins \
    > "$sync_log" 2>&1; then
    fail "Plugin pull ignored cancelled confirmation"
fi
cmp -s "$manifest" "${tmp_dir}/before-cancel.json" || \
    fail "Plugin pull wrote after cancelled confirmation"
grep -F 'codex-new' "$sync_log" >/dev/null || \
    fail "Plugin pull did not preview the repository diff"

printf 'y\n' | "$DOTFILES_DIR/sync-agents.sh" --quiet pull-plugins \
    > "$sync_log" 2>&1 || {
    cat "$sync_log" >&2
    fail "Plugin pull failed"
}

jq -e '
    .plugins.keep.claude == "keep@keep-mp" and
    .plugins.keep.codex == "plugin_connector_keep" and
    .plugins.new.claude == "new@new-mp" and
    .plugins["codex-new"].codex == "plugin_connector_new" and
    (.plugins["removed-shared"] == null) and
    (.plugins["removed-only"] == null) and
    (.marketplaces | keys) == ["keep-mp", "new-mp"] and
    .marketplaces["new-mp"].repo == "example/new"
' "$manifest" >/dev/null || fail "Plugin pull wrote wrong state"

"$DOTFILES_DIR/sync-agents.sh" --quiet claude-export --check \
    > "$sync_log" 2>&1 || {
    cat "$sync_log" >&2
    fail "Claude plugin check failed after export"
}
"$DOTFILES_DIR/sync-agents.sh" --quiet codex-plugins-check \
    > "$sync_log" 2>&1 || {
    cat "$sync_log" >&2
    fail "Codex plugin check failed after pull"
}

cat > "${home_dir}/.claude/plugins/installed_plugins.json" <<'JSON'
{
  "plugins": {
    "keep@keep-mp": [
      {"scope": "user"}
    ]
  }
}
JSON
if "$DOTFILES_DIR/sync-agents.sh" --quiet plugins-check \
    > "$sync_log" 2>&1; then
    fail "Plugin check ignored a missing Claude plugin"
fi
grep -F 'new@new-mp' "$sync_log" >/dev/null || \
    fail "Plugin check did not report the missing Claude plugin"
grep -F 'Run: just push-plugins' "$sync_log" >/dev/null || \
    fail "Plugin check did not recommend authoritative push"

cat > "${home_dir}/.claude/plugins/installed_plugins.json" <<JSON
{
  "plugins": {
    "keep@keep-mp": [
      {"scope": "user"}
    ],
    "project-plugin@keep-mp": [
      {"scope": "project", "projectPath": "$project_dir"}
    ]
  }
}
JSON

cat > "${stub_dir}/codex" <<'STUB'
#!/bin/bash
set -eu
printf 'codex\t%s\n' "$*" >> "$PLUGIN_UPDATE_LOG"
STUB

cat > "${stub_dir}/claude" <<'STUB'
#!/bin/bash
set -eu
printf 'claude\t%s\t%s\n' "$PWD" "$*" >> "$PLUGIN_UPDATE_LOG"
STUB

chmod +x "${stub_dir}/codex" "${stub_dir}/claude"
: > "$update_log"

export PATH="${stub_dir}:/usr/bin:/bin"
export PLUGIN_UPDATE_LOG="$update_log"

"$DOTFILES_DIR/sync-agents.sh" --quiet push-plugins \
    > "$sync_log" 2>&1 || {
    cat "$sync_log" >&2
    fail "Plugin push failed"
}
grep -F $'\tplugin install new@new-mp' "$update_log" \
    >/dev/null || fail "Plugin push did not install missing membership"
grep -F $'\tplugin uninstall project-plugin@keep-mp' "$update_log" \
    >/dev/null || fail "Plugin push did not remove extra membership"
if grep -F $'\tplugin update ' "$update_log" >/dev/null; then
    fail "Plugin push upgraded a plugin"
fi

: > "$update_log"
"$DOTFILES_DIR/sync-agents.sh" --quiet plugins-update \
    > "$sync_log" 2>&1 || {
    cat "$sync_log" >&2
    fail "Plugin update failed"
}

grep -Fx $'codex\tplugin marketplace upgrade' "$update_log" \
    >/dev/null || fail "Codex marketplaces were not updated"
grep -F $'claude\t' "$update_log" |
    grep -F $'\tplugin marketplace update' \
    >/dev/null || fail "Claude marketplaces were not updated"
grep -F $'\tplugin update keep@keep-mp --scope user' "$update_log" \
    >/dev/null || fail "User-scoped Claude plugin was not updated"
grep -Fx $'claude\t'"${project_dir}"$'\tplugin update project-plugin@keep-mp --scope project' \
    "$update_log" >/dev/null || \
    fail "Project-scoped Claude plugin was not updated in its project"

echo "[INFO] Claude plugin sync smoke test passed"

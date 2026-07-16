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

mkdir -p "${home_dir}/.claude/plugins" "$stub_dir" "$project_dir"

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

export HOME="$home_dir"
export CLAUDE_MANIFEST="$manifest"

if "$DOTFILES_DIR/sync-agents.sh" --quiet claude-export --check \
    > "$sync_log" 2>&1; then
    fail "Claude plugin check should detect live-state drift"
fi

"$DOTFILES_DIR/sync-agents.sh" --quiet claude-export \
    > "$sync_log" 2>&1 || {
    cat "$sync_log" >&2
    fail "Claude plugin export failed"
}

jq -e '
    .plugins.keep.claude == "keep@keep-mp" and
    .plugins.keep.codex == "plugin_connector_keep" and
    .plugins.new.claude == "new@new-mp" and
    .plugins["removed-shared"].codex ==
        "plugin_connector_removed_shared" and
    (.plugins["removed-shared"].claude == null) and
    (.plugins["removed-only"] == null) and
    (.marketplaces | keys) == ["keep-mp", "new-mp"] and
    .marketplaces["new-mp"].repo == "example/new"
' "$manifest" >/dev/null || fail "Claude plugin export wrote wrong state"

"$DOTFILES_DIR/sync-agents.sh" --quiet claude-export --check \
    > "$sync_log" 2>&1 || {
    cat "$sync_log" >&2
    fail "Claude plugin check failed after export"
}

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

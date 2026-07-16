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

manifest="${tmp_dir}/plugin-manifest.json"
cache="${tmp_dir}/cache"
sync_log="${tmp_dir}/sync.log"

mkdir -p "$cache/figma" "$cache/unexpected-plugin"

cat > "$manifest" <<'JSON'
{
  "marketplaces": {},
  "plugins": {
    "figma": {
      "claude": "figma@example",
      "codex": "plugin_connector_keep"
    },
    "missing-plugin": {
      "codex": "plugin_connector_missing"
    }
  }
}
JSON

cat > "$cache/figma/.codex-remote-plugin-install.json" <<'JSON'
{
  "schema_version": 1,
  "remote_plugin_id": "plugin_connector_keep"
}
JSON

cat > "$cache/unexpected-plugin/.codex-remote-plugin-install.json" <<'JSON'
{
  "schema_version": 1,
  "remote_plugin_id": "plugin_connector_extra"
}
JSON

export CODEX_PLUGIN_MANIFEST="$manifest"
export CODEX_REMOTE_PLUGIN_CACHE="$cache"

if "$DOTFILES_DIR/sync-agents.sh" --quiet codex-plugins-check \
    > "$sync_log" 2>&1; then
    fail "Codex plugin check should detect missing and extra plugins"
fi

grep -F "missing-plugin (plugin_connector_missing)" "$sync_log" \
    >/dev/null || fail "Codex plugin check did not report missing plugin"
grep -F "unexpected-plugin (plugin_connector_extra)" "$sync_log" \
    >/dev/null || fail "Codex plugin check did not report extra plugin"

"$DOTFILES_DIR/sync-agents.sh" --quiet codex-plugins-export \
    > "$sync_log" 2>&1 || {
    cat "$sync_log" >&2
    fail "Codex plugin export failed"
}

jq -e '
    .plugins.figma.claude == "figma@example" and
    .plugins.figma.codex == "plugin_connector_keep" and
    .plugins["unexpected-plugin"].codex == "plugin_connector_extra" and
    (.plugins["missing-plugin"] == null)
' "$manifest" >/dev/null || fail "Codex plugin export wrote wrong state"

"$DOTFILES_DIR/sync-agents.sh" --quiet codex-plugins-check \
    > "$sync_log" 2>&1 || {
    cat "$sync_log" >&2
    fail "Codex plugin check failed after export"
}

echo "[INFO] Codex plugin sync smoke test passed"

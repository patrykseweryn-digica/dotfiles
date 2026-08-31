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
stub_dir="${tmp_dir}/stubs"

mkdir -p "$cache/figma" "$cache/unexpected-plugin" "$stub_dir"

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
grep -F 'Open Codex and enter: /plugins' "$sync_log" \
    >/dev/null || fail "Codex plugin check omitted the interactive command"
grep -F 'Complete OAuth when prompted' "$sync_log" \
    >/dev/null || fail "Codex plugin check omitted OAuth instructions"
grep -F 'Run again: just push-plugins' "$sync_log" \
    >/dev/null || fail "Codex plugin check omitted the verification command"

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

cat > "${stub_dir}/codex" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "${stub_dir}/codex"
export PATH="${stub_dir}:/usr/bin:/bin"
export CODEX_REMOTE_PLUGIN_CACHE="${tmp_dir}/missing-cache"
if "$DOTFILES_DIR/sync-agents.sh" --quiet codex-plugins-check \
    > "$sync_log" 2>&1; then
    fail "Codex plugin check passed without remote plugin state"
fi
grep -F 'figma (plugin_connector_keep)' "$sync_log" >/dev/null || \
    fail "Codex plugin check did not report missing state"

echo "[INFO] Codex plugin sync smoke test passed"

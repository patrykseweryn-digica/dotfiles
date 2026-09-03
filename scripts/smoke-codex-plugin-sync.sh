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
plugin_list="${tmp_dir}/plugin-list.json"
marketplace_list="${tmp_dir}/marketplace-list.json"
stub_dir="${tmp_dir}/stubs"
plugin_log="${tmp_dir}/plugin.log"

mkdir -p "$cache/figma" "$cache/unexpected-plugin" "$stub_dir"
printf '{"installed":[]}\n' > "$plugin_list"
printf '{"marketplaces":[]}\n' > "$marketplace_list"

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
export CODEX_PLUGIN_LIST_FILE="$plugin_list"
export CODEX_MARKETPLACE_LIST_FILE="$marketplace_list"

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
export CODEX_REMOTE_PLUGIN_CACHE="$cache"

cat > "$plugin_list" <<'JSON'
{
  "installed": [
    {
      "pluginId": "keep@official",
      "installed": true,
      "enabled": true,
      "marketplaceSource": {"sourceType": "git"}
    }
  ]
}
JSON
cat > "$marketplace_list" <<'JSON'
{
  "marketplaces": [
    {
      "name": "official",
      "marketplaceSource": {
        "sourceType": "git",
        "source": "https://example.test/official.git"
      }
    },
    {
      "name": "built-in",
      "marketplaceSource": {
        "sourceType": "local",
        "source": "/tmp/built-in"
      }
    }
  ]
}
JSON
"$DOTFILES_DIR/sync-agents.sh" --quiet codex-plugins-export \
    > "$sync_log" 2>&1 || {
    cat "$sync_log" >&2
    fail "Codex marketplace plugin export failed"
}
jq -e '
    .codexPlugins == ["keep@official"] and
    .codexMarketplaces == {
      official: "https://example.test/official.git"
    }
' "$manifest" >/dev/null ||
    fail "Codex marketplace plugin export wrote wrong state"

cat > "$plugin_list" <<'JSON'
{
  "installed": [
    {
      "pluginId": "extra@extra",
      "installed": true,
      "enabled": true,
      "marketplaceSource": {"sourceType": "git"}
    }
  ]
}
JSON
cat > "$marketplace_list" <<'JSON'
{
  "marketplaces": [
    {
      "name": "extra",
      "marketplaceSource": {
        "sourceType": "git",
        "source": "https://example.test/extra.git"
      }
    }
  ]
}
JSON
cat > "${stub_dir}/codex" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$CODEX_PLUGIN_LOG"
STUB
cat > "${stub_dir}/claude" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "${stub_dir}/codex" "${stub_dir}/claude"
mkdir -p "${tmp_dir}/home"
: > "$plugin_log"
HOME="${tmp_dir}/home" PATH="${stub_dir}:$PATH" \
    CODEX_PLUGIN_LOG="$plugin_log" \
    "$DOTFILES_DIR/sync-agents.sh" --quiet push-plugins \
    > "$sync_log" 2>&1 || {
    cat "$sync_log" >&2
    fail "Codex marketplace plugin push failed"
}
for command in \
    "plugin marketplace add https://example.test/official.git" \
    "plugin add keep@official" \
    "plugin remove extra@extra" \
    "plugin marketplace remove extra"; do
    grep -Fx "$command" "$plugin_log" >/dev/null ||
        fail "Codex marketplace plugin push omitted: $command"
done

echo "[INFO] Codex plugin sync smoke test passed"

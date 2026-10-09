#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENT_TOOLS="${DOTFILES_DIR}/scripts/agent-tools.sh"
JUST_BIN="$(command -v just)"
REAL_NPM="$(command -v npm)"
expected_node="$(node --version)"
expected_node="${expected_node#v}"
REAL_NODE_BIN="${NVM_DIR:-$HOME/.nvm}/versions/node/v$expected_node/bin"
[ -x "$REAL_NODE_BIN/node" ] || REAL_NODE_BIN="$(dirname "$(command -v node)")"

fail() {
  echo "[ERROR] $*" >&2
  exit 1
}

jq -e 'all(.tools[] | select((.scope // "agent") == "agent");
  .channel == "latest" and (has("version") | not))' \
  "$DOTFILES_DIR/.agents/tool-versions.json" >/dev/null ||
  fail "repository tools must follow latest without version pins"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

invalid_manifest="${tmp_dir}/invalid-tool-versions.json"
cat >"$invalid_manifest" <<'JSON'
{"platforms":["linux-x86_64"],"tools":[{
  "scope":"core","name":"uninstallable","commands":["uninstallable"],
  "versionPolicy":"system","packages":{"brew":"uninstallable"}
}]}
JSON
if AGENT_TOOL_VERSIONS="$invalid_manifest" \
  "$AGENT_TOOLS" plan >/dev/null 2>&1; then
  fail "manifest accepted a platform without an install source"
fi

manifest="${tmp_dir}/tool-versions.json"
stub_dir="${tmp_dir}/stubs"
npm_log="${tmp_dir}/npm.log"
native_log="${tmp_dir}/native.log"
mkdir -p "$stub_dir" "${tmp_dir}/home"
export HOME="${tmp_dir}/home"
export PS1=""
# Model only nvm activation; execute the real required Node binary.
export EXPECTED_NODE="$expected_node"
node_bin="$HOME/.nvm/versions/node/v$expected_node/bin"
mkdir -p "$node_bin"
ln -s "$REAL_NODE_BIN/node" "$node_bin/node"
cat >"$HOME/.nvm/nvm.sh" <<'STUB'
nvm() {
    case "$1" in
    version) printf 'v%s\n' "$EXPECTED_NODE" ;;
    use) export PATH="$NVM_DIR/versions/node/v$EXPECTED_NODE/bin:$PATH" ;;
    install|alias) return 0 ;;
    *) return 1 ;;
    esac
}
STUB

cat >"$manifest" <<'JSON'
{
  "tools": [
    {
      "name": "Pi",
      "command": "pi",
      "package": "@example/pi",
      "ignore_scripts": true,
      "channel": "latest",
      "installer": "npm"
    },
    {
      "name": "Codex",
      "command": "codex",
      "package": "@example/codex",
      "channel": "latest",
      "installer": "npm"
    },
    {
      "name": "Claude Code",
      "command": "claude",
      "package": "@example/claude",
      "channel": "latest",
      "installer": "claude-native"
    },
    {
      "name": "OpenCode",
      "command": "opencode",
      "package": "opencode-ai",
      "channel": "latest",
      "installer": "npm"
    },
    {
      "name": "Skill manager",
      "command": "skills",
      "package": "skills",
      "channel": "latest",
      "installer": "npm"
    }
  ]
}
JSON

for command_name in pi codex claude opencode skills; do
  cat >"${stub_dir}/${command_name}" <<'STUB'
#!/bin/bash
if [ "${1:-}" = --version ] && [ -n "${VERSION_MARKER:-}" ]; then
    : >"$VERSION_MARKER"
fi
name="$(basename "$0" | tr '[:lower:]' '[:upper:]')"
variable="TEST_AGENT_${name}_VERSION"
printf '%s %s\n' "$(basename "$0")" "${!variable:-1.2.3}"
STUB
done

cat >"${stub_dir}/npm" <<'STUB'
#!/bin/bash
if [ "$1" = view ]; then
    [ "${REGISTRY_FAIL:-false}" = false ] || exit 1
    printf '%s\n' "${LATEST_VERSION:-1.2.3}"
else
    [ "$(node --version)" = "v$EXPECTED_NODE" ] || exit 90
    printf '%s\n' "$*" >> "$NPM_LOG"
fi
STUB

cat >"${stub_dir}/curl" <<'STUB'
#!/bin/bash
cat <<'INSTALLER'
#!/bin/bash
printf '%s\n' "$1" >> "$NATIVE_LOG"
INSTALLER
STUB
chmod +x "${stub_dir}"/*

export AGENT_TOOL_VERSIONS="$manifest"
export NPM_LOG="$npm_log"
export NATIVE_LOG="$native_log"
export VERSION_MARKER="${tmp_dir}/version-called"
export PATH="${stub_dir}:/usr/bin:/bin"

plan="$("$AGENT_TOOLS" plan)"
[ ! -e "$VERSION_MARKER" ] || fail "tool plan executed a CLI"
[ "$(grep -c '^PASS[[:space:]]' <<<"$plan")" -eq 5 ] ||
  fail "offline plan omitted available tools"
grep -F $'PASS\ttools\tnone\tCodex is available' <<<"$plan" \
  >/dev/null || fail "tool plan omitted its contract fields"
"$AGENT_TOOLS" check
[ ! -e "$VERSION_MARKER" ] || fail "tool check executed a CLI"
outdated_report="$(AGENT_TOOLS="$AGENT_TOOLS" \
  "$JUST_BIN" --justfile "${DOTFILES_DIR}/justfile" outdated)"
[ -e "$VERSION_MARKER" ] || fail "outdated skipped version inspection"
rm "$VERSION_MARKER"
grep -F 'No outdated tools found' <<<"$outdated_report" >/dev/null ||
  fail "outdated did not report a current tool set"
if grep -F 'OpenCode' <<<"$outdated_report" >/dev/null; then
  fail "outdated included a current tool"
fi

TEST_AGENT_CODEX_VERSION=1.2.2
export TEST_AGENT_CODEX_VERSION
outdated_report="$(AGENT_TOOLS="$AGENT_TOOLS" \
  "$JUST_BIN" --justfile "${DOTFILES_DIR}/justfile" outdated)"
grep -F 'Codex' <<<"$outdated_report" >/dev/null ||
  fail "outdated omitted a stale tool"
if grep -F 'OpenCode' <<<"$outdated_report" >/dev/null; then
  fail "outdated included a current tool beside a stale tool"
fi
REGISTRY_FAIL=true "$AGENT_TOOLS" check >"${tmp_dir}/offline.log" ||
  fail "offline check rejected an available latest-channel tool"
unset TEST_AGENT_CODEX_VERSION

mv "${stub_dir}/codex" "${stub_dir}/codex.missing"
outdated_report="$(AGENT_TOOLS="$AGENT_TOOLS" \
  "$JUST_BIN" --justfile "${DOTFILES_DIR}/justfile" outdated)"
grep -F 'Codex' <<<"$outdated_report" | grep -F 'missing' >/dev/null ||
  fail "outdated omitted a missing tool"
if "$AGENT_TOOLS" check >"${tmp_dir}/missing.log" 2>&1; then
  fail "offline check accepted a missing tool"
fi
grep -F $'FAIL\ttools\tupdate\tCodex is missing or not runnable' \
  "${tmp_dir}/missing.log" >/dev/null || fail "missing tool plan is incomplete"
mv "${stub_dir}/codex.missing" "${stub_dir}/codex"

TEST_AGENT_PI_VERSION=1.0.0
TEST_AGENT_CODEX_VERSION=1.0.0
TEST_AGENT_CLAUDE_VERSION=1.0.0
TEST_AGENT_OPENCODE_VERSION=1.0.0
TEST_AGENT_SKILLS_VERSION=1.0.0
export TEST_AGENT_PI_VERSION TEST_AGENT_CODEX_VERSION TEST_AGENT_CLAUDE_VERSION TEST_AGENT_OPENCODE_VERSION TEST_AGENT_SKILLS_VERSION
: >"$npm_log"
: >"$native_log"
"$AGENT_TOOLS" install
[ ! -s "$npm_log" ] || fail "install queried or replaced available npm tools"
[ ! -s "$native_log" ] || fail "install replaced available native tools"

cp "$manifest" "$manifest.before"
LATEST_VERSION=2.0.0 "$AGENT_TOOLS" update
cmp "$manifest" "$manifest.before" || fail "update changed the tool inventory"
grep -Fx 'install -g --ignore-scripts @example/pi@latest' "$npm_log" >/dev/null ||
  fail "Pi did not install latest"
for package in @example/codex opencode-ai skills; do
  grep -Fx "install -g ${package}@latest" "$npm_log" >/dev/null ||
    fail "latest npm version not installed: $package"
done
grep -Fx '2.0.0' "$native_log" >/dev/null ||
  fail "resolved latest Claude version not installed by update"

export TEST_AGENT_PI_VERSION=2.0.0 TEST_AGENT_CODEX_VERSION=2.0.0 TEST_AGENT_CLAUDE_VERSION=2.0.0
export TEST_AGENT_OPENCODE_VERSION=2.0.0 TEST_AGENT_SKILLS_VERSION=2.0.0
: >"$npm_log"
: >"$native_log"
LATEST_VERSION=2.0.0 "$AGENT_TOOLS" install
[ ! -s "$npm_log" ] || fail "current tools reinstalled"
[ ! -s "$native_log" ] || fail "current native tools reinstalled"
LATEST_VERSION=3.0.0 "$AGENT_TOOLS" install
[ ! -s "$npm_log" ] || fail "install checked upstream for available tools"
LATEST_VERSION=3.0.0 "$AGENT_TOOLS" update
[ "$(wc -l < "$npm_log" | tr -d ' ')" -eq 4 ] ||
  fail "explicit update did not update every npm tool"
for action in report update; do
  if REGISTRY_FAIL=true "$AGENT_TOOLS" "$action" >/dev/null 2>&1; then
    fail "$action hid registry failure"
  fi
done
REGISTRY_FAIL=true "$AGENT_TOOLS" plan >/dev/null ||
  fail "tool plan contacted the registry"
REGISTRY_FAIL=true "$AGENT_TOOLS" check >/dev/null ||
  fail "tool check contacted the registry"
REGISTRY_FAIL=true "$AGENT_TOOLS" install >/dev/null ||
  fail "install queried the registry for available tools"

if grep -En 'npm view|@latest|"\$AGENT_TOOLS" (install|update)' \
  "${DOTFILES_DIR}/sync-agents.sh" >/dev/null; then
  fail "configuration push path can update agent tool versions"
fi

# Missing runtime prevents package installs; reports do not activate nvm.
mv "$HOME/.nvm/nvm.sh" "$HOME/.nvm/nvm.saved"
: >"$npm_log"
cp "$manifest" "$manifest.before"
for action in install update; do
  if "$AGENT_TOOLS" "$action" >"${tmp_dir}/node-error.log" 2>&1; then
    fail "$action accepted missing required runtime"
  fi
done
[ ! -s "$npm_log" ] || fail "npm ran without required Node"
cmp "$manifest" "$manifest.before" || fail "runtime failure changed inventory"
LATEST_VERSION=2.0.0 "$AGENT_TOOLS" check >/dev/null
mv "$HOME/.nvm/nvm.saved" "$HOME/.nvm/nvm.sh"

# Native declarations dispatch through the existing installers.
cat >"$manifest" <<'JSON'
{"tools":[
 {"name":"Hermes Agent","command":"hermes","installer":"hermes-native","channel":"latest","update":["hermes","update"]},
 {"name":"Herdr","command":"herdr","installer":"herdr-native","channel":"latest","update":["herdr","update"]},
 {"name":"Treehouse","command":"treehouse","installer":"treehouse-native","channel":"latest","update":["treehouse","update"]},
 {"name":"no-mistakes","command":"no-mistakes","installer":"no-mistakes-native","channel":"latest","update":["no-mistakes","update"]},
 {"name":"Cursor CLI","command":"agent","installer":"cursor-native","channel":"latest","update":["agent","update"]},
 {"name":"Grok Build","command":"grok","installer":"grok-native","channel":"latest","update":["grok","update"]}
]}
JSON
cat >"$stub_dir/curl" <<'STUB'
#!/bin/bash
case "$*" in
    *cursor.com/install*)
        cat <<'INSTALLER'
mkdir -p "$HOME/.local/bin"
printf '#!/bin/sh\nif [ "$1" = update ]; then echo "update agent" >> "$NATIVE_LOG"; else echo 2026.09.28-test; fi\n' > "$HOME/.local/bin/cursor-agent"
chmod +x "$HOME/.local/bin/cursor-agent"
ln -sf cursor-agent "$HOME/.local/bin/agent"
echo cursor-agent >> "$NATIVE_LOG"
INSTALLER
        [ "${NATIVE_DOWNLOAD_FAIL:-false}" = false ] || exit 22
        exit 0 ;;
    *x.ai/cli/install.sh*)
        cat <<'INSTALLER'
[ "$SHELL" = /bin/false ] || exit 1
case ":$PATH:" in *":$GROK_BIN_DIR:"*) ;; *) exit 1 ;; esac
mkdir -p "$GROK_BIN_DIR"
printf '#!/bin/sh\nif [ "$1" = update ]; then echo "update grok" >> "$NATIVE_LOG"; else echo 1.2.3; fi\n' > "$GROK_BIN_DIR/grok"
chmod +x "$GROK_BIN_DIR/grok"
ln -sf grok "$GROK_BIN_DIR/agent"
echo grok >> "$NATIVE_LOG"
INSTALLER
        [ "${NATIVE_DOWNLOAD_FAIL:-false}" = false ] || exit 22
        exit 0 ;;
    *treehouse/releases/latest*)
        [ "${NATIVE_DOWNLOAD_FAIL:-false}" = false ] || exit 22
        echo 'https://github.com/kunchenguid/treehouse/releases/tag/v1.2.3'
        exit 0 ;;
    *treehouse/releases/download/*)
        [ "${NATIVE_DOWNLOAD_FAIL:-false}" = false ] || exit 22
        while [ "$1" != -o ]; do shift; done
        package_dir=$(mktemp -d)
        printf '#!/bin/sh\nif [ "$1" = update ]; then echo "update treehouse" >> "$NATIVE_LOG"; else echo 1.2.3; fi\n' > "$package_dir/treehouse"
        chmod +x "$package_dir/treehouse"
        tar czf "$2" -C "$package_dir" treehouse
        rm -rf "$package_dir"
        echo treehouse >> "$NATIVE_LOG"
        exit 0 ;;
esac
output_path=""
for arg in "$@"; do
    if [ "${previous:-}" = -o ]; then output_path="$arg"; fi
    previous="$arg"
done
installer=$(cat <<'INSTALLER'
#!/bin/bash
if [ "${1:-}" = --skip-setup ]; then name=hermes
elif [ -n "${HERDR_INSTALL_DIR:-}" ]; then name=herdr
elif [ -n "${NO_MISTAKES_LINK_DIR:-}" ]; then name=no-mistakes
else name=treehouse; fi
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/$name" <<'CLI'
#!/bin/bash
if [ "$1" = --version ]; then echo 1.2.3; exit; fi
if [ "$1" = update ]; then echo "update $(basename "$0")" >> "$NATIVE_LOG"; exit; fi
[ "$*" = 'integration install claude' ] || exit 1
mkdir -p "$CLAUDE_CONFIG_DIR/hooks"
printf '#!/bin/sh\n' > "$CLAUDE_CONFIG_DIR/hooks/herdr-agent-state.sh"
printf '%s\n' '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"herdr-agent-state.sh"}]}]}}' > "$CLAUDE_CONFIG_DIR/settings.json"
CLI
chmod +x "$HOME/.local/bin/$name"
if [ "$name" = hermes ]; then
    mkdir -p "$HOME/.hermes/bin"
    printf '#!/bin/sh\n' > "$HOME/.hermes/bin/browser-use"
    chmod +x "$HOME/.hermes/bin/browser-use"
fi
printf '%s\n' "$name" >> "$NATIVE_LOG"
INSTALLER
)
if [ -n "$output_path" ]; then
    printf '%s\n' "$installer" >"$output_path"
else
    printf '%s\n' "$installer"
fi
[ "${NATIVE_DOWNLOAD_FAIL:-false}" = false ] || exit 22
STUB
export PATH="$HOME/.local/bin:$PATH"
: >"$native_log"
"$AGENT_TOOLS" install
"$AGENT_TOOLS" check >"$tmp_dir/native-report.log"
[ "$(grep -c '^PASS[[:space:]]' "$tmp_dir/native-report.log")" -eq 6 ] ||
  fail "native tool plan omitted an available tool"
for name in hermes herdr treehouse no-mistakes cursor-agent grok; do
  [ "$(grep -Fxc "$name" "$native_log")" -eq 1 ] || fail "native install missing: $name"
done
: >"$native_log"
"$AGENT_TOOLS" update
for name in hermes herdr treehouse no-mistakes agent grok; do
  grep -Fx "update $name" "$native_log" >/dev/null || fail "native update missing: $name"
done
[ "$(agent --version)" = 2026.09.28-test ] || fail "Grok replaced Cursor's agent"
[ ! -L "$HOME/.grok/bin/agent" ] || fail "Grok's agent symlink was not removed"
[ "$(grok --version)" = 1.2.3 ] || fail "Grok CLI missing from PATH"
rm "$HOME/.local/bin/treehouse"
if "$AGENT_TOOLS" check >/dev/null; then fail "missing native command accepted"; fi
: >"$native_log"
if NATIVE_DOWNLOAD_FAIL=true "$AGENT_TOOLS" install >/dev/null 2>&1; then
  fail "native download failure was ignored"
fi
[ ! -s "$native_log" ] || fail "partial native installer ran"

# A new npm declaration must work through the real npm installer and CLI.
# Only registry resolution/package transport are replaced by local tarballs.
fixture_dir="${tmp_dir}/fixture"
mkdir -p "$fixture_dir/package" "$fixture_dir/bin" "${tmp_dir}/prefix"
cat >"$fixture_dir/package/cli.js" <<'JS'
#!/usr/bin/env node
console.log(require('./package.json').version);
JS
chmod +x "$fixture_dir/package/cli.js"
for version in 1.2.3 2.0.0; do
  printf '{"name":"dotfiles-fixture","version":"%s","bin":{"dotfiles-fixture":"cli.js"}}\n' \
    "$version" >"$fixture_dir/package/package.json"
  tar -czf "$fixture_dir/$version.tgz" -C "$fixture_dir" package
done
cat >"$fixture_dir/bin/npm" <<'STUB'
#!/bin/bash
set -eu
if [ "$1" = view ]; then
  [ "${REGISTRY_FAIL:-false}" = false ] || exit 1
  printf '%s\n' "${LATEST_VERSION:-1.2.3}"
elif [ "$1" = install ]; then
  [ "$(node --version)" = "v$EXPECTED_NODE" ] || exit 90
  printf '%s\n' "$*" >> "$NPM_LOG"
  spec="${!#}"
  version="${spec##*@}"
  [ "$version" != latest ] || version="${LATEST_VERSION:-1.2.3}"
  exec "$REAL_NPM" install -g --offline --no-audit --no-fund \
    "$FIXTURE_DIR/$version.tgz"
else
  exec "$REAL_NPM" "$@"
fi
STUB
chmod +x "$fixture_dir/bin/npm"
export FIXTURE_DIR="$fixture_dir" REAL_NPM
export npm_config_prefix="${tmp_dir}/prefix"
export npm_config_cache="${tmp_dir}/npm-cache"
export PATH="${tmp_dir}/prefix/bin:${fixture_dir}/bin:${REAL_NODE_BIN}:/usr/bin:/bin"
cat >"$manifest" <<'JSON'
{"tools":[{"name":"Fixture","command":"dotfiles-fixture",
 "package":"dotfiles-fixture","installer":"npm","channel":"latest"
 }]}
JSON
if "$AGENT_TOOLS" check >"${tmp_dir}/missing.log"; then
  fail "new npm declaration was not missing before installation"
fi
REGISTRY_FAIL=true "$AGENT_TOOLS" install
"$AGENT_TOOLS" check
[ "$(dotfiles-fixture --version)" = 1.2.3 ] || fail "real npm did not install latest"
: >"$npm_log"
"$AGENT_TOOLS" install
[ ! -s "$npm_log" ] || fail "current npm package reinstalled"
cp "$manifest" "$manifest.before"
LATEST_VERSION=2.0.0 "$AGENT_TOOLS" update
[ "$(dotfiles-fixture --version)" = 2.0.0 ] || fail "explicit update omitted new declaration"
LATEST_VERSION=2.0.0 "$AGENT_TOOLS" check
cmp "$manifest" "$manifest.before" || fail "real update changed inventory"
# A locally available latest-channel tool stays healthy until update resolves upstream.
"$REAL_NPM" install -g --offline --no-audit --no-fund "$fixture_dir/1.2.3.tgz"
REGISTRY_FAIL=true "$AGENT_TOOLS" check >"${tmp_dir}/fixture-offline.log" ||
  fail "offline check rejected an available latest-channel fixture"
LATEST_VERSION=2.0.0 "$AGENT_TOOLS" install
[ "$(dotfiles-fixture --version)" = 1.2.3 ] ||
  fail "install replaced an available latest-channel tool"
LATEST_VERSION=2.0.0 "$AGENT_TOOLS" update
LATEST_VERSION=2.0.0 "$AGENT_TOOLS" check
jq -e '.tools[0] | has("version") | not' "$manifest" >/dev/null ||
  fail "update pinned latest tool"
cp "$manifest" "$manifest.before"
for action in report update; do
  if REGISTRY_FAIL=true "$AGENT_TOOLS" "$action" >"${tmp_dir}/registry-error.log" 2>&1; then
    fail "ordinary latest $action hid registry failure"
  fi
done
REGISTRY_FAIL=true "$AGENT_TOOLS" check >/dev/null ||
  fail "ordinary latest check contacted the registry"
REGISTRY_FAIL=true "$AGENT_TOOLS" install >/dev/null ||
  fail "install queried the registry for an available fixture"
cmp "$manifest" "$manifest.before" || fail "failed update changed declaration"

echo "[INFO] agent tools smoke test passed"

#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENT_TOOLS="${DOTFILES_DIR}/scripts/agent-tools.sh"
JUST_BIN="$(command -v just)"
REAL_NPM="$(command -v npm)"
expected_node=$(cat "$DOTFILES_DIR/.nvmrc")
REAL_NODE_BIN="${NVM_DIR:-$HOME/.nvm}/versions/node/v$expected_node/bin"
[ -x "$REAL_NODE_BIN/node" ] || REAL_NODE_BIN="$(dirname "$(command -v node)")"

fail() {
  echo "[ERROR] $*" >&2
  exit 1
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

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
    [ "$1" = use ] && [ "$2" = --silent ] || return 1
    [ -x "$NVM_DIR/versions/node/v$3/bin/node" ] || return 1
    export PATH="$NVM_DIR/versions/node/v$3/bin:$PATH"
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
      "version": "1.2.3",
      "installer": "npm"
    },
    {
      "name": "Claude Code",
      "command": "claude",
      "package": "@example/claude",
      "channel": "latest",
      "version": "1.2.3",
      "installer": "claude-native"
    },
    {
      "name": "OpenCode",
      "command": "opencode",
      "package": "opencode-ai",
      "channel": "latest",
      "version": "1.2.3",
      "installer": "npm"
    },
    {
      "name": "Skill manager",
      "command": "skills",
      "package": "skills",
      "channel": "latest",
      "version": "1.2.3",
      "installer": "npm"
    }
  ]
}
JSON

for command_name in pi codex claude opencode skills; do
  cat >"${stub_dir}/${command_name}" <<'STUB'
#!/bin/bash
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
export PATH="${stub_dir}:/usr/bin:/bin"

"$AGENT_TOOLS" check
AGENT_TOOLS="$AGENT_TOOLS" \
  "$JUST_BIN" --justfile "${DOTFILES_DIR}/justfile" agent-versions |
  grep -F 'OpenCode' >/dev/null || fail "version report omitted OpenCode"

TEST_AGENT_CODEX_VERSION=1.2.2
export TEST_AGENT_CODEX_VERSION
if "$AGENT_TOOLS" check >"${tmp_dir}/drift.log" 2>&1; then
  fail "version check ignored drift"
fi
unset TEST_AGENT_CODEX_VERSION

TEST_AGENT_PI_VERSION=1.0.0
TEST_AGENT_CODEX_VERSION=1.0.0
TEST_AGENT_CLAUDE_VERSION=1.0.0
TEST_AGENT_OPENCODE_VERSION=1.0.0
TEST_AGENT_SKILLS_VERSION=1.0.0
export TEST_AGENT_PI_VERSION TEST_AGENT_CODEX_VERSION TEST_AGENT_CLAUDE_VERSION TEST_AGENT_OPENCODE_VERSION TEST_AGENT_SKILLS_VERSION
: >"$npm_log"
: >"$native_log"
"$AGENT_TOOLS" install

grep -Fx 'install -g --ignore-scripts @example/pi@latest' "$npm_log" >/dev/null ||
  fail "Pi did not install latest"
for package in @example/codex opencode-ai skills; do
  grep -Fx "install -g ${package}@1.2.3" "$npm_log" >/dev/null ||
    fail "exact npm version not installed: $package"
done
grep -Fx '1.2.3' "$native_log" >/dev/null ||
  fail "exact Claude version not installed"

LATEST_VERSION=2.0.0 AGENT_TOOLS="$AGENT_TOOLS" \
  "$JUST_BIN" --justfile "${DOTFILES_DIR}/justfile" update-agent-tools
jq -e 'all(.tools[]; if .command == "pi" then
    .channel == "latest" and (has("version") | not)
    else .version == "2.0.0" end)' "$manifest" >/dev/null ||
  fail "update did not resolve moving channels into exact versions"

export TEST_AGENT_PI_VERSION=2.0.0 TEST_AGENT_CODEX_VERSION=2.0.0 TEST_AGENT_CLAUDE_VERSION=2.0.0
export TEST_AGENT_OPENCODE_VERSION=2.0.0 TEST_AGENT_SKILLS_VERSION=2.0.0
: >"$npm_log"
LATEST_VERSION=2.0.0 "$AGENT_TOOLS" install
[ ! -s "$npm_log" ] || fail "current tools reinstalled"
LATEST_VERSION=3.0.0 "$AGENT_TOOLS" install
[ "$(cat "$npm_log")" = 'install -g --ignore-scripts @example/pi@latest' ] ||
  fail "moving latest updated tools other than Pi"
for action in report check install; do
  if REGISTRY_FAIL=true "$AGENT_TOOLS" "$action" >/dev/null 2>&1; then
    fail "$action hid registry failure"
  fi
done

if grep -En 'agent-tools|npm view|@latest' \
  "${DOTFILES_DIR}/sync-agents.sh" >/dev/null; then
  fail "configuration push path can update agent tool versions"
fi

# Missing runtime prevents all writes; read-only reports do not activate nvm.
mv "$HOME/.nvm/nvm.sh" "$HOME/.nvm/nvm.saved"
: >"$npm_log"
cp "$manifest" "$manifest.before"
for action in install update; do
  if "$AGENT_TOOLS" "$action" >"${tmp_dir}/node-error.log" 2>&1; then
    fail "$action accepted missing required runtime"
  fi
done
[ ! -s "$npm_log" ] || fail "npm ran without required Node"
cmp "$manifest" "$manifest.before" || fail "runtime failure changed pins"
LATEST_VERSION=2.0.0 "$AGENT_TOOLS" check >/dev/null
mv "$HOME/.nvm/nvm.saved" "$HOME/.nvm/nvm.sh"

# Native declarations dispatch through the existing installers.
cat >"$manifest" <<'JSON'
{"tools":[
 {"name":"Hermes Agent","command":"hermes","installer":"hermes-native","channel":"latest"},
 {"name":"Herdr","command":"herdr","installer":"herdr-native","channel":"latest"},
 {"name":"Treehouse","command":"treehouse","installer":"treehouse-native","channel":"latest"},
 {"name":"no-mistakes","command":"no-mistakes","installer":"no-mistakes-native","channel":"latest"}
]}
JSON
cat >"$stub_dir/curl" <<'STUB'
#!/bin/bash
case "$*" in
    *treehouse/releases/latest*)
        [ "${NATIVE_DOWNLOAD_FAIL:-false}" = false ] || exit 22
        echo 'https://github.com/kunchenguid/treehouse/releases/tag/v1.2.3'
        exit 0 ;;
    *treehouse/releases/download/*)
        [ "${NATIVE_DOWNLOAD_FAIL:-false}" = false ] || exit 22
        while [ "$1" != -o ]; do shift; done
        package_dir=$(mktemp -d)
        printf '#!/bin/sh\necho 1.2.3\n' > "$package_dir/treehouse"
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
[ "$(grep -Fc 'available (latest not checked)' "$tmp_dir/native-report.log")" -eq 4 ] ||
  fail "native report claims latest verification"
"$AGENT_TOOLS" update
for name in hermes herdr treehouse no-mistakes; do
  [ "$(grep -Fxc "$name" "$native_log")" -eq 2 ] || fail "native dispatch missing: $name"
done
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
 "package":"dotfiles-fixture","installer":"npm","channel":"latest",
 "version":"1.2.3"}]}
JSON
if "$AGENT_TOOLS" check >"${tmp_dir}/missing.log"; then
  fail "new npm declaration was not missing before installation"
fi
"$AGENT_TOOLS" install
"$AGENT_TOOLS" check
[ "$(dotfiles-fixture --version)" = 1.2.3 ] || fail "real npm did not install pin"
: >"$npm_log"
"$AGENT_TOOLS" install
[ ! -s "$npm_log" ] || fail "pinned npm package reinstalled"
LATEST_VERSION=2.0.0 "$AGENT_TOOLS" install
[ "$(dotfiles-fixture --version)" = 1.2.3 ] || fail "ordinary install changed pin"
LATEST_VERSION=2.0.0 "$AGENT_TOOLS" update
[ "$(dotfiles-fixture --version)" = 2.0.0 ] || fail "explicit update omitted new declaration"
"$AGENT_TOOLS" check
# Downgrade the installed package independently to exercise drift and repair.
"$REAL_NPM" install -g --offline --no-audit --no-fund "$fixture_dir/1.2.3.tgz"
if "$AGENT_TOOLS" check >"${tmp_dir}/fixture-drift.log"; then
  fail "new npm declaration ignored real installed version drift"
fi
grep -F drift "${tmp_dir}/fixture-drift.log" >/dev/null
"$AGENT_TOOLS" install
"$AGENT_TOOLS" check

# The same ordinary tool supports latest without a command-name exception.
jq 'del(.tools[0].version)' "$manifest" >"$manifest.next"
mv "$manifest.next" "$manifest"
LATEST_VERSION=1.2.3 "$AGENT_TOOLS" install
LATEST_VERSION=1.2.3 "$AGENT_TOOLS" check
LATEST_VERSION=2.0.0 "$AGENT_TOOLS" update
LATEST_VERSION=2.0.0 "$AGENT_TOOLS" check
jq -e '.tools[0] | has("version") | not' "$manifest" >/dev/null ||
  fail "update pinned latest tool"
cp "$manifest" "$manifest.before"
for action in check report install update; do
  if REGISTRY_FAIL=true "$AGENT_TOOLS" "$action" >"${tmp_dir}/registry-error.log" 2>&1; then
    fail "ordinary latest $action hid registry failure"
  fi
done
cmp "$manifest" "$manifest.before" || fail "failed update changed declaration"

echo "[INFO] agent tools smoke test passed"

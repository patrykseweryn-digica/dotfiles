#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${DOTFILES_DIR}/scripts/host-tools.sh"
AGENT_TOOLS="${DOTFILES_DIR}/scripts/agent-tools.sh"
REAL_JQ="$(command -v jq)"
# shellcheck source=bootstrap.d/07-node.sh
source "$DOTFILES_DIR/bootstrap.d/07-node.sh"
expected_node="$(node --version)"
expected_node="${expected_node#v}"
REAL_NODE_BIN="$(dirname "$(command -v node)")"

fail() {
  echo "[ERROR] $*" >&2
  exit 1
}

jq -e 'all(.tools[] | select((.scope // "agent") == "agent");
  (.channel | test("^(latest|[0-9]+[.][0-9]+[.][0-9]+)$")) and
  (has("version") | not))' \
  "$DOTFILES_DIR/.agents/tool-versions.json" >/dev/null ||
  fail "agent tools must declare a valid release channel"
jq -e '[.tools[] | select(.command == "codex") | .installer] ==
  ["codex-native"]' "$DOTFILES_DIR/.agents/tool-versions.json" >/dev/null ||
  fail "Codex must use OpenAI's native installer on every platform"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
# The machine group setting must not change fixture results.
export DOTFILES_ENV_FILE="${tmp_dir}/all-groups.env"
printf 'DOTFILES_GROUPS=core,agents,desktop\n' >"$DOTFILES_ENV_FILE"

manifest="${tmp_dir}/tool-versions.json"
stub_dir="${tmp_dir}/stubs"
npm_log="${tmp_dir}/npm.log"
mise_log="${tmp_dir}/mise.log"
native_log="${tmp_dir}/native.log"
mkdir -p "$stub_dir" "${tmp_dir}/home"
export HOME="${tmp_dir}/home"
export PS1=""
# Model only mise activation; execute the real required Node binary.
export EXPECTED_NODE="$expected_node"
mise_root="$HOME/.local/share/mise"
node_bin="$mise_root/installs/node/$expected_node/bin"
mkdir -p "$node_bin" "$HOME/.local/bin"
ln -s "$REAL_NODE_BIN/node" "$node_bin/node"
printf '%s\n' "$expected_node" >"$mise_root/current-node"
cat >"$HOME/.local/bin/mise" <<'STUB'
#!/bin/bash
set -eu
case ":${MISE_TRUSTED_CONFIG_PATHS:-}:" in
*":$HOME/.config/mise/conf.d:"*) ;;
*) exit 21 ;;
esac
if [ "$1" = --cd ]; then
    shift 2
fi
root="$HOME/.local/share/mise"
version=$(cat "$root/current-node")
case "$1" in
which)
    if [ "$2" = node ]; then
        printf '%s/installs/node/%s/bin/node\n' "$root" "$version"
    else
        binary="$root/npm-tools/bin/$2"
        [ -x "$binary" ]
        printf '%s\n' "$binary"
    fi
    ;;
install | upgrade)
    if [ "$1" = install ] && [ "$2" = node ]; then
        exit 0
    fi
    [ "${REGISTRY_FAIL:-false}" = false ] || exit 22
    spec="${!#}"
    package="${spec#npm:}"
    command_name=$(
        "$REAL_JQ" -r --arg package "$package" \
            '.tools[] | select(.package == $package) | .command' \
            "$AGENT_TOOL_VERSIONS"
    )
    [ -n "$command_name" ] && [ "$command_name" != null ]
    mkdir -p "$root/npm-tools/bin"
    printf '#!/bin/sh\necho %s\n' "${LATEST_VERSION:-1.2.3}" \
        >"$root/npm-tools/bin/$command_name"
    chmod +x "$root/npm-tools/bin/$command_name"
    printf '%s\n' "$*" >>"$MISE_LOG"
    ;;
config)
    [ "$2" = set ]
    [ "$3" = --global ]
    [ "$4" = tools.node ]
    mkdir -p "$HOME/.config/mise"
    printf '[tools]\nnode = "%s"\n' "$5" \
        >"$HOME/.config/mise/config.toml"
    ;;
activate)
    printf 'export PATH="%s/npm-tools/bin:%s/installs/node/%s/bin:$PATH"\n' \
        "$root" "$root" "$version"
    ;;
*) exit 1 ;;
esac
STUB
chmod +x "$HOME/.local/bin/mise"

cat >"$manifest" <<'JSON'
{
  "tools": [
    {
      "name": "Pi",
      "command": "pi",
      "package": "@example/pi",
      "channel": "latest",
      "group": "agents",
      "installer": "npm"
    },
    {
      "name": "Codex",
      "command": "codex",
      "package": "@example/codex",
      "channel": "latest",
      "group": "agents",
      "installer": "npm"
    },
    {
      "name": "Claude Code",
      "command": "claude",
      "package": "@example/claude",
      "channel": "latest",
      "group": "agents",
      "installer": "claude-native",
      "update": ["claude", "install", "latest"]
    },
    {
      "name": "OpenCode",
      "command": "opencode",
      "package": "opencode-ai",
      "allow_builds": ["opencode-ai"],
      "channel": "latest",
      "group": "agents",
      "installer": "npm"
    },
    {
      "name": "Skill manager",
      "command": "skills",
      "package": "skills",
      "allow_low_downloads": true,
      "channel": "latest",
      "group": "agents",
      "installer": "npm"
    }
  ]
}
JSON

jq '.tools[0].trust_policy_excludes = ["@example/pi"]' "$manifest" \
  >"${tmp_dir}/broad-trust-exception.json"
if AGENT_TOOL_VERSIONS="${tmp_dir}/broad-trust-exception.json" \
  "$AGENT_TOOLS" plan >/dev/null 2>&1; then
  fail "manifest accepted a trust exception without an exact version"
fi
jq '.tools[0].allow_builds = []' "$manifest" \
  >"${tmp_dir}/empty-build-allowlist.json"
if AGENT_TOOL_VERSIONS="${tmp_dir}/empty-build-allowlist.json" \
  "$AGENT_TOOLS" plan >/dev/null 2>&1; then
  fail "manifest accepted an empty build allowlist"
fi

jq '.tools[4].allow_low_downloads = false' "$manifest" \
  >"${tmp_dir}/false-low-downloads.json"
if AGENT_TOOL_VERSIONS="${tmp_dir}/false-low-downloads.json" \
  "$AGENT_TOOLS" plan >/dev/null 2>&1; then
  fail "manifest accepted a false low-download approval"
fi
jq '.tools[2].allow_low_downloads = true' "$manifest" \
  >"${tmp_dir}/native-low-downloads.json"
if AGENT_TOOL_VERSIONS="${tmp_dir}/native-low-downloads.json" \
  "$AGENT_TOOLS" plan >/dev/null 2>&1; then
  fail "manifest accepted a low-download approval for a native tool"
fi

for command_name in pi codex claude opencode skills; do
  cat >"${stub_dir}/${command_name}" <<'STUB'
#!/bin/bash
if [ "$(basename "$0")" = claude ] && [ "$*" = "install latest" ]; then
    printf '%s\n' 'claude install latest' >>"$NATIVE_LOG"
    exit 0
fi
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
export MISE_LOG="$mise_log"
export NATIVE_LOG="$native_log"
export REAL_JQ
export VERSION_MARKER="${tmp_dir}/version-called"
export PATH="${stub_dir}:${HOST_JQ_DIR}:/usr/bin:/bin"

plan="$("$AGENT_TOOLS" plan)"
[ ! -e "$VERSION_MARKER" ] || fail "tool plan executed a CLI"
[ "$(grep -c '^PASS[[:space:]]' <<<"$plan")" -eq 5 ] ||
  fail "offline plan omitted available tools"
grep -F $'PASS\ttools\tnone\tCodex is available' <<<"$plan" \
  >/dev/null || fail "tool plan omitted its contract fields"
"$AGENT_TOOLS" check
[ ! -e "$VERSION_MARKER" ] || fail "tool check executed a CLI"
outdated_report="$("$AGENT_TOOLS" outdated)"
[ -e "$VERSION_MARKER" ] || fail "outdated skipped version inspection"
rm "$VERSION_MARKER"
grep -F 'No outdated tools found' <<<"$outdated_report" >/dev/null ||
  fail "outdated did not report a current tool set"
if grep -F 'OpenCode' <<<"$outdated_report" >/dev/null; then
  fail "outdated included a current tool"
fi

TEST_AGENT_CODEX_VERSION=1.2.2
export TEST_AGENT_CODEX_VERSION
outdated_report="$("$AGENT_TOOLS" outdated)"
grep -F 'Codex' <<<"$outdated_report" >/dev/null ||
  fail "outdated omitted a stale tool"
if grep -F 'OpenCode' <<<"$outdated_report" >/dev/null; then
  fail "outdated included a current tool beside a stale tool"
fi
REGISTRY_FAIL=true "$AGENT_TOOLS" check >"${tmp_dir}/offline.log" ||
  fail "offline check rejected an available latest-channel tool"
unset TEST_AGENT_CODEX_VERSION

mv "${stub_dir}/codex" "${stub_dir}/codex.missing"
outdated_report="$("$AGENT_TOOLS" outdated)"
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
: >"$mise_log"
: >"$native_log"
"$AGENT_TOOLS" install
[ ! -s "$npm_log" ] || fail "mise migration used global npm install"
[ "$(grep -c '^install npm:' "$mise_log")" -eq 4 ] ||
  fail "install did not migrate every npm tool to mise"
[ ! -s "$native_log" ] || fail "install replaced available native tools"
mise_config="$HOME/.config/mise/conf.d/20-agent-tools.toml"
grep -Fx '"npm:@example/pi" = "latest"' "$mise_config" >/dev/null ||
  fail "Pi mise declaration is not latest"
grep -Fx '"npm:skills" = { version = "latest", allow_low_downloads = true }' \
  "$mise_config" >/dev/null || fail "Skill manager low-download approval is missing"
grep -Fx '"npm:@example/codex" = "latest"' "$mise_config" >/dev/null ||
  fail "Codex mise declaration is not latest"
grep -F '"npm:opencode-ai" = { version = "latest", allow_builds = ["opencode-ai"] }' \
  "$mise_config" >/dev/null || fail "OpenCode build allowlist is missing"

cp "$manifest" "$manifest.before"
: >"$mise_log"
LATEST_VERSION=2.0.0 "$AGENT_TOOLS" update
cmp "$manifest" "$manifest.before" || fail "update changed the tool inventory"
for package in @example/pi @example/codex opencode-ai skills; do
  grep -Fx "upgrade --global --no-prune npm:${package}" "$mise_log" \
    >/dev/null || fail "latest npm tool was not upgraded: $package"
done
grep -Fx 'claude install latest' "$native_log" >/dev/null ||
  fail "Claude native updater was not used"

export TEST_AGENT_PI_VERSION=2.0.0 TEST_AGENT_CODEX_VERSION=2.0.0 TEST_AGENT_CLAUDE_VERSION=2.0.0
export TEST_AGENT_OPENCODE_VERSION=2.0.0 TEST_AGENT_SKILLS_VERSION=2.0.0
: >"$npm_log"
: >"$mise_log"
: >"$native_log"
LATEST_VERSION=2.0.0 "$AGENT_TOOLS" install
[ ! -s "$npm_log" ] || fail "current tools reinstalled"
[ ! -s "$mise_log" ] || fail "current mise tools reinstalled"
[ ! -s "$native_log" ] || fail "current native tools reinstalled"
LATEST_VERSION=3.0.0 "$AGENT_TOOLS" install
[ ! -s "$npm_log" ] || fail "install checked upstream for available tools"
LATEST_VERSION=3.0.0 "$AGENT_TOOLS" update
[ "$(wc -l < "$mise_log" | tr -d ' ')" -eq 4 ] ||
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

# Missing runtime prevents package installs; reports do not activate mise.
mv "$HOME/.local/bin/mise" "$HOME/.local/bin/mise.saved"
: >"$npm_log"
: >"$mise_log"
cp "$manifest" "$manifest.before"
for action in install update; do
  if "$AGENT_TOOLS" "$action" >"${tmp_dir}/node-error.log" 2>&1; then
    fail "$action accepted missing required runtime"
  fi
done
[ ! -s "$npm_log" ] || fail "npm ran without required Node"
[ ! -s "$mise_log" ] || fail "mise tools ran without required Node"
cmp "$manifest" "$manifest.before" || fail "runtime failure changed inventory"
LATEST_VERSION=2.0.0 "$AGENT_TOOLS" check >/dev/null
mv "$HOME/.local/bin/mise.saved" "$HOME/.local/bin/mise"

# Every npm CLI remains runnable after switching between two LTS runtimes.
host_os="$(uname -s)"
host_arch="$(uname -m)"
case "$host_arch" in
arm64|aarch64) host_arch=arm64 ;;
x86_64|amd64) host_arch=x86_64 ;;
*) fail "unsupported architecture: $host_arch" ;;
esac
case "$host_os" in
Darwin) host_os=darwin ;;
Linux) host_os=linux ;;
*) fail "unsupported OS: $host_os" ;;
esac
host_platform="${host_os}-${host_arch}"
other_platform=linux-x86_64
[ "$host_platform" != "$other_platform" ] || other_platform=darwin-arm64
npm_manifest="${tmp_dir}/all-npm-tools.json"
# The second tool is limited to another platform and must stay out.
jq --arg other "$other_platform" '
  {tools: [.tools[] | select(.installer == "npm")]} |
  .tools[0].trust_policy_excludes = [.tools[0].package + "@1.2.3"] |
  .tools[1].platforms = [$other]' \
  "$DOTFILES_DIR/.agents/tool-versions.json" >"$npm_manifest"
other_package="$(jq -r '.tools[1].package' "$npm_manifest")"
trust_exclude="$(jq -r '.tools[0].trust_policy_excludes[0]' "$npm_manifest")"
previous_manifest="$AGENT_TOOL_VERSIONS"
export AGENT_TOOL_VERSIONS="$npm_manifest"
"$AGENT_TOOLS" install
grep -F "trust_policy_excludes = [\"${trust_exclude}\"]" \
  "$HOME/.config/mise/conf.d/20-agent-tools.toml" >/dev/null ||
  fail "npm trust exception was not exact"
if grep -F "npm:${other_package}" \
  "$HOME/.config/mise/conf.d/20-agent-tools.toml"; then
  fail "a tool for another platform was written into mise config"
fi
switched_node="$HOME/.local/share/mise/installs/node/24.11.1/bin/node"
mkdir -p "$(dirname "$switched_node")"
printf '#!/bin/sh\necho v24.11.1\n' >"$switched_node"
chmod +x "$switched_node"
printf '24.11.1\n' >"$HOME/.local/share/mise/current-node"
activate_node >/dev/null
platform_commands="${tmp_dir}/platform-npm-commands.txt"
jq -r --arg platform "$host_platform" '
  (.platforms // ["darwin-arm64", "darwin-x86_64",
    "linux-arm64", "linux-x86_64"]) as $default_platforms |
  .tools[] |
  select(((.platforms // $default_platforms) | index($platform)) != null) |
  .command
' "$npm_manifest" >"$platform_commands"
while IFS= read -r command_name; do
  "$command_name" --version >/dev/null ||
    fail "npm CLI failed after Node switch: $command_name"
done <"$platform_commands"
if grep -F '/installs/node/' "$HOME/.config/mise/conf.d/20-agent-tools.toml";
then
  fail "mise npm config contains a versioned Node path"
fi
printf '%s\n' "$expected_node" >"$HOME/.local/share/mise/current-node"
activate_node >/dev/null
export AGENT_TOOL_VERSIONS="$previous_manifest"

# Native declarations dispatch through the existing installers.
# The npm Codex fixtures would shadow the native Codex.
rm "$stub_dir/codex" "$HOME/.local/share/mise/npm-tools/bin/codex"
# macOS installs Codex as a Homebrew cask; Linux uses OpenAI's installer.
mkdir -p "$tmp_dir/brew/bin"
cat >"$tmp_dir/brew/bin/brew" <<'STUB'
#!/bin/bash
prefix="$(cd "$(dirname "$0")/.." && pwd)"
case "$*" in
--prefix) echo "$prefix" ;;
'list --cask codex') [ -x "$prefix/bin/codex" ] ;;
'install --cask codex' | 'upgrade --cask codex')
    [ "${NATIVE_DOWNLOAD_FAIL:-false}" = false ] || exit 1
    printf '#!/bin/sh\necho "codex-cli 1.2.3"\n' >"$prefix/bin/codex"
    chmod +x "$prefix/bin/codex"
    echo codex >>"$NATIVE_LOG" ;;
*) exit 1 ;;
esac
STUB
chmod +x "$tmp_dir/brew/bin/brew"
cat >"$manifest" <<'JSON'
{"tools":[
 {"name":"Herdr","command":"herdr","installer":"herdr-native","channel":"latest","group":"agents","update":["herdr","update"]},
 {"name":"Treehouse","command":"treehouse","installer":"treehouse-native","channel":"latest","group":"agents"},
 {"name":"no-mistakes","command":"no-mistakes","installer":"no-mistakes-native","channel":"latest","group":"agents","update":["no-mistakes","update"]},
 {"name":"Cursor CLI","command":"agent","installer":"cursor-native","channel":"latest","group":"agents","update":["agent","update"]},
 {"name":"Grok Build","command":"grok","installer":"grok-native","channel":"latest","group":"agents","update":["grok","update"]},
 {"name":"Codex","command":"codex","installer":"codex-native","channel":"latest","group":"agents"}
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
    *chatgpt.com/codex/install.sh*)
        cat <<'INSTALLER'
[ "$CODEX_NON_INTERACTIVE" = 1 ] || exit 1
mkdir -p "$CODEX_INSTALL_DIR"
printf '#!/bin/sh\necho "codex-cli 1.2.3"\n' > "$CODEX_INSTALL_DIR/codex"
chmod +x "$CODEX_INSTALL_DIR/codex"
echo codex >> "$NATIVE_LOG"
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
        echo treehouse-check >> "$NATIVE_LOG"
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
if [ -n "${HERDR_INSTALL_DIR:-}" ]; then name=herdr
elif [ -n "${NO_MISTAKES_LINK_DIR:-}" ]; then name=no-mistakes
else name=treehouse; fi
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/$name" <<'CLI'
#!/bin/bash
if [ "$1" = --version ]; then echo 1.2.3; exit; fi
if [ "$1" = update ] && [ "$(basename "$0")" = herdr ] &&
    [ "${HERDR_ENV:-}" = 1 ]; then
    echo 'update failed: run `herdr update` outside herdr after detaching from the session' >&2
    exit 1
fi
if [ "$1" = update ]; then echo "update $(basename "$0")" >> "$NATIVE_LOG"; exit; fi
[ "$*" = 'integration install claude' ] || exit 1
mkdir -p "$CLAUDE_CONFIG_DIR/hooks"
printf '#!/bin/sh\n' > "$CLAUDE_CONFIG_DIR/hooks/herdr-agent-state.sh"
printf '%s\n' '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"herdr-agent-state.sh"}]}]}}' > "$CLAUDE_CONFIG_DIR/settings.json"
CLI
chmod +x "$HOME/.local/bin/$name"
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
export PATH="$HOME/.local/bin:$tmp_dir/brew/bin:$PATH"
: >"$native_log"
"$AGENT_TOOLS" install
"$AGENT_TOOLS" check >"$tmp_dir/native-report.log"
[ "$(grep -c '^PASS[[:space:]]' "$tmp_dir/native-report.log")" -eq 6 ] ||
  fail "native tool plan omitted an available tool"
for name in herdr treehouse no-mistakes cursor-agent grok codex; do
  [ "$(grep -Fxc "$name" "$native_log")" -eq 1 ] || fail "native install missing: $name"
done
: >"$native_log"
env -u HERDR_ENV "$AGENT_TOOLS" update
for name in herdr no-mistakes agent grok; do
  grep -Fx "update $name" "$native_log" >/dev/null || fail "native update missing: $name"
done
# Herdr refuses to update from inside its own panes; sync must continue.
: >"$native_log"
HERDR_ENV=1 "$AGENT_TOOLS" update >"$tmp_dir/herdr-pane.log" 2>&1 || {
  cat "$tmp_dir/herdr-pane.log" >&2
  fail "update failed inside a Herdr pane"
}
grep -F '[SKIP] Herdr: run `herdr update` outside Herdr after detaching' \
  "$tmp_dir/herdr-pane.log" >/dev/null || fail "Herdr skip was not reported"
! grep -Fx 'update herdr' "$native_log" >/dev/null ||
  fail "Herdr update ran inside a Herdr pane"
grep -Fx 'update no-mistakes' "$native_log" >/dev/null ||
  fail "Herdr skip stopped other native updates"
grep -Fx codex "$native_log" >/dev/null ||
  fail "Codex update did not rerun its platform installer"
for name in Codex Treehouse; do
  grep -E "^\[INFO\] Updating ${name} [0-9.]+ to latest\.\.\.$" \
    "$tmp_dir/herdr-pane.log" >/dev/null ||
    fail "$name update was not reported as an update"
  ! grep -F "Installing ${name}" "$tmp_dir/herdr-pane.log" ||
    fail "$name update was reported as an install"
done
grep -Fx treehouse-check "$native_log" >/dev/null || fail "Treehouse update was not checked"
! grep -Fx treehouse "$native_log" >/dev/null || fail "current Treehouse was downloaded"
! grep -Fx 'update treehouse' "$native_log" >/dev/null || fail "Treehouse used its API updater"
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

# A new npm declaration must install and update through mise.
export PATH="$HOME/.local/share/mise/npm-tools/bin:${stub_dir}:${REAL_NODE_BIN}:${HOST_JQ_DIR}:/usr/bin:/bin"
cat >"$manifest" <<'JSON'
{"tools":[{"name":"Fixture","command":"dotfiles-fixture",
 "package":"dotfiles-fixture","installer":"npm","channel":"latest",
 "group":"agents","group":"agents"
 }]}
JSON
if "$AGENT_TOOLS" check >"${tmp_dir}/missing.log"; then
  fail "new npm declaration was not missing before installation"
fi
"$AGENT_TOOLS" install
"$AGENT_TOOLS" check
[ "$(dotfiles-fixture --version)" = 1.2.3 ] || fail "mise did not install latest"
: >"$npm_log"
"$AGENT_TOOLS" install
[ ! -s "$npm_log" ] || fail "current npm package reinstalled"
cp "$manifest" "$manifest.before"
LATEST_VERSION=2.0.0 "$AGENT_TOOLS" update
[ "$(dotfiles-fixture --version)" = 2.0.0 ] || fail "explicit update omitted new declaration"
LATEST_VERSION=2.0.0 "$AGENT_TOOLS" check
cmp "$manifest" "$manifest.before" || fail "mise update changed inventory"
# A locally available latest-channel tool stays healthy until update resolves upstream.
printf '#!/bin/sh\necho 1.2.3\n' \
  >"$HOME/.local/share/mise/npm-tools/bin/dotfiles-fixture"
chmod +x "$HOME/.local/share/mise/npm-tools/bin/dotfiles-fixture"
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

# A foreign Codex first on PATH, e.g. an nvm global, is not the managed one.
codex_manifest="${tmp_dir}/codex-native.json"
printf '%s\n' '{"tools":[{"name":"Codex","command":"codex",' \
  '"installer":"codex-native","channel":"latest","group":"agents"}]}' \
  >"$codex_manifest"
foreign_dir="${tmp_dir}/foreign"
mkdir -p "$foreign_dir"
printf '#!/bin/sh\necho codex-cli 0.1.0\n' >"$foreign_dir/codex"
chmod +x "$foreign_dir/codex"
if AGENT_TOOL_VERSIONS="$codex_manifest" PATH="$foreign_dir:$tmp_dir/brew/bin:$PATH" \
  "$AGENT_TOOLS" install >"${tmp_dir}/foreign-codex.log" 2>&1; then
  fail "install accepted a foreign Codex instead of the managed one"
fi
if grep -F 'already installed' "${tmp_dir}/foreign-codex.log" >/dev/null; then
  fail "install reported a foreign Codex as installed"
fi
grep -F "another install is on PATH: $foreign_dir/codex" \
  "${tmp_dir}/foreign-codex.log" >/dev/null ||
  fail "install did not name the foreign Codex"

# Tool-sync channels run through public install, update, report and check.
jq '{tools: [.tools[] | select(.installer == "uv" or
  .installer == "gh-extension" or .package == "@ast-grep/cli" or
  .package == "fallow")]}' "$DOTFILES_DIR/.agents/tool-versions.json" \
  >"$manifest"
export CHANNEL_LOG="$tmp_dir/channels.log"
cat >"$stub_dir/uv" <<'STUB'
#!/bin/bash
set -eu
printf 'uv %s\n' "$*" >>"$CHANNEL_LOG"
[ "${UV_FAIL:-false}" = false ] || exit 29
spec="${!#}"
package="${spec%%==*}"
while IFS=$'\t' read -r command_name version; do
    [ "$version" != latest ] || version=4.1.4
    printf '#!/bin/sh\necho %s\n' "$version" >"$HOME/.local/bin/$command_name"
    chmod +x "$HOME/.local/bin/$command_name"
done < <("$REAL_JQ" -r --arg package "$package" '
  .tools[] | select(.package == $package) |
  .channel as $version | (.commands // [.command])[] |
  [., $version] | @tsv' "$AGENT_TOOL_VERSIONS")
STUB
cat >"$stub_dir/gh" <<'STUB'
#!/bin/bash
set -eu
case "$*" in
'dash --version')
    [ -f "$HOME/dash-installed" ] || exit 1
    printf 'gh-dash version dev\nmodule version: v4.26.3\n'
    ;;
'extension install dlvhdr/gh-dash --pin v4.26.3 --force')
    printf 'gh %s\n' "$*" >>"$CHANNEL_LOG"
    [ "${GH_EXTENSION_FAIL:-false}" = false ] || exit 30
    touch "$HOME/dash-installed"
    ;;
*) exit 31 ;;
esac
STUB
chmod +x "$stub_dir/uv" "$stub_dir/gh"
export PATH="$HOME/.local/bin:$PATH"
if "$AGENT_TOOLS" check >"$tmp_dir/channels-missing.log"; then
  fail "missing tool-sync tools passed their check"
fi
LATEST_VERSION=0.51.3 "$AGENT_TOOLS" install
"$AGENT_TOOLS" check
"$AGENT_TOOLS" report >"$tmp_dir/channels-report.log"
grep -F 'gh-dash' "$tmp_dir/channels-report.log" >/dev/null ||
  fail "report omitted the GitHub extension"
grep -Fx 'uv tool install rust-just==1.59.0' "$CHANNEL_LOG" >/dev/null ||
  fail "just did not use the pinned uv channel"
grep -Fx 'uv tool install yt-dlp==2026.10.26' "$CHANNEL_LOG" >/dev/null ||
  fail "yt-dlp did not use the pinned uv channel"
grep -Fx 'uv tool install cmakelang==0.6.13' "$CHANNEL_LOG" >/dev/null ||
  fail "cmakelang did not use the pinned uv channel"
grep -Fx 'uv tool install pylint' "$CHANNEL_LOG" >/dev/null ||
  fail "pylint did not use uv"
grep -Fx 'gh extension install dlvhdr/gh-dash --pin v4.26.3 --force' \
  "$CHANNEL_LOG" >/dev/null || fail "gh-dash did not use its release pin"
grep -Fx '"npm:@ast-grep/cli" = { version = "0.51.3", allow_builds = ["@ast-grep/cli"] }' \
  "$mise_config" >/dev/null || fail "ast-grep native postinstall is not approved"
for command_name in cmake-format cmake-lint cmake-annotate \
  cmake-genparsers ctest-to pylint; do
  command -v "$command_name" >/dev/null || fail "$command_name was not installed"
done
cp "$manifest" "$manifest.before"
: >"$CHANNEL_LOG"
LATEST_VERSION=0.51.3 "$AGENT_TOOLS" install
if grep -q '^gh ' "$CHANNEL_LOG"; then
  fail "current gh-dash was reinstalled"
fi
LATEST_VERSION=0.51.3 "$AGENT_TOOLS" update
grep -Fx 'uv tool install --upgrade rust-just==1.59.0' "$CHANNEL_LOG" \
  >/dev/null || fail "update did not preserve the uv release pin"
cmp "$manifest" "$manifest.before" || fail "channel update rewrote inventory"
if UV_FAIL=true "$AGENT_TOOLS" install >"$tmp_dir/uv-failure.log" 2>&1; then
  fail "uv install failure was ignored"
fi
rm "$HOME/dash-installed"
if GH_EXTENSION_FAIL=true "$AGENT_TOOLS" install \
  >"$tmp_dir/gh-extension-failure.log" 2>&1; then
  fail "GitHub extension failure was ignored"
fi
jq '(.tools[] | select(.installer == "gh-extension")).channel = "latest"' \
  "$manifest" >"$tmp_dir/unpinned-extension.json"
if AGENT_TOOL_VERSIONS="$tmp_dir/unpinned-extension.json" \
  "$AGENT_TOOLS" plan >/dev/null 2>&1; then
  fail "extension installer accepted an unsupported latest pin"
fi

echo "[INFO] agent tools smoke test passed"

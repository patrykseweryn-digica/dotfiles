#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENT_TOOLS="${DOTFILES_DIR}/scripts/agent-tools.sh"
JUST_BIN="$(command -v just)"

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
mkdir -p "$stub_dir"

cat > "$manifest" <<'JSON'
{
  "tools": [
    {
      "name": "Pi",
      "command": "pi",
      "package": "@example/pi",
      "channel": "latest",
      "version": "1.2.3",
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
    cat > "${stub_dir}/${command_name}" <<'STUB'
#!/bin/bash
name="$(basename "$0" | tr '[:lower:]' '[:upper:]')"
variable="${name}_VERSION"
printf '%s %s\n' "$(basename "$0")" "${!variable:-1.2.3}"
STUB
done

cat > "${stub_dir}/npm" <<'STUB'
#!/bin/bash
if [ "$1" = view ]; then
    printf '%s\n' "${LATEST_VERSION:-2.0.0}"
else
    printf '%s\n' "$*" >> "$NPM_LOG"
fi
STUB

cat > "${stub_dir}/curl" <<'STUB'
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

CODEX_VERSION=1.2.2
export CODEX_VERSION
if "$AGENT_TOOLS" check > "${tmp_dir}/drift.log" 2>&1; then
    fail "version check ignored drift"
fi
unset CODEX_VERSION

PI_VERSION=1.0.0
CODEX_VERSION=1.0.0
CLAUDE_VERSION=1.0.0
OPENCODE_VERSION=1.0.0
SKILLS_VERSION=1.0.0
export PI_VERSION CODEX_VERSION CLAUDE_VERSION OPENCODE_VERSION SKILLS_VERSION
: > "$npm_log"
: > "$native_log"
"$AGENT_TOOLS" install

for package in @example/pi @example/codex opencode-ai skills; do
    grep -Fx "install -g ${package}@1.2.3" "$npm_log" >/dev/null || \
        fail "exact npm version not installed: $package"
done
grep -Fx '1.2.3' "$native_log" >/dev/null || \
    fail "exact Claude version not installed"

AGENT_TOOLS="$AGENT_TOOLS" \
    "$JUST_BIN" --justfile "${DOTFILES_DIR}/justfile" update-agent-tools
jq -e 'all(.tools[]; .version == "2.0.0")' "$manifest" >/dev/null || \
    fail "update did not resolve moving channels into exact versions"

if grep -En 'agent-tools|npm view|@latest' \
    "${DOTFILES_DIR}/sync-agents.sh" >/dev/null; then
    fail "configuration push path can update agent tool versions"
fi

echo "[INFO] agent tools smoke test passed"

#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
    echo "[ERROR] $*" >&2
    exit 1
}

cd "$DOTFILES_DIR"

tracked_symlinks="$(git ls-files -s | awk '$1 == "120000" {print $4}')"
while IFS= read -r link_path; do
    [ -n "$link_path" ] || continue
    [ -e "$link_path" ] || fail "tracked symlink is broken: $link_path -> $(readlink "$link_path")"
done <<EOF
$tracked_symlinks
EOF

[ -f AGENTS.md ] && [ ! -L AGENTS.md ] || fail "root AGENTS.md must be repo-local"
[ -f CLAUDE.md ] && [ ! -L CLAUDE.md ] || fail "root CLAUDE.md must be a regular import file"
cmp -s CLAUDE.md <(printf '%s\n' \
    '<!-- Points Claude at AGENTS.md via import; edit AGENTS.md, not this file. -->' \
    '@AGENTS.md') || fail "root CLAUDE.md must import repo-local AGENTS.md"
if grep -q 'docs/agents/' .agents/AGENTS.md; then
    fail "global instructions must not include dotfiles-only documentation"
fi
for doc in issue-tracker triage-labels domain; do
    [ -f "docs/agents/$doc.md" ] || fail "missing repo-local doc: $doc"
    grep -Fq "docs/agents/$doc.md" AGENTS.md || fail "missing repo-local pointer: $doc"
done

[ -L config/codex/AGENTS.md ] || fail "Codex AGENTS.md adapter must be a symlink"
[ "$(readlink config/codex/AGENTS.md)" = "../../.agents/AGENTS.md" ] || fail "Codex AGENTS.md adapter points at wrong target"

[ -f .agents/plugin-manifest.json ] || fail "Shared plugin manifest is missing"
[ -L config/codex/plugin-manifest.json ] || fail "Codex plugin manifest adapter must be a symlink"
[ "$(readlink config/codex/plugin-manifest.json)" = "../../.agents/plugin-manifest.json" ] || fail "Codex plugin manifest adapter points at wrong target"
jq -e '
    (.plugins | type) == "object" and
    any(.plugins[]; (.codex? // "") | startswith("plugin_")) and
    any(.plugins[]; (.claude? // "") | contains("@")) and
    ((.codexPlugins // []) | type) == "array" and
    ((.codexMarketplaces // {}) | type) == "object"
' .agents/plugin-manifest.json >/dev/null || fail "Shared plugin manifest is invalid"

[ -f config/codex/settings.toml ] || fail "Codex settings template is missing"

[ -L config/claude/CLAUDE.md ] || fail "Claude CLAUDE.md adapter must be a symlink"
[ "$(readlink config/claude/CLAUDE.md)" = "../../.agents/AGENTS.md" ] || fail "Claude CLAUDE.md adapter points at wrong target"
[ -f config/claude/settings.local.json ] || fail "Claude local settings are missing"

[ -L config/claude/claude-manifest.json ] || fail "Claude plugin manifest adapter must be a symlink"
[ "$(readlink config/claude/claude-manifest.json)" = "../../.agents/plugin-manifest.json" ] || fail "Claude plugin manifest adapter points at wrong target"

[ -L config/opencode/AGENTS.md ] || fail "OpenCode AGENTS.md adapter must be a symlink"
[ "$(readlink config/opencode/AGENTS.md)" = "../../.agents/AGENTS.md" ] || fail "OpenCode AGENTS.md adapter points at wrong target"

[ -L config/pi/AGENTS.md ] || fail "Pi AGENTS.md adapter must be a symlink"
[ "$(readlink config/pi/AGENTS.md)" = "../../.agents/AGENTS.md" ] || fail "Pi AGENTS.md adapter points at wrong target"
jq -e '
    (.packages | type) == "array" and
    (.packages | length) > 0 and
    all(.packages[]; contains("@")) and
    (keys - [
        "defaultModel",
        "defaultProvider",
        "defaultThinkingLevel",
        "hideThinkingBlock",
        "enabledModels",
        "theme",
        "images",
        "terminal",
        "quietStartup",
        "steeringMode",
        "followUpMode",
        "collapseChangelog",
        "packages"
    ] | length) == 0
' config/pi/settings.json >/dev/null || fail "Pi stable settings are invalid"

[ -L config/claude/mcp-servers.json ] || fail "Claude MCP adapter must be a symlink"
[ "$(readlink config/claude/mcp-servers.json)" = "../../.agents/mcp-servers.json" ] || fail "Claude MCP adapter points at wrong target"

[ -L config/claude/skill-lock.json ] || fail "Claude skill lock adapter must be a symlink"
[ "$(readlink config/claude/skill-lock.json)" = "../../.agents/skill-lock.json" ] || fail "Claude skill lock adapter points at wrong target"

[ -L config/claude/skills-custom ] || fail "Claude custom skills adapter must be a symlink"
[ "$(readlink config/claude/skills-custom)" = "../../.agents/skills-custom" ] || fail "Claude custom skills adapter points at wrong target"

if git ls-files '.agents/skills/*' | grep -q .; then
    git ls-files '.agents/skills/*' >&2
    fail ".agents/skills must stay runtime-only; track lock/custom skills instead"
fi

if git ls-files 'skills-lock.json' | grep -q .; then
    fail "legacy root skills-lock.json must not be tracked"
fi

echo "[INFO] agent repo layout smoke test passed"

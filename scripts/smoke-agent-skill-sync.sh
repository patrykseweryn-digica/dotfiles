#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK_FILE="${DOTFILES_DIR}/.agents/skill-lock.json"
CUSTOM_SKILLS_DIR="${DOTFILES_DIR}/.agents/skills-custom"

fail() {
    echo "[ERROR] $*" >&2
    exit 1
}

JQ_BIN="$(command -v jq 2>/dev/null || true)"
[ -n "$JQ_BIN" ] || fail "jq is required"

tmp_dir="$(mktemp -d)"
cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

home_dir="${tmp_dir}/home"
stub_dir="${tmp_dir}/stubs"
lock_names="${tmp_dir}/lock-skill-names.txt"
sync_log="${tmp_dir}/sync.log"

mkdir -p "$home_dir/.agents/skills" "$stub_dir"
ln -s "$JQ_BIN" "${stub_dir}/jq"
jq -r '.skills | keys[]' "$LOCK_FILE" > "$lock_names"

# Pretend lock-managed skills already exist in the shared Codex-compatible runtime.
# The smoke test should prove sync links them into Claude/OpenCode without needing npx.
while IFS= read -r skill_name; do
    [ -n "$skill_name" ] || continue
    mkdir -p "${home_dir}/.agents/skills/${skill_name}"
    printf '# %s\n' "$skill_name" > "${home_dir}/.agents/skills/${skill_name}/SKILL.md"
done < "$lock_names"

export HOME="$home_dir"
export CODEX_HOME="${HOME}/.codex"
export OPENCODE_CONFIG_DIR="${HOME}/.config/opencode"
export OPENCODE_CONFIG="${OPENCODE_CONFIG_DIR}/opencode.json"
export PATH="${stub_dir}:/usr/bin:/bin"

if ! "${DOTFILES_DIR}/sync-agents.sh" --quiet install > "$sync_log" 2>&1; then
    cat "$sync_log" >&2
    fail "sync-agents.sh install failed"
fi

if grep -F "Installing skill:" "$sync_log" >/dev/null 2>&1; then
    cat "$sync_log" >&2
    fail "sync tried to install lock-managed skills instead of linking existing shared copies"
fi

while IFS= read -r skill_name; do
    [ -n "$skill_name" ] || continue
    [ -e "${HOME}/.agents/skills/${skill_name}/SKILL.md" ] || fail "missing shared skill: $skill_name"
    [ -e "${HOME}/.claude/skills/${skill_name}/SKILL.md" ] || fail "missing Claude skill: $skill_name"
    [ -e "${OPENCODE_CONFIG_DIR}/skills/${skill_name}/SKILL.md" ] || fail "missing OpenCode skill: $skill_name"
done < "$lock_names"

for skill_dir in "$CUSTOM_SKILLS_DIR"/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name="$(basename "$skill_dir")"
    [ -e "${HOME}/.agents/skills/${skill_name}/SKILL.md" ] || fail "missing shared custom skill: $skill_name"
    [ -e "${HOME}/.claude/skills/${skill_name}/SKILL.md" ] || fail "missing Claude custom skill: $skill_name"
    [ -e "${OPENCODE_CONFIG_DIR}/skills/${skill_name}/SKILL.md" ] || fail "missing OpenCode custom skill: $skill_name"
done

for skill_file in "$CUSTOM_SKILLS_DIR"/*.skill; do
    [ -f "$skill_file" ] || continue
    skill_name="$(basename "$skill_file")"
    [ -e "${HOME}/.agents/skills/${skill_name}" ] || fail "missing shared custom skill file: $skill_name"
    [ -e "${HOME}/.claude/skills/${skill_name}" ] || fail "missing Claude custom skill file: $skill_name"
    [ -e "${OPENCODE_CONFIG_DIR}/skills/${skill_name}" ] || fail "missing OpenCode custom skill file: $skill_name"
done

[ -e "${CODEX_HOME}/AGENTS.md" ] || fail "missing Codex AGENTS.md"
[ -e "${HOME}/.claude/CLAUDE.md" ] || fail "missing Claude CLAUDE.md"
[ -e "${OPENCODE_CONFIG_DIR}/AGENTS.md" ] || fail "missing OpenCode AGENTS.md"

echo "[INFO] agent skill sync smoke test passed"

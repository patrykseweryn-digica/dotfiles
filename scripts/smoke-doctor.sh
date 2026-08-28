#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCTOR="${DOTFILES_DIR}/scripts/doctor.sh"

fail() {
    echo "[ERROR] $*" >&2
    exit 1
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

home_dir="${tmp_dir}/home"
stub_dir="${tmp_dir}/stubs"
check_log="${tmp_dir}/checks.log"
mkdir -p \
    "${home_dir}/.agents/skills" \
    "${home_dir}/.claude/skills" \
    "${home_dir}/.codex" \
    "${home_dir}/.config/opencode/skills" \
    "$stub_dir"

cp "${DOTFILES_DIR}/.agents/skill-lock.json" \
    "${home_dir}/.agents/.skill-lock.json"
ln -s "${DOTFILES_DIR}/config/codex/AGENTS.md" \
    "${home_dir}/.codex/AGENTS.md"
ln -s "${DOTFILES_DIR}/config/claude/CLAUDE.md" \
    "${home_dir}/.claude/CLAUDE.md"
ln -s "${DOTFILES_DIR}/config/opencode/AGENTS.md" \
    "${home_dir}/.config/opencode/AGENTS.md"

cat > "${stub_dir}/sync-agents" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$DOCTOR_CHECK_LOG"
[ "$*" != "${FAIL_CHECK:-}" ]
STUB

cat > "${stub_dir}/npm" <<'STUB'
#!/bin/bash
printf '%s\n' "${LATEST_VERSION:-1.2.3}"
STUB

cat > "${stub_dir}/codex" <<'STUB'
#!/bin/bash
printf 'codex-cli 1.2.3\n'
STUB

cat > "${stub_dir}/claude" <<'STUB'
#!/bin/bash
printf '1.2.3 (Claude Code)\n'
STUB
chmod +x "${stub_dir}"/*

run_doctor() {
    HOME="$home_dir" \
    PATH="${stub_dir}:/usr/bin:/bin" \
    DOTFILES_DIR="$DOTFILES_DIR" \
    SYNC_AGENTS="${stub_dir}/sync-agents" \
    DOCTOR_CHECK_LOG="$check_log" \
    FAIL_CHECK="${FAIL_CHECK:-}" \
    LATEST_VERSION="${LATEST_VERSION:-1.2.3}" \
    "$DOCTOR" > "${tmp_dir}/doctor.log" 2>&1
}

: > "$check_log"
run_doctor || { cat "${tmp_dir}/doctor.log" >&2; fail "doctor failed"; }

for expected in \
    plugins-check \
    claude-settings-check \
    mcp-check \
    'custom-skills-export --check'; do
    grep -Fx "$expected" "$check_log" >/dev/null || \
        fail "doctor skipped: $expected"
done

FAIL_CHECK=plugins-check
if run_doctor; then
    fail "doctor passed with plugin drift"
fi
unset FAIL_CHECK

ln -s "${home_dir}/missing" "${home_dir}/.agents/skills/broken-link"
if run_doctor; then
    fail "doctor passed with a broken skill link"
fi
rm "${home_dir}/.agents/skills/broken-link"

LATEST_VERSION=9.9.9
if run_doctor; then
    fail "doctor passed with version drift"
fi
unset LATEST_VERSION

jq '.skills.extra = {source: "example/skills"}' \
    "${home_dir}/.agents/.skill-lock.json" > "${tmp_dir}/lock.json"
mv "${tmp_dir}/lock.json" "${home_dir}/.agents/.skill-lock.json"
if run_doctor; then
    fail "doctor passed with skill lock drift"
fi

if grep -Eq \
    'agent-plugin-check|claude-settings-check|mcp-config-check' \
    "${DOTFILES_DIR}/.pre-commit-config.yaml"; then
    fail "pre-commit still contains live machine checks"
fi

echo "[INFO] doctor smoke test passed"

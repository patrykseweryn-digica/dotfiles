#!/bin/bash
# Drive public just install, doctor and sync with three group settings:
# no setting (all groups), core only, and an unknown group.
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Hook-local Git state must not redirect fixture repositories.
# shellcheck disable=SC2046
unset $(git -C "$DOTFILES_DIR" rev-parse --local-env-vars)
unset DOTFILES_FIRSTMATE_HOME CODEX_HOME CLAUDE_SETTINGS_FILE

fail() {
    echo "[ERROR] $*" >&2
    exit 1
}

JUST_BIN="$(command -v just)"
JQ_BIN="$(command -v jq)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
stub_dir="${tmp_dir}/stubs"
calls="${tmp_dir}/calls.log"
mkdir -p "$stub_dir" "${tmp_dir}/fixture"
ln -s "$JQ_BIN" "${stub_dir}/jq"
: >"$calls"

# Network clients must never run; each call is recorded as a failure.
for command_name in npm curl gh; do
    cat >"${stub_dir}/${command_name}" <<'STUB'
#!/bin/bash
printf 'network %s %s\n' "$(basename "$0")" "$*" >>"$CALLS_LOG"
exit 99
STUB
    chmod +x "${stub_dir}/${command_name}"
done

write_env() {
    local file="$1"
    shift
    printf '%s\n' 'EMAIL=test@example.com' 'WORK_EMAIL=work@example.com' \
        'EDITOR=vim' "$@" >"$file"
}
write_env "${tmp_dir}/none.env"
write_env "${tmp_dir}/core.env" 'DOTFILES_GROUPS=core'
write_env "${tmp_dir}/unknown.env" 'DOTFILES_GROUPS="core, gaming"'
write_env "${tmp_dir}/no-core.env" 'DOTFILES_GROUPS=agents'

case "$(uname -s)" in
Darwin) ghostty_target='Library/Application Support/com.mitchellh.ghostty/config.ghostty' ;;
*) ghostty_target='.config/ghostty/config' ;;
esac

# Install: the real main flow with external installers replaced by loggers.
cp "${DOTFILES_DIR}/justfile" "${tmp_dir}/fixture/justfile"
cat >"${tmp_dir}/fixture/install.sh" <<'STUB'
#!/bin/bash
set -eu
source "$GROUPS_TEST_REPO/install.sh"
step() { printf 'step %s\n' "$1" >>"$CALLS_LOG"; }
setup_repo_git() { :; }
install_uv() { step uv; }
install_zsh() { step zsh; }
install_oh_my_zsh() { step oh-my-zsh; }
install_pipx() { step pipx; }
install_tools() { step cli-tools; }
install_fonts() { step fonts; }
install_node() { step node; }
activate_node() { step node-activation; }
install_developer_tools() { step developer-tools; }
install_terminal_colors() { step terminal-colors; }
install_macos_apps() { step macos-apps; }
install_tmux_plugins() { step tmux-plugins; }
setup_firstmate() { step firstmate; }
configure_agent_apps() { step agent-apps; }
sync_agent_config() { step agent-config; }
main
STUB
chmod +x "${tmp_dir}/fixture/install.sh"

run_install() {
    local case_name="$1"
    HOME="${tmp_dir}/${case_name}-home" \
        PATH="${stub_dir}:/usr/bin:/bin" \
        CALLS_LOG="$calls" GROUPS_CASE="$case_name" \
        GROUPS_TEST_REPO="$DOTFILES_DIR" \
        DOTFILES_ENV_FILE="${tmp_dir}/${case_name}.env" \
        DOTFILES_SKIP_SSH=true \
        "$JUST_BIN" --justfile "${tmp_dir}/fixture/justfile" install \
        >"${tmp_dir}/install.log" 2>&1
}

expect_log() {
    grep -F -- "$2" "${tmp_dir}/$1.log" >/dev/null ||
        fail "$3 (missing '$2' in $1.log)"
}

reject_log() {
    if grep -F -- "$2" "${tmp_dir}/$1.log" >/dev/null; then
        fail "$3 (unexpected '$2' in $1.log)"
    fi
}

all_steps='uv zsh oh-my-zsh pipx cli-tools fonts node developer-tools
terminal-colors macos-apps tmux-plugins firstmate agent-apps agent-config'
core_steps='uv zsh oh-my-zsh pipx cli-tools tmux-plugins'

for case_name in none core unknown no-core; do
    mkdir -p "${tmp_dir}/${case_name}-home"
done

# No setting keeps every group, as on existing machines.
run_install none || {
    cat "${tmp_dir}/install.log" >&2
    fail "install without a group setting failed"
}
for name in $all_steps; do
    grep -Fx "step $name" "$calls" >/dev/null ||
        fail "install without a setting skipped step: $name"
done
for target in .zshrc .claude/CLAUDE.md "$ghostty_target"; do
    [ -L "${tmp_dir}/none-home/${target}" ] ||
        fail "install without a setting omitted link: $target"
done
reject_log install 'is not selected' "install without a setting skipped a group"
echo "[INFO] install: no setting installs every group"

# Core only installs core elements and names each skipped group.
: >"$calls"
run_install core || {
    cat "${tmp_dir}/install.log" >&2
    fail "core-only install failed"
}
for name in $all_steps; do
    if grep -Fx "step $name" "$calls" >/dev/null; then
        case " $(echo $core_steps) " in
        *" $name "*) ;;
        *) fail "core-only install ran step from another group: $name" ;;
        esac
    else
        case " $(echo $core_steps) " in
        *" $name "*) fail "core-only install skipped core step: $name" ;;
        esac
    fi
done
[ -L "${tmp_dir}/core-home/.zshrc" ] || fail "core-only install omitted .zshrc"
for target in .claude/CLAUDE.md .codex/AGENTS.md "$ghostty_target"; do
    [ ! -e "${tmp_dir}/core-home/${target}" ] &&
        [ ! -L "${tmp_dir}/core-home/${target}" ] ||
        fail "core-only install created link from another group: $target"
done
[ ! -d "${tmp_dir}/core-home/.claude" ] ||
    fail "core-only install created agent directories"
expect_log install 'fonts: group desktop is not selected' \
    "core-only install did not name the skipped desktop step"
expect_log install 'developer tools: group agents is not selected' \
    "core-only install did not name the skipped agents step"
grep -E "^\[INFO\] +skipped \(group agents\): mise and Node.js LTS$" \
    "${tmp_dir}/install.log" >/dev/null ||
    fail "core-only install summary omitted the skipped group"
grep -F 'network ' "$calls" && fail "core-only install used the network"
echo "[INFO] install: core only skips agents and desktop"

# Invalid settings fail before any machine change.
for case_name in unknown no-core; do
    : >"$calls"
    if run_install "$case_name"; then
        fail "$case_name group setting passed install"
    fi
    [ ! -s "$calls" ] || fail "$case_name group setting changed the machine"
    [ -z "$(ls -A "${tmp_dir}/${case_name}-home")" ] ||
        fail "$case_name group setting changed HOME"
done
run_install unknown || true
expect_log install '[ERROR] Unknown install group "gaming" in DOTFILES_GROUPS' \
    "unknown group error is unclear"
expect_log install 'Use: core, agents, desktop' \
    "unknown group error omitted valid groups"
run_install no-core || true
expect_log install '[ERROR] DOTFILES_GROUPS must include core' \
    "missing core error is unclear"
echo "[INFO] install: invalid groups fail before changes"

# Doctor: real planners. Core tools are simulated without mise.
cat >"${stub_dir}/core-tools" <<'STUB'
#!/bin/bash
printf 'core-tools %s\n' "$*" >>"$CALLS_LOG"
case "$1" in
plan) printf 'PASS\ttools\tnone\tCore tool is available\n' ;;
update) ;;
*) exit 1 ;;
esac
STUB
# Agent adapters log every call. With core only, plans come from the real
# scripts, which must skip by group. Otherwise plans are fixture rows.
for adapter in sync-agents agent-tools; do
    case "$adapter" in
    sync-agents)
        real="${DOTFILES_DIR}/sync-agents.sh"
        rows='PASS\tsettings:codex\tnone\tCodex settings match\n'
        ;;
    agent-tools)
        real="${DOTFILES_DIR}/scripts/agent-tools.sh"
        rows='PASS\ttools\tnone\tCodex is available\n'
        ;;
    esac
    cat >"${stub_dir}/${adapter}" <<STUB
#!/bin/bash
printf '%s %s\n' "$adapter" "\$*" >>"\$CALLS_LOG"
case "\$*" in
'--quiet state-plan' | plan)
    [ "\$GROUPS_CASE" != core ] || exec "$real" "\$@"
    printf '$rows'
    ;;
esac
exit 0
STUB
done
chmod +x "${stub_dir}/core-tools" "${stub_dir}/sync-agents" \
    "${stub_dir}/agent-tools"

run_doctor() {
    local case_name="$1"
    HOME="${tmp_dir}/${case_name}-home" \
        PATH="${stub_dir}:/usr/bin:/bin" \
        CALLS_LOG="$calls" GROUPS_CASE="$case_name" \
        DOTFILES_ENV_FILE="${tmp_dir}/${case_name}.env" \
        CORE_TOOLS="${stub_dir}/core-tools" \
        SYNC_AGENTS="${stub_dir}/sync-agents" \
        AGENT_TOOLS="${stub_dir}/agent-tools" \
        "$JUST_BIN" --justfile "${DOTFILES_DIR}/justfile" doctor \
        >"${tmp_dir}/doctor.log" 2>&1
}

: >"$calls"
run_doctor core || {
    cat "${tmp_dir}/doctor.log" >&2
    fail "core-only doctor failed with only skipped groups"
}
for category in settings:codex settings:claude settings:opencode \
    settings:pi mcp skills plugins hooks node; do
    grep -E "^\[SKIP\] ${category}: .*group agents is not selected$" \
        "${tmp_dir}/doctor.log" >/dev/null ||
        fail "core-only doctor did not skip $category with its group"
done
for tool in Pi 'Cursor CLI' 'Claude Code'; do
    expect_log doctor "[SKIP] tools: ${tool} skipped: group agents is not selected" \
        "core-only doctor did not skip agent tool $tool"
done
expect_log doctor "[SKIP] links: ${ghostty_target} skipped: group desktop is not selected" \
    "core-only doctor did not skip the desktop link"
expect_log doctor '[PASS] links:' "core-only doctor did not check core links"
reject_log doctor '[FAIL]' "core-only doctor reported a failure"
reject_log doctor '[UPDATE]' "core-only doctor requested an update"
reject_log doctor '[EXPORT]' "core-only doctor requested an export"
grep -F 'network ' "$calls" && fail "core-only doctor used the network"
echo "[INFO] doctor: core only passes with SKIP rows"

: >"$calls"
run_doctor none || true
reject_log doctor 'is not selected' "doctor without a setting skipped a group"
grep -Fx 'agent-tools plan' "$calls" >/dev/null ||
    fail "doctor without a setting skipped agent tools"
for category in hooks node; do
    grep -E "^\[(PASS|UPDATE|FAIL)\] ${category}:" \
        "${tmp_dir}/doctor.log" >/dev/null ||
        fail "doctor without a setting did not check $category"
done
echo "[INFO] doctor: no setting plans every group"

: >"$calls"
if run_doctor unknown; then fail "doctor accepted an unknown group"; fi
expect_log doctor '[ERROR] Unknown install group "gaming"' \
    "doctor did not explain the unknown group"
[ ! -s "$calls" ] || fail "doctor planned with an unknown group"
echo "[INFO] doctor: unknown group fails clearly"

# Sync: a fixture checkout with one upstream commit to fast-forward.
remote_dir="${tmp_dir}/remote.git"
checkout="${tmp_dir}/checkout"
publisher="${tmp_dir}/publisher"
git init --bare --quiet --initial-branch=master "$remote_dir"
git init --quiet --initial-branch=master "$checkout"
git -C "$checkout" config user.name "Smoke Test"
git -C "$checkout" config user.email "smoke@example.com"
touch "${checkout}/base"
git -C "$checkout" add base
git -C "$checkout" commit --quiet -m "test: initialize fixture"
git -C "$checkout" remote add origin "$remote_dir"
git -C "$checkout" push --quiet --set-upstream origin master
git clone --quiet "$remote_dir" "$publisher"
git -C "$publisher" config user.name "Smoke Test"
git -C "$publisher" config user.email "smoke@example.com"
touch "${publisher}/upstream"
git -C "$publisher" add upstream
git -C "$publisher" commit --quiet -m "test: add upstream change"
git -C "$publisher" push --quiet

run_sync() {
    local case_name="$1" repo_dir="$DOTFILES_DIR"
    HOME="${tmp_dir}/${case_name}-home" \
        PATH="${stub_dir}:/usr/bin:/bin" \
        CALLS_LOG="$calls" GROUPS_CASE="$case_name" \
        DOTFILES_DIR="$checkout" \
        DOTFILES_ENV_FILE="${tmp_dir}/${case_name}.env" \
        UPDATE_SCRIPT="${repo_dir}/scripts/update-local.sh" \
        INSTALL_SCRIPT="${repo_dir}/install.sh" \
        STATE_PLAN="${repo_dir}/scripts/state-plan.sh" \
        CORE_TOOLS="${stub_dir}/core-tools" \
        SYNC_AGENTS="${stub_dir}/sync-agents" \
        AGENT_TOOLS="${stub_dir}/agent-tools" \
        "$JUST_BIN" --justfile "${repo_dir}/justfile" sync \
        >"${tmp_dir}/sync.log" 2>&1
}

: >"$calls"
if run_sync unknown; then fail "sync accepted an unknown group"; fi
expect_log sync '[ERROR] Unknown install group "gaming"' \
    "sync did not explain the unknown group"
expect_log sync '[RESULT] FAIL' "sync omitted its failed result"
[ ! -e "${checkout}/upstream" ] || fail "sync pulled before group validation"
[ ! -s "$calls" ] || fail "sync changed the machine with an unknown group"
echo "[INFO] sync: unknown group fails before fetch"

: >"$calls"
run_sync core || {
    cat "${tmp_dir}/sync.log" >&2
    fail "core-only sync failed with only skipped groups"
}
[ -e "${checkout}/upstream" ] || fail "core-only sync did not pull"
grep -Fx 'core-tools update' "$calls" >/dev/null ||
    fail "core-only sync did not refresh core tools"
if grep -vE '^(core-tools (plan|update)|sync-agents --quiet state-plan|agent-tools plan)$' \
    "$calls"; then
    fail "core-only sync called an unselected adapter"
fi
for phase in 'Node and agent tools' 'Pi packages' skills \
    'plugin versions'; do
    expect_log sync "[SKIP] ${phase}: group agents is not selected" \
        "core-only sync did not skip $phase with its group"
done
expect_log sync '[RESULT] PASS' "core-only sync did not pass"
echo "[INFO] sync: core only refreshes core and passes"

git -C "$publisher" commit --quiet --allow-empty -m "test: next upstream"
git -C "$publisher" push --quiet
: >"$calls"
run_sync none || true
reject_log sync 'is not selected' "sync without a setting skipped a group"
grep -Fx 'agent-tools update' "$calls" >/dev/null ||
    fail "sync without a setting skipped agent tools"
echo "[INFO] sync: no setting refreshes every group"

echo "[INFO] Install group smoke test passed (external installers simulated)"

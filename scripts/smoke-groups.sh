#!/bin/bash
# Drive public Make commands with
# these group settings: no setting (core only), core only, all groups,
# an unknown group, and a list without core.
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${DOTFILES_DIR}/scripts/host-tools.sh"

# Hook-local Git state must not redirect fixture repositories.
# shellcheck disable=SC2046
unset $(git -C "$DOTFILES_DIR" rev-parse --local-env-vars)
unset DOTFILES_FIRSTMATE_HOME CODEX_HOME CLAUDE_SETTINGS_FILE

fail() {
    echo "[ERROR] $*" >&2
    exit 1
}

MAKE_BIN="$(command -v make)"
PYTHON_BIN="$(command -v python3)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
set_smoke_base_path "$tmp_dir"
stub_dir="${tmp_dir}/stubs"
calls="${tmp_dir}/calls.log"
mkdir -p "$stub_dir" "${tmp_dir}/fixture"
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
write_env "${tmp_dir}/all.env" 'DOTFILES_GROUPS=core,agents,desktop'
write_env "${tmp_dir}/unknown.env" 'DOTFILES_GROUPS="core, gaming"'
write_env "${tmp_dir}/no-core.env" 'DOTFILES_GROUPS=agents'

case "$(uname -s)" in
Darwin) ghostty_target='Library/Application Support/com.mitchellh.ghostty/config.ghostty' ;;
*) ghostty_target='.config/ghostty/config' ;;
esac

# Install: the real main flow with external installers replaced by loggers.
cp "${DOTFILES_DIR}/Makefile" "${tmp_dir}/fixture/Makefile"
cat >"${tmp_dir}/fixture/install.sh" <<'STUB'
#!/bin/bash
set -eu
source "$GROUPS_TEST_REPO/install.sh"
step() { printf 'step %s\n' "$1" >>"$CALLS_LOG"; }
setup_repo_git() { :; }
install_uv() { step uv; }
install_zsh() { step zsh; }
install_oh_my_zsh() { step oh-my-zsh; }
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
        PATH="${stub_dir}:${SMOKE_BASE_PATH}" \
        CALLS_LOG="$calls" GROUPS_CASE="$case_name" \
        GROUPS_TEST_REPO="$DOTFILES_DIR" \
        DOTFILES_ENV_FILE="${tmp_dir}/${case_name}.env" \
        DOTFILES_SKIP_SSH=true \
        "$MAKE_BIN" --no-print-directory -C "${tmp_dir}/fixture" install \
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

all_steps='uv zsh oh-my-zsh cli-tools fonts node developer-tools
terminal-colors macos-apps tmux-plugins firstmate agent-apps agent-config'
core_steps='uv zsh oh-my-zsh cli-tools tmux-plugins'

for case_name in none core all unknown no-core; do
    mkdir -p "${tmp_dir}/${case_name}-home"
done

# All groups install every step and link.
run_install all || {
    cat "${tmp_dir}/install.log" >&2
    fail "install with all groups failed"
}
for name in $all_steps; do
    grep -Fx "step $name" "$calls" >/dev/null ||
        fail "install with all groups skipped step: $name"
done
for target in .zshrc .claude/CLAUDE.md "$ghostty_target"; do
    [ -L "${tmp_dir}/all-home/${target}" ] ||
        fail "install with all groups omitted link: $target"
done
reject_log install 'is not selected' "install with all groups skipped a group"
echo "[INFO] install: all groups install every element"

# Core only, and no setting, install core elements and name skipped groups.
for case_name in core none; do
    : >"$calls"
    run_install "$case_name" || {
        cat "${tmp_dir}/install.log" >&2
        fail "$case_name install failed"
    }
    for name in $all_steps; do
        if grep -Fx "step $name" "$calls" >/dev/null; then
            case " $(echo $core_steps) " in
            *" $name "*) ;;
            *) fail "$case_name install ran step from another group: $name" ;;
            esac
        else
            case " $(echo $core_steps) " in
            *" $name "*) fail "$case_name install skipped core step: $name" ;;
            esac
        fi
    done
    home="${tmp_dir}/${case_name}-home"
    [ -L "${home}/.zshrc" ] || fail "$case_name install omitted .zshrc"
    for target in .claude/CLAUDE.md .codex/AGENTS.md "$ghostty_target"; do
        [ ! -e "${home}/${target}" ] && [ ! -L "${home}/${target}" ] ||
            fail "$case_name install created link from another group: $target"
    done
    [ ! -d "${home}/.claude" ] ||
        fail "$case_name install created agent directories"
    expect_log install 'fonts: group desktop is not selected' \
        "$case_name install did not name the skipped desktop step"
    expect_log install 'developer tools: group agents is not selected' \
        "$case_name install did not name the skipped agents step"
    grep -E "^\[INFO\] +skipped \(group agents\): mise and Node.js LTS$" \
        "${tmp_dir}/install.log" >/dev/null ||
        fail "$case_name install summary omitted the skipped group"
    grep -F 'network ' "$calls" && fail "$case_name install used the network"
done
echo "[INFO] install: core only and no setting skip agents and desktop"

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
# Agent adapters log every call. With all groups, plans are fixture rows.
# Otherwise plans come from the real scripts, which must skip by group.
for adapter in sync-agents agent-tools; do
    case "$adapter" in
    sync-agents)
        real="${DOTFILES_DIR}/sync-agents.sh"
        rows='PASS\tsettings:codex\tnone\tCodex settings match\nPASS\thooks\tnone\tHerdr hook is available\n'
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
    [ "\$GROUPS_CASE" = all ] || exec "$real" "\$@"
    printf '$rows'
    ;;
esac
exit 0
STUB
done
chmod +x "${stub_dir}/core-tools" "${stub_dir}/sync-agents" \
    "${stub_dir}/agent-tools"

# Run doctor with a group setting, in its own HOME or in another case's HOME.
run_doctor() {
    local case_name="$1" home_case="${2:-$1}"
    HOME="${tmp_dir}/${home_case}-home" \
        PATH="${stub_dir}:${SMOKE_BASE_PATH}" \
        CALLS_LOG="$calls" GROUPS_CASE="$case_name" \
        DOTFILES_ENV_FILE="${tmp_dir}/${case_name}.env" \
        CORE_TOOLS="${stub_dir}/core-tools" \
        SYNC_AGENTS="${stub_dir}/sync-agents" \
        AGENT_TOOLS="${stub_dir}/agent-tools" \
        "$MAKE_BIN" --no-print-directory -C "$DOTFILES_DIR" machine \
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
run_doctor all || true
reject_log doctor 'is not selected' "doctor with all groups skipped a group"
grep -Fx 'agent-tools plan' "$calls" >/dev/null ||
    fail "doctor with all groups skipped agent tools"
for category in hooks node; do
    grep -E "^\[(PASS|UPDATE|FAIL)\] ${category}:" \
        "${tmp_dir}/doctor.log" >/dev/null ||
        fail "doctor with all groups did not check $category"
done
reject_log doctor '] groups:' "doctor with all groups printed a group notice"
echo "[INFO] doctor: all groups plan every group"

# A machine without a setting that has agent and desktop links installed
# gets one notice per group and keeps passing.
: >"$calls"
run_doctor none all || {
    cat "${tmp_dir}/doctor.log" >&2
    fail "doctor failed for installed groups that are not selected"
}
for group in agents desktop; do
    grep -Fx "[SKIP] groups: Group ${group} is installed but not selected; dotfiles do not update it. Run: make enable group=${group}" \
        "${tmp_dir}/doctor.log" >/dev/null ||
        fail "doctor did not name installed group $group"
done
[ "$(grep -c '] groups:' "${tmp_dir}/doctor.log")" -eq 2 ] ||
    fail "doctor printed an unexpected number of group notices"
reject_log doctor '[FAIL]' "an installed unselected group failed doctor"
: >"$calls"
run_doctor none || true
reject_log doctor '] groups:' "doctor named a group that is not installed"
echo "[INFO] doctor: installed unselected groups get one notice each"

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
        PATH="${stub_dir}:${SMOKE_BASE_PATH}" \
        CALLS_LOG="$calls" GROUPS_CASE="$case_name" \
        DOTFILES_DIR="$checkout" \
        DOTFILES_ENV_FILE="${tmp_dir}/${case_name}.env" \
        UPDATE_SCRIPT="${repo_dir}/scripts/update-local.sh" \
        INSTALL_SCRIPT="${repo_dir}/install.sh" \
        STATE_PLAN="${repo_dir}/scripts/state-plan.sh" \
        CORE_TOOLS="${stub_dir}/core-tools" \
        SYNC_AGENTS="${stub_dir}/sync-agents" \
        AGENT_TOOLS="${stub_dir}/agent-tools" \
        "$MAKE_BIN" --no-print-directory -C "$repo_dir" sync \
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
run_sync all || true
reject_log sync 'is not selected' "sync with all groups skipped a group"
grep -Fx 'agent-tools update' "$calls" >/dev/null ||
    fail "sync with all groups skipped agent tools"
echo "[INFO] sync: all groups refresh every group"

git -C "$publisher" commit --quiet --allow-empty -m "test: last upstream"
git -C "$publisher" push --quiet
: >"$calls"
run_sync none || {
    cat "${tmp_dir}/sync.log" >&2
    fail "sync without a setting failed"
}
expect_log sync '[SKIP] Node and agent tools: group agents is not selected' \
    "sync without a setting did not skip agents"
expect_log sync '[RESULT] PASS' "sync without a setting did not pass"
echo "[INFO] sync: no setting refreshes core only"

# Group commands: the fixture checkout runs the real group script and logs
# install runs.
mkdir -p "${tmp_dir}/fixture/scripts"
for script in groups.sh managed-links.sh; do
    ln -s "${DOTFILES_DIR}/scripts/${script}" \
        "${tmp_dir}/fixture/scripts/${script}"
done
group_env="${tmp_dir}/group-command.env"

# Group commands read stdin only to ask for a group. They get no terminal,
# unless run_group_tty types an answer into one.
group_launcher=(env)
run_group_command() {
    HOME="${tmp_dir}/core-home" \
        PATH="${stub_dir}:${SMOKE_BASE_PATH}" \
        CALLS_LOG="$calls" GROUPS_CASE=command \
        GROUPS_TEST_REPO="$DOTFILES_DIR" \
        DOTFILES_ENV_FILE="$group_env" \
        DOTFILES_SKIP_SSH=true \
        "${group_launcher[@]}" \
        "$MAKE_BIN" --no-print-directory -C "${tmp_dir}/fixture" "$@" \
        </dev/null >"${tmp_dir}/group.log" 2>&1
}

# Run a group command with a terminal on stdin that already holds the input.
cat >"${tmp_dir}/tty.py" <<'PY'
import os
import subprocess
import sys

controller, terminal = os.openpty()
os.write(controller, sys.argv[1].encode())
sys.exit(subprocess.call(sys.argv[2:], stdin=terminal))
PY
run_group_tty() {
    local input="$1" status=0
    shift
    group_launcher=("$PYTHON_BIN" "${tmp_dir}/tty.py" "$input")
    run_group_command "$@" || status=$?
    group_launcher=(env)
    return "$status"
}

# Print the group setting lines of the command fixture.
group_lines() {
    grep -E '^[[:space:]]*(export[[:space:]]+)?DOTFILES_GROUPS=' "$group_env"
}

write_env "$group_env"
run_group_command groups || fail "make groups failed without a setting"
expect_log group 'Install groups - 1 of 3 selected' \
    "make groups did not count core as the default"
for row in '✓ core .* required' '○ agents .* make enable group=agents' \
    '○ desktop .* make enable group=desktop'; do
    grep -Ex "    ${row}" "${tmp_dir}/group.log" >/dev/null ||
        fail "make groups has no row: ${row}"
done
(
    # shellcheck source=scripts/groups.sh
    source "${DOTFILES_DIR}/scripts/groups.sh"
    for group in $DOTFILES_GROUP_NAMES; do
        [ -n "$(group_description "$group")" ] ||
            fail "install group has no description: $group"
    done
)
echo "[INFO] groups: the table names every group and its command"

# A template line keeps its position; other lines stay unchanged.
printf '%s\n' 'EMAIL=test@example.com' '# Install groups' 'DOTFILES_GROUPS=' \
    'WORK_EMAIL=work@example.com' 'EDITOR=vim' >"$group_env"
: >"$calls"
run_group_command enable group=agents || {
    cat "${tmp_dir}/group.log" >&2
    fail "make enable agents failed"
}
[ "$(sed -n 3p "$group_env")" = 'DOTFILES_GROUPS=core,agents' ] ||
    fail "make enable agents did not replace the setting in place"
[ "$(sed -n '1,2p;4,5p' "$group_env")" = "$(printf '%s\n' \
    'EMAIL=test@example.com' '# Install groups' \
    'WORK_EMAIL=work@example.com' 'EDITOR=vim')" ] ||
    fail "make enable changed other env lines"
grep -Fx 'step agent-config' "$calls" >/dev/null ||
    fail "make enable agents did not install the agents group"
grep -Fx 'step fonts' "$calls" >/dev/null &&
    fail "make enable agents installed the desktop group"
echo "[INFO] enable: agents is written in place and installed"

: >"$calls"
run_group_command enable group=desktop || fail "make enable desktop failed"
[ "$(group_lines)" = 'DOTFILES_GROUPS=core,agents,desktop' ] ||
    fail "make enable desktop did not keep the canonical group order"
grep -Fx 'step fonts' "$calls" >/dev/null ||
    fail "make enable desktop did not install the desktop group"

: >"$calls"
run_group_command enable group=agents || fail "enabling a selected group failed"
expect_log group '[INFO] Group agents is already selected' \
    "make enable did not report a selected group"
[ "$(group_lines)" = 'DOTFILES_GROUPS=core,agents,desktop' ] ||
    fail "enabling a selected group changed the setting"
echo "[INFO] enable: a second group keeps canonical order"

: >"$calls"
run_group_command disable group=agents || fail "make disable agents failed"
[ "$(group_lines)" = 'DOTFILES_GROUPS=core,desktop' ] ||
    fail "make disable agents did not remove the group"
[ ! -s "$calls" ] || fail "make disable ran an install"
expect_log group 'Installed elements of group agents stay on this machine' \
    "make disable did not say that installed elements stay"

# An exported duplicate setting collapses into the first line.
printf '%s\n' 'EMAIL=test@example.com' 'WORK_EMAIL=work@example.com' \
    'export DOTFILES_GROUPS="core, desktop"' 'EDITOR=vim' \
    'DOTFILES_GROUPS=core,desktop' >"$group_env"
run_group_command disable group=desktop || fail "disable with duplicate lines failed"
[ "$(group_lines)" = 'DOTFILES_GROUPS=core' ] ||
    fail "disable did not collapse duplicate settings"
[ "$(sed -n 3p "$group_env")" = 'DOTFILES_GROUPS=core' ] ||
    fail "disable did not keep the first setting position"
echo "[INFO] disable: removes the group and keeps installed elements"

# Without a group, enable and disable ask on a terminal. Without one, or with
# a wrong answer, they fail. A cancel, or nothing to choose, changes nothing
# and passes without a make error.
write_env "$group_env" 'DOTFILES_GROUPS=core'
expect_setting() {
    [ "$(group_lines)" = "$1" ] && [ ! -s "$calls" ] ||
        fail "$2 changed the machine"
}
expect_quiet_pass() {
    reject_log group 'make: ***' "$1 printed a make error"
    reject_log group '[ERROR]' "$1 printed an error"
}
: >"$calls"
if run_group_command enable; then fail "make enable without a group passed"; fi
expect_log group 'Usage: make enable group=NAME, where NAME is one of: agents, desktop' \
    "make enable without a group and terminal did not print the usage"
expect_setting 'DOTFILES_GROUPS=core' "make enable without a terminal"
run_group_tty $'\n' enable || fail "a cancelled choice failed"
expect_log group '[INFO] No group chosen; nothing changed' \
    "a cancelled choice did not say that nothing changed"
expect_quiet_pass "a cancelled choice"
expect_setting 'DOTFILES_GROUPS=core' "a cancelled choice"
if run_group_tty $'3\n' enable; then fail "make enable accepted 3 of 2 groups"; fi
expect_log group '[ERROR] "3" is not a group number: 1-2' \
    "make enable did not reject a number outside the list"
expect_setting 'DOTFILES_GROUPS=core' "a wrong answer"
run_group_tty $'2\n' enable || {
    cat "${tmp_dir}/group.log" >&2
    fail "make enable did not accept a chosen group"
}
expect_log group '    2) desktop  Fonts, terminal colors and GUI apps' \
    "make enable did not offer the unselected groups"
[ "$(group_lines)" = 'DOTFILES_GROUPS=core,desktop' ] ||
    fail "make enable did not select the chosen group"
grep -Fx 'step fonts' "$calls" >/dev/null ||
    fail "make enable did not install the chosen group"
: >"$calls"
run_group_tty $'1\n' disable || fail "make disable did not accept a chosen group"
expect_log group 'Group number [1, Enter cancels]:' \
    "make disable offered core or an unselected group"
expect_setting 'DOTFILES_GROUPS=core' "make disable"
write_env "$group_env" 'DOTFILES_GROUPS=core,agents,desktop'
run_group_command enable || fail "make enable failed with all groups selected"
expect_log group '[INFO] All install groups are already selected' \
    "make enable did not say that all groups are selected"
expect_quiet_pass "make enable with all groups selected"
expect_setting 'DOTFILES_GROUPS=core,agents,desktop' "make enable with all groups"
write_env "$group_env" 'DOTFILES_GROUPS=core'
run_group_command disable || fail "make disable failed with only core"
expect_log group '[INFO] Only core is selected, and core is required' \
    "make disable did not explain that only core is selected"
expect_quiet_pass "make disable with only core"
expect_setting 'DOTFILES_GROUPS=core' "make disable with only core"
echo "[INFO] group commands: a missing group is chosen on a terminal"


# Invalid commands leave the env file and the machine unchanged.
cp "$group_env" "${tmp_dir}/group-before.env"
for args in 'disable group=core' 'enable group=gaming' 'disable group=gaming'; do
    : >"$calls"
    # shellcheck disable=SC2086
    if run_group_command $args; then fail "make $args passed"; fi
    cmp -s "$group_env" "${tmp_dir}/group-before.env" ||
        fail "make $args changed the env file"
    [ ! -s "$calls" ] || fail "make $args ran an install"
done
run_group_command disable group=core || true
expect_log group '[ERROR] Group core is required' \
    "make disable core did not explain the required group"
run_group_command enable group=gaming || true
expect_log group '[ERROR] Unknown install group "gaming"' \
    "make enable did not explain the unknown group"
expect_log group 'Use: core, agents, desktop' \
    "make enable did not name the valid groups"
rm "$group_env"
if run_group_command enable group=agents; then
    fail "make enable passed without an env file"
fi
[ ! -e "$group_env" ] || fail "make enable created a partial env file"
expect_log group 'Run: make install' \
    "make enable without an env file did not name the next step"
echo "[INFO] group commands: invalid commands change nothing"

echo "[INFO] Install group smoke test passed (external installers simulated)"

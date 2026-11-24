#!/bin/bash
set -eu
repo="$(cd "$(dirname "$0")/.." && pwd)"
source "${repo}/scripts/host-tools.sh"
task_dir="$(mktemp -d)"
trap 'rm -rf "$task_dir"' EXIT
mkdir -p "$task_dir/bin"
real_git="$(command -v git)"
# Keep simulated upstream skills independent of the installed inventory.
cat > "$task_dir/fixture-lock.json" <<'JSON'
{
  "skills": {
    "control-cli": {
      "ref": "main",
      "skillPath": "team-kit/skills/control-cli/SKILL.md",
      "source": "example/plugins",
      "sourceType": "github",
      "sourceUrl": "https://github.com/example/plugins.git"
    },
    "poteto-mode": {
      "installName": "poteto-mode",
      "ref": "main",
      "runtimeName": "Poteto Mode",
      "skillPath": "harness/pstack/claude-code/skills/poteto-mode/SKILL.md",
      "source": "example/plugins",
      "sourceType": "github",
      "sourceUrl": "https://github.com/example/plugins.git"
    }
  }
}
JSON
cp "$task_dir/fixture-lock.json" "$task_dir/lock.json"
cat > "$task_dir/bin/skills" <<'STUB'
#!/bin/bash
set -eu
printf '%s\n' "$*" >> "$SKILL_TEST_LOG"
[ "${FAIL_SKILL:-false}" = false ] || { echo 'download interrupted' >&2; exit 1; }
skills=()
collect=false
for arg in "$@"; do
    if [ "$arg" = --skill ]; then
        collect=true
        continue
    fi
    if [ "$arg" = --agent ]; then
        collect=false
    fi
    [ "$collect" = true ] && skills+=("$arg")
done
for skill in "${skills[@]}"; do
    case "$skill" in
    'poteto-mode')
        folder=poteto-mode
        ;;
    'control-cli')
        folder=control-cli
        ;;
    'Second Skill')
        folder=second-skill
        ;;
    *)
        echo "No matching skills found for: $skill" >&2
        exit 1
        ;;
    esac
    mkdir -p "$HOME/.agents/skills/$folder"
    printf '%s\n' '---' "name: $skill" 'version: current' '---' \
        > "$HOME/.agents/skills/$folder/SKILL.md"
    # The real CLI records the upstream path it resolved in the lock.
    if [ -n "${RESOLVED_SKILL_PATH:-}" ] && [ "$folder" = poteto-mode ]; then
        jq --arg path "$RESOLVED_SKILL_PATH" \
            '.skills["poteto-mode"].skillPath = $path' \
            "$SKILL_LOCK_LIVE" >"$SKILL_LOCK_LIVE.next"
        mv "$SKILL_LOCK_LIVE.next" "$SKILL_LOCK_LIVE"
    fi
done
if [ "${INSTALL_EXTRA:-false}" = true ]; then
    mkdir -p "$HOME/.agents/skills/unexpected"
    printf '%s\n' '---' 'name: unexpected' '---' \
        > "$HOME/.agents/skills/unexpected/SKILL.md"
fi
STUB
cat > "$task_dir/bin/cp" <<'STUB'
#!/bin/bash
exec /bin/cp "$@"
STUB
cat > "$task_dir/bin/mv" <<'STUB'
#!/bin/bash
if [ -n "${FAIL_APPLY_TARGET:-}" ] && [ "${2:-}" = "$FAIL_APPLY_TARGET" ] &&
    [ ! -e "$FAIL_APPLY_MARKER" ]; then
    : >"$FAIL_APPLY_MARKER"
    echo 'apply failed' >&2
    exit 1
fi
if [ -n "${FAIL_ROLLBACK_TARGET:-}" ] &&
    [ "${2:-}" = "$FAIL_ROLLBACK_TARGET" ] &&
    [[ "${1:-}" == */skill-sync.*/claude ]]; then
    echo 'rollback failed' >&2
    exit 1
fi
exec /bin/mv "$@"
STUB
cat > "$task_dir/bin/git" <<'STUB'
#!/bin/bash
set -eu
if [ "${1:-}" = ls-remote ]; then
    printf '%s\n' "$*" >>"$SKILL_REF_LOG"
    printf '%s\t%s\n' "${SKILL_SOURCE_SHA:-1111111}" "${3:-HEAD}"
    exit 0
fi
exec "$REAL_GIT" "$@"
STUB
cat > "$task_dir/bin/mise" <<'STUB'
#!/bin/bash
set -eu
[ "${1:-}" = which ] && [ "${2:-}" = skills ] || exit 1
printf '%s\n' "$REAL_SKILLS"
STUB
chmod +x "$task_dir/bin/skills" "$task_dir/bin/cp" \
    "$task_dir/bin/mv" "$task_dir/bin/git" "$task_dir/bin/mise"
export REAL_GIT="$real_git"

preflight_home="$task_dir/preflight home"
mkdir -p "$preflight_home/.local/share/mise/shims"
cat > "$preflight_home/.local/share/mise/shims/skills" <<'STUB'
#!/bin/bash
echo 'mise shim ran after HOME changed' >&2
exit 97
STUB
chmod +x "$preflight_home/.local/share/mise/shims/skills"
env -u CODEX_HOME -u OPENCODE_CONFIG_DIR -u PI_CODING_AGENT_DIR \
    -u PI_SKILLS_DIR HOME="$preflight_home" \
    SKILL_LOCK_LIVE="$preflight_home/.agents/.skill-lock.json" \
    SKILL_LOCK_REPO="$task_dir/lock.json" \
    PATH="$preflight_home/.local/share/mise/shims:$task_dir/bin:$PATH" \
    SKILLS_CLI=skills REAL_SKILLS="$task_dir/bin/skills" \
    SKILL_TEST_LOG="$task_dir/preflight-calls" \
    "$repo/sync-agents.sh" skills-preflight >"$task_dir/preflight-output" 2>&1 || {
    cat "$task_dir/preflight-output" >&2
    exit 1
}
test ! -e "$preflight_home/.agents"
tree='https://github.com/example/plugins/tree/main'
rg -qxF \
    "add -g $tree/team-kit --skill control-cli --agent codex -y --full-depth" \
    "$task_dir/preflight-calls"
rg -qxF \
    "add -g $tree/harness/pstack/claude-code --skill poteto-mode --agent codex -y --full-depth" \
    "$task_dir/preflight-calls"

multi_home="$task_dir/multi failure home"
mkdir -p "$multi_home/.agents/skills/preserve"
printf '%s\n' 'preserve me' >"$multi_home/.agents/skills/preserve/SKILL.md"
jq '
    .skills["missing-skill"] = (
        .skills["poteto-mode"] |
        .installName = "Missing Skill"
    )
' "$task_dir/lock.json" >"$task_dir/multi-lock.json"
if env -u CODEX_HOME -u OPENCODE_CONFIG_DIR -u PI_CODING_AGENT_DIR \
    -u PI_SKILLS_DIR HOME="$multi_home" \
    SKILL_LOCK_LIVE="$multi_home/.agents/.skill-lock.json" \
    SKILL_LOCK_REPO="$task_dir/multi-lock.json" \
    PATH="$task_dir/bin:$PATH" SKILLS_CLI="$task_dir/bin/skills" \
    SKILL_TEST_LOG="$task_dir/multi-calls" \
    "$repo/sync-agents.sh" push-skills >"$task_dir/multi-output" 2>&1; then
    echo 'Missing second skill passed' >&2
    exit 1
fi
rg -q 'No matching skills found for: Missing Skill' "$task_dir/multi-output"
rg -q -- \
    '--skill poteto-mode Missing Skill --agent codex -y --full-depth' \
    "$task_dir/multi-calls"
rg -q '^preserve me$' "$multi_home/.agents/skills/preserve/SKILL.md"
test ! -e "$multi_home/.agents/.skill-lock.json"

extra_home="$task_dir/extra inventory home"
mkdir -p "$extra_home/.agents/skills/preserve"
printf '%s\n' 'preserve me' >"$extra_home/.agents/skills/preserve/SKILL.md"
if env -u CODEX_HOME -u OPENCODE_CONFIG_DIR -u PI_CODING_AGENT_DIR \
    -u PI_SKILLS_DIR HOME="$extra_home" \
    SKILL_LOCK_LIVE="$extra_home/.agents/.skill-lock.json" \
    SKILL_LOCK_REPO="$task_dir/lock.json" \
    PATH="$task_dir/bin:$PATH" SKILLS_CLI="$task_dir/bin/skills" \
    SKILL_TEST_LOG="$task_dir/extra-calls" INSTALL_EXTRA=true \
    "$repo/sync-agents.sh" push-skills >"$task_dir/extra-output" 2>&1; then
    echo 'Unexpected staged skill passed' >&2
    exit 1
fi
rg -q 'Staged skill inventory differs' "$task_dir/extra-output"
rg -q '^preserve me$' "$extra_home/.agents/skills/preserve/SKILL.md"
test ! -e "$extra_home/.agents/.skill-lock.json"

# Upstream can hold two copies of a skill; the CLI may pick the other one.
variant_home="$task_dir/variant home"
mkdir -p "$variant_home/.agents/skills/preserve"
printf '%s\n' 'preserve me' >"$variant_home/.agents/skills/preserve/SKILL.md"
other_path='pstack/skills/poteto-mode/SKILL.md'
if env -u CODEX_HOME -u OPENCODE_CONFIG_DIR -u PI_CODING_AGENT_DIR \
    -u PI_SKILLS_DIR HOME="$variant_home" \
    SKILL_LOCK_LIVE="$variant_home/.agents/.skill-lock.json" \
    SKILL_LOCK_REPO="$task_dir/lock.json" \
    PATH="$task_dir/bin:$PATH" SKILLS_CLI="$task_dir/bin/skills" \
    SKILL_TEST_LOG="$task_dir/variant-calls" \
    RESOLVED_SKILL_PATH="$other_path" \
    "$repo/sync-agents.sh" push-skills >"$task_dir/variant-output" 2>&1; then
    echo 'Skill from another upstream path passed' >&2
    exit 1
fi
expected_path="$(jq -r '.skills["poteto-mode"].skillPath' "$task_dir/lock.json")"
rg -qF "Skill poteto-mode resolved from $other_path; inventory expects $expected_path" \
    "$task_dir/variant-output"
rg -q '^preserve me$' "$variant_home/.agents/skills/preserve/SKILL.md"
test ! -e "$variant_home/.agents/.skill-lock.json"

for state in empty partial complete broken alias no_url apply_failure rollback_failure backup_collision; do
    jq 'del(.skills["control-cli"])' \
        "$task_dir/fixture-lock.json" > "$task_dir/lock.json"
    if [ "$state" = no_url ]; then
        jq 'del(.skills["poteto-mode"].sourceUrl)' "$task_dir/lock.json" > "$task_dir/lock.next"
        mv "$task_dir/lock.next" "$task_dir/lock.json"
    fi
    task_home="$task_dir/$state home"
    if [ "$state" = alias ]; then
        mkdir -p "$task_dir/physical home"
        ln -s "$task_dir/physical home" "$task_home"
    fi
    mkdir -p "$task_home/.agents/skills" "$task_home/.claude/skills"
    if [ "$state" = partial ] || [ "$state" = complete ]; then
        mkdir -p "$task_home/.claude/skills/poteto-mode"
        printf '%s\n' '---' 'name: Poteto Mode' 'version: stale' '---' \
            > "$task_home/.claude/skills/poteto-mode/SKILL.md"
    fi
    if [ "$state" = complete ]; then
        for root in .agents/skills .config/opencode/skills .pi/agent/skills; do
            mkdir -p "$task_home/$root"
            ln -s "$task_home/.claude/skills/poteto-mode" "$task_home/$root/poteto-mode"
        done
    fi
    if [ "$state" = broken ]; then
        ln -s "$task_dir/missing" "$task_home/.agents/skills/poteto-mode"
    fi
    if [ "$state" = apply_failure ] || [ "$state" = rollback_failure ]; then
        for root in .agents/skills .claude/skills .config/opencode/skills .pi/agent/skills; do
            mkdir -p "$task_home/$root/poteto-mode"
            printf '%s\n' '---' 'name: Poteto Mode' 'version: original' '---' \
                > "$task_home/$root/poteto-mode/SKILL.md"
            touch "$task_home/$root/poteto-mode/preserve-me"
        done
    fi
    if [ "$state" = backup_collision ]; then
        mkdir -p "$task_dir/old-skill" "$task_home/.config/opencode/skills"
        printf '%s\n' '---' 'name: local-skill' '---' > "$task_dir/old-skill/SKILL.md"
        ln -s "$task_dir/old-skill" "$task_home/.claude/skills/local-skill"
        ln -s "$task_home/.claude/skills/local-skill" "$task_home/.agents/skills/local-skill"
        ln -s "$task_home/.claude/skills/local-skill" "$task_home/.config/opencode/skills/local-skill"
        printf '#!/bin/sh\necho 20000101000000\n' > "$task_dir/bin/date"
        chmod +x "$task_dir/bin/date"
    fi
    run_sync() {
        env -u CODEX_HOME -u OPENCODE_CONFIG_DIR -u PI_CODING_AGENT_DIR \
            -u PI_SKILLS_DIR HOME="$task_home" \
            SKILL_LOCK_LIVE="$task_home/.agents/.skill-lock.json" \
            SKILL_LOCK_REPO="$task_dir/lock.json" \
            PATH="$task_dir/bin:$PATH" SKILLS_CLI="$task_dir/bin/skills" SKILL_TEST_LOG="$task_dir/calls" \
            "$repo/sync-agents.sh" push-skills > "$task_dir/output" 2>&1
    }
    if [ "$state" = broken ]; then
        if FAIL_SKILL=true run_sync; then echo 'Failed download passed' >&2; exit 1; fi
        rg -q 'download interrupted' "$task_dir/output"
        rg -q 'poteto-mode.*example/plugins' "$task_dir/output"
        test -L "$task_home/.agents/skills/poteto-mode"
        [ "$(readlink "$task_home/.agents/skills/poteto-mode")" = "$task_dir/missing" ]
        test ! -e "$task_home/.agents/.skill-lock.json"
    fi
    if [ "$state" = apply_failure ]; then
        # Fail after the Pi directory has been replaced by a link.
        if FAIL_APPLY_TARGET="$task_home/.agents/docs" \
            FAIL_APPLY_MARKER="$task_dir/apply-failed" run_sync; then
            echo 'Failed apply passed' >&2
            exit 1
        fi
        rg -q 'apply failed' "$task_dir/output"
        test ! -L "$task_home/.pi/agent/skills"
        for root in .agents/skills .claude/skills .config/opencode/skills .pi/agent/skills; do
            test -f "$task_home/$root/poteto-mode/preserve-me"
            rg -q '^version: original$' "$task_home/$root/poteto-mode/SKILL.md"
        done
        continue
    fi
    if [ "$state" = rollback_failure ]; then
        if FAIL_APPLY_TARGET="$task_home/.claude/skills" \
            FAIL_APPLY_MARKER="$task_dir/rollback-apply-failed" \
            FAIL_ROLLBACK_TARGET="$task_home/.claude/skills" run_sync; then
            echo 'Incomplete rollback passed' >&2
            exit 1
        fi
        rg -q 'rollback failed' "$task_dir/output"
        rg -q 'Skill rollback incomplete' "$task_dir/output"
        backups=("$task_home"/.dotfiles-backup/skill-sync.*/claude)
        [ "${#backups[@]}" -eq 1 ]
        backup="${backups[0]}"
        test -f "$backup/poteto-mode/preserve-me"
        continue
    fi
    backup_count=""
    for run in 1 2; do
        run_sync || { cat "$task_dir/output" >&2; exit 1; }
        if rg -q '^diff: .*No such file or directory' "$task_dir/output"; then
            fail "skill comparison exposed a missing-path warning"
        fi
        for root in .agents/skills .claude/skills .config/opencode/skills .pi/agent/skills; do
            test -r "$task_home/$root/poteto-mode/SKILL.md"
            rg -q '^name: Poteto Mode$' "$task_home/$root/poteto-mode/SKILL.md"
            rg -q '^version: current$' "$task_home/$root/poteto-mode/SKILL.md"
        done
        set -- "$task_home"/.dotfiles-backup/skill-sync.*
        current_backup_count=$#
        if [ "$run" = 1 ]; then
            backup_count="$current_backup_count"
        else
            [ "$current_backup_count" = "$backup_count" ]
        fi
    done
    if [ "$state" = complete ]; then
        live_lock="$task_home/.agents/.skill-lock.json"
        jq '.skills["poteto-mode"].pluginName = "pstack"' "$live_lock" > "$live_lock.next"
        mv "$live_lock.next" "$live_lock"
        run_sync || { cat "$task_dir/output" >&2; exit 1; }
        jq -e '.skills["poteto-mode"].pluginName == "pstack"' "$live_lock" >/dev/null
        # A source field removed from the repository must leave the live lock.
        jq '.skills["poteto-mode"].subpath = "old/path"' "$live_lock" \
            > "$live_lock.next"
        mv "$live_lock.next" "$live_lock"
        run_sync || { cat "$task_dir/output" >&2; exit 1; }
        jq -e '.skills["poteto-mode"] |
            (has("subpath") | not) and .pluginName == "pstack"' \
            "$live_lock" >/dev/null || {
            echo 'Stale skill source field survived sync' >&2
            exit 1
        }
    fi
done

update_home="$task_dir/update command home"
mkdir -p "$update_home"
update_refs="$update_home/.agents/.skill-source-refs.json"
update_calls="$task_dir/update-calls"
ref_calls="$task_dir/ref-calls"
run_update() {
    env -u CODEX_HOME -u OPENCODE_CONFIG_DIR -u PI_CODING_AGENT_DIR \
        -u PI_SKILLS_DIR HOME="$update_home" \
        SKILL_LOCK_LIVE="$update_home/.agents/.skill-lock.json" \
        SKILL_LOCK_REPO="$task_dir/lock.json" \
        SKILL_SOURCE_REFS="$update_refs" \
        PATH="$task_dir/bin:$PATH" SKILLS_CLI="$task_dir/bin/skills" \
        SKILL_TEST_LOG="$update_calls" SKILL_REF_LOG="$ref_calls" \
        "$repo/sync-agents.sh" skills-update \
        >"$task_dir/update-output" 2>&1
}
run_update
rg -q '^name: Poteto Mode$' "$update_home/.agents/skills/poteto-mode/SKILL.md"
rg -q '^version: current$' "$update_home/.agents/skills/poteto-mode/SKILL.md"
[ "$(wc -l <"$update_calls" | tr -d ' ')" = 1 ]
run_update
[ "$(wc -l <"$update_calls" | tr -d ' ')" = 1 ]
[ "$(wc -l <"$ref_calls" | tr -d ' ')" = 2 ]
SKILL_SOURCE_SHA=2222222 run_update
[ "$(wc -l <"$update_calls" | tr -d ' ')" = 2 ]

# External removal of a shared skill must not leave a per-skill link in Pi.
rm -r "$update_home/.agents/skills/poteto-mode"
if [ -L "$update_home/.pi/agent/skills/poteto-mode" ]; then
    echo 'Removing a shared skill left a dangling link in Pi' >&2
    exit 1
fi
test "$(readlink "$update_home/.pi/agent/skills")" = "$update_home/.agents/skills"

# Drive the public sync across a real Git fast-forward with installed skills.
# Only unrelated plan/refresh categories and external skill downloads are stubbed.
(
    # shellcheck disable=SC2046
    unset $(git -C "$repo" rev-parse --local-env-vars)
    publisher="$task_dir/publisher"
    client="$task_dir/client"
    home="$task_dir/upgrade-home"
    mkdir -p "$publisher/.agents" "$home"
    git -C "$publisher" init -q -b master
    git -C "$publisher" config user.name 'Smoke Test'
    git -C "$publisher" config user.email smoke@example.invalid
    ln -s "$repo/sync-agents.sh" "$publisher/sync-agents.sh"
    ln -s "$repo/scripts" "$publisher/scripts"
    ln -s "$repo/config" "$publisher/config"
    for file in AGENTS.md mcp-servers.json plugin-manifest.json; do
        ln -s "$repo/.agents/$file" "$publisher/.agents/$file"
    done
    lock='.agents/skill-lock.json'
    cp "$task_dir/fixture-lock.json" "$publisher/$lock"
    git -C "$publisher" add .
    git -C "$publisher" commit -qm 'test: manage two skills'
    git clone -q "$publisher" "$client"

    printf 'DOTFILES_GROUPS=core,agents\n' >"$task_dir/groups.env"
    printf 'activate_node() { :; }\n' >"$task_dir/upgrade-install.sh"
    printf '#!/bin/bash\nexit 0\n' >"$task_dir/upgrade-tools"
    cat >"$task_dir/upgrade-plan" <<'STUB'
#!/bin/bash
set -eo pipefail
"$DOTFILES_DIR/sync-agents.sh" --quiet state-plan 2>/dev/null |
    awk -F '\t' '$2 == "skills"'
STUB
    cat >"$task_dir/upgrade-agents" <<'STUB'
#!/bin/bash
case "$1" in
pi-packages-update | plugins-update) exit 0 ;;
*) exec "$DOTFILES_DIR/sync-agents.sh" "$@" ;;
esac
STUB
    chmod +x "$task_dir/upgrade-plan" "$task_dir/upgrade-agents" \
        "$task_dir/upgrade-tools"

    unset CODEX_HOME OPENCODE_CONFIG_DIR PI_CODING_AGENT_DIR PI_SKILLS_DIR \
        SKILL_LOCK_REPO SKILL_LOCK_LIVE SKILL_SOURCE_REFS
    export HOME="$home" PATH="$task_dir/bin:$PATH" DOTFILES_DIR="$client"
    export DOTFILES_ENV_FILE="$task_dir/groups.env"
    export SKILLS_CLI="$task_dir/bin/skills" SKILL_TEST_LOG="$task_dir/upgrade-calls"
    export SKILL_REF_LOG="$task_dir/upgrade-refs" SKILL_SOURCE_SHA=1111111
    export STATE_PLAN="$task_dir/upgrade-plan" SYNC_AGENTS="$task_dir/upgrade-agents"
    export AGENT_TOOLS="$task_dir/upgrade-tools" CORE_TOOLS="$task_dir/upgrade-tools"
    export INSTALL_SCRIPT="$task_dir/upgrade-install.sh"
    unset UPDATE_SCRIPT
    run_upgrade() {
        just --justfile "$repo/justfile" sync >"$task_dir/upgrade.log" 2>&1
    }
    expect_upgrade() {
        grep -F -- "$1" "$task_dir/upgrade.log" >/dev/null || {
            cat "$task_dir/upgrade.log" >&2
            echo "Missing sync result: $1" >&2
            exit 1
        }
    }

    "$client/sync-agents.sh" skills-update >"$task_dir/seed.log" 2>&1
    test -f "$home/.agents/skills/control-cli/SKILL.md"
    applied="$home/.agents/.dotfiles-applied-skill-lock.json"
    refs="$home/.agents/.skill-source-refs.json"
    live="$home/.agents/.skill-lock.json"
    # Before this fix, only the hash from the last successful sync was tracked.
    mv "$applied" "$task_dir/old-applied"
    mv "$refs" "$task_dir/old-refs"
    jq 'del(.skills["control-cli"])' "$publisher/$lock" >"$task_dir/next-lock"
    cp "$task_dir/next-lock" "$publisher/$lock"
    git -C "$publisher" commit -qam 'test: retire control-cli'

    expect_export() {
        if run_upgrade; then
            echo 'Sync accepted unknown local skill state' >&2
            exit 1
        fi
        expect_upgrade '[RESULT] EXPORT'
        test -f "$home/.agents/skills/control-cli/SKILL.md"
        test ! -s "$SKILL_TEST_LOG"
    }
    : >"$SKILL_TEST_LOG"
    expect_export  # No trustworthy baseline yet, even after the pull.
    cp "$task_dir/old-refs" "$refs"

    local_skill="$home/.claude/skills/local-skill"
    mkdir "$local_skill"
    printf '%s\n' '# local skill' >"$local_skill/SKILL.md"
    expect_export
    test -f "$local_skill/SKILL.md"
    rm -r "$local_skill"

    # A local replacement by the same name is not the retired managed skill.
    cp "$live" "$task_dir/live-before"
    jq '.skills["control-cli"].sourceUrl = "https://github.com/example/replacement"' \
        "$live" >"$task_dir/live-modified"
    cp "$task_dir/live-modified" "$live"
    expect_export
    cmp "$task_dir/live-modified" "$live"
    cp "$task_dir/live-before" "$live"

    # A successful checkout update followed by a failed skill swap is retryable.
    if FAIL_APPLY_TARGET="$applied" FAIL_APPLY_MARKER="$task_dir/upgrade-failed" run_upgrade; then
        echo 'Failed skill swap passed sync' >&2
        exit 1
    fi
    expect_upgrade '[RESULT] FAIL'
    test -f "$task_dir/upgrade-failed"
    test -f "$home/.agents/skills/control-cli/SKILL.md"
    test ! -e "$applied"
    cmp "$task_dir/old-refs" "$refs"
    cmp "$task_dir/live-before" "$live"
    cmp "$client/$lock" "$publisher/$lock"

    run_upgrade || { cat "$task_dir/upgrade.log" >&2; exit 1; }
    expect_upgrade '[RESULT] PASS'
    for root in .agents/skills .claude/skills .config/opencode/skills .pi/agent/skills; do
        test ! -e "$home/$root/control-cli"
        test ! -L "$home/$root/control-cli"
        test -f "$home/$root/poteto-mode/SKILL.md"
    done

    # Future upgrades do not depend on the old Git blob hash cache.
    rm "$refs"
    printf '{"skills":{}}\n' >"$publisher/$lock"
    git -C "$publisher" commit -qam 'test: retire the last skill'
    run_upgrade || { cat "$task_dir/upgrade.log" >&2; exit 1; }
    expect_upgrade '[RESULT] PASS'
    test ! -e "$home/.agents/skills/poteto-mode"
)

echo '[INFO] Skill install smoke test passed'

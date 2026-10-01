#!/bin/bash
set -eu
repo="$(cd "$(dirname "$0")/.." && pwd)"
task_dir="$(mktemp -d)"
trap 'rm -rf "$task_dir"' EXIT
mkdir -p "$task_dir/bin" "$task_dir/custom"
jq '{skills: {"poteto-mode": .skills["poteto-mode"]}}' \
    "$repo/.agents/skill-lock.json" > "$task_dir/lock.json"
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
    'Poteto Mode')
        folder=poteto-mode
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
chmod +x "$task_dir/bin/skills" "$task_dir/bin/cp" "$task_dir/bin/mv"

preflight_home="$task_dir/preflight home"
mkdir -p "$preflight_home"
env -u CODEX_HOME -u OPENCODE_CONFIG_DIR -u PI_CODING_AGENT_DIR \
    -u PI_SKILLS_DIR HOME="$preflight_home" \
    SKILL_LOCK_LIVE="$preflight_home/.agents/.skill-lock.json" \
    SKILL_LOCK_REPO="$task_dir/lock.json" \
    SHARED_SKILLS_CUSTOM_DIR="$task_dir/custom" \
    PATH="$task_dir/bin:$PATH" SKILLS_CLI="$task_dir/bin/skills" \
    SKILL_TEST_LOG="$task_dir/preflight-calls" \
    "$repo/sync-agents.sh" skills-preflight >"$task_dir/preflight-output" 2>&1
test ! -e "$preflight_home/.agents"
rg -q 'cursor/plugins.*--skill Poteto Mode' "$task_dir/preflight-calls"

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
    SHARED_SKILLS_CUSTOM_DIR="$task_dir/custom" \
    PATH="$task_dir/bin:$PATH" SKILLS_CLI="$task_dir/bin/skills" \
    SKILL_TEST_LOG="$task_dir/multi-calls" \
    "$repo/sync-agents.sh" push-skills >"$task_dir/multi-output" 2>&1; then
    echo 'Missing second skill passed' >&2
    exit 1
fi
rg -q 'No matching skills found for: Missing Skill' "$task_dir/multi-output"
rg -q -- '--skill Poteto Mode Missing Skill --agent codex' "$task_dir/multi-calls"
rg -q '^preserve me$' "$multi_home/.agents/skills/preserve/SKILL.md"
test ! -e "$multi_home/.agents/.skill-lock.json"

extra_home="$task_dir/extra inventory home"
mkdir -p "$extra_home/.agents/skills/preserve"
printf '%s\n' 'preserve me' >"$extra_home/.agents/skills/preserve/SKILL.md"
if env -u CODEX_HOME -u OPENCODE_CONFIG_DIR -u PI_CODING_AGENT_DIR \
    -u PI_SKILLS_DIR HOME="$extra_home" \
    SKILL_LOCK_LIVE="$extra_home/.agents/.skill-lock.json" \
    SKILL_LOCK_REPO="$task_dir/lock.json" \
    SHARED_SKILLS_CUSTOM_DIR="$task_dir/custom" \
    PATH="$task_dir/bin:$PATH" SKILLS_CLI="$task_dir/bin/skills" \
    SKILL_TEST_LOG="$task_dir/extra-calls" INSTALL_EXTRA=true \
    "$repo/sync-agents.sh" push-skills >"$task_dir/extra-output" 2>&1; then
    echo 'Unexpected staged skill passed' >&2
    exit 1
fi
rg -q 'Staged skill inventory differs' "$task_dir/extra-output"
rg -q '^preserve me$' "$extra_home/.agents/skills/preserve/SKILL.md"
test ! -e "$extra_home/.agents/.skill-lock.json"

for state in empty partial complete broken alias no_url apply_failure rollback_failure backup_collision; do
    jq '{skills: {"poteto-mode": .skills["poteto-mode"]}}' \
        "$repo/.agents/skill-lock.json" > "$task_dir/lock.json"
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
        mkdir -p "$task_dir/custom/local-skill" "$task_dir/old-skill" \
            "$task_home/.config/opencode/skills"
        printf '%s\n' '---' 'name: local-skill' '---' > "$task_dir/custom/local-skill/SKILL.md"
        cp "$task_dir/custom/local-skill/SKILL.md" "$task_dir/old-skill/SKILL.md"
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
            SHARED_SKILLS_CUSTOM_DIR="$task_dir/custom" \
            PATH="$task_dir/bin:$PATH" SKILLS_CLI="$task_dir/bin/skills" SKILL_TEST_LOG="$task_dir/calls" \
            "$repo/sync-agents.sh" push-skills > "$task_dir/output" 2>&1
    }
    if [ "$state" = broken ]; then
        if FAIL_SKILL=true run_sync; then echo 'Failed download passed' >&2; exit 1; fi
        rg -q 'download interrupted' "$task_dir/output"
        rg -q 'poteto-mode.*cursor/plugins' "$task_dir/output"
        test -L "$task_home/.agents/skills/poteto-mode"
        [ "$(readlink "$task_home/.agents/skills/poteto-mode")" = "$task_dir/missing" ]
        test ! -e "$task_home/.agents/.skill-lock.json"
    fi
    if [ "$state" = apply_failure ]; then
        if FAIL_APPLY_TARGET="$task_home/.claude/skills" \
            FAIL_APPLY_MARKER="$task_dir/apply-failed" run_sync; then
            echo 'Failed apply passed' >&2
            exit 1
        fi
        rg -q 'apply failed' "$task_dir/output"
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
        for root in .agents/skills .claude/skills .config/opencode/skills .pi/agent/skills; do
            test -r "$task_home/$root/poteto-mode/SKILL.md"
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
    fi
done

update_home="$task_dir/update command home"
mkdir -p "$update_home"
env -u CODEX_HOME -u OPENCODE_CONFIG_DIR -u PI_CODING_AGENT_DIR \
    -u PI_SKILLS_DIR HOME="$update_home" \
    SKILL_LOCK_LIVE="$update_home/.agents/.skill-lock.json" \
    SKILL_LOCK_REPO="$task_dir/lock.json" \
    SHARED_SKILLS_CUSTOM_DIR="$task_dir/custom" \
    PATH="$task_dir/bin:$PATH" SKILLS_CLI="$task_dir/bin/skills" \
    SKILL_TEST_LOG="$task_dir/update-calls" \
    "$repo/sync-agents.sh" skills-update >"$task_dir/update-output" 2>&1
rg -q '^version: current$' "$update_home/.agents/skills/poteto-mode/SKILL.md"

echo '[INFO] Skill install smoke test passed'

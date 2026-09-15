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
[ "$4" = --skill ] && [ "$5" = 'Poteto Mode' ] || {
    echo "No matching skills found for: $5" >&2; exit 1;
}
[ "$6" = --agent ] && [ "$7" = codex ]
jq '.skills = {"Poteto Mode": (.skills["poteto-mode"] | del(.installName))}' \
    "$SKILL_LOCK_LIVE" > "$SKILL_LOCK_LIVE.next"
mv "$SKILL_LOCK_LIVE.next" "$SKILL_LOCK_LIVE"
mkdir -p "$HOME/.agents/skills/poteto-mode"
printf '%s\n' '---' 'name: Poteto Mode' '---' > "$HOME/.agents/skills/poteto-mode/SKILL.md"
STUB
cat > "$task_dir/bin/cp" <<'STUB'
#!/bin/bash
if [ "${FAIL_BACKUP:-false}" = true ] && [[ "$*" == *'.dotfiles-backup/'* ]]; then
    echo 'backup failed' >&2
    exit 1
fi
exec /bin/cp "$@"
STUB
chmod +x "$task_dir/bin/skills" "$task_dir/bin/cp"
for state in empty partial complete broken alias no_url backup_failure backup_collision; do
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
        printf '%s\n' '---' 'name: Poteto Mode' '---' > "$task_home/.claude/skills/poteto-mode/SKILL.md"
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
    if [ "$state" = backup_failure ]; then
        for root in .agents/skills .claude/skills; do
            mkdir -p "$task_home/$root/poteto-mode"
            printf '%s\n' '---' 'name: Poteto Mode' '---' > "$task_home/$root/poteto-mode/SKILL.md"
        done
        echo 'preserve me' > "$task_home/.claude/skills/poteto-mode/local-notes"
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
    fi
    if [ "$state" = backup_failure ]; then
        if FAIL_BACKUP=true run_sync; then echo 'Failed backup passed' >&2; exit 1; fi
        rg -q 'backup failed' "$task_dir/output"
        test -f "$task_home/.claude/skills/poteto-mode/local-notes"
    fi
    for _ in 1 2; do
        run_sync || { cat "$task_dir/output" >&2; exit 1; }
        for root in .agents/skills .claude/skills .config/opencode/skills .pi/agent/skills; do
            test -r "$task_home/$root/poteto-mode/SKILL.md"
        done
    done
    if [ "$state" = complete ]; then
        live_lock="$task_home/.agents/.skill-lock.json"
        jq '.skills["poteto-mode"].pluginName = "pstack"' "$live_lock" > "$live_lock.next"
        mv "$live_lock.next" "$live_lock"
        run_sync || { cat "$task_dir/output" >&2; exit 1; }
        jq -e '.skills["poteto-mode"].pluginName == "pstack"' "$live_lock" >/dev/null
    fi
done
echo '[INFO] Skill install smoke test passed'

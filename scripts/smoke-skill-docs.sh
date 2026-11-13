#!/bin/bash
# A skill that links ../../docs/<path> must find that file in every runtime.
# Upstream pstack skills link their Claude Code adapter this way.
set -eu
repo="$(cd "$(dirname "$0")/.." && pwd)"

fail() {
    echo "[ERROR] $*" >&2
    exit 1
}

task_dir="$(mktemp -d)"
trap 'rm -rf "$task_dir"' EXIT
mkdir -p "$task_dir/bin" "$task_dir/custom"
# A fixture lock entry; the doc lives next to skills/ in its package.
doc_url='https://raw.githubusercontent.com/example/kit/main/pack/docs/'
doc_url="${doc_url}harness/claude-code.md"
cat >"$task_dir/lock.json" <<'JSON'
{"skills": {"maintain-verification-skill": {
  "ref": "main",
  "skillPath": "pack/skills/maintain-verification-skill/SKILL.md",
  "source": "example/kit", "sourceType": "github",
  "sourceUrl": "https://github.com/example/kit.git"}}}
JSON

# The skills CLI copies only the skill folder, as upstream does.
cat >"$task_dir/bin/skills" <<'STUB'
#!/bin/bash
set -eu
collect=false
for arg in "$@"; do
    case "$arg" in
    --skill) collect=true; continue ;;
    --*) collect=false ;;
    esac
    [ "$collect" = true ] || continue
    mkdir -p "$HOME/.agents/skills/$arg"
    printf '%s\n' '---' "name: $arg" '---' \
        "In Claude Code, read [the adapter](../../docs/${DOC_LINK_PATH}) once." \
        >"$HOME/.agents/skills/$arg/SKILL.md"
done
STUB
cat >"$task_dir/bin/curl" <<'STUB'
#!/bin/bash
set -eu
output=""
url=""
while [ "$#" -gt 0 ]; do
    case "$1" in
    -o) output="$2"; shift ;;
    -*) ;;
    *) url="$1" ;;
    esac
    shift
done
printf '%s\n' "$url" >>"$CURL_LOG"
[ "${FAIL_DOC:-false}" = false ] || { echo 'HTTP 404' >&2; exit 22; }
case "$url" in
*/other/*) printf '%s\n' "${OTHER_DOC_CONTENT:-$DOC_CONTENT}" >"$output" ;;
*) printf '%s\n' "$DOC_CONTENT" >"$output" ;;
esac
STUB
chmod +x "$task_dir/bin/skills" "$task_dir/bin/curl"

home="$task_dir/fresh home"
mkdir -p "$home"
printf 'DOTFILES_GROUPS=core,agents,desktop\n' >"$task_dir/all-groups.env"
run_sync_agents() {
    env -u CODEX_HOME -u OPENCODE_CONFIG_DIR -u PI_CODING_AGENT_DIR \
        -u PI_SKILLS_DIR -u CLAUDE_SETTINGS_FILE HOME="$home" \
        SKILL_LOCK_LIVE="$home/.agents/.skill-lock.json" \
        SKILL_LOCK_REPO="$task_dir/lock.json" \
        SHARED_SKILLS_CUSTOM_DIR="$task_dir/custom" \
        DOTFILES_ENV_FILE="$task_dir/all-groups.env" \
        PATH="$task_dir/bin:$PATH" SKILLS_CLI="$task_dir/bin/skills" \
        CURL_LOG="$task_dir/curl.log" DOC_CONTENT="${DOC_CONTENT:-adapter v1}" \
        DOC_LINK_PATH="${DOC_LINK_PATH:-harness/claude-code.md}" \
        "$repo/sync-agents.sh" "$@" >"$task_dir/output" 2>&1
}

skills_plan_status() {
    run_sync_agents --quiet state-plan || true
    awk -F '\t' '$2 == "skills" { print $1 }' "$task_dir/output"
}

: >"$task_dir/curl.log"
run_sync_agents push-skills || {
    cat "$task_dir/output" >&2
    fail "push-skills failed for a skill with a support doc"
}
grep -Fx "$doc_url" "$task_dir/curl.log" >/dev/null ||
    fail "support doc was not fetched from the skill's source package"
[ "$(cat "$home/.agents/docs/harness/claude-code.md")" = 'adapter v1' ] ||
    fail "support doc is missing from ~/.agents/docs"
for runtime_docs in "$home/.claude/docs" "$home/.config/opencode/docs" \
    "$home/.pi/agent/docs"; do
    [ -L "$runtime_docs" ] &&
        [ "$(readlink "$runtime_docs")" = "$home/.agents/docs" ] ||
        fail "runtime docs do not link to ~/.agents/docs: $runtime_docs"
done
claude_skill="$home/.claude/skills/maintain-verification-skill"
[ "$(cat "$claude_skill/../../docs/harness/claude-code.md")" = 'adapter v1' ] ||
    fail "Claude skill link does not resolve its support doc"
run_sync_agents skills-check || fail "skills-check rejected installed docs"
[ "$(skills_plan_status)" = PASS ] || fail "skills plan rejected installed docs"
echo "[INFO] fresh install provides support docs in every runtime"

backups_before="$(find "$home/.dotfiles-backup" -mindepth 1 -maxdepth 1 | wc -l)"
run_sync_agents push-skills || fail "repeated push-skills failed"
[ "$(find "$home/.dotfiles-backup" -mindepth 1 -maxdepth 1 | wc -l)" = \
    "$backups_before" ] || fail "unchanged support docs created a new backup"
DOC_CONTENT='adapter v2' run_sync_agents push-skills ||
    fail "push-skills failed for an updated support doc"
[ "$(cat "$home/.agents/docs/harness/claude-code.md")" = 'adapter v2' ] ||
    fail "updated upstream support doc was not applied"
echo "[INFO] repeat is unchanged and an upstream change is applied"

# Doctor reports a missing doc as an update, offline.
rm "$home/.claude/docs"
: >"$task_dir/curl.log"
if run_sync_agents skills-check; then
    fail "skills-check passed without the Claude support doc"
fi
missing='Claude missing support doc: maintain-verification-skill'
grep -F "${missing} -> docs/harness/claude-code.md" "$task_dir/output" \
    >/dev/null || fail "skills-check did not name the missing doc"
[ "$(skills_plan_status)" = UPDATE ] ||
    fail "skills plan did not request an update for a missing doc"
[ ! -s "$task_dir/curl.log" ] || fail "offline checks downloaded a doc"
run_sync_agents push-skills || fail "push-skills did not repair a missing doc"
[ -L "$home/.claude/docs" ] || fail "push-skills did not restore Claude docs"
echo "[INFO] a missing doc is reported offline and repaired"

# A failed download changes no runtime.
snapshot() {
    (
        cd "$home"
        find . -type l -exec sh -c 'printf "%s -> %s\n" "$1" "$(readlink "$1")"' _ {} \;
        find . -type f -exec cksum {} \;
    ) | LC_ALL=C sort
}
snapshot >"$task_dir/before"
if DOC_CONTENT='adapter v3' FAIL_DOC=true run_sync_agents push-skills; then
    fail "push-skills passed after a failed doc download"
fi
grep -F 'harness/claude-code.md' "$task_dir/output" >/dev/null ||
    fail "failed download did not name the doc"
snapshot | cmp -s "$task_dir/before" - ||
    fail "failed doc download changed the runtime"
echo "[INFO] a failed download leaves runtimes unchanged"

# A link outside the docs directory is rejected before any download.
: >"$task_dir/curl.log"
if DOC_LINK_PATH='../secret.md' run_sync_agents push-skills; then
    fail "push-skills accepted a doc path outside docs"
fi
grep -F 'Unsafe support doc path' "$task_dir/output" >/dev/null ||
    fail "unsafe doc path was not explained"
[ ! -s "$task_dir/curl.log" ] || fail "unsafe doc path was downloaded"
echo "[INFO] an unsafe doc path is rejected before any download"

# Two packages can ship the same doc; only different content conflicts.
jq '.skills["second-skill"] = (.skills["maintain-verification-skill"] |
    .skillPath = "other/skills/second-skill/SKILL.md")' \
    "$task_dir/lock.json" >"$task_dir/lock.next"
mv "$task_dir/lock.next" "$task_dir/lock.json"
run_sync_agents push-skills || {
    cat "$task_dir/output" >&2
    fail "identical support docs from two packages were rejected"
}
[ "$(cat "$home/.agents/docs/harness/claude-code.md")" = 'adapter v1' ] ||
    fail "shared support doc is wrong"
snapshot >"$task_dir/before"
if OTHER_DOC_CONTENT='other adapter' run_sync_agents push-skills; then
    fail "different support docs from two packages were accepted"
fi
grep -F 'Support doc docs/harness/claude-code.md differs between' \
    "$task_dir/output" >/dev/null || fail "doc conflict was not explained"
snapshot | cmp -s "$task_dir/before" - ||
    fail "a doc conflict changed the runtime"
echo "[INFO] skill support doc smoke test passed (network simulated)"

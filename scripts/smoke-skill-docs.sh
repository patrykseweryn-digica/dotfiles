#!/bin/bash
# A skill that links ../../docs/<path> must find that file in every runtime.
# Upstream pstack skills link their Claude Code adapter this way.
set -eu
repo="$(cd "$(dirname "$0")/.." && pwd)"
source "${repo}/scripts/host-tools.sh"

fail() {
    echo "[ERROR] $*" >&2
    exit 1
}

task_dir="$(mktemp -d)"
trap 'rm -rf "$task_dir"' EXIT
mkdir -p "$task_dir/bin"
# A fixture lock entry; the doc lives next to skills/ in its package.
doc_url='https://api.github.com/repos/example/kit/contents/pack/docs/'
doc_url="${doc_url}harness/claude-code.md?ref=main"
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
output="" url="" auth=false retry="" retry_max="" max_time="" http1=false
while [ "$#" -gt 0 ]; do
    case "$1" in
    -o) output="$2"; shift ;;
    --retry) retry="$2"; shift ;;
    --retry-max-time) retry_max="$2"; shift ;;
    --max-time) max_time="$2"; shift ;;
    # curl 8.7 skips --retry for HTTP/2 429 responses.
    --http1.1) http1=true ;;
    --connect-timeout | -w) shift ;;
    -H)
        case "$2" in
        Authorization:*)
            [ "$2" = "Authorization: Bearer ${GITHUB_TOKEN:-}" ] || exit 98
            auth=true
            ;;
        esac
        shift
        ;;
    -*) ;;
    *) url="$1" ;;
    esac
    shift
done
printf '%s\n' "$url" >>"$CURL_LOG"
[ "$auth" = false ] || printf '%s\n' "$GITHUB_TOKEN" >>"$AUTH_LOG"
# Reproduce the real host-specific failure; the API serves the same file.
case "$url" in
https://api.github.com/repos/*) ;;
*) echo 'curl: (22) The requested URL returned error: 429' >&2; exit 22 ;;
esac
[ "$retry:$retry_max:$max_time:$http1" = '3:180:30:true' ] || exit 97
[ -z "${GITHUB_TOKEN:-}" ] || [ "$auth" = true ] || exit 96
[ "${FAIL_DOC:-false}" = false ] || { echo 'HTTP 404' >&2; exit 22; }
status="${DOC_HTTP_STATUS:-200}"
[ "$status" -lt 400 ] || { echo "HTTP $status" >&2; exit 22; }
case "$url" in
*/other/*) printf '%s\n' "${OTHER_DOC_CONTENT:-$DOC_CONTENT}" >"$output" ;;
*) printf '%s\n' "$DOC_CONTENT" >"$output" ;;
esac
printf '%s' "$status"
STUB
# The GitHub CLI login is the token source when no token is set.
cat >"$task_dir/bin/gh" <<'STUB'
#!/bin/bash
[ "$*" = 'auth token --hostname github.com' ] || exit 2
[ -n "${GH_STUB_TOKEN:-}" ] || { echo 'not logged in' >&2; exit 1; }
printf '%s\n' "$GH_STUB_TOKEN"
STUB
chmod +x "$task_dir/bin/skills" "$task_dir/bin/curl" "$task_dir/bin/gh"

home="$task_dir/fresh home"
mkdir -p "$home"
printf 'DOTFILES_GROUPS=core,agents,desktop\n' >"$task_dir/all-groups.env"
run_sync_agents() {
    env -u CODEX_HOME -u OPENCODE_CONFIG_DIR -u PI_CODING_AGENT_DIR \
        -u PI_SKILLS_DIR -u CLAUDE_SETTINGS_FILE HOME="$home" \
        SKILL_LOCK_LIVE="$home/.agents/.skill-lock.json" \
        SKILL_LOCK_REPO="$task_dir/lock.json" \
        DOTFILES_ENV_FILE="$task_dir/all-groups.env" \
        PATH="$task_dir/bin:$PATH" SKILLS_CLI="$task_dir/bin/skills" \
        CURL_LOG="$task_dir/curl.log" AUTH_LOG="$task_dir/auth.log" \
        DOC_CONTENT="${DOC_CONTENT:-adapter v1}" \
        DOC_LINK_PATH="${DOC_LINK_PATH:-harness/claude-code.md}" \
        "$repo/sync-agents.sh" "$@" >"$task_dir/output" 2>&1
}

skills_plan_status() {
    run_sync_agents --quiet state-plan || true
    awk -F '\t' '$2 == "skills" { print $1 }' "$task_dir/output"
}

: >"$task_dir/curl.log"
GITHUB_TOKEN='fixture-token' run_sync_agents skills-preflight || {
    cat "$task_dir/output" >&2
    fail "preflight failed while raw GitHub is rate limited and API is healthy"
}
grep -Fx "$doc_url" "$task_dir/curl.log" >/dev/null ||
    fail "preflight did not fetch the doc from GitHub API"
! grep -F 'fixture-token' "$task_dir/output" >/dev/null ||
    fail "preflight printed the token"
[ ! -e "$home/.agents" ] || fail "preflight changed the live runtime"
for status in 401 403 404 429 302; do
    if DOC_HTTP_STATUS="$status" run_sync_agents skills-preflight; then
        fail "preflight accepted HTTP $status for a required support doc"
    fi
    [ ! -e "$home/.agents" ] || fail "failed preflight changed the runtime"
done
echo "[INFO] preflight survives raw-host 429 without hiding API failures"

# Without a token, downloads authenticate with GH_TOKEN or the gh login.
check_token_source() {
    local source="$1" expected="$2"
    : >"$task_dir/auth.log"
    run_sync_agents skills-preflight || {
        cat "$task_dir/output" >&2
        fail "preflight failed with a ${source} token"
    }
    grep -Fx "$expected" "$task_dir/auth.log" >/dev/null ||
        fail "doc download did not authenticate with ${source}"
    ! grep -F "$expected" "$task_dir/output" >/dev/null ||
        fail "preflight printed the ${source} token"
}
(
    unset GITHUB_TOKEN GH_TOKEN
    GH_STUB_TOKEN='gh-login-token' check_token_source gh 'gh-login-token'
    GH_TOKEN='gh-env-token' check_token_source GH_TOKEN 'gh-env-token'
    : >"$task_dir/auth.log"
    run_sync_agents skills-preflight ||
        fail "preflight failed without any GitHub login"
    [ ! -s "$task_dir/auth.log" ] || fail "doc download invented a token"
)
echo "[INFO] doc downloads reuse GH_TOKEN or the gh login"

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

# A token must never reach a lookalike GitHub host.
cp "$task_dir/lock.json" "$task_dir/lock.saved"
jq '.skills[].sourceUrl = "https://github.com.evil.invalid/example/kit"' \
    "$task_dir/lock.saved" >"$task_dir/lock.json"
: >"$task_dir/curl.log"
if GITHUB_TOKEN='fixture-token' run_sync_agents skills-preflight; then
    fail "preflight accepted an untrusted doc source"
fi
[ ! -s "$task_dir/curl.log" ] || fail "untrusted doc source received a request"
mv "$task_dir/lock.saved" "$task_dir/lock.json"

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

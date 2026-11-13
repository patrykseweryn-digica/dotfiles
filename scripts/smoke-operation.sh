#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPERATION_LIB="${DOTFILES_DIR}/scripts/operation.sh"

fail() {
    echo "[ERROR] $*" >&2
    exit 1
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
export DOTFILES_OPERATION_LOG="${tmp_dir}/sync.log"
export DOTFILES_OPERATION_FAILURES="${tmp_dir}/failures.tsv"

# A GNU timeout stand-in proves the limit does not depend on it.
fake_bin="${tmp_dir}/fake-bin"
mkdir -p "$fake_bin"
printf '#!/bin/sh\nexit 99\n' >"${fake_bin}/timeout"
chmod +x "${fake_bin}/timeout"

run_case() {
    local name="$1" path="$2"
    shift 2
    : >"$DOTFILES_OPERATION_FAILURES"
    status=0
    # Real callers run with errexit and nounset.
    PATH="$path" bash -c '
        set -eu
        source "$1"
        shift
        operation_run "$@"
    ' operation-smoke "$OPERATION_LIB" "$@" \
        >"${tmp_dir}/${name}.out" 2>"${tmp_dir}/${name}.err" || status=$?
}

expect_line() {
    local name="$1" text="$2"
    grep -F -- "$text" "${tmp_dir}/${name}.err" >/dev/null ||
        fail "$name report omitted: $text"
}

assert_stopped() {
    local pid_file="$1" pid
    [ -s "$pid_file" ] || fail "fixture did not record $pid_file"
    pid="$(cat "$pid_file")"
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        kill -0 "$pid" 2>/dev/null || return 0
        sleep 0.2
    done
    kill -9 "$pid" 2>/dev/null || true
    fail "process $pid survived the time limit"
}

hang_case() {
    local name="$1" path="$2"
    rm -f "${tmp_dir}/parent.pid" "${tmp_dir}/child.pid"
    DOTFILES_OPERATION_TIMEOUT=1 run_case "$name" "$path" \
        "skills example/agent-skills" "stage skills" fetch -- \
        bash -c '
            echo $$ >"$1/parent.pid"
            sleep 300 &
            echo $! >"$1/child.pid"
            echo "Cloning into staging" >&2
            wait
        ' hang "$tmp_dir"
    [ "$status" -eq 124 ] || fail "$name returned $status, expected 124"
    assert_stopped "${tmp_dir}/parent.pid"
    assert_stopped "${tmp_dir}/child.pid"
    expect_line "$name" "[ERROR] skills example/agent-skills: stage skills failed"
    expect_line "$name" "cause: timed out after 1 s"
    expect_line "$name" "exit: 124"
    expect_line "$name" "Cloning into staging"
    expect_line "$name" "next: Check the network connection, then run: just sync"
    expect_line "$name" "log: ${DOTFILES_OPERATION_LOG}"
    grep -F "Cloning into staging" "$DOTFILES_OPERATION_LOG" >/dev/null ||
        fail "$name tool output missing from log"
    [ "$(wc -l <"$DOTFILES_OPERATION_FAILURES")" -eq 1 ] ||
        fail "$name did not record exactly one failure"
    awk -F '\t' '$1 == "skills example/agent-skills" &&
        $2 == "stage skills" && $3 ~ /^timed out after 1 s/ &&
        $4 == 124 && $5 ~ /^Check the network/' \
        "$DOTFILES_OPERATION_FAILURES" | grep . >/dev/null ||
        fail "$name failure record is incomplete"
}

hang_case hang "${fake_bin}:${PATH}"

# Linux machines without procps must still stop the whole process tree.
if [ -r /proc/self/stat ]; then
    no_ps_bin="${tmp_dir}/no-ps-bin"
    mkdir -p "$no_ps_bin"
    for command_name in bash sh sleep cat mktemp awk tail sed rm tr \
        mkdir wc date grep dirname; do
        ln -s "$(command -v "$command_name")" "${no_ps_bin}/${command_name}"
    done
    hang_case hang-no-ps "$no_ps_bin"
fi

run_case dns "$PATH" "dotfiles repo" "fetch upstream" fetch -- \
    bash -c 'echo "fatal: unable to access: Could not resolve host: github.com" >&2
             exit 128'
[ "$status" -eq 128 ] || fail "dns returned $status, expected 128"
expect_line dns "[ERROR] dotfiles repo: fetch upstream failed"
expect_line dns "cause: DNS lookup failed"
expect_line dns "exit: 128"
expect_line dns "Could not resolve host: github.com"

run_case unknown "$PATH" "Pi packages" "update extensions" install -- \
    bash -c 'echo "something odd" >&2; exit 3'
[ "$status" -eq 3 ] || fail "unknown returned $status, expected 3"
expect_line unknown "cause: unknown cause"
expect_line unknown "exit: 3"
expect_line unknown "next: Read the tool output in the log: ${DOTFILES_OPERATION_LOG}"

run_case value "$PATH" "claude-code" "resolve latest version" query \
    --stdout -- bash -c 'echo 2.1.0; echo "npm notice" >&2'
[ "$status" -eq 0 ] || fail "value returned $status"
[ "$(cat "${tmp_dir}/value.out")" = 2.1.0 ] ||
    fail "--stdout did not pass the value through"
[ ! -s "${tmp_dir}/value.err" ] || fail "successful operation wrote a report"
[ ! -s "$DOTFILES_OPERATION_FAILURES" ] || fail "success recorded a failure"
grep -F "npm notice" "$DOTFILES_OPERATION_LOG" >/dev/null ||
    fail "stderr of a successful operation missing from log"

run_case optional "$PATH" "tldr pages" "update cache" fetch --optional -- \
    bash -c 'echo "cache offline" >&2; exit 4'
[ "$status" -eq 4 ] || fail "optional returned $status, expected 4"
[ ! -s "${tmp_dir}/optional.err" ] || fail "optional failure wrote a report"
[ ! -s "$DOTFILES_OPERATION_FAILURES" ] ||
    fail "optional failure was recorded as a sync problem"

run_case quiet "$PATH" "core tools" "upgrade" install -- \
    bash -c 'echo "installer progress"'
[ "$status" -eq 0 ] || fail "quiet returned $status"
[ ! -s "${tmp_dir}/quiet.out" ] || fail "tool output reached the terminal"
grep -F "installer progress" "$DOTFILES_OPERATION_LOG" >/dev/null ||
    fail "tool stdout missing from log"

echo "[INFO] operation smoke test passed"

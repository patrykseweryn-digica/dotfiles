#!/bin/bash
# Shared boundary for external sync operations.
#
# operation_run ELEMENT OPERATION CLASS [--stdout] [--optional] -- COMMAND...
#
# Runs COMMAND with a finite time limit chosen by CLASS (query, fetch or
# install). On expiry it stops COMMAND and all its descendants and returns 124.
# Tool output goes to the operation log; --stdout keeps stdout for the caller.
# A failure prints the element, operation, cause, exit code, tool output tail,
# next step and log path, and appends one row to DOTFILES_OPERATION_FAILURES.
# With --optional, a failure only returns its status; the caller may warn.
# Processes that leave the tree (daemons) or run as another user (sudo
# children) depend on their parent forwarding the stop signal.
# The file defines functions only. It works with Bash 3.2 and errexit.

OPERATION_QUERY_LIMIT=120
OPERATION_FETCH_LIMIT=600
OPERATION_INSTALL_LIMIT=1800
OPERATION_STOP_GRACE_TICKS=15
OPERATION_TAIL_LINES=5

# Sync keeps its log in the state directory.
operation_sync_log_path() {
    printf '%s\n' "${XDG_STATE_HOME:-${HOME}/.local/state}/dotfiles/sync.log"
}

# Other commands, such as export, must not write to HOME.
operation_log_path() {
    printf '%s\n' "${DOTFILES_OPERATION_LOG:-${TMPDIR:-/tmp}/dotfiles-operations-${EUID}.log}"
}

operation_limit() {
    if [ -n "${DOTFILES_OPERATION_TIMEOUT:-}" ]; then
        printf '%s\n' "$DOTFILES_OPERATION_TIMEOUT"
        return
    fi
    case "$1" in
    query) printf '%s\n' "$OPERATION_QUERY_LIMIT" ;;
    fetch) printf '%s\n' "$OPERATION_FETCH_LIMIT" ;;
    install) printf '%s\n' "$OPERATION_INSTALL_LIMIT" ;;
    *) return 1 ;;
    esac
}

# Print "PID PPID" rows. Minimal Linux images can lack procps.
operation_process_table() {
    local stat_file pid stat rest ppid
    if command -v ps >/dev/null 2>&1; then
        ps -A -o pid= -o ppid=
        return
    fi
    for stat_file in /proc/[0-9]*/stat; do
        stat="$(cat "$stat_file" 2>/dev/null)" || continue
        pid="${stat_file#/proc/}"
        pid="${pid%/stat}"
        # The command name can contain spaces; fields follow its last ")".
        rest="${stat##*) }"
        read -r _ ppid _ <<<"$rest"
        printf '%s %s\n' "$pid" "$ppid"
    done
}

# Print ROOT and its descendants, parents before children.
operation_descendants() {
    operation_process_table | awk -v root="$1" '
        { parent[$1] = $2 }
        END {
            found[root] = 1
            order[1] = root
            count = 1
            for (i = 1; i <= count; i++) {
                for (pid in parent) {
                    if (parent[pid] == order[i] && !(pid in found)) {
                        found[pid] = 1
                        order[++count] = pid
                    }
                }
            }
            for (i = 1; i <= count; i++) print order[i]
        }
    '
}

# Freeze the tree first so no process can fork or escape while it is stopped.
# Print the number of stopped processes.
operation_stop_tree() {
    local root="$1" pids=" " new pid tick alive count=0

    for _ in 1 2 3 4 5; do
        new=""
        for pid in $(operation_descendants "$root"); do
            case "$pids" in *" $pid "*) continue ;; esac
            kill -STOP "$pid" 2>/dev/null || continue
            new="${new}${pid} "
        done
        [ -n "$new" ] || break
        pids="${pids}${new}"
    done
    for pid in $pids; do
        kill -TERM "$pid" 2>/dev/null || true
        kill -CONT "$pid" 2>/dev/null || true
        count=$((count + 1))
    done
    for ((tick = 0; tick < OPERATION_STOP_GRACE_TICKS; tick++)); do
        alive=false
        for pid in $pids; do
            if kill -0 "$pid" 2>/dev/null; then
                alive=true
            fi
        done
        [ "$alive" = true ] || break
        sleep 0.2
    done
    for pid in $pids; do
        kill -KILL "$pid" 2>/dev/null || true
    done
    printf '%s\n' "$count"
}

# Remove cursor control and keep the final state of carriage-return redraws.
operation_clean_output() {
    awk '
        {
            gsub(/\033\[[0-9;?]*[A-Za-z]/, "")
            gsub(/\033\][^\007]*\007/, "")
            count = split($0, parts, "\r")
            line = ""
            for (i = count; i >= 1; i--) {
                if (parts[i] != "") { line = parts[i]; break }
            }
            print line
        }
    ' "$1"
}

# Print "CAUSE<TAB>NEXT" for an exit status and cleaned tool output.
operation_cause() {
    local status="$1" output="$2" limit="$3" stopped="$4" log="$5"
    local retry="then run: ${DOTFILES_RUNNER:-just} sync"

    if [ "$status" -eq 124 ] && [ -n "$stopped" ]; then
        printf 'timed out after %s s; stopped %s processes\t%s\n' \
            "$limit" "$stopped" "Check the network connection, ${retry}"
    elif grep -Eqi 'could not resolve|resolve host|name resolution|getaddrinfo|ENOTFOUND|EAI_AGAIN|nodename nor servname' "$output"; then
        printf 'DNS lookup failed\t%s\n' "Check the network connection, ${retry}"
    elif grep -Eqi 'timed out|ETIMEDOUT|connection refused|ECONNREFUSED|ECONNRESET|connection reset|network is unreachable|failed to connect|could not connect|unexpected disconnect|early EOF' "$output"; then
        printf 'network connection failed\t%s\n' \
            "Check the network connection, ${retry}"
    elif grep -Eqi 'no space left|ENOSPC|disk quota' "$output"; then
        printf 'no disk space left\t%s\n' "Free disk space, ${retry}"
    elif grep -Eqi 'rate limit|HTTP 429|error: 429|403 Forbidden|HTTP 403|error: 403' "$output"; then
        printf 'remote access denied or rate limited\t%s\n' \
            "Wait or authenticate with the provider, ${retry}"
    elif grep -Eqi 'certificate|SSL|TLS handshake' "$output"; then
        printf 'secure connection failed\t%s\n' \
            "Check the system clock and CA certificates, ${retry}"
    elif grep -Eqi '404|not found|repository not found|E404' "$output" &&
        [ "$status" -ne 127 ]; then
        printf 'remote resource not found\t%s\n' \
            "Check the source in the repository inventory, ${retry}"
    elif grep -Eqi 'permission denied|EACCES|operation not permitted' "$output"; then
        printf 'permission denied\t%s\n' \
            "Fix ownership of the path in the tool output, ${retry}"
    elif [ "$status" -eq 127 ]; then
        printf 'command not found\t%s\n' "Run: ${DOTFILES_RUNNER:-just} install"
    else
        printf 'unknown cause\t%s\n' "Read the tool output in the log: ${log}"
    fi
}

# Bash 3.2 lacks printf %(...)T.
operation_timestamp() {
    if [ "${BASH_VERSINFO[0]}" -ge 5 ]; then
        printf '%(%Y-%m-%dT%H:%M:%S)T' -1
    else
        date '+%Y-%m-%dT%H:%M:%S'
    fi
}

operation_one_line() {
    printf '%s' "$1" | tr '\t\n' '  '
}

operation_record_failure() {
    local element="$1" operation="$2" cause="$3" status="$4" next="$5"
    [ -n "${DOTFILES_OPERATION_FAILURES:-}" ] || return 0
    printf '%s\t%s\t%s\t%s\t%s\n' \
        "$(operation_one_line "$element")" \
        "$(operation_one_line "$operation")" \
        "$(operation_one_line "$cause")" "$status" \
        "$(operation_one_line "$next")" \
        >>"$DOTFILES_OPERATION_FAILURES" 2>/dev/null || true
}

operation_run() {
    local element="$1" operation="$2" class="$3" keep_stdout=false
    local optional=false limit log log_dir work output cleaned marker started
    local status=0 command_pid watchdog_pid stopped="" diagnosis cause next
    local report=false

    shift 3
    while :; do
        case "${1:-}" in
        --stdout) keep_stdout=true ;;
        --optional) optional=true ;;
        *) break ;;
        esac
        shift
    done
    if [ "${1:-}" != -- ] || [ "$#" -lt 2 ]; then
        echo "[ERROR] operation_run: expected -- COMMAND" >&2
        return 2
    fi
    shift
    limit="$(operation_limit "$class")" || {
        echo "[ERROR] operation_run: unknown class: $class" >&2
        return 2
    }
    log="$(operation_log_path)"
    work="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-operation.XXXXXX")" || {
        echo "[ERROR] ${element}: failed to create an operation directory" >&2
        return 1
    }
    if ! mkfifo "$work/cancel"; then
        echo "[ERROR] ${element}: failed to create an operation channel" >&2
        rm -rf "$work"
        return 1
    fi
    output="${work}/output"
    cleaned="${work}/cleaned"
    marker="${work}/timed-out"
    started=$SECONDS

    {
        if [ "$keep_stdout" = true ]; then
            "$@" 2>"$output" </dev/null 9>&- &
        else
            "$@" >"$output" 2>&1 </dev/null 9>&- &
        fi
        command_pid=$!
        (
            # A buffered byte cancels read even if Bash 3.2 has not started
            # the watchdog. This needs neither a signal trap nor a child sleep.
            if IFS= read -r -t "$limit" _ <&9; then
                exit 0
            fi
            operation_stop_tree "$command_pid" 9>&- >"$marker"
        ) >/dev/null 2>&1 </dev/null &
        watchdog_pid=$!

        { wait "$command_pid"; } 2>/dev/null || status=$?
        printf '\n' >&9
        { wait "$watchdog_pid"; } 2>/dev/null || true
    } 9<>"$work/cancel" || {
        echo "[ERROR] ${element}: ${operation} failed before the command finished" >&2
        rm -rf "$work"
        return 1
    }
    [ ! -s "$marker" ] || read -r stopped <"$marker" || true
    # Zero stopped processes means the command finished before the limit.
    if [ -n "$stopped" ] && [ "$stopped" -gt 0 ]; then
        { wait "$command_pid"; } 2>/dev/null || true
        status=124
    else
        stopped=""
    fi

    # A report needs the cleaned output twice; a success logs it directly.
    if [ "$status" -ne 0 ] && [ "$optional" = false ]; then
        report=true
        operation_clean_output "$output" >"$cleaned" 2>/dev/null ||
            : >"$cleaned"
    fi
    # Expansion instead of dirname saves a process per operation.
    case "$log" in
    */*) log_dir="${log%/*}/" ;;
    *) log_dir=./ ;;
    esac
    if [ -d "$log_dir" ] || mkdir -p "$log_dir" 2>/dev/null; then
        {
            printf '==> %s %s: %s (exit %s, %s s)\n' \
                "$(operation_timestamp)" "$element" "$operation" \
                "$status" "$((SECONDS - started))"
            if [ "$report" = true ]; then
                cat "$cleaned"
            else
                operation_clean_output "$output"
            fi
        } >>"$log" 2>/dev/null || true
    fi

    if [ "$report" = true ]; then
        diagnosis="$(operation_cause "$status" "$cleaned" "$limit" \
            "$stopped" "$log")"
        cause="${diagnosis%%$'\t'*}"
        next="${diagnosis#*$'\t'}"
        {
            printf '[ERROR] %s: %s failed\n' "$element" "$operation"
            printf '  cause: %s\n' "$cause"
            printf '  exit: %s\n' "$status"
            if grep -q '[^[:space:]]' "$cleaned"; then
                printf '  tool output:\n'
                grep '[^[:space:]]' "$cleaned" |
                    tail -n "$OPERATION_TAIL_LINES" | sed 's/^/    | /'
            fi
            printf '  next: %s\n' "$next"
            printf '  log: %s\n' "$log"
        } >&2
        operation_record_failure "$element" "$operation" "$cause" \
            "$status" "$next"
    fi
    rm -rf "$work"
    return "$status"
}

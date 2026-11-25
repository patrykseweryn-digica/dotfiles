# shellcheck shell=bash
# Smoke tests replace HOME. A mise shim then searches the test HOME, finds no
# tools and fails. Put the real tool directories before the shims, as
# `mise activate` does in an interactive shell. Source this before HOME changes.
host_tools_mise="$(command -v mise 2>/dev/null || printf '%s' "${HOME}/.local/bin/mise")"
if [ -x "$host_tools_mise" ] &&
    host_tools_bins="$("$host_tools_mise" bin-paths 2>/dev/null)" &&
    [ -n "$host_tools_bins" ]; then
    PATH="$(printf '%s\n' "$host_tools_bins" | paste -sd: -):${PATH}"
    export PATH
fi
unset host_tools_mise host_tools_bins

# Tests narrow PATH to stubs and /usr/bin:/bin. Ubuntu 22.04 ships jq 1.6 there,
# about ten times slower per call. HOST_JQ_DIR holds only the host jq; put it
# before /usr/bin. It lives in the real HOME cache and is reused across runs.
HOST_JQ_DIR="${XDG_CACHE_HOME:-${HOME}/.cache}/dotfiles/smoke-jq"
export HOST_JQ_DIR
host_tools_jq="$(command -v jq 2>/dev/null || true)"
if [ -n "$host_tools_jq" ] && [ "$(readlink "${HOST_JQ_DIR}/jq" 2>/dev/null)" != "$host_tools_jq" ]; then
    mkdir -p "$HOST_JQ_DIR"
    # Rename replaces the link atomically for checks running in other worktrees.
    ln -sf "$host_tools_jq" "${HOST_JQ_DIR}/jq.$$"
    mv -f "${HOST_JQ_DIR}/jq.$$" "${HOST_JQ_DIR}/jq"
fi
host_tools_jq_version="$(PATH="${HOST_JQ_DIR}:/usr/bin:/bin" jq --version 2>/dev/null || true)"
host_tools_jq_version="${host_tools_jq_version#jq-}"
if [ "$(printf '1.7\n%s\n' "$host_tools_jq_version" | sort -V | head -n 1)" != 1.7 ]; then
    echo "[ERROR] smoke tests need jq 1.7 or newer in narrowed PATH; found '${host_tools_jq_version}'" >&2
    exit 1
fi
unset host_tools_jq host_tools_jq_version

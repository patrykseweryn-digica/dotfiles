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

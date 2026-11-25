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

# Tests narrow PATH to stubs and SMOKE_BASE_PATH. Ubuntu 22.04 ships jq 1.6 in
# /usr/bin, about ten times slower per call. Call this after creating the test
# scratch directory: it links only the host jq there, before /usr/bin:/bin.
set_smoke_base_path() {
    local jq_dir="$1/host-jq" jq_bin version
    jq_bin="$(command -v jq 2>/dev/null || true)"
    mkdir -p "$jq_dir"
    [ -z "$jq_bin" ] || ln -sf "$jq_bin" "${jq_dir}/jq"
    SMOKE_BASE_PATH="${jq_dir}:/usr/bin:/bin"
    export SMOKE_BASE_PATH
    version="$(PATH="$SMOKE_BASE_PATH" jq --version 2>/dev/null || true)"
    version="${version#jq-}"
    if [ "$(printf '1.7\n%s\n' "$version" | sort -V | head -n 1)" != 1.7 ]; then
        echo "[ERROR] smoke tests need jq 1.7 or newer in narrowed PATH; found '${version}'" >&2
        exit 1
    fi
}

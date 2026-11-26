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

# Smoke tests drive the public interface through just. A machine without just
# uses GNU Make, which runs the same scripts. Set SMOKE_RUNNER to choose one.
if [ -z "${SMOKE_RUNNER:-}" ]; then
    SMOKE_RUNNER="make"
    ! command -v just >/dev/null 2>&1 || SMOKE_RUNNER="just"
fi
case "$SMOKE_RUNNER" in
just | make) ;;
*)
    echo "[ERROR] SMOKE_RUNNER must be just or make; found '${SMOKE_RUNNER}'" >&2
    exit 1
    ;;
esac
SMOKE_RUNNER_BIN="$(command -v "$SMOKE_RUNNER")" || {
    echo "[ERROR] smoke tests need just or make" >&2
    exit 1
}

# Set PUBLIC_RECIPE to the command that runs a recipe of the checkout in DIR.
# Append the recipe: "${PUBLIC_RECIPE[@]}" sync. It also works after env.
# shellcheck disable=SC2034 # The sourcing smoke test reads PUBLIC_RECIPE.
public_recipe_command() {
    if [ "$SMOKE_RUNNER" = just ]; then
        PUBLIC_RECIPE=("$SMOKE_RUNNER_BIN" --justfile "$1/justfile")
    else
        PUBLIC_RECIPE=("$SMOKE_RUNNER_BIN" --no-print-directory -C "$1")
    fi
}

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

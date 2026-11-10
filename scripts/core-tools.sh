#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL_INVENTORY="${TOOL_INVENTORY:-${DOTFILES_DIR}/.agents/tool-versions.json}"
MISE_BIN="${MISE_BIN:-${HOME}/.local/bin/mise}"
MISE_CORE_TOOLS_FILE="${MISE_CORE_TOOLS_FILE:-${HOME}/.config/mise/conf.d/10-core-tools.toml}"

jq_run() {
    if [ -x "${JQ_BIN:-}" ]; then
        "$JQ_BIN" "$@"
    elif command -v jq >/dev/null 2>&1; then
        jq "$@"
    else
        "$MISE_BIN" exec jq@latest -- jq "$@"
    fi
}

tool_platform() {
    local os="${CORE_TOOLS_OS:-$(uname -s)}"
    local arch="${CORE_TOOLS_ARCH:-$(uname -m)}"

    case "$os" in
    Darwin | darwin) os=darwin ;;
    Linux | linux) os=linux ;;
    *) return 1 ;;
    esac
    case "$arch" in
    arm64 | aarch64) arch=arm64 ;;
    x86_64 | amd64) arch=x86_64 ;;
    *) return 1 ;;
    esac
    printf '%s-%s\n' "$os" "$arch"
}

validate_inventory() {
    jq_run -e '
        def valid_platforms:
            type == "array" and length > 0 and
            all(.[]; test("^(darwin|linux)-(arm64|x86_64)$"));
        def command_name:
            type == "string" and
            test("^[a-zA-Z0-9][a-zA-Z0-9._-]*$");
        (.tools | type == "array") and
        all(.tools[] | select(.scope == "core");
            (.name | command_name) and
            (.commands | type == "array" and length > 0 and
                all(.[]; command_name)) and
            ((.platforms // ["darwin-arm64", "darwin-x86_64",
                "linux-arm64", "linux-x86_64"]) | valid_platforms) and
            .versionPolicy == "latest" and
            (has("github") | not) and (has("packages") | not) and
            (has("adapter") | not)
        )
    ' "$TOOL_INVENTORY" >/dev/null || {
        echo "[ERROR] Invalid core tool inventory: $TOOL_INVENTORY" >&2
        return 1
    }
}

mise_tool_names() {
    local platform="$1"
    jq_run -r --arg platform "$platform" '
        .tools[] | select(.scope == "core" and
            .versionPolicy == "latest") |
        select(((.platforms // ["darwin-arm64", "darwin-x86_64",
            "linux-arm64", "linux-x86_64"]) | index($platform)) != null) |
        .name
    ' "$TOOL_INVENTORY"
}

write_mise_config() {
    local platform="$1" candidate
    mkdir -p "$(dirname "$MISE_CORE_TOOLS_FILE")"
    candidate=$(mktemp "${MISE_CORE_TOOLS_FILE}.XXXXXX") || return 1
    jq_run -r --arg platform "$platform" '
        (["[tools]"] + [
            .tools[] | select(.scope == "core" and
                .versionPolicy == "latest") |
            select(((.platforms // ["darwin-arm64", "darwin-x86_64",
                "linux-arm64", "linux-x86_64"]) | index($platform)) != null) |
            ((.name | @json) + " = \"latest\"")
        ])[]
    ' "$TOOL_INVENTORY" >"$candidate" || {
        rm -f "$candidate"
        return 1
    }
    if [ -f "$MISE_CORE_TOOLS_FILE" ] &&
        cmp -s "$candidate" "$MISE_CORE_TOOLS_FILE"; then
        rm -f "$candidate"
    else
        mv "$candidate" "$MISE_CORE_TOOLS_FILE"
    fi
}

run_mise_tools() {
    local action="$1" platform="$2" name
    local -a tools=()

    while IFS= read -r name; do
        [ -n "$name" ] && tools+=("$name")
    done < <(mise_tool_names "$platform")
    [ "${#tools[@]}" -gt 0 ] || return 0
    write_mise_config "$platform" || return 1
    case "$action" in
    install)
        env -u MISE_NODE_VERSION "$MISE_BIN" --cd "$HOME" \
            install "${tools[@]}"
        ;;
    update)
        env -u MISE_NODE_VERSION "$MISE_BIN" --cd "$HOME" \
            upgrade --global --no-prune "${tools[@]}"
        ;;
    esac
    env -u MISE_NODE_VERSION "$MISE_BIN" --cd "$HOME" \
        exec -- git lfs install --skip-repo
    env -u MISE_NODE_VERSION "$MISE_BIN" --cd "$HOME" \
        exec -- tldr --update 2>/dev/null || true
}

show_plan() {
    local platform="$1" name command_name status
    while IFS= read -r name; do
        command_name="$(jq_run -r --arg name "$name" \
            '.tools[] | select(.scope == "core" and .name == $name) | .commands[0]' \
            "$TOOL_INVENTORY")"
        status=INSTALL
        if env -u MISE_NODE_VERSION "$MISE_BIN" --cd "$HOME" \
            which "$command_name" >/dev/null 2>&1; then
            status=PASS
        fi
        printf '%s\t%s\tmise\n' "$status" "$name"
    done < <(mise_tool_names "$platform")
}

check_tools() {
    local platform="$1" failed=false name command_name
    while IFS= read -r name; do
        command_name="$(jq_run -r --arg name "$name" \
            '.tools[] | select(.scope == "core" and .name == $name) | .commands[0]' \
            "$TOOL_INVENTORY")"
        if ! env -u MISE_NODE_VERSION "$MISE_BIN" --cd "$HOME" \
            which "$command_name" >/dev/null 2>&1; then
            echo "[ERROR] $name is unavailable through mise" >&2
            failed=true
        fi
    done < <(mise_tool_names "$platform")
    [ "$failed" = false ]
}

main() {
    local action="${1:-}" platform
    case "$action" in
    plan | install | update | check) ;;
    *)
        echo "Usage: $0 [plan|install|update|check]" >&2
        return 1
        ;;
    esac
    [ -x "$MISE_BIN" ] || {
        echo "[ERROR] mise is unavailable: $MISE_BIN" >&2
        return 1
    }
    platform="$(tool_platform)" || {
        echo "[ERROR] Unsupported platform" >&2
        return 1
    }
    validate_inventory || return 1
    case "$action" in
    plan) show_plan "$platform" ;;
    install | update) run_mise_tools "$action" "$platform" ;;
    check) check_tools "$platform" ;;
    esac
}

main "$@"

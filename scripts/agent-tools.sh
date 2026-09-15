#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
default_versions_file="${DOTFILES_DIR}/.agents/tool-versions.json"
VERSIONS_FILE="${AGENT_TOOL_VERSIONS:-$default_versions_file}"
CLAUDE_INSTALL_URL="${CLAUDE_INSTALL_URL:-https://claude.ai/install.sh}"

validate_manifest() {
    jq -e '
        (.tools | type) == "array" and
        (.tools | length) > 0 and
        all(.tools[];
            (.name | type) == "string" and
            (.command | type) == "string" and
            (.package | type) == "string" and
            (.channel | type) == "string" and
            (if .command == "pi" then
                .channel == "latest" and .installer == "npm" and
                (has("version") | not)
             else
                (.version | test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))
             end) and
            (.installer == "npm" or .installer == "claude-native")
        ) and
        (([.tools[].command] | length) ==
         ([.tools[].command] | unique | length)) and
        (([.tools[].package] | length) ==
         ([.tools[].package] | unique | length))
    ' "$VERSIONS_FILE" >/dev/null || {
        echo "[ERROR] Invalid agent tool manifest: $VERSIONS_FILE" >&2
        return 1
    }
}

tool_rows() {
    jq -r '.tools[] | [
        .name,
        .command,
        .package,
        .channel,
        (.version // .channel),
        .installer
    ] | @tsv' "$VERSIONS_FILE"
}

installed_version() {
    local command_name="$1"
    local output

    command -v "$command_name" >/dev/null 2>&1 || return 1
    output=$("$command_name" --version 2>/dev/null) || return 1
    if [[ "$output" =~ ([0-9]+\.[0-9]+\.[0-9]+) ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return 0
    fi
    return 1
}

resolve_latest() {
    local package="$1" version
    version=$(npm view "${package}@latest" version) || {
        echo "[ERROR] Failed to resolve ${package}@latest" >&2
        return 1
    }
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "[ERROR] Invalid latest version for $package: $version" >&2
        return 1
    fi
    printf '%s\n' "$version"
}

report_versions() {
    local strict="$1"
    local failed=false
    local name command_name package channel expected installer current status

    printf '%-16s %-12s %-12s %s\n' "Tool" "Installed" "Expected" "Status"
    while IFS=$'\t' read -r \
        name command_name package channel expected installer; do
        if [ "$command_name" = pi ]; then
            expected=$(resolve_latest "$package") || return 1
        fi
        if current=$(installed_version "$command_name"); then
            if [ "$current" = "$expected" ]; then
                status="ok"
            else
                status="drift"
                failed=true
            fi
        else
            current="missing"
            status="missing"
            failed=true
        fi
        printf '%-16s %-12s %-12s %s\n' \
            "$name" "$current" "$expected" "$status"
    done < <(tool_rows)

    [ "$strict" = false ] || [ "$failed" = false ]
}

install_tools() {
    local failed=false
    local name command_name package channel expected installer current install_spec

    while IFS=$'\t' read -r \
        name command_name package channel expected installer; do
        install_spec="${package}@${expected}"
        if [ "$command_name" = pi ]; then
            expected=$(resolve_latest "$package") || return 1
        fi
        current="$(installed_version "$command_name" || true)"
        if [ "$current" = "$expected" ]; then
            echo "[INFO] $name $expected already installed"
            continue
        fi

        echo "[INFO] Installing $name $expected..."
        case "$installer" in
            npm)
                if [ "$command_name" = pi ]; then
                    npm install -g --ignore-scripts "$install_spec" || failed=true
                else
                    npm install -g "$install_spec" || failed=true
                fi
                ;;
            claude-native)
                curl -fsSL "$CLAUDE_INSTALL_URL" |
                    bash -s -- "$expected" || failed=true
                ;;
        esac
    done < <(tool_rows)

    [ "$failed" = false ]
}

update_tools() {
    local current next latest
    local name command_name package channel expected installer

    current="$(mktemp)"
    cp "$VERSIONS_FILE" "$current"

    while IFS=$'\t' read -r \
        name command_name package channel expected installer; do
        [ "$command_name" != pi ] || continue
        latest=$(npm view "${package}@${channel}" version) || {
            rm -f "$current"
            echo "[ERROR] Failed to resolve ${package}@${channel}" >&2
            return 1
        }
        next="$(mktemp)"
        jq -S --arg package "$package" --arg version "$latest" '
            .tools |= map(
                if .package == $package then
                    .version = $version
                else
                    .
                end
            )
        ' "$current" > "$next"
        mv "$next" "$current"
    done < <(tool_rows)

    if cmp -s "$current" "$VERSIONS_FILE"; then
        rm -f "$current"
        echo "[INFO] Agent tool versions already current"
    else
        mv "$current" "$VERSIONS_FILE"
        echo "[INFO] Updated $VERSIONS_FILE"
    fi
    install_tools
}

validate_manifest
case "${1:-}" in
    report)
        report_versions false
        ;;
    check)
        report_versions true
        ;;
    install)
        install_tools
        ;;
    update)
        update_tools
        ;;
    *)
        echo "Usage: $0 {report|check|install|update}" >&2
        exit 1
        ;;
esac

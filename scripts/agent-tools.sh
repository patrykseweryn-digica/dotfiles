#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
default_versions_file="${DOTFILES_DIR}/.agents/tool-versions.json"
VERSIONS_FILE="${AGENT_TOOL_VERSIONS:-$default_versions_file}"
CLAUDE_INSTALL_URL="${CLAUDE_INSTALL_URL:-https://claude.ai/install.sh}"

validate_manifest() {
    jq -e '
        def semver: type == "string" and
            test("^[0-9]+\\.[0-9]+\\.[0-9]+(-[0-9A-Za-z.-]+)?(\\+[0-9A-Za-z.-]+)?$");
        (.tools | type) == "array" and (.tools | length) > 0 and
        all(.tools[];
            (.name | type == "string" and test("^[^\\t\\r\\n]+$")) and
            (.command | type == "string" and test("^[a-zA-Z0-9][a-zA-Z0-9._-]*$")) and
            .channel == "latest" and
            (if has("version") then (.version | semver) else true end) and
            (if has("ignore_scripts") then
                (.ignore_scripts | type) == "boolean" and .installer == "npm"
             else true end) and
            (if .installer == "npm" or .installer == "claude-native" then
                (.package | type == "string" and
                    test("^(@[a-z0-9._-]+/)?[a-z0-9][a-z0-9._-]*$"))
             else
                (.installer == "hermes-native" or
                 .installer == "herdr-native" or
                 .installer == "treehouse-native" or
                 .installer == "no-mistakes-native") and
                (has("version") | not)
             end)
        ) and
        (([.tools[].command] | length) ==
         ([.tools[].command] | unique | length)) and
        (([.tools[] | select(.package) | .package] | length) ==
         ([.tools[] | select(.package) | .package] | unique | length))
    ' "$VERSIONS_FILE" >/dev/null || {
        echo "[ERROR] Invalid agent tool manifest: $VERSIONS_FILE" >&2
        return 1
    }
}

tool_rows() {
    jq -r '.tools[] | [
        .name, .command, (.package // .command),
        (.version // .channel), .installer, (.ignore_scripts // false)
    ] | @tsv' "$VERSIONS_FILE"
}

installed_version() {
    local command_name="$1" output
    command -v "$command_name" >/dev/null 2>&1 || return 1
    output=$("$command_name" --version 2>/dev/null) || return 1
    if [[ "$output" =~ ([0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?) ]]; then
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
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]]; then
        echo "[ERROR] Invalid latest version for $package: $version" >&2
        return 1
    fi
    printf '%s\n' "$version"
}

report_versions() {
    local strict="$1" failed=false
    local name command_name package expected installer ignore_scripts current status

    printf '%-20s %-12s %-12s %s\n' "Tool" "Installed" "Expected" "Status"
    while IFS=$'\t' read -r \
        name command_name package expected installer ignore_scripts; do
        if [ "$expected" = latest ] && { [ "$installer" = npm ] || [ "$installer" = claude-native ]; }; then
            expected=$(resolve_latest "$package") || return 1
        fi
        if current=$(installed_version "$command_name"); then
            if [ "$expected" = latest ]; then
                # Native installers own latest resolution; check availability offline.
                status="available (latest not checked)"
            elif [ "$current" = "$expected" ]; then
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
        printf '%-20s %-12s %-12s %s\n' \
            "$name" "$current" "$expected" "$status"
    done < <(tool_rows)

    [ "$strict" = false ] || [ "$failed" = false ]
}

install_declared_tools() {
    local failed=false script
    local name command_name package expected installer ignore_scripts current install_spec

    while IFS=$'\t' read -r \
        name command_name package expected installer ignore_scripts; do
        install_spec="${package}@${expected}"
        if [ "$expected" = latest ] && { [ "$installer" = npm ] || [ "$installer" = claude-native ]; }; then
            expected=$(resolve_latest "$package") || {
                failed=true
                continue
            }
        fi
        current="$(installed_version "$command_name" || true)"
        if [ "$current" = "$expected" ]; then
            echo "[INFO] $name $expected already installed"
            continue
        fi

        echo "[INFO] Installing $name $expected..."
        case "$installer" in
        npm)
            if [ "$ignore_scripts" = true ]; then
                npm install -g --ignore-scripts "$install_spec" || failed=true
            else
                npm install -g "$install_spec" || failed=true
            fi
            ;;
        claude-native)
            script=$(curl -fsSL "$CLAUDE_INSTALL_URL") || {
                failed=true
                continue
            }
            bash -c "$script" -- "$expected" || failed=true
            ;;
        hermes-native | herdr-native | treehouse-native | no-mistakes-native)
            # Reuse the existing, small native installers.
            # shellcheck source=bootstrap.d/05-tools.sh
            source "$DOTFILES_DIR/bootstrap.d/05-tools.sh"
            BIN_DIR="${HOME}/.local/bin"
            mkdir -p "$BIN_DIR"
            case "$installer" in
            hermes-native) install_hermes || failed=true ;;
            herdr-native) install_herdr || failed=true ;;
            treehouse-native) install_treehouse || failed=true ;;
            no-mistakes-native) install_no_mistakes || failed=true ;;
            esac
            ;;
        esac
    done < <(tool_rows)

    [ "$failed" = false ]
}

update_tools() {
    local current next latest
    local name command_name package expected installer ignore_scripts

    current="$(mktemp "${VERSIONS_FILE}.XXXXXX")"
    cp "$VERSIONS_FILE" "$current"

    while IFS=$'\t' read -r \
        name command_name package expected installer ignore_scripts; do
        [ "$expected" != latest ] || continue
        latest=$(resolve_latest "$package") || {
            rm -f "$current"
            return 1
        }
        next="${current}.next"
        jq -S --arg command "$command_name" --arg version "$latest" '
            .tools |= map(
                if .command == $command then .version = $version else . end
            )
        ' "$current" >"$next"
        mv "$next" "$current"
    done < <(tool_rows)

    if cmp -s "$current" "$VERSIONS_FILE"; then
        rm -f "$current"
        echo "[INFO] Agent tool versions already current"
    else
        mv "$current" "$VERSIONS_FILE"
        echo "[INFO] Updated $VERSIONS_FILE"
    fi
    install_declared_tools
}

validate_manifest
case "${1:-}" in
report) report_versions false ;;
check) report_versions true ;;
install | update)
    # Also protect direct callers such as just update-agent-tools in old shells.
    # shellcheck source=bootstrap.d/07-node.sh
    source "$DOTFILES_DIR/bootstrap.d/07-node.sh"
    activate_node || {
        echo "[ERROR] Required Node unavailable; run install.sh before installing tools" >&2
        exit 1
    }
    if [ "$1" = install ]; then install_declared_tools; else update_tools; fi
    ;;
*)
    echo "Usage: $0 {report|check|install|update}" >&2
    exit 1
    ;;
esac

#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
default_versions_file="${DOTFILES_DIR}/.agents/tool-versions.json"
VERSIONS_FILE="${AGENT_TOOL_VERSIONS:-$default_versions_file}"
CLAUDE_INSTALL_URL="${CLAUDE_INSTALL_URL:-https://claude.ai/install.sh}"

validate_manifest() {
    jq -e '
        def command_name:
            if has("command") then .command else .commands[0] end;
        def valid_platforms:
            type == "array" and length > 0 and
            all(.[]; test("^(darwin|linux)-(arm64|x86_64)$"));
        ((.platforms // ["darwin-arm64", "darwin-x86_64",
            "linux-arm64", "linux-x86_64"]) | valid_platforms) and
        (.tools | type) == "array" and (.tools | length) > 0 and
        all(.tools[];
            (.name | type == "string" and test("^[^\\t\\r\\n]+$")) and
            (command_name | type == "string" and
                test("^[a-zA-Z0-9][a-zA-Z0-9._-]*$")) and
            ((.platforms // ["darwin-arm64", "darwin-x86_64",
                "linux-arm64", "linux-x86_64"]) | valid_platforms) and
            if (.scope // "agent") == "agent" then
                .channel == "latest" and
                (has("version") | not) and
                (if has("ignore_scripts") then
                    (.ignore_scripts | type) == "boolean" and .installer == "npm"
                 else true end) and
                (if .installer == "npm" or .installer == "claude-native" then
                    (.package | type == "string" and
                        test("^(@[a-z0-9._-]+/)?[a-z0-9][a-z0-9._-]*$"))
                 else
                    (.installer == "cursor-native" or
                     .installer == "grok-native" or
                     .installer == "hermes-native" or
                     .installer == "herdr-native" or
                     .installer == "treehouse-native" or
                     .installer == "no-mistakes-native")
                 end)
            else
                .scope == "core" and
                (.commands | type == "array" and length > 0) and
                (.versionPolicy == "latest" or
                    .versionPolicy == "pinned" or
                    .versionPolicy == "system") and
                ((.packages // {}) | type == "object") and
                ((.github // {}) | type == "object") and
                ((.adapter // "package") == "package" or
                    .adapter == "zoxide-native" or .adapter == "uv")
            end
        ) and
        (([.tools[] | command_name] | length) ==
         ([.tools[] | command_name] | unique | length)) and
        (([.tools[] | select((.scope // "agent") == "agent" and .package) |
            .package] | length) ==
         ([.tools[] | select((.scope // "agent") == "agent" and .package) |
            .package] | unique | length))
    ' "$VERSIONS_FILE" >/dev/null || {
        echo "[ERROR] Invalid agent tool manifest: $VERSIONS_FILE" >&2
        return 1
    }
}

tool_rows() {
    jq -r '.tools[] | select((.scope // "agent") == "agent") | [
        .name, .command, (.package // .command),
        .channel, .installer, (.ignore_scripts // false)
    ] | @tsv' "$VERSIONS_FILE"
}

platform_key() {
    local os arch
    os="$(uname -s)"
    arch="$(uname -m)"
    case "$arch" in
    arm64 | aarch64) arch=arm64 ;;
    x86_64 | amd64) arch=x86_64 ;;
    *) return 1 ;;
    esac
    case "$os" in
    Darwin) os=darwin ;;
    Linux) os=linux ;;
    *) return 1 ;;
    esac
    printf '%s-%s\n' "$os" "$arch"
}

plan_rows() {
    local platform
    platform="$(platform_key)" || return 1
    jq -r --arg platform "$platform" '
        (.platforms // ["darwin-arm64", "darwin-x86_64",
            "linux-arm64", "linux-x86_64"]) as $default_platforms |
        .tools[] |
        select(((.platforms // $default_platforms) | index($platform)) != null) |
        [.name, (.scope // "agent"),
         (if has("commands") then (.commands | join(" ")) else .command end)] |
        @tsv
    ' "$VERSIONS_FILE"
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
        if [ "$strict" = true ] && { [ "$status" = drift ] || [ "$status" = missing ]; }; then
            echo "[ERROR] $name: installed=$current expected=$expected ($status)" >&2
        fi
    done < <(tool_rows)

    if [ "$strict" = true ] && [ "$failed" = true ]; then
        echo "Run: just update-agent-tools" >&2
        return 1
    fi
}

plan_tools() {
    local rows name scope commands command_name current available

    rows="$(plan_rows)" || return 1
    while IFS=$'\t' read -r name scope commands; do
        command_name="${commands%% *}"
        if [ "$scope" = agent ] && current=$(installed_version "$command_name"); then
            printf 'PASS\ttools\tnone\t%s %s is available\n' "$name" "$current"
        elif [ "$scope" = core ]; then
            available=false
            for command_name in $commands; do
                command -v "$command_name" >/dev/null 2>&1 && available=true
            done
            if [ "$available" = true ]; then
                printf 'PASS\ttools\tnone\t%s is available\n' "$name"
            else
                printf 'FAIL\ttools\tupdate\t%s is missing or not runnable\n' "$name"
            fi
        else
            printf 'FAIL\ttools\tupdate\t%s is missing or not runnable\n' "$name"
        fi
    done <<<"$rows"
}

check_tools() {
    local plan

    plan="$(plan_tools)" || return 1
    printf '%s\n' "$plan"
    ! grep -q '^FAIL' <<<"$plan"
}

install_declared_tools() {
    local refresh="${1:-false}"
    local failed=false script
    local name command_name package expected installer ignore_scripts current install_spec

    while IFS=$'\t' read -r \
        name command_name package expected installer ignore_scripts; do
        install_spec="${package}@${expected}"
        current="$(installed_version "$command_name" || true)"
        if [ "$refresh" != true ] && [ -n "$current" ]; then
            echo "[INFO] $name $current already installed"
            continue
        fi
        if [ "$expected" = latest ] &&
            { [ "$installer" = claude-native ] ||
              { [ "$installer" = npm ] && [ "$refresh" = true ]; }; }; then
            expected=$(resolve_latest "$package") || {
                failed=true
                continue
            }
        fi
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
        cursor-native | grok-native | hermes-native | herdr-native | treehouse-native | no-mistakes-native)
            # Reuse the existing, small native installers.
            # shellcheck source=bootstrap.d/05-tools.sh
            source "$DOTFILES_DIR/bootstrap.d/05-tools.sh"
            BIN_DIR="${HOME}/.local/bin"
            mkdir -p "$BIN_DIR"
            case "$installer" in
            cursor-native) install_cursor_cli || failed=true ;;
            grok-native) install_grok || failed=true ;;
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

validate_manifest
case "${1:-}" in
report) report_versions false ;;
plan) plan_tools ;;
check) check_tools ;;
install | update)
    # Also protect direct callers such as just update-agent-tools in old shells.
    # shellcheck source=bootstrap.d/07-node.sh
    source "$DOTFILES_DIR/bootstrap.d/07-node.sh"
    refresh=false
    if [ "$1" = update ]; then
        refresh=true
        install_nvm true || exit 1
    fi
    activate_node || {
        echo "[ERROR] Required Node unavailable; run install.sh before installing tools" >&2
        exit 1
    }
    install_declared_tools "$refresh"
    ;;
*)
    echo "Usage: $0 {plan|report|check|install|update}" >&2
    exit 1
    ;;
esac

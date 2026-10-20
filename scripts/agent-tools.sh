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
        def nonempty: type == "string" and length > 0;
        def github_source($tool; $platform):
            (($tool.github.repo // "") | nonempty) and
            (($tool.github.tag // "") | nonempty) and
            (($tool.github.artifacts[$platform].archive // "") | nonempty) and
            (($tool.github.artifacts[$platform].binary // "") | nonempty);
        def install_source($tool; $platform):
            if ($tool.adapter // "package") != "package" then true
            elif ($platform | startswith("darwin-")) then
                (($tool.packages.brew // "") | nonempty) or
                github_source($tool; $platform)
            else
                (($tool.packages.apt // "") | nonempty) or
                github_source($tool; $platform)
            end;
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
                (if has("update") then
                    (.update | type == "array" and length > 1 and
                        all(.[]; type == "string" and
                            test("^[a-zA-Z0-9][a-zA-Z0-9._-]*$")))
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
                . as $tool |
                $tool.scope == "core" and
                ($tool.commands | type == "array" and length > 0) and
                ($tool.versionPolicy == "latest" or
                    $tool.versionPolicy == "pinned" or
                    $tool.versionPolicy == "system") and
                (($tool.packages // {}) | type == "object") and
                (($tool.github // {}) | type == "object") and
                (($tool.adapter // "package") == "package" or
                    $tool.adapter == "zoxide-native" or
                    $tool.adapter == "uv") and
                all(($tool.platforms // [
                    "darwin-arm64", "darwin-x86_64",
                    "linux-arm64", "linux-x86_64"
                ])[]; install_source($tool; .))
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
        .channel, .installer, (.ignore_scripts // false),
        ((.update // []) | join(" "))
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

declared_commands() {
    jq -r '.tools[] | if has("commands") then .commands[] else .command end' \
        "$VERSIONS_FILE"
}

declared_npm_packages() {
    jq -r '.tools[] | select(.installer == "npm") | .package' \
        "$VERSIONS_FILE"
}

tool_export_dirs() {
    local command_name command_path
    if [ -n "${TOOL_EXPORT_BIN_DIRS:-}" ]; then
        tr ':' '\n' <<<"$TOOL_EXPORT_BIN_DIRS"
        return
    fi

    while IFS= read -r command_name; do
        command_path="$(command -v "$command_name" 2>/dev/null || true)"
        [[ "$command_path" == /* ]] && dirname "$command_path"
    done < <(declared_commands)
    [ ! -d "${HOME}/.local/bin" ] || printf '%s\n' "${HOME}/.local/bin"
}

npm_link_identity() {
    local path="$1" link rest scope name
    [ -L "$path" ] || return 1
    link="$(readlink "$path")"
    case "$link" in
    ../lib/node_modules/@*/*/*)
        rest="${link#../lib/node_modules/}"
        scope="${rest%%/*}"
        rest="${rest#*/}"
        name="${rest%%/*}"
        printf '%s/%s\n' "$scope" "$name"
        ;;
    ../lib/node_modules/*/*)
        rest="${link#../lib/node_modules/}"
        printf '%s\n' "${rest%%/*}"
        ;;
    *) return 1 ;;
    esac
}

single_command_npm_link() {
    local path="$1" package="$2" command_name="$3"
    local directory link relative package_json
    directory="$(dirname "$path")"
    link="$(readlink "$path")"
    relative="${link#../lib/node_modules/${package}/}"
    [ "$relative" != "$link" ] || return 1
    package_json="${directory}/../lib/node_modules/${package}/package.json"
    [ -f "$package_json" ] || return 1

    jq -er --arg package "$package" --arg command "$command_name" \
        --arg relative "$relative" '
        select(.name == $package) |
        .bin as $bin |
        (if ($bin | type) == "string" then
            select(($package | split("/") | last) == $command) | $bin
         elif ($bin | type) == "object" and ($bin | length) == 1 then
            $bin[$command]
         else empty end) |
        select(type == "string") |
        sub("^\\./"; "") |
        select(test("(^/|(^|/)\\.\\.(/|$))") | not) |
        select(. == $relative)
    ' "$package_json" >/dev/null
}

build_tool_export_candidate() {
    local output="$1" report="$2"
    local directory path command_name package report_unknown
    local commands packages additions addition_array rendered
    commands="$(mktemp)"
    packages="$(mktemp)"
    additions="$(mktemp)"
    addition_array="$(mktemp)"
    rendered="$(mktemp)"
    declared_commands | sort -u >"$commands"
    declared_npm_packages | sort -u >"$packages"
    : >"$additions"
    : >"$report"

    while IFS= read -r directory; do
        [ -d "$directory" ] || continue
        report_unknown=false
        if [ -n "${TOOL_EXPORT_BIN_DIRS:-}" ] ||
            [[ "$directory" == "$HOME"/* ]]; then
            report_unknown=true
        fi
        for path in "$directory"/*; do
            [ -x "$path" ] || continue
            command_name="${path##*/}"
            [[ "$command_name" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] ||
                continue
            case "$command_name" in node | npm | npx | corepack) continue ;; esac
            grep -Fxq "$command_name" "$commands" && continue

            package="$(npm_link_identity "$path" || true)"
            if [ -n "$package" ] && grep -Fxq "$package" "$packages"; then
                continue
            fi
            if [ -n "$package" ] &&
                [[ "$package" =~ ^(@[a-z0-9._-]+/)?[a-z0-9][a-z0-9._-]*$ ]] &&
                single_command_npm_link \
                    "$path" "$package" "$command_name"; then
                jq -nc --arg name "$package" --arg command "$command_name" '
                    {channel: "latest", command: $command, installer: "npm",
                     name: $name, package: $name}
                ' >>"$additions"
                printf '%s\n' "$command_name" >>"$commands"
                printf '%s\n' "$package" >>"$packages"
            elif [ "$report_unknown" = true ]; then
                printf '%s\n' "$command_name" >>"$report"
            fi
        done
    done < <(tool_export_dirs | awk 'NF && !seen[$0]++')

    sort -u -o "$report" "$report"
    jq -s '.' "$additions" >"$addition_array"
    jq --slurpfile additions "$addition_array" \
        '.tools += $additions[0]' "$VERSIONS_FILE" >"$rendered"
    local previous_versions="$VERSIONS_FILE"
    VERSIONS_FILE="$rendered"
    if ! validate_manifest; then
        VERSIONS_FILE="$previous_versions"
        rm -f "$commands" "$packages" "$additions" \
            "$addition_array" "$rendered"
        return 1
    fi
    VERSIONS_FILE="$previous_versions"
    mv "$rendered" "$output"
    rm -f "$commands" "$packages" "$additions" "$addition_array"
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
    local strict="$1" only_outdated="${2:-false}" failed=false
    local displayed=false native_unchecked=false
    local name command_name package expected installer ignore_scripts update_command
    local current status

    if [ "$only_outdated" != true ]; then
        printf '%-20s %-12s %-12s %s\n' \
            "Tool" "Installed" "Expected" "Status"
    fi
    while IFS=$'\t' read -r \
        name command_name package expected installer ignore_scripts \
        update_command; do
        if [ "$expected" = latest ] && { [ "$installer" = npm ] || [ "$installer" = claude-native ]; }; then
            expected=$(resolve_latest "$package") || return 1
        fi
        if current=$(installed_version "$command_name"); then
            if [ "$expected" = latest ]; then
                # Native installers own latest resolution; check availability offline.
                status="available (latest not checked)"
                native_unchecked=true
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
        if [ "$only_outdated" != true ] || \
            [ "$status" = drift ] || [ "$status" = missing ]; then
            if [ "$only_outdated" = true ] && [ "$displayed" = false ]; then
                printf '%-20s %-12s %-12s %s\n' \
                    "Tool" "Installed" "Expected" "Status"
            fi
            printf '%-20s %-12s %-12s %s\n' \
                "$name" "$current" "$expected" "$status"
            displayed=true
        fi
        if [ "$strict" = true ] && { [ "$status" = drift ] || [ "$status" = missing ]; }; then
            echo "[ERROR] $name: installed=$current expected=$expected ($status)" >&2
        fi
    done < <(tool_rows)

    if [ "$only_outdated" = true ]; then
        [ "$displayed" = true ] || echo "[INFO] No outdated tools found"
        [ "$native_unchecked" = false ] || \
            echo "[INFO] Native latest versions were not checked"
    fi

    if [ "$strict" = true ] && [ "$failed" = true ]; then
        echo "Run: just sync" >&2
        return 1
    fi
}

plan_tools() {
    local rows name scope commands command_name available
    local candidate report

    rows="$(plan_rows)" || return 1
    while IFS=$'\t' read -r name scope commands; do
        command_name="${commands%% *}"
        if [ "$scope" = agent ] &&
            command -v "$command_name" >/dev/null 2>&1; then
            printf 'PASS\ttools\tnone\t%s is available\n' "$name"
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

    candidate="$(mktemp)"
    report="$(mktemp)"
    build_tool_export_candidate "$candidate" "$report" || {
        rm -f "$candidate" "$report"
        return 1
    }
    jq -r --slurpfile current "$VERSIONS_FILE" '
        .tools[] |
        select(([.command] - [$current[0].tools[].command]) | length > 0) |
        ["EXPORT", "tools", "export",
         (.name + " can be exported to the tool inventory")] | @tsv
    ' "$candidate"
    rm -f "$candidate" "$report"
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
    local -a update_args
    local name command_name package expected installer ignore_scripts
    local update_command current install_spec

    while IFS=$'\t' read -r \
        name command_name package expected installer ignore_scripts \
        update_command; do
        install_spec="${package}@${expected}"
        current="$(installed_version "$command_name" || true)"
        if [ "$refresh" != true ] && [ -n "$current" ]; then
            echo "[INFO] $name $current already installed"
            continue
        fi
        if [ "$refresh" = true ] && [ -n "$current" ] &&
            [ -n "$update_command" ]; then
            read -r -a update_args <<<"$update_command"
            echo "[INFO] Updating $name..."
            "${update_args[@]}" || failed=true
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
outdated) report_versions false true ;;
report) report_versions false false ;;
plan) plan_tools ;;
check) check_tools ;;
export-candidate)
    [ "$#" -eq 3 ] || {
        echo "Usage: $0 export-candidate OUTPUT REPORT" >&2
        exit 1
    }
    build_tool_export_candidate "$2" "$3"
    ;;
install | update)
    # Also protect direct callers such as the local update workflow.
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
    echo "Usage: $0 {plan|outdated|report|check|install|update|export-candidate}" >&2
    exit 1
    ;;
esac

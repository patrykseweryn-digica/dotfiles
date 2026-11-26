#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
default_versions_file="${DOTFILES_DIR}/.agents/tool-versions.json"
VERSIONS_FILE="${AGENT_TOOL_VERSIONS:-$default_versions_file}"
CLAUDE_INSTALL_URL="${CLAUDE_INSTALL_URL:-https://claude.ai/install.sh}"
MISE_AGENT_TOOLS_FILE="${MISE_AGENT_TOOLS_FILE:-${HOME}/.config/mise/conf.d/20-agent-tools.toml}"
export MISE_TRUSTED_CONFIG_PATHS="${HOME}/.config/mise/conf.d\
${MISE_TRUSTED_CONFIG_PATHS:+:${MISE_TRUSTED_CONFIG_PATHS}}"
# shellcheck source=scripts/operation.sh
source "${DOTFILES_DIR}/scripts/operation.sh"
# shellcheck source=scripts/groups.sh
source "${DOTFILES_DIR}/scripts/groups.sh"

validate_manifest() {
    jq -e --arg names "$DOTFILES_GROUP_NAMES" '
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
            '"$GROUP_VALID_JQ"' and
            (command_name | type == "string" and
                test("^[a-zA-Z0-9][a-zA-Z0-9._-]*$")) and
            ((.platforms // ["darwin-arm64", "darwin-x86_64",
                "linux-arm64", "linux-x86_64"]) | valid_platforms) and
            if (.scope // "agent") == "agent" then
                (.channel | type == "string" and
                    test("^(latest|[0-9]+[.][0-9]+[.][0-9]+)$")) and
                (.channel == "latest" or
                    .installer == "npm" or .installer == "uv" or
                    .installer == "gh-extension") and
                (has("version") | not) and
                (if has("commands") then
                    (.commands | type == "array" and length > 0 and
                        all(.[]; type == "string" and
                            test("^[a-zA-Z0-9][a-zA-Z0-9._-]*$"))) and
                    (.command as $command |
                        (.commands | index($command)) != null)
                 else true end) and
                (if has("allow_builds") then
                    .installer == "npm" and
                    (.allow_builds | type) == "array" and
                    (.allow_builds | length) > 0 and
                    all(.allow_builds[];
                        type == "string" and
                        test("^(@[a-z0-9._-]+/)?[a-z0-9][a-z0-9._-]*$"))
                 else true end) and
                (if has("allow_low_downloads") then
                    .installer == "npm" and .allow_low_downloads == true
                 else true end) and
                (if has("trust_policy_excludes") then
                    .installer == "npm" and
                    (.trust_policy_excludes | type) == "array" and
                    (.trust_policy_excludes | length) > 0 and
                    all(.trust_policy_excludes[];
                        type == "string" and
                        test("^(@[a-z0-9._-]+/)?[a-z0-9][a-z0-9._-]*@[0-9]+\\.[0-9]+\\.[0-9]+$"))
                 else true end) and
                (if has("update") then
                    (.update | type == "array" and length > 1 and
                        all(.[]; type == "string" and
                            test("^[a-zA-Z0-9][a-zA-Z0-9._-]*$")))
                 else true end) and
                (if .installer == "gh-extension" then
                    .channel != "latest" and
                    (.package | type == "string" and
                        test("^[a-zA-Z0-9._-]+/gh-[a-zA-Z0-9._-]+$"))
                 elif .installer == "npm" or .installer == "claude-native" or
                      .installer == "uv" then
                    (.package | type == "string" and
                        test("^(@[a-z0-9._-]+/)?[a-z0-9][a-z0-9._-]*$"))
                 else
                    (.installer == "codex-native" or
                     .installer == "cursor-native" or
                     .installer == "grok-native" or
                     .installer == "herdr-native" or
                     .installer == "treehouse-native" or
                     .installer == "no-mistakes-native")
                 end)
            else
                (.commands | type == "array" and length > 0) and
                if .scope == "core" then
                    (.versionPolicy == "latest" or
                     (.versionPolicy == "pinned" and
                      (.version | type == "string" and
                          test("^[0-9]+[.][0-9]+[.][0-9]+$"))))
                elif .scope == "system" then
                    .versionPolicy == "system" and
                    (.packages | type == "object" and length > 0)
                else false
                end
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
    local platform
    platform="$(platform_key)" || return 1
    jq -r --arg groups "$DOTFILES_SELECTED_GROUPS" \
        --arg platform "$platform" --arg runner "${DOTFILES_RUNNER:-just}" '
        (.platforms // ["darwin-arm64", "darwin-x86_64",
            "linux-arm64", "linux-x86_64"]) as $default_platforms |
        .tools[] |
        select((.scope // "agent") == "agent") |
        select($runner != "make" or .package != "rust-just") |
        select(((.platforms // $default_platforms) | index($platform)) != null) |
        select('"$GROUP_SELECTED_JQ"') | [
        .name, .command, (.package // .command),
        .channel, .installer, ((.update // []) | join(" "))
    ] | @tsv' "$VERSIONS_FILE"
}

write_mise_agent_tools_config() {
    local candidate platform
    platform="$(platform_key)" || return 1
    mkdir -p "$(dirname "$MISE_AGENT_TOOLS_FILE")"
    candidate=$(mktemp "${MISE_AGENT_TOOLS_FILE}.XXXXXX") || return 1
    jq -r --arg groups "$DOTFILES_SELECTED_GROUPS" \
        --arg platform "$platform" '
        (.platforms // ["darwin-arm64", "darwin-x86_64",
            "linux-arm64", "linux-x86_64"]) as $default_platforms |
        (["[tools]"] + [
            .tools[] | select(.installer == "npm") |
            select(((.platforms // $default_platforms) |
                index($platform)) != null) |
            select('"$GROUP_SELECTED_JQ"') |
            (. as $tool |
                ([
                    if (($tool.allow_builds // []) | length) > 0 then
                        "allow_builds = [" +
                        (($tool.allow_builds | map(@json)) | join(", ")) +
                        "]"
                    else empty end,
                    if $tool.allow_low_downloads == true then
                        "allow_low_downloads = true"
                    else empty end,
                    if (($tool.trust_policy_excludes // []) | length) > 0 then
                        "trust_policy_excludes = [" +
                        (($tool.trust_policy_excludes | map(@json)) | join(", ")) +
                        "]"
                    else empty end
                ]) as $options |
                (("npm:" + $tool.package | @json) + " = " +
                    if ($options | length) == 0 then
                        ($tool.channel | @json)
                    else
                        "{ version = " + ($tool.channel | @json) + ", " +
                        ($options | join(", ")) + " }"
                    end))
        ])[]
    ' "$VERSIONS_FILE" >"$candidate" || {
        rm -f "$candidate"
        return 1
    }
    if [ -f "$MISE_AGENT_TOOLS_FILE" ] &&
        cmp -s "$candidate" "$MISE_AGENT_TOOLS_FILE"; then
        rm -f "$candidate"
    else
        mv "$candidate" "$MISE_AGENT_TOOLS_FILE"
    fi
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
    jq -r --arg platform "$platform" --arg runner "${DOTFILES_RUNNER:-just}" '
        (.platforms // ["darwin-arm64", "darwin-x86_64",
            "linux-arm64", "linux-x86_64"]) as $default_platforms |
        .tools[] |
        select(((.platforms // $default_platforms) | index($platform)) != null) |
        select((.scope // "agent") == "agent") |
        select($runner != "make" or .package != "rust-just") |
        [.name, (.scope // "agent"), .group,
         (if has("commands") then (.commands | join(" ")) else .command end),
         (.installer // "none")] |
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
    local directory path command_name package report_unknown npm_bin
    local commands packages additions addition_array rendered
    additions="$(mktemp)"
    addition_array="$(mktemp)"
    rendered="$(mktemp)"
    # Newline-delimited names, matched in memory instead of a grep per file.
    commands=$'\n'"$(declared_commands | sort -u)"$'\n'
    packages=$'\n'"$(declared_npm_packages | sort -u)"$'\n'
    : >"$additions"
    : >"$report"

    while IFS= read -r directory; do
        [ -d "$directory" ] || continue
        report_unknown=false
        if [ -n "${TOOL_EXPORT_BIN_DIRS:-}" ] ||
            [[ "$directory" == "$HOME"/* ]]; then
            report_unknown=true
        fi
        # Working npm links resolve to ../lib/node_modules; skip readlink elsewhere.
        npm_bin=false
        [ ! -d "$directory/../lib/node_modules" ] || npm_bin=true
        for path in "$directory"/*; do
            [ -x "$path" ] || continue
            command_name="${path##*/}"
            [[ "$command_name" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] ||
                continue
            case "$command_name" in node | npm | npx | corepack) continue ;; esac
            case "$commands" in *$'\n'"$command_name"$'\n'*) continue ;; esac

            package=""
            if [ "$npm_bin" = true ] && [ -L "$path" ]; then
                package="$(npm_link_identity "$path" || true)"
            fi
            if [ -n "$package" ]; then
                case "$packages" in *$'\n'"$package"$'\n'*) continue ;; esac
            fi
            if [ -n "$package" ] &&
                [[ "$package" =~ ^(@[a-z0-9._-]+/)?[a-z0-9][a-z0-9._-]*$ ]] &&
                single_command_npm_link \
                    "$path" "$package" "$command_name"; then
                jq -nc --arg name "$package" --arg command "$command_name" '
                    {channel: "latest", command: $command, group: "agents",
                     installer: "npm", name: $name, package: $name}
                ' >>"$additions"
                commands+="$command_name"$'\n'
                packages+="$package"$'\n'
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
        rm -f "$additions" "$addition_array" "$rendered"
        return 1
    fi
    VERSIONS_FILE="$previous_versions"
    mv "$rendered" "$output"
    rm -f "$additions" "$addition_array"
}

installed_version() {
    local command_name="$1" output
    if [ "$command_name" = gh-dash ]; then
        output=$(gh dash --version 2>/dev/null) || return 1
    else
        output=$("$command_name" --version 2>/dev/null) || return 1
    fi
    if [[ "$output" =~ ([0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?) ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return 0
    fi
    return 1
}

resolve_latest() {
    local package="$1" version
    version=$(operation_run "$package" "resolve latest version" query \
        --stdout -- npm view "${package}@latest" version) || {
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
    local name command_name package expected installer update_command
    local current status

    if [ "$only_outdated" != true ]; then
        printf '%-20s %-12s %-12s %s\n' \
            "Tool" "Installed" "Expected" "Status"
    fi
    while IFS=$'\t' read -r \
        name command_name package expected installer update_command; do
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
        echo "Run: ${DOTFILES_RUNNER:-just} sync" >&2
        return 1
    fi
}

# shellcheck source=bootstrap.d/05-tools.sh
source "$DOTFILES_DIR/bootstrap.d/05-tools.sh"

plan_tools() {
    local rows name scope group commands installer command_name available
    local candidate report resolved

    rows="$(plan_rows)" || return 1
    while IFS=$'\t' read -r name scope group commands installer; do
        command_name="${commands%% *}"
        resolved="$(command -v "$command_name" 2>/dev/null || true)"
        if ! group_selected "$group"; then
            group_skip_row tools "$name" "$group"
        elif [ "$installer" = codex-native ] && [ -n "$resolved" ] &&
            [ "$resolved" != "$(codex_managed_path)" ]; then
            # Another Codex first on PATH shadows the managed install.
            printf 'FAIL\ttools\tupdate\t%s resolves to %s; expected %s\n' \
                "$name" "$resolved" "$(codex_managed_path)"
        elif [ "$scope" = agent ] &&
            { if [ "$installer" = gh-extension ]; then
                installed_version "$command_name" >/dev/null 2>&1
              else
                command -v "$command_name" >/dev/null 2>&1
              fi; }; then
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

    # Only agent machines can export agent tools to the inventory.
    group_selected agents || return 0
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
    local failed=false managed_by_mise script
    local -a update_args
    local name command_name package expected installer
    local update_command current package_spec

    while IFS=$'\t' read -r \
        name command_name package expected installer update_command; do
        current="$(installed_version "$command_name" || true)"
        # Another Codex first on PATH does not count as the managed one.
        if [ "$installer" = codex-native ] &&
            [ "$(command -v codex 2>/dev/null)" != "$(codex_managed_path)" ]; then
            current=""
        fi
        case "$installer" in
        uv)
            if [ "$expected" = latest ]; then
                package_spec="$package"
            else
                package_spec="${package}==${expected}"
            fi
            update_args=()
            [ "$refresh" != true ] || update_args+=(--upgrade)
            operation_run "$name" "install with uv" install -- \
                uv tool install ${update_args[@]+"${update_args[@]}"} \
                "$package_spec" || failed=true
            continue
            ;;
        gh-extension)
            if [ "$current" != "$expected" ]; then
                operation_run "$name" "install GitHub extension" install -- \
                    gh extension install "$package" --pin "v${expected}" \
                    --force || failed=true
            fi
            continue
            ;;
        esac
        if [ "$installer" = npm ]; then
            managed_by_mise=false
            if run_global_mise which "$command_name" >/dev/null 2>&1; then
                managed_by_mise=true
            fi
            if [ "$refresh" != true ] && [ -n "$current" ] &&
                { [ "$expected" = latest ] || [ "$current" = "$expected" ]; } &&
                [ "$managed_by_mise" = true ]; then
                echo "[INFO] $name $current already installed"
                continue
            fi
            if [ "$refresh" = true ]; then
                echo "[INFO] Updating $name..."
                operation_run "$name" "upgrade with mise" install -- \
                    run_global_mise upgrade --global --no-prune \
                    "npm:${package}" || failed=true
            else
                echo "[INFO] Installing $name latest..."
                if [ "$managed_by_mise" = true ]; then
                    operation_run "$name" "reinstall with mise" install -- \
                        run_global_mise install --force \
                        "npm:${package}" || failed=true
                else
                    operation_run "$name" "install with mise" install -- \
                        run_global_mise install "npm:${package}" ||
                        failed=true
                fi
            fi
            continue
        fi
        if [ "$refresh" != true ] && [ -n "$current" ]; then
            echo "[INFO] $name $current already installed"
            continue
        fi
        if [ "$refresh" = true ] && [ -n "$current" ] &&
            [ -n "$update_command" ]; then
            # Herdr refuses to update from inside its own panes.
            if [ "$installer" = herdr-native ] && [ "${HERDR_ENV:-}" = 1 ]; then
                echo "[SKIP] $name: run \`herdr update\` outside Herdr after detaching"
                continue
            fi
            read -r -a update_args <<<"$update_command"
            echo "[INFO] Updating $name..."
            operation_run "$name" "self-update" install -- \
                "${update_args[@]}" || failed=true
            continue
        fi
        if [ "$expected" = latest ] && [ "$installer" = claude-native ]; then
            expected=$(resolve_latest "$package") || {
                failed=true
                continue
            }
        fi
        if [ "$current" = "$expected" ]; then
            echo "[INFO] $name $expected already installed"
            continue
        fi

        if [ -n "$current" ]; then
            echo "[INFO] Updating $name $current to $expected..."
        else
            echo "[INFO] Installing $name $expected..."
        fi
        case "$installer" in
        claude-native)
            script=$(operation_run "$name" "download installer" fetch \
                --stdout -- curl -fsSL "$CLAUDE_INSTALL_URL") || {
                failed=true
                continue
            }
            operation_run "$name" "install $expected" install -- \
                bash -c "$script" -- "$expected" || failed=true
            ;;
        codex-native | cursor-native | grok-native | herdr-native | \
            treehouse-native | no-mistakes-native)
            # Reuse the existing, small native installers.
            BIN_DIR="${HOME}/.local/bin"
            mkdir -p "$BIN_DIR"
            case "$installer" in
            codex-native) set -- install_codex ;;
            cursor-native) set -- install_cursor_cli ;;
            grok-native) set -- install_grok ;;
            herdr-native) set -- install_herdr ;;
            treehouse-native) set -- install_treehouse ;;
            no-mistakes-native) set -- install_no_mistakes ;;
            esac
            operation_run "$name" install install -- "$@" || failed=true
            ;;
        esac
    done < <(tool_rows)

    [ "$failed" = false ]
}

validate_manifest
groups_load || exit 1
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
    # Node and every agent tool belong to the agents group.
    if ! group_selected agents; then
        echo "[SKIP] Node and agent tools: $(group_skip_reason agents)"
        exit 0
    fi
    # Also protect direct callers such as the local update workflow.
    # shellcheck source=bootstrap.d/07-node.sh
    source "$DOTFILES_DIR/bootstrap.d/07-node.sh"
    refresh=false
    if [ "$1" = update ]; then
        refresh=true
        install_node true || exit 1
    fi
    activate_node || {
        echo "[ERROR] Required Node unavailable; run install.sh before installing tools" >&2
        exit 1
    }
    write_mise_agent_tools_config || exit 1
    install_declared_tools "$refresh"
    ;;
*)
    echo "Usage: $0 {plan|outdated|report|check|install|update|export-candidate}" >&2
    exit 1
    ;;
esac

#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL_INVENTORY="${TOOL_INVENTORY:-${DOTFILES_DIR}/.agents/tool-versions.json}"
MISE_BIN="${MISE_BIN:-${HOME}/.local/bin/mise}"
MISE_CORE_TOOLS_FILE="${MISE_CORE_TOOLS_FILE:-${HOME}/.config/mise/conf.d/10-core-tools.toml}"
export MISE_TRUSTED_CONFIG_PATHS="${HOME}/.config/mise/conf.d\
${MISE_TRUSTED_CONFIG_PATHS:+:${MISE_TRUSTED_CONFIG_PATHS}}"

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
        def nonempty: type == "string" and length > 0;
        def package_source($tool; $platform):
            if ($platform | startswith("darwin-")) then
                (($tool.packages.brew // "") | nonempty)
            else
                (["apt", "dnf", "pacman"] |
                    any(. as $manager |
                        (($tool.packages[$manager] // "") | nonempty)))
            end;
        def no_sudo_source($tool; $platform):
            ($platform | startswith("darwin-")) and
            (($tool.packages.brew // "") | nonempty);
        (.tools | type == "array" and length > 0) and
        all(.tools[] | select(.scope == "core");
            (.name | command_name) and
            (.commands | type == "array" and length > 0 and
                all(.[]; command_name)) and
            ((.platforms // ["darwin-arm64", "darwin-x86_64",
                "linux-arm64", "linux-x86_64"]) | valid_platforms) and
            .versionPolicy == "latest" and
            ((.mise // .name) | nonempty and test("^[^[:space:]]+$")) and
            (has("github") | not) and (has("packages") | not) and
            (has("adapter") | not)
        ) and
        all(.tools[] | select(.scope == "system");
            . as $tool |
            ($tool.name | command_name) and
            ($tool.commands | type == "array" and length > 0 and
                all(.[]; command_name)) and
            ($tool.versionPolicy == "system") and
            ($tool.packages | type == "object" and length > 0) and
            (($tool.platforms // ["darwin-arm64", "darwin-x86_64",
                "linux-arm64", "linux-x86_64"]) | valid_platforms) and
            all(($tool.platforms // ["darwin-arm64", "darwin-x86_64",
                "linux-arm64", "linux-x86_64"])[];
                package_source($tool; .) and
                if no_sudo_source($tool; .) then
                    ($tool | has("requires") | not)
                else
                    $tool.requires == "sudo"
                end)
        )
    ' "$TOOL_INVENTORY" >/dev/null || {
        echo "[ERROR] Invalid core tool inventory: $TOOL_INVENTORY" >&2
        return 1
    }
}

system_tool_rows() {
    local platform="$1"
    jq_run -r --arg platform "$platform" '
        .tools[] | select(.scope == "system") |
        select(((.platforms // ["darwin-arm64", "darwin-x86_64",
            "linux-arm64", "linux-x86_64"]) | index($platform)) != null) |
        [.name, (.commands | join(" ")), (.packages.apt // "-"),
         (.packages.dnf // "-"), (.packages.pacman // "-"),
         (.packages.brew // "-"), (.requires // "-")] | @tsv
    ' "$TOOL_INVENTORY"
}

mise_tool_rows() {
    local platform="$1"
    jq_run -r --arg platform "$platform" '
        .tools[] | select(.scope == "core" and
            .versionPolicy == "latest") |
        select(((.platforms // ["darwin-arm64", "darwin-x86_64",
            "linux-arm64", "linux-x86_64"]) | index($platform)) != null) |
        [.name, (.mise // .name), .commands[0]] | @tsv
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
            (((.mise // .name) | @json) + " = \"latest\"")
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
    local action="$1" platform="$2" name source command_name
    local -a tools=()

    while IFS=$'\t' read -r name source command_name; do
        [ -n "$source" ] && tools+=("$source")
    done < <(mise_tool_rows "$platform")
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

sudo_available() {
    if [ -n "${CORE_TOOLS_HAS_SUDO:-}" ]; then
        [ "$CORE_TOOLS_HAS_SUDO" = true ]
    else
        command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null
    fi
}

tool_available() {
    local command_name
    for command_name in $1; do
        command -v "$command_name" >/dev/null 2>&1 && return 0
    done
    return 1
}

system_package_manager() {
    local platform="$1" manager
    if [[ "$platform" == darwin-* ]]; then
        command -v brew >/dev/null 2>&1 && printf '%s\n' brew
        return
    fi
    for manager in apt-get dnf pacman; do
        if command -v "$manager" >/dev/null 2>&1; then
            printf '%s\n' "$manager"
            return
        fi
    done
    return 1
}

run_system_tools() {
    local platform="$1" failed=false manager package
    local name commands apt dnf pacman brew requires

    while IFS=$'\t' read -r name commands apt dnf pacman brew requires; do
        [ -n "$name" ] || continue
        if tool_available "$commands"; then
            echo "[INFO] $name is already installed"
            continue
        fi
        if [ "$requires" = sudo ] && ! sudo_available; then
            echo "[SKIP] $name: requires sudo on $platform"
            continue
        fi
        manager="$(system_package_manager "$platform")" || {
            echo "[ERROR] $name: no supported package manager" >&2
            failed=true
            continue
        }
        case "$manager" in
        brew) package="$brew" ;;
        apt-get) package="$apt" ;;
        dnf) package="$dnf" ;;
        pacman) package="$pacman" ;;
        esac
        if [ "$package" = - ]; then
            echo "[ERROR] $name: no package for $manager" >&2
            failed=true
            continue
        fi
        case "$manager" in
        brew) brew install "$package" || failed=true ;;
        apt-get) sudo apt-get install -y "$package" || failed=true ;;
        dnf) sudo dnf install -y "$package" || failed=true ;;
        pacman) sudo pacman -S --noconfirm "$package" || failed=true ;;
        esac
        if ! tool_available "$commands"; then
            echo "[ERROR] $name: package installed without its command" >&2
            failed=true
        fi
    done < <(system_tool_rows "$platform")
    [ "$failed" = false ]
}

show_plan() {
    local platform="$1" name source command_name status
    local commands apt dnf pacman brew requires
    while IFS=$'\t' read -r name source command_name; do
        status=INSTALL
        if env -u MISE_NODE_VERSION "$MISE_BIN" --cd "$HOME" \
            which "$command_name" >/dev/null 2>&1; then
            status=PASS
        fi
        if [ "$status" = PASS ]; then
            printf 'PASS\ttools\tnone\t%s is available through mise\n' "$name"
        else
            printf 'FAIL\ttools\tupdate\t%s is missing from mise\n' "$name"
        fi
    done < <(mise_tool_rows "$platform")
    while IFS=$'\t' read -r name commands apt dnf pacman brew requires; do
        [ -n "$name" ] || continue
        if tool_available "$commands"; then
            printf 'PASS\ttools\tnone\t%s is available\n' "$name"
        elif [ "$requires" = sudo ] && ! sudo_available; then
            printf 'SKIP\ttools\tnone\t%s requires sudo on %s\n' \
                "$name" "$platform"
        else
            printf 'FAIL\ttools\tupdate\t%s is missing\n' "$name"
        fi
    done < <(system_tool_rows "$platform")
}

check_tools() {
    local platform="$1" failed=false name source command_name
    local commands apt dnf pacman brew requires
    while IFS=$'\t' read -r name source command_name; do
        if ! env -u MISE_NODE_VERSION "$MISE_BIN" --cd "$HOME" \
            which "$command_name" >/dev/null 2>&1; then
            echo "[ERROR] $name is unavailable through mise" >&2
            failed=true
        fi
    done < <(mise_tool_rows "$platform")
    while IFS=$'\t' read -r name commands apt dnf pacman brew requires; do
        [ -n "$name" ] || continue
        if tool_available "$commands"; then
            continue
        fi
        if [ "$requires" = sudo ] && ! sudo_available; then
            echo "[SKIP] $name: requires sudo on $platform"
        else
            echo "[ERROR] $name is unavailable" >&2
            failed=true
        fi
    done < <(system_tool_rows "$platform")
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
    if [ ! -x "$MISE_BIN" ]; then
        # A machine provisioned before mise must still plan and converge.
        case "$action" in
        plan)
            printf 'FAIL\ttools\tupdate\tmise is missing\n'
            return 0
            ;;
        install | update)
            # shellcheck source=bootstrap.d/07-node.sh
            source "$DOTFILES_DIR/bootstrap.d/07-node.sh"
            MISE_BIN="$MISE_BIN" install_mise || return 1
            ;;
        *)
            echo "[ERROR] mise is unavailable: $MISE_BIN" >&2
            return 1
            ;;
        esac
    fi
    platform="$(tool_platform)" || {
        echo "[ERROR] Unsupported platform" >&2
        return 1
    }
    validate_inventory || return 1
    case "$action" in
    plan) show_plan "$platform" ;;
    install | update)
        run_mise_tools "$action" "$platform" &&
            run_system_tools "$platform"
        ;;
    check) check_tools "$platform" ;;
    esac
}

main "$@"

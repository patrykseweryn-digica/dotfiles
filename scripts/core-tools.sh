#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL_INVENTORY="${TOOL_INVENTORY:-${DOTFILES_DIR}/.agents/tool-versions.json}"
MISE_BIN="${MISE_BIN:-${HOME}/.local/bin/mise}"
MISE_CORE_TOOLS_FILE="${MISE_CORE_TOOLS_FILE:-${HOME}/.config/mise/conf.d/10-core-tools.toml}"
# .zshrc adds this directory to fpath.
ZSH_COMPLETION_DIR="${ZSH_COMPLETION_DIR:-${HOME}/.zfunc}"
export MISE_TRUSTED_CONFIG_PATHS="${HOME}/.config/mise/conf.d\
${MISE_TRUSTED_CONFIG_PATHS:+:${MISE_TRUSTED_CONFIG_PATHS}}"
# shellcheck source=scripts/operation.sh
source "${DOTFILES_DIR}/scripts/operation.sh"
# shellcheck source=scripts/groups.sh
source "${DOTFILES_DIR}/scripts/groups.sh"

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
    jq_run -e --arg names "$DOTFILES_GROUP_NAMES" '
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
        # A generator command or a file relative to the mise install directory.
        def valid_completion:
            type == "object" and
            ((keys == ["args"] and (.args | type == "array" and
                length > 0 and all(.[]; nonempty))) or
             (keys == ["file"] and (.file | nonempty and
                (startswith("/") | not) and
                (split("/") | index("..") == null))));
        (.tools | type == "array" and length > 0) and
        all(.tools[]; '"$GROUP_VALID_JQ"') and
        all(.tools[] | select(.scope == "core");
            (.name | command_name) and
            (.commands | type == "array" and length > 0 and
                all(.[]; command_name)) and
            ((.platforms // ["darwin-arm64", "darwin-x86_64",
                "linux-arm64", "linux-x86_64"]) | valid_platforms) and
            ((.versionPolicy == "latest" and (has("version") | not)) or
             (.versionPolicy == "pinned" and
              (.version | type == "string" and test("^[0-9]+\\.[0-9]+\\.[0-9]+$")))) and
            ((.mise // .name) | nonempty and test("^[^[:space:]]+$")) and
            (has("github") | not) and (has("packages") | not) and
            (has("adapter") | not) and
            ((has("zshCompletion") | not) or (.zshCompletion | valid_completion))
        ) and
        all(.tools[] | select(.scope == "system");
            . as $tool |
            ($tool.name | command_name) and
            ($tool.commands | type == "array" and length > 0 and
                all(.[]; command_name)) and
            ($tool.versionPolicy == "system") and
            ($tool | has("zshCompletion") | not) and
            ($tool.packages | type == "object" and length > 0) and
            (($tool.platforms // ["darwin-arm64", "darwin-x86_64",
                "linux-arm64", "linux-x86_64"]) | valid_platforms) and
            (($tool.platforms // ["darwin-arm64", "darwin-x86_64",
                "linux-arm64", "linux-x86_64"]) as $platforms |
                all($platforms[]; package_source($tool; .)) and
                if all($platforms[]; no_sudo_source($tool; .)) then
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
    jq_run -r --arg platform "$platform" \
        --arg groups "$DOTFILES_SELECTED_GROUPS" '
        .tools[] | select(.scope == "system") |
        select(((.platforms // ["darwin-arm64", "darwin-x86_64",
            "linux-arm64", "linux-x86_64"]) | index($platform)) != null) |
        select('"$GROUP_SELECTED_JQ"') |
        [.name, (.commands | join(" ")), (.packages.apt // "-"),
         (.packages.dnf // "-"), (.packages.pacman // "-"),
         (.packages.brew // "-"),
         # macOS needs Homebrew, not sudo; Linux package managers need sudo.
         (if ($platform | startswith("darwin-")) then "brew"
          else (.requires // "-") end)] | @tsv
    ' "$TOOL_INVENTORY"
}

mise_tool_rows() {
    local platform="$1"
    jq_run -r --arg platform "$platform" \
        --arg groups "$DOTFILES_SELECTED_GROUPS" '
        .tools[] | select(.scope == "core") |
        select(((.platforms // ["darwin-arm64", "darwin-x86_64",
            "linux-arm64", "linux-x86_64"]) | index($platform)) != null) |
        select('"$GROUP_SELECTED_JQ"') |
        [.name, (.mise // .name), .commands[0]] | @tsv
    ' "$TOOL_INVENTORY"
}

write_mise_config() {
    local platform="$1" candidate
    mkdir -p "$(dirname "$MISE_CORE_TOOLS_FILE")"
    candidate=$(mktemp "${MISE_CORE_TOOLS_FILE}.XXXXXX") || return 1
    jq_run -r --arg platform "$platform" \
        --arg groups "$DOTFILES_SELECTED_GROUPS" '
        (["[tools]"] + [
            .tools[] | select(.scope == "core") |
            select(((.platforms // ["darwin-arm64", "darwin-x86_64",
                "linux-arm64", "linux-x86_64"]) | index($platform)) != null) |
            select('"$GROUP_SELECTED_JQ"') |
            (((.mise // .name) | @json) + " = " +
                ((.version // "latest") | @json))
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

retire_bitwarden() {
    # The old managed config marks ownership and lets a failed removal retry.
    local tool='aqua:bitwarden/clients'
    if [ -f "$MISE_CORE_TOOLS_FILE" ] &&
        grep -Fxq "\"$tool\" = \"latest\"" "$MISE_CORE_TOOLS_FILE"; then
        operation_run "Bitwarden CLI" "uninstall retired tool" install -- \
            env -u MISE_NODE_VERSION "$MISE_BIN" --cd "$HOME" \
            uninstall --all "$tool" || return 1
        rm -f "${ZSH_COMPLETION_DIR}/_bw"
    fi
}

run_mise_tools() {
    local action="$1" platform="$2" name source command_name
    local -a tools=()

    while IFS=$'\t' read -r name source command_name; do
        [ -n "$source" ] && tools+=("$source")
    done < <(mise_tool_rows "$platform")
    retire_bitwarden || return 1
    [ "${#tools[@]}" -gt 0 ] || return 0
    write_mise_config "$platform" || return 1
    case "$action" in
    install)
        operation_run "core tools" "install with mise" install -- \
            env -u MISE_NODE_VERSION "$MISE_BIN" --cd "$HOME" \
            install "${tools[@]}"
        ;;
    update)
        operation_run "core tools" "upgrade with mise" install -- \
            env -u MISE_NODE_VERSION "$MISE_BIN" --cd "$HOME" \
            upgrade --global --no-prune "${tools[@]}"
        ;;
    esac
    env -u MISE_NODE_VERSION "$MISE_BIN" --cd "$HOME" \
        exec -- git lfs install --skip-repo
    # The tldr page cache is optional; a failed refresh keeps the old pages.
    operation_run "tldr pages" "update cache" fetch --optional -- \
        env -u MISE_NODE_VERSION "$MISE_BIN" --cd "$HOME" \
        exec -- tldr --update ||
        echo "[WARN] Could not update tldr pages; see $(operation_log_path)" >&2
}

# Print name, command and completion source (args or file, as JSON) of
# selected mise tools that declare a zsh completion.
completion_rows() {
    local platform="$1"
    jq_run -r --arg platform "$platform" \
        --arg groups "$DOTFILES_SELECTED_GROUPS" '
        .tools[] | select(.scope == "core" and has("zshCompletion")) |
        select(((.platforms // ["darwin-arm64", "darwin-x86_64",
            "linux-arm64", "linux-x86_64"]) | index($platform)) != null) |
        select('"$GROUP_SELECTED_JQ"') |
        [.name, (.mise // .name), .commands[0],
         (.zshCompletion | keys[0]),
         (.zshCompletion | to_entries[0].value | tojson)] | @tsv
    ' "$TOOL_INVENTORY"
}

# Write the zsh completion of one tool into a file.
render_completion() {
    local source="$1" command_name="$2" kind="$3" value="$4" output="$5"
    local dir arg
    local -a args=()

    case "$kind" in
    args)
        while IFS= read -r arg; do args+=("$arg"); done < <(
            jq_run -r '.[]' <<<"$value")
        env -u MISE_NODE_VERSION "$MISE_BIN" --cd "$HOME" \
            exec -- "$command_name" "${args[@]}" >"$output" 2>/dev/null ||
            return 1
        ;;
    file)
        dir="$(env -u MISE_NODE_VERSION "$MISE_BIN" --cd "$HOME" \
            where "$source" 2>/dev/null)" || return 1
        cp "${dir}/$(jq_run -r . <<<"$value")" "$output" 2>/dev/null ||
            return 1
        ;;
    *) return 1 ;;
    esac
    head -n 1 "$output" | grep -q '^#compdef '
}

# Print the names of tools whose completion file is missing or outdated.
outdated_completions() {
    local platform="$1" name source command_name kind value candidate
    candidate="$(mktemp)" || return 1
    while IFS=$'\t' read -r name source command_name kind value; do
        [ -n "$name" ] || continue
        # A missing tool already has its own plan row.
        env -u MISE_NODE_VERSION "$MISE_BIN" --cd "$HOME" \
            which "$command_name" >/dev/null 2>&1 || continue
        if ! render_completion "$source" "$command_name" "$kind" "$value" \
            "$candidate" ||
            ! cmp -s "$candidate" "${ZSH_COMPLETION_DIR}/_${command_name}"; then
            printf '%s\n' "$name"
        fi
    done < <(completion_rows "$platform")
    rm -f "$candidate"
}

# Write each changed completion; keep the old file when generation fails.
write_completions() {
    local platform="$1" failed=false name source command_name kind value
    local target candidate

    mkdir -p "$ZSH_COMPLETION_DIR" || return 1
    while IFS=$'\t' read -r name source command_name kind value; do
        [ -n "$name" ] || continue
        target="${ZSH_COMPLETION_DIR}/_${command_name}"
        candidate="$(mktemp "${ZSH_COMPLETION_DIR}/.${command_name}.XXXXXX")" ||
            return 1
        if ! render_completion "$source" "$command_name" "$kind" "$value" \
            "$candidate"; then
            echo "[ERROR] ${name}: could not generate the zsh completion" >&2
            rm -f "$candidate"
            failed=true
            continue
        fi
        if cmp -s "$candidate" "$target"; then
            rm -f "$candidate"
        else
            mv "$candidate" "$target" || failed=true
        fi
    done < <(completion_rows "$platform")
    [ "$failed" = false ]
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

# A system tool needs sudo on Linux and Homebrew on macOS.
requirement_met() {
    case "$1" in
    sudo) sudo_available ;;
    brew) command -v brew >/dev/null 2>&1 ;;
    *) return 0 ;;
    esac
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
        if ! requirement_met "$requires"; then
            echo "[SKIP] $name: requires $requires on $platform"
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
        brew) set -- brew install "$package" ;;
        apt-get) set -- sudo apt-get install -y "$package" ;;
        dnf) set -- sudo dnf install -y "$package" ;;
        pacman) set -- sudo pacman -S --noconfirm "$package" ;;
        esac
        operation_run "$name" "install with $manager" install -- "$@" ||
            failed=true
        if ! tool_available "$commands"; then
            echo "[ERROR] $name: package installed without its command" >&2
            failed=true
        fi
    done < <(system_tool_rows "$platform")
    [ "$failed" = false ]
}

# Print name and group for core and system tools of unselected groups.
skipped_tool_rows() {
    local platform="$1"
    jq_run -r --arg platform "$platform" \
        --arg groups "$DOTFILES_SELECTED_GROUPS" '
        .tools[] | select(.scope == "core" or .scope == "system") |
        select(((.platforms // ["darwin-arm64", "darwin-x86_64",
            "linux-arm64", "linux-x86_64"]) | index($platform)) != null) |
        select(('"$GROUP_SELECTED_JQ"') | not) |
        [.name, .group] | @tsv
    ' "$TOOL_INVENTORY"
}

show_plan() {
    local platform="$1" name source command_name status group outdated
    local commands apt dnf pacman brew requires
    while IFS=$'\t' read -r name group; do
        [ -n "$name" ] || continue
        group_skip_row tools "$name" "$group"
    done < <(skipped_tool_rows "$platform")
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
    outdated="$(outdated_completions "$platform" | paste -sd ',' - |
        sed 's/,/, /g')" || return 1
    if [ -n "$outdated" ]; then
        printf 'UPDATE\ttools\tupdate\tZsh completions are missing or outdated: %s\n' \
            "$outdated"
    else
        printf 'PASS\ttools\tnone\tZsh completions match installed tools\n'
    fi
    while IFS=$'\t' read -r name commands apt dnf pacman brew requires; do
        [ -n "$name" ] || continue
        if tool_available "$commands"; then
            printf 'PASS\ttools\tnone\t%s is available\n' "$name"
        elif ! requirement_met "$requires"; then
            printf 'SKIP\ttools\tnone\t%s requires %s on %s\n' \
                "$name" "$requires" "$platform"
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
        if ! requirement_met "$requires"; then
            echo "[SKIP] $name: requires $requires on $platform"
        else
            echo "[ERROR] $name is unavailable" >&2
            failed=true
        fi
    done < <(system_tool_rows "$platform")
    [ "$failed" = false ]
}

main() {
    local action="${1:-}" platform completions just_version
    case "$action" in
    plan | install | update | check) ;;
    *)
        echo "Usage: $0 [plan|install|update|check]" >&2
        return 1
        ;;
    esac
    # Reject an invalid group setting before installing mise.
    groups_load || return 1
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
        just_version=$(jq_run -er '.tools[] |
            select(.package == "rust-just") | .channel' "$TOOL_INVENTORY") ||
            return 1
        operation_run just "install with uv" install -- \
            uv tool install "rust-just==$just_version" || return 1
        run_mise_tools "$action" "$platform" || return 1
        # A failed completion must not stop system tools; report it after.
        completions=0
        write_completions "$platform" || completions=1
        run_system_tools "$platform" || return 1
        return "$completions"
        ;;
    check) check_tools "$platform" ;;
    esac
}

main "$@"

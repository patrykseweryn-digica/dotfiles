#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS_FILE="${DOTFILES_DIR}/.agents/AGENTS.md"
MCP_SERVERS="${MCP_SERVERS:-${DOTFILES_DIR}/.agents/mcp-servers.json}"
SHARED_SKILLS_CUSTOM_DIR="${SHARED_SKILLS_CUSTOM_DIR:-${DOTFILES_DIR}/.agents/skills-custom}"
CODEX_AGENTS_SOURCE="${DOTFILES_DIR}/config/codex/AGENTS.md"
CLAUDE_AGENTS_SOURCE="${DOTFILES_DIR}/config/claude/CLAUDE.md"
OPENCODE_AGENTS_SOURCE="${DOTFILES_DIR}/config/opencode/AGENTS.md"
OPENCODE_TEMPLATE="${DOTFILES_DIR}/config/opencode/opencode.json"
PI_AGENTS_SOURCE="${PI_AGENTS_SOURCE:-${DOTFILES_DIR}/config/pi/AGENTS.md}"
PI_SETTINGS_TEMPLATE="${PI_SETTINGS_TEMPLATE:-${DOTFILES_DIR}/config/pi/settings.json}"
CODEX_HOME="${CODEX_HOME:-${HOME}/.codex}"
CODEX_CONFIG="${CODEX_CONFIG:-${CODEX_HOME}/config.toml}"
CODEX_AGENTS_FILE="${CODEX_HOME}/AGENTS.md"
CLAUDE_AGENTS_FILE="${HOME}/.claude/CLAUDE.md"
CLAUDE_SKILLS_DIR="${HOME}/.claude/skills"
AGENT_SKILLS_DIR="${HOME}/.agents/skills"
OPENCODE_CONFIG_DIR="${OPENCODE_CONFIG_DIR:-${HOME}/.config/opencode}"
OPENCODE_CONFIG="${OPENCODE_CONFIG:-${OPENCODE_CONFIG_DIR}/opencode.json}"
OPENCODE_AGENTS_FILE="${OPENCODE_CONFIG_DIR}/AGENTS.md"
OPENCODE_SKILLS_DIR="${OPENCODE_CONFIG_DIR}/skills"
PI_AGENT_DIR="${PI_CODING_AGENT_DIR:-${HOME}/.pi/agent}"
PI_AGENTS_FILE="${PI_AGENT_DIR}/AGENTS.md"
PI_SETTINGS_FILE="${PI_SETTINGS_FILE:-${PI_AGENT_DIR}/settings.json}"
PI_SKILLS_DIR="${PI_SKILLS_DIR:-${PI_AGENT_DIR}/skills}"
PI_MCP_CONFIG="${PI_MCP_CONFIG:-${HOME}/.agents/mcp.json}"
KIMI_HOME="${KIMI_CODE_HOME:-${HOME}/.kimi-code}"
KIMI_MCP_CONFIG="${KIMI_MCP_CONFIG:-${KIMI_HOME}/mcp.json}"
PLUGIN_MANIFEST="${PLUGIN_MANIFEST:-${DOTFILES_DIR}/.agents/plugin-manifest.json}"
CLAUDE_MANIFEST="${CLAUDE_MANIFEST:-${PLUGIN_MANIFEST}}"
CODEX_PLUGIN_MANIFEST="${CODEX_PLUGIN_MANIFEST:-${PLUGIN_MANIFEST}}"
CODEX_REMOTE_PLUGIN_CACHE="${CODEX_REMOTE_PLUGIN_CACHE:-${CODEX_HOME}/plugins/cache/openai-curated-remote}"
CLAUDE_TEMPLATE_FILE="${CLAUDE_TEMPLATE_FILE:-${DOTFILES_DIR}/config/claude/settings.json}"
CLAUDE_SETTINGS_FILE="${CLAUDE_SETTINGS_FILE:-${HOME}/.claude/settings.json}"
CLAUDE_USER_CONFIG="${CLAUDE_USER_CONFIG:-${HOME}/.claude.json}"
SKILL_LOCK_REPO="${SKILL_LOCK_REPO:-${DOTFILES_DIR}/.agents/skill-lock.json}"
SKILL_LOCK_LIVE="${SKILL_LOCK_LIVE:-${HOME}/.agents/.skill-lock.json}"
SKILLS_CLI="${SKILLS_CLI:-skills}"

QUIET=false
MANAGED_START="# dotfiles-managed-mcp-start"
MANAGED_END="# dotfiles-managed-mcp-end"

if ! command -v jq >/dev/null 2>&1; then
    echo "[ERROR] jq is required but not installed" >&2
    exit 1
fi

if [ ! -f "$AGENTS_FILE" ]; then
    echo "[ERROR] Agent instructions not found: $AGENTS_FILE" >&2
    exit 1
fi

if [ ! -f "$MCP_SERVERS" ]; then
    echo "[ERROR] MCP servers file not found: $MCP_SERVERS" >&2
    exit 1
fi

if [ ! -e "$CODEX_AGENTS_SOURCE" ] || [ ! -e "$CLAUDE_AGENTS_SOURCE" ] || [ ! -e "$OPENCODE_AGENTS_SOURCE" ] || [ ! -e "$PI_AGENTS_SOURCE" ]; then
    echo "[ERROR] Tool-specific agent instruction symlinks are missing" >&2
    exit 1
fi

if [ ! -f "$PI_SETTINGS_TEMPLATE" ]; then
    echo "[ERROR] Pi settings template not found: $PI_SETTINGS_TEMPLATE" >&2
    exit 1
fi

if [ ! -f "$OPENCODE_TEMPLATE" ]; then
    echo "[ERROR] OpenCode template not found: $OPENCODE_TEMPLATE" >&2
    exit 1
fi

log_info() {
    [ "$QUIET" = true ] && return
    echo "[INFO] $*"
}

skill_runtime_rows() {
    cat <<EOF
Codex|$AGENT_SKILLS_DIR
Claude|$CLAUDE_SKILLS_DIR
OpenCode|$OPENCODE_SKILLS_DIR
Pi|$PI_SKILLS_DIR
EOF
}

link_file() {
    local source_path="$1"
    local target_path="$2"
    local backup_dir="${HOME}/.dotfiles-backup"

    if [ -L "$target_path" ] && [ "$(readlink "$target_path")" = "$source_path" ]; then
        return
    fi

    if [ -e "$target_path" ] || [ -L "$target_path" ]; then
        mkdir -p "$backup_dir"
        local backup_name
        backup_name="$(basename "$target_path").$(date +%Y%m%d%H%M%S)"
        cp -rP "$target_path" "${backup_dir}/${backup_name}"
        rm -rf "$target_path"
        log_info "Backed up $target_path to ${backup_dir}/${backup_name}"
    fi

    mkdir -p "$(dirname "$target_path")"
    ln -s "$source_path" "$target_path"
    log_info "Linked $target_path -> $source_path"
}

link_custom_skills() {
    local target_dir="$1"
    local skill_dir skill_name skill_file

    mkdir -p "$target_dir"

    for skill_dir in "$SHARED_SKILLS_CUSTOM_DIR"/*/; do
        [ -d "$skill_dir" ] || continue
        skill_name="$(basename "$skill_dir")"
        link_file "$skill_dir" "${target_dir}/${skill_name}"
    done

    for skill_file in "$SHARED_SKILLS_CUSTOM_DIR"/*.skill; do
        [ -f "$skill_file" ] || continue
        link_file "$skill_file" "${target_dir}/$(basename "$skill_file")"
    done
}

cmd_custom_skills_install() {
    local runtime root
    while IFS='|' read -r runtime root; do
        link_custom_skills "$root"
    done < <(skill_runtime_rows)
}

normalize_skill_lock() {
    jq -e -S '
        select((.skills | type) == "object")
        | {
            skills: (.skills | map_values(
                del(.skillFolderHash, .installedAt, .updatedAt)
            )),
            dismissed: (.dismissed // {})
        }
    ' "$1"
}

normalize_live_skill_lock() {
    local source_file="$1"
    local target_file="$2"
    local normalized installed_names
    normalized="$(mktemp)"
    installed_names="$(mktemp)"

    normalize_skill_lock "$source_file" > "$normalized" || {
        rm -f "$normalized" "$installed_names"
        return 1
    }
    write_live_skill_names "$AGENT_SKILLS_DIR" "$installed_names" || {
        rm -f "$normalized" "$installed_names"
        return 1
    }
    local status=0
    jq -e -S --rawfile installed "$installed_names" '
        ($installed | split("\n") | map(select(length > 0))) as $installed
        | .skills |= (
            to_entries
            | map(
                .key as $key
                | (.value.skillPath // "" | split("/")) as $parts
                | if ($installed | index($key)) != null then
                    .
                  elif ($parts | length) >= 2 and
                       ($installed | index($parts[-2])) != null then
                    .key = $parts[-2]
                  else
                    empty
                  end
            )
            | group_by(.key)
            | if any(.[]; length > 1) then
                error("normalized skill names collide")
              else
                map(.[0]) | from_entries
              end
        )
    ' "$normalized" > "$target_file" || status=$?
    rm -f "$normalized" "$installed_names"
    return "$status"
}

is_locked_skill() {
    local skill_name="$1"
    local lock_file

    for lock_file in "$SKILL_LOCK_LIVE" "$SKILL_LOCK_REPO"; do
        [ -f "$lock_file" ] || continue
        jq -e --arg name "$skill_name" '.skills[$name] != null' "$lock_file" >/dev/null 2>&1 && return 0
    done

    return 1
}

build_live_skill_inventory() {
    local lock_target="$1"
    local custom_target="$2"

    [ -f "$SKILL_LOCK_LIVE" ] || {
        echo "[ERROR] Missing live skill lock: $SKILL_LOCK_LIVE" >&2
        return 1
    }
    [ -d "$AGENT_SKILLS_DIR" ] || {
        echo "[ERROR] Missing live skill directory: $AGENT_SKILLS_DIR" >&2
        return 1
    }
    command -v rsync >/dev/null 2>&1 || {
        echo "[ERROR] rsync is required for skill reconciliation" >&2
        return 1
    }

    normalize_live_skill_lock "$SKILL_LOCK_LIVE" "$lock_target" || {
        echo "[ERROR] Invalid live skill lock: $SKILL_LOCK_LIVE" >&2
        return 1
    }
    rm -rf "$custom_target"
    mkdir -p "$custom_target"

    local skill_path skill_name
    for skill_path in "$AGENT_SKILLS_DIR"/*; do
        [ -e "$skill_path" ] || continue
        skill_name="$(basename "$skill_path")"
        if jq -e --arg name "$skill_name" \
            '.skills[$name] != null' "$lock_target" >/dev/null; then
            continue
        fi
        is_locked_skill "$skill_name" && continue

        if [ -d "$skill_path" ] && [ -f "${skill_path}/SKILL.md" ]; then
            mkdir -p "${custom_target}/${skill_name}"
            rsync -aL --delete --exclude '.git/' \
                "${skill_path}/" "${custom_target}/${skill_name}/"
        elif [ -f "$skill_path" ] && [[ "$skill_name" == *.skill ]]; then
            cp -L "$skill_path" "${custom_target}/${skill_name}"
        fi
    done
}

write_expected_skill_names() {
    local target_file="$1"
    local skill_path

    {
        jq -r '.skills | keys[]' "$SKILL_LOCK_REPO"
        for skill_path in "$SHARED_SKILLS_CUSTOM_DIR"/*/; do
            [ -d "$skill_path" ] && basename "$skill_path"
        done
        for skill_path in "$SHARED_SKILLS_CUSTOM_DIR"/*.skill; do
            [ -f "$skill_path" ] && basename "$skill_path"
        done
    } | sort -u > "$target_file"
}

write_live_skill_names() {
    local root="$1"
    local target_file="$2"
    local skill_path skill_name

    : > "$target_file"
    [ -d "$root" ] || return 1

    for skill_path in "$root"/*; do
        if [ -L "$skill_path" ] && [ -e "$skill_path" ]; then
            basename "$skill_path" >> "$target_file"
        elif [ -d "$skill_path" ] && [ -f "${skill_path}/SKILL.md" ]; then
            basename "$skill_path" >> "$target_file"
        elif [ -f "$skill_path" ]; then
            skill_name="$(basename "$skill_path")"
            [[ "$skill_name" == *.skill ]] && echo "$skill_name" >> "$target_file"
        fi
    done
    sort -u -o "$target_file" "$target_file"
}

is_requested_skill() {
    local skill_name="$1"
    shift

    [ "$#" -gt 0 ] || return 0

    local requested
    for requested in "$@"; do
        [ "$requested" = "$skill_name" ] && return 0
    done

    return 1
}

cmd_custom_skills_export() {
    local check_only=false
    local dry_run=false
    local requested=()

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --check)
                check_only=true
                ;;
            -n|--dry-run)
                dry_run=true
                ;;
            --)
                shift
                break
                ;;
            --*)
                echo "[ERROR] Unknown custom-skills-export flag: $1" >&2
                return 1
                ;;
            *)
                requested+=("$1")
                ;;
        esac
        shift
    done

    while [ "$#" -gt 0 ]; do
        requested+=("$1")
        shift
    done

    [ -d "$AGENT_SKILLS_DIR" ] || { log_info "No live agent skills dir: $AGENT_SKILLS_DIR"; return 0; }
    [ "$check_only" = true ] || [ "$dry_run" = true ] || command -v rsync >/dev/null 2>&1 || { echo "[ERROR] rsync is required for custom-skills-export" >&2; return 1; }

    local found_count=0
    local drift_count=0
    local failed=false
    local skill_dir skill_path skill_name target_dir action action_label

    for skill_dir in "$AGENT_SKILLS_DIR"/*/; do
        [ -d "$skill_dir" ] || continue
        skill_path="${skill_dir%/}"
        skill_name="$(basename "$skill_path")"

        if [ "${#requested[@]}" -gt 0 ]; then
            is_requested_skill "$skill_name" "${requested[@]}" || continue
        fi
        [ -f "${skill_path}/SKILL.md" ] || continue
        [ ! -L "$skill_path" ] || continue
        is_locked_skill "$skill_name" && continue

        found_count=$((found_count + 1))
        target_dir="${SHARED_SKILLS_CUSTOM_DIR}/${skill_name}"
        action="same"

        if [ -L "$target_dir" ]; then
            echo "[ERROR] Refusing to overwrite symlink target: $target_dir" >&2
            failed=true
            continue
        elif [ ! -e "$target_dir" ]; then
            action="add"
        elif ! diff -qr "$skill_path" "$target_dir" >/dev/null 2>&1; then
            action="update"
        fi

        [ "$action" != "same" ] || { log_info "Custom skill already in sync: $skill_name"; continue; }

        drift_count=$((drift_count + 1))
        if [ "$check_only" = true ]; then
            echo "[ERROR] Custom skill drift: $skill_name ($action)" >&2
            failed=true
        elif [ "$dry_run" = true ]; then
            echo "[INFO] Would ${action} custom skill: $skill_name"
        else
            mkdir -p "$target_dir"
            rsync -a --delete --exclude '.git/' "${skill_path}/" "${target_dir}/"
            case "$action" in
                add) action_label="Add" ;;
                update) action_label="Update" ;;
                *) action_label="$action" ;;
            esac
            log_info "$action_label custom skill: $skill_name"
        fi
    done

    if [ "$found_count" -eq 0 ]; then
        if [ "${#requested[@]}" -gt 0 ]; then
            echo "[ERROR] No matching live custom skills found: ${requested[*]}" >&2
            return 1
        fi
        log_info "No live custom skills to export"
        return 0
    fi

    if [ "$failed" = true ]; then
        [ "$check_only" = true ] && echo "Run: ./sync-agents.sh custom-skills-export" >&2
        return 1
    fi

    if [ "$check_only" = true ] && [ "$drift_count" -eq 0 ]; then
        log_info "Custom skills already in sync"
    fi
}

normalize_mcp_inventory() {
    jq -S '
        with_entries(
            .value = (
                if (.value.type == "http") then
                    {type: "http", url: .value.url}
                else
                    {
                        type: "stdio",
                        command: .value.command,
                        args: (.value.args // [])
                    }
                end
            )
        )
    ' "$1"
}

collect_codex_mcp() {
    command -v codex >/dev/null 2>&1 || return 0

    local raw
    raw="$(mktemp)"
    if ! codex mcp list --json > "$raw"; then
        rm -f "$raw"
        echo "[ERROR] Failed to read Codex MCP state" >&2
        return 1
    fi

    jq -c '
        .[]
        | select(.enabled != false)
        | .name as $name
        | .transport
        | if .type == "stdio" then
            {
                runtime: "codex",
                name: $name,
                server: {
                    type: "stdio",
                    command: .command,
                    args: (.args // [])
                }
            }
          elif (.type == "streamable_http" or
                .type == "http" or
                .type == "sse") then
            {
                runtime: "codex",
                name: $name,
                server: {type: "http", url: .url}
            }
          else empty
          end
    ' "$raw"
    local status=$?
    rm -f "$raw"
    return "$status"
}

collect_claude_mcp() {
    [ -f "$CLAUDE_USER_CONFIG" ] || return 0

    jq -c '
        (.mcpServers // {})
        | to_entries[]
        | .key as $name
        | .value
        | if .type == "stdio" then
            {
                runtime: "claude",
                name: $name,
                server: {
                    type: "stdio",
                    command: .command,
                    args: (.args // [])
                }
            }
          elif (.type == "http" or .type == "sse") then
            {
                runtime: "claude",
                name: $name,
                server: {type: "http", url: .url}
            }
          else empty
          end
    ' "$CLAUDE_USER_CONFIG"
}

collect_opencode_mcp() {
    [ -f "$OPENCODE_CONFIG" ] || return 0

    jq -c '
        (.mcp // {})
        | to_entries[]
        | select(.value.enabled != false)
        | .key as $name
        | .value
        | if .type == "local" then
            {
                runtime: "opencode",
                name: $name,
                server: {
                    type: "stdio",
                    command: .command[0],
                    args: (.command[1:] // [])
                }
            }
          elif .type == "remote" then
            {
                runtime: "opencode",
                name: $name,
                server: {type: "http", url: .url}
            }
          else empty
          end
    ' "$OPENCODE_CONFIG"
}

collect_kimi_mcp() {
    [ -f "$KIMI_MCP_CONFIG" ] || return 0

    jq -c '
        (.mcpServers // {})
        | to_entries[]
        | .key as $name
        | .value
        | if .url then
            {
                runtime: "kimi",
                name: $name,
                server: {type: "http", url: .url}
            }
          elif .command then
            {
                runtime: "kimi",
                name: $name,
                server: {
                    type: "stdio",
                    command: .command,
                    args: (.args // [])
                }
            }
          else empty
          end
    ' "$KIMI_MCP_CONFIG"
}

collect_pi_mcp() {
    [ -f "$PI_MCP_CONFIG" ] || return 0

    jq -c '
        (.mcpServers // {})
        | to_entries[]
        | select(.value.disabled != true)
        | .key as $name
        | .value
        | if .url then
            {
                runtime: "pi",
                name: $name,
                server: {type: "http", url: .url}
            }
          elif .command then
            {
                runtime: "pi",
                name: $name,
                server: {
                    type: "stdio",
                    command: .command,
                    args: (.args // [])
                }
            }
          else empty
          end
    ' "$PI_MCP_CONFIG"
}

available_mcp_runtimes() {
    command -v codex >/dev/null 2>&1 && echo codex
    [ -f "$CLAUDE_USER_CONFIG" ] && echo claude
    [ -f "$OPENCODE_CONFIG" ] && echo opencode
    [ -f "$KIMI_MCP_CONFIG" ] && echo kimi
    [ -f "$PI_MCP_CONFIG" ] && echo pi
    return 0
}

collect_mcp_rows() {
    collect_codex_mcp || return 1
    collect_claude_mcp || return 1
    collect_opencode_mcp || return 1
    collect_kimi_mcp || return 1
    collect_pi_mcp || return 1
}

mcp_rows_to_inventory() {
    local rows_file="$1"
    local runtime="${2:-}"

    jq -S -s --arg runtime "$runtime" '
        map(select($runtime == "" or .runtime == $runtime))
        | sort_by(.name, .runtime)
        | group_by(.name)
        | map({key: .[0].name, value: .[0].server})
        | from_entries
    ' "$rows_file"
}

cmd_pull_mcp() {
    [ "$#" -eq 0 ] || {
        echo "[ERROR] pull-mcp takes no arguments" >&2
        return 1
    }

    local rows runtimes conflicts candidate current reply
    rows="$(mktemp)"
    runtimes="$(available_mcp_runtimes)"
    [ -n "$runtimes" ] || {
        rm -f "$rows"
        echo "[ERROR] No supported runtime MCP state found" >&2
        return 1
    }
    collect_mcp_rows > "$rows" || {
        rm -f "$rows"
        return 1
    }

    conflicts=$(jq -s '
        sort_by(.name, .runtime)
        | group_by(.name)
        | map(select((map(.server | tojson) | unique | length) > 1))
        | map({
            name: .[0].name,
            definitions: map({runtime, server})
        })
    ' "$rows")
    if [ "$(jq 'length' <<< "$conflicts")" -gt 0 ]; then
        echo "[ERROR] Conflicting MCP definitions; repository unchanged:" >&2
        jq -r '.[] | "  - \(.name): " +
            ([.definitions[] | "\(.runtime)=\(.server | tojson)"] |
             join(", "))' <<< "$conflicts" >&2
        rm -f "$rows"
        return 1
    fi

    candidate="$(mktemp)"
    current="$(mktemp)"
    mcp_rows_to_inventory "$rows" > "$candidate"
    normalize_mcp_inventory "$MCP_SERVERS" > "$current"
    rm -f "$rows"

    if cmp -s "$current" "$candidate"; then
        rm -f "$current" "$candidate"
        log_info "Shared MCP inventory already matches live state"
        return 0
    fi

    diff -u "$current" "$candidate" || true
    printf 'Apply this MCP inventory? [y/N] '
    read -r reply || reply=""
    case "$reply" in
        y|Y|yes|YES)
            mv "$candidate" "$MCP_SERVERS"
            rm -f "$current"
            log_info "Updated $MCP_SERVERS from live state"
            ;;
        *)
            rm -f "$current" "$candidate"
            echo "[ERROR] MCP pull cancelled; repository unchanged" >&2
            return 1
            ;;
    esac
}

cmd_mcp_check() {
    local rows wanted actual runtime failed=false
    rows="$(mktemp)"
    wanted="$(mktemp)"
    collect_mcp_rows > "$rows" || {
        rm -f "$rows" "$wanted"
        return 1
    }
    normalize_mcp_inventory "$MCP_SERVERS" > "$wanted"

    while IFS= read -r runtime; do
        [ -n "$runtime" ] || continue
        actual="$(mktemp)"
        mcp_rows_to_inventory "$rows" "$runtime" > "$actual"
        if cmp -s "$wanted" "$actual"; then
            log_info "${runtime} MCP state matches shared inventory"
        else
            echo "[ERROR] ${runtime} MCP drift detected" >&2
            diff -u "$wanted" "$actual" >&2 || true
            failed=true
        fi
        rm -f "$actual"
    done < <(available_mcp_runtimes)

    rm -f "$rows" "$wanted"
    [ "$failed" = false ]
}

render_codex_mcp_block() {
    {
        echo "$MANAGED_START"
        jq -r '
          to_entries[]
          | .key as $name
          | .value as $server
          | "[mcp_servers.\($name)]",
            (if $server.type == "http" then
                "url = \($server.url | @json)"
             else
                "command = \($server.command | @json)\nargs = \($server.args // [] | @json)"
             end),
            (if (($server.env? // null) | type) == "object" and (($server.env // {}) | length) > 0 then
                "[mcp_servers.\($name).env]\n" + (
                    $server.env
                    | to_entries
                    | map("\(.key) = \(.value | tostring | @json)")
                    | join("\n")
                )
             else
                empty
             end),
            ""
        ' "$MCP_SERVERS"
        echo "$MANAGED_END"
    }
}

strip_codex_managed_mcp() {
    local source_file="$1"
    local names
    names="$(jq -r 'keys | join(" ")' "$MCP_SERVERS")"

    [ -f "$source_file" ] || return 0

    awk -v start="$MANAGED_START" -v end="$MANAGED_END" -v names="$names" '
        BEGIN {
            split(names, managed_names, " ")
            in_managed_block = 0
            skip_table = 0
        }

        function is_managed_header(line, i, exact, prefix) {
            for (i in managed_names) {
                exact = "[mcp_servers." managed_names[i] "]"
                prefix = "[mcp_servers." managed_names[i] "."
                if (line == exact || index(line, prefix) == 1) {
                    return 1
                }
            }
            return 0
        }

        $0 == start { in_managed_block = 1; next }
        $0 == end { in_managed_block = 0; next }
        in_managed_block { next }

        /^\[/ {
            skip_table = is_managed_header($0)
        }

        !skip_table { print }
    ' "$source_file"
}

render_codex_config() {
    local source_file="$1"
    local target_file="$2"
    local stripped
    local block

    stripped="$(mktemp)"
    block="$(mktemp)"
    strip_codex_managed_mcp "$source_file" > "$stripped"
    render_codex_mcp_block > "$block"

    awk '
        NF {
            while (blank_lines > 0) {
                print ""
                blank_lines--
            }
            print
            next
        }
        { blank_lines++ }
    ' "$stripped" > "$target_file"
    if [ -s "$target_file" ]; then
        printf '\n\n' >> "$target_file"
    fi
    cat "$block" >> "$target_file"

    rm -f "$stripped" "$block"
}

sync_codex_mcp_config() {
    mkdir -p "$CODEX_HOME"

    local tmp
    tmp="$(mktemp)"
    render_codex_config "$CODEX_CONFIG" "$tmp"

    if [ -f "$CODEX_CONFIG" ] && cmp -s "$tmp" "$CODEX_CONFIG"; then
        rm -f "$tmp"
        log_info "Codex MCP config already in sync"
    else
        mv "$tmp" "$CODEX_CONFIG"
        log_info "Wrote $CODEX_CONFIG"
    fi
}

cmd_codex_install() {
    log_info "Installing Codex agent config..."
    mkdir -p "$CODEX_HOME"
    link_file "$CODEX_AGENTS_SOURCE" "$CODEX_AGENTS_FILE"
    sync_codex_mcp_config
}

cmd_codex_check() {
    local tmp

    if [ ! -f "$CODEX_CONFIG" ]; then
        log_info "No Codex config found; skipping drift check"
        return 0
    fi

    tmp="$(mktemp)"
    render_codex_config "$CODEX_CONFIG" "$tmp"

    if [ -f "$CODEX_CONFIG" ] && cmp -s "$tmp" "$CODEX_CONFIG"; then
        rm -f "$tmp"
        log_info "Codex MCP config in sync"
        return 0
    fi

    echo "[ERROR] Codex MCP config drift detected: $CODEX_CONFIG" >&2
    echo "Run: ./sync-agents.sh codex-install" >&2
    if [ -f "$CODEX_CONFIG" ]; then
        diff -u "$CODEX_CONFIG" "$tmp" >&2 || true
    fi
    rm -f "$tmp"
    return 1
}

validate_plugin_manifest() {
    local manifest_file="$1"

    [ -f "$manifest_file" ] || {
        echo "[ERROR] Manifest not found: $manifest_file" >&2
        return 1
    }

    jq -e '
        ([.plugins[].claude] | map(select(. != null))) as $claude |
        ([.plugins[].codex] | map(select(. != null))) as $codex |
        (.marketplaces | type) == "object" and
        (.plugins | type) == "object" and
        all(.plugins | to_entries[];
            (.key | type) == "string" and (.key | length) > 0 and
            (.value | type) == "object" and
            ((.value | keys) - ["claude", "codex"] | length) == 0 and
            (.value | length) > 0 and
            (
                .value.claude == null or
                ((.value.claude | type) == "string" and
                 (.value.claude | contains("@")))
            ) and
            (
                .value.codex == null or
                ((.value.codex | type) == "string" and
                 (.value.codex | startswith("plugin_")))
            )
        ) and
        (($claude | length) == ($claude | unique | length)) and
        (($codex | length) == ($codex | unique | length))
    ' "$manifest_file" >/dev/null || {
        echo "[ERROR] Invalid shared plugin manifest: $manifest_file" >&2
        return 1
    }
}

render_codex_remote_plugins() {
    local target_file="$1"
    local rows
    rows="$(mktemp)"
    : > "$rows"

    if [ -d "$CODEX_REMOTE_PLUGIN_CACHE" ]; then
        local marker cache_name remote_plugin_id
        for marker in "$CODEX_REMOTE_PLUGIN_CACHE"/*/.codex-remote-plugin-install.json; do
            [ -f "$marker" ] || continue
            cache_name="$(basename "$(dirname "$marker")")"
            remote_plugin_id="$(jq -er '.remote_plugin_id | strings' "$marker")" || {
                rm -f "$rows"
                echo "[ERROR] Invalid Codex plugin marker: $marker" >&2
                return 1
            }
            jq -cn \
                --arg cache_name "$cache_name" \
                --arg remote_plugin_id "$remote_plugin_id" \
                '{cacheName: $cache_name, remotePluginId: $remote_plugin_id}' \
                >> "$rows"
        done
    fi

    jq -s 'sort_by(.remotePluginId)' "$rows" > "$target_file"
    rm -f "$rows"
}

codex_plugin_state_available() {
    [ -d "$CODEX_REMOTE_PLUGIN_CACHE" ] ||
        command -v codex >/dev/null 2>&1
}

claude_plugin_state_available() {
    [ -f "$1" ] || command -v claude >/dev/null 2>&1
}

cmd_codex_plugins_check() {
    validate_plugin_manifest "$CODEX_PLUGIN_MANIFEST" || return 1

    if ! codex_plugin_state_available; then
        log_info "No Codex remote plugin state found; skipping drift check"
        return 0
    fi

    local live wanted missing extra
    live="$(mktemp)"
    wanted="$(mktemp)"
    render_codex_remote_plugins "$live" || {
        rm -f "$live" "$wanted"
        return 1
    }
    jq '[.plugins | to_entries[] |
        select(.value.codex != null) | {
            name: .key,
            remotePluginId: .value.codex
        }
    ] | sort_by(.remotePluginId)' "$CODEX_PLUGIN_MANIFEST" > "$wanted"

    missing=$(jq -rn \
        --slurpfile wanted "$wanted" \
        --slurpfile live "$live" '
        ($live[0] | map(.remotePluginId)) as $live_ids |
        $wanted[0][] as $plugin |
        select(($live_ids | index($plugin.remotePluginId)) | not) |
        [$plugin.name, $plugin.remotePluginId] | @tsv
    ')
    extra=$(jq -rn \
        --slurpfile wanted "$wanted" \
        --slurpfile live "$live" '
        ($wanted[0] | map(.remotePluginId)) as $wanted_ids |
        $live[0][] as $plugin |
        select(($wanted_ids | index($plugin.remotePluginId)) | not) |
        [$plugin.cacheName, $plugin.remotePluginId] | @tsv
    ')
    rm -f "$live" "$wanted"

    if [ -z "$missing" ] && [ -z "$extra" ]; then
        log_info "Codex remote plugins match manifest"
        return 0
    fi

    echo "[ERROR] Codex remote plugin drift detected:" >&2
    if [ -n "$missing" ]; then
        echo "Missing plugins:" >&2
        echo "$missing" | awk -F '\t' \
            '{ print "  - " $1 " (" $2 ")" }' >&2
    fi
    if [ -n "$extra" ]; then
        echo "Extra plugins:" >&2
        echo "$extra" | awk -F '\t' \
            '{ print "  - " $1 " (" $2 ")" }' >&2
    fi
    echo "" >&2
    echo "Manual Codex steps:" >&2
    echo "  - Open Codex and enter: /plugins" >&2
    if [ -n "$missing" ]; then
        echo "  - Install the missing plugins listed above" >&2
        echo "  - Complete OAuth when prompted" >&2
    fi
    if [ -n "$extra" ]; then
        echo "  - Remove the extra plugins listed above" >&2
    fi
    echo "  - Run again: just push-plugins" >&2
    return 1
}

cmd_codex_plugins_export() {
    validate_plugin_manifest "$CODEX_PLUGIN_MANIFEST" || return 1

    if ! codex_plugin_state_available; then
        log_info "No Codex remote plugin state found; skipping export"
        return 0
    fi

    local live tmp
    live="$(mktemp)"
    tmp="$(mktemp)"
    render_codex_remote_plugins "$live" || {
        rm -f "$live" "$tmp"
        return 1
    }

    jq -S --slurpfile live "$live" '
        (.plugins | to_entries |
            map(select(.value.codex != null) | {
                key: .value.codex,
                value: .key
            }) | from_entries
        ) as $names |
        ($live[0] | map({
            key: ($names[.remotePluginId] // .cacheName),
            value: .remotePluginId
        }) | from_entries) as $codex |
        .plugins as $plugins |
        .plugins = reduce (
            (($plugins | keys) + ($codex | keys) | unique)[]
        ) as $name ({};
            (($plugins[$name] // {}) | del(.codex)) as $other |
            ($other + (
                if $codex[$name] != null then
                    {codex: $codex[$name]}
                else
                    {}
                end
            )) as $entry |
            if ($entry | length) > 0 then
                .[$name] = $entry
            else
                .
            end
        )
    ' "$CODEX_PLUGIN_MANIFEST" > "$tmp"
    rm -f "$live"

    if cmp -s "$tmp" "$CODEX_PLUGIN_MANIFEST"; then
        rm -f "$tmp"
        log_info "Codex plugin manifest already in sync"
        return 0
    fi

    mv "$tmp" "$CODEX_PLUGIN_MANIFEST"
    log_info "Updated Codex plugin manifest from live state"
}

cmd_codex_plugins_update() {
    command -v codex >/dev/null 2>&1 || {
        echo "[ERROR] codex CLI not found; cannot update plugin marketplaces" >&2
        return 1
    }

    log_info "Updating Codex plugin marketplaces..."
    codex plugin marketplace upgrade
}

render_opencode_config() {
    local source_file="$1"
    local target_file="$2"

    [ -f "$source_file" ] || source_file="$OPENCODE_TEMPLATE"

    jq -S --slurpfile mcp "$MCP_SERVERS" '
        def envmap($server):
            if (($server.env? // null) | type) == "array" then
                ($server.env | map({(.): "{env:\(.)}"}) | add // {})
            elif (($server.env? // null) | type) == "object" then
                $server.env
            else
                {}
            end;

        def opencode_mcp:
            $mcp[0] | to_entries |
            map(
                .key as $name |
                .value as $server |
                {
                    ($name): (
                        if (($server.type // "") == "http") then
                            {
                                "type": "remote",
                                "url": $server.url,
                                "enabled": true
                            }
                        else
                            {
                                "type": "local",
                                "command": ([$server.command] + ($server.args // [])),
                                "enabled": true
                            }
                        end
                        + (envmap($server) as $env | if ($env | length) > 0 then {"environment": $env} else {} end)
                    )
                }
            ) | add // {};

        .instructions = (((.instructions // []) | if type == "array" then . else [.] end) + ["AGENTS.md"] | unique) |
        .mcp = opencode_mcp
    ' "$source_file" > "$target_file"
}

sync_opencode_mcp_config() {
    mkdir -p "$OPENCODE_CONFIG_DIR"

    local tmp
    tmp="$(mktemp)"
    render_opencode_config "$OPENCODE_CONFIG" "$tmp"

    if [ -f "$OPENCODE_CONFIG" ] && cmp -s "$tmp" "$OPENCODE_CONFIG"; then
        rm -f "$tmp"
        log_info "OpenCode config already in sync"
    else
        mv "$tmp" "$OPENCODE_CONFIG"
        log_info "Wrote $OPENCODE_CONFIG"
    fi
}

cmd_opencode_install() {
    log_info "Installing OpenCode agent config..."
    mkdir -p "$OPENCODE_CONFIG_DIR" "$OPENCODE_SKILLS_DIR"
    link_file "$OPENCODE_AGENTS_SOURCE" "$OPENCODE_AGENTS_FILE"
    link_custom_skills "$OPENCODE_SKILLS_DIR"
    sync_opencode_mcp_config
}

cmd_opencode_check() {
    local tmp

    if [ ! -f "$OPENCODE_CONFIG" ]; then
        log_info "No OpenCode config found; skipping drift check"
        return 0
    fi

    tmp="$(mktemp)"
    render_opencode_config "$OPENCODE_CONFIG" "$tmp"

    if [ -f "$OPENCODE_CONFIG" ] && cmp -s "$tmp" "$OPENCODE_CONFIG"; then
        rm -f "$tmp"
        log_info "OpenCode config in sync"
        return 0
    fi

    echo "[ERROR] OpenCode config drift detected: $OPENCODE_CONFIG" >&2
    echo "Run: ./sync-agents.sh opencode-install" >&2
    if [ -f "$OPENCODE_CONFIG" ]; then
        diff -u "$OPENCODE_CONFIG" "$tmp" >&2 || true
    fi
    rm -f "$tmp"
    return 1
}

render_kimi_config() {
    local source_file="$1"
    local target_file="$2"

    jq -S --slurpfile mcp "$MCP_SERVERS" '
        ($mcp[0] | to_entries |
            map({(.key): (
                .value
                | if ((.type // "") == "http") then
                    {url}
                else
                    {command}
                    + (if .args then {args} else {} end)
                    + (if ((.env? // null) | type) == "object" and (.env | length) > 0 then {env} else {} end)
                end
            )}) | add // {}) as $servers |
        (. // {}) | .mcpServers = $servers
    ' < <(if [ -f "$source_file" ]; then cat "$source_file"; else echo '{}'; fi) > "$target_file"
}

render_pi_mcp_config() {
    local source_file="$1"
    local target_file="$2"

    jq -S --slurpfile mcp "$MCP_SERVERS" '
        (. // {})
        | .mcpServers = reduce ($mcp[0] | to_entries[]) as $entry (
            (.mcpServers // {});
            .[$entry.key] as $live
            | .[$entry.key] = (
                (($live // {}) | del(.command, .args, .url, .type, .enabled, .disabled))
                + ($entry.value
                    | if ((.type // "") == "http") then
                        {url}
                      else
                        {command, args: (.args // [])}
                      end)
                + (if (($entry.value.env? // null) | type) == "object" then
                    {env: $entry.value.env}
                  else
                    {}
                  end)
            )
        )
    ' < <(
        if [ -f "$source_file" ]; then
            cat "$source_file"
        else
            echo '{}'
        fi
    ) > "$target_file"
}

sync_pi_mcp_config() {
    mkdir -p "$(dirname "$PI_MCP_CONFIG")"

    local tmp
    tmp="$(mktemp)"
    render_pi_mcp_config "$PI_MCP_CONFIG" "$tmp"

    if [ -f "$PI_MCP_CONFIG" ] &&
        cmp -s "$tmp" "$PI_MCP_CONFIG"; then
        rm -f "$tmp"
        log_info "Pi MCP config already in sync"
    else
        mv "$tmp" "$PI_MCP_CONFIG"
        log_info "Wrote $PI_MCP_CONFIG"
    fi
}

cmd_kimi_install() {
    log_info "Installing Kimi MCP config..."
    mkdir -p "$KIMI_HOME"

    local tmp
    tmp="$(mktemp)"
    render_kimi_config "$KIMI_MCP_CONFIG" "$tmp"

    if [ -f "$KIMI_MCP_CONFIG" ] && cmp -s "$tmp" "$KIMI_MCP_CONFIG"; then
        rm -f "$tmp"
        log_info "Kimi MCP config already in sync"
    else
        mv "$tmp" "$KIMI_MCP_CONFIG"
        log_info "Wrote $KIMI_MCP_CONFIG"
    fi
}

sync_claude_mcp_permissions() {
    local tmp
    tmp="$(mktemp)"
    mkdir -p "$(dirname "$CLAUDE_SETTINGS_FILE")"

    jq -S --slurpfile mcp "$MCP_SERVERS" '
        ($mcp[0] | keys | map("mcp__" + . + "__*")) as $wanted
        | .permissions.allow = (
            (.permissions.allow // [])
            | map(select(
                (startswith("mcp__") and endswith("__*")) | not
            ))
            | . + $wanted
        )
        | del(.mcpServers)
    ' < <(
        if [ -f "$CLAUDE_SETTINGS_FILE" ]; then
            cat "$CLAUDE_SETTINGS_FILE"
        else
            echo '{}'
        fi
    ) > "$tmp" || {
        rm -f "$tmp"
        echo "[ERROR] Failed to render Claude MCP permissions" >&2
        return 1
    }

    if [ -f "$CLAUDE_SETTINGS_FILE" ] &&
        cmp -s "$tmp" "$CLAUDE_SETTINGS_FILE"; then
        rm -f "$tmp"
        log_info "Claude MCP permissions already in sync"
    else
        mv "$tmp" "$CLAUDE_SETTINGS_FILE"
        log_info "Wrote MCP permissions to $CLAUDE_SETTINGS_FILE"
    fi
}

sync_claude_mcp_config() {
    local tmp
    tmp="$(mktemp)"
    mkdir -p "$(dirname "$CLAUDE_USER_CONFIG")"

    jq -S --slurpfile mcp "$MCP_SERVERS" '
        (. // {})
        | .mcpServers = reduce ($mcp[0] | to_entries[]) as $entry (
            (.mcpServers // {});
            .[$entry.key] as $live
            | .[$entry.key] = (
                $entry.value
                + if (($entry.value | has("env")) | not) and
                     (($live.env? // null) != null) then
                    {env: $live.env}
                  else {} end
                + if (($entry.value | has("headers")) | not) and
                     (($live.headers? // null) != null) then
                    {headers: $live.headers}
                  else {} end
            )
        )
    ' < <(
        if [ -f "$CLAUDE_USER_CONFIG" ]; then
            cat "$CLAUDE_USER_CONFIG"
        else
            echo '{}'
        fi
    ) > "$tmp" || {
        rm -f "$tmp"
        echo "[ERROR] Failed to render Claude MCP config" >&2
        return 1
    }

    if [ -f "$CLAUDE_USER_CONFIG" ] &&
        cmp -s "$tmp" "$CLAUDE_USER_CONFIG"; then
        rm -f "$tmp"
        log_info "Claude MCP config already in sync"
    else
        mv "$tmp" "$CLAUDE_USER_CONFIG"
        log_info "Wrote $CLAUDE_USER_CONFIG"
    fi
}

cmd_push_mcp() {
    sync_codex_mcp_config
    sync_claude_mcp_config
    sync_claude_mcp_permissions
    sync_opencode_mcp_config
    cmd_kimi_install
    sync_pi_mcp_config
}

cmd_kimi_check() {
    local tmp

    if [ ! -f "$KIMI_MCP_CONFIG" ]; then
        log_info "No Kimi MCP config found; skipping drift check"
        return 0
    fi

    tmp="$(mktemp)"
    render_kimi_config "$KIMI_MCP_CONFIG" "$tmp"

    if [ -f "$KIMI_MCP_CONFIG" ] && cmp -s "$tmp" "$KIMI_MCP_CONFIG"; then
        rm -f "$tmp"
        log_info "Kimi MCP config in sync"
        return 0
    fi

    echo "[ERROR] Kimi MCP config drift detected: $KIMI_MCP_CONFIG" >&2
    echo "Run: ./sync-agents.sh kimi-install" >&2
    if [ -f "$KIMI_MCP_CONFIG" ]; then
        diff -u "$KIMI_MCP_CONFIG" "$tmp" >&2 || true
    fi
    rm -f "$tmp"
    return 1
}

cmd_claude_settings_check() {
    [ -f "$CLAUDE_TEMPLATE_FILE" ] || { echo "[ERROR] Template not found: $CLAUDE_TEMPLATE_FILE" >&2; return 1; }
    if [ ! -f "$CLAUDE_SETTINGS_FILE" ]; then
        log_info "No $CLAUDE_SETTINGS_FILE yet; skipping drift check"
        return 0
    fi

    local extras
    extras=$(jq -r --slurpfile tpl "$CLAUDE_TEMPLATE_FILE" '
        (($tpl[0] | keys) + [
            "enabledPlugins",
            "extraKnownMarketplaces"
        ]) as $allowed |
        (keys - $allowed)[]
    ' "$CLAUDE_SETTINGS_FILE") || { echo "[ERROR] Failed to parse $CLAUDE_SETTINGS_FILE" >&2; return 1; }

    if [ -n "$extras" ]; then
        echo "[ERROR] $CLAUDE_SETTINGS_FILE has keys outside the template:" >&2
        echo "$extras" | sed 's/^/  - /' >&2
        echo "" >&2
        echo "Add them to $CLAUDE_TEMPLATE_FILE (then re-run install) or remove from live settings." >&2
        return 1
    fi
    log_info "settings.json keys in sync with template"
}

generate_claude_settings() {
    [ -f "$CLAUDE_TEMPLATE_FILE" ] || { echo "[ERROR] Template not found: $CLAUDE_TEMPLATE_FILE" >&2; return 1; }
    validate_plugin_manifest "$CLAUDE_MANIFEST" || return 1

    mkdir -p "$(dirname "$CLAUDE_SETTINGS_FILE")"
    local tmp="${CLAUDE_SETTINGS_FILE}.tmp"

    jq -S --slurpfile m "$CLAUDE_MANIFEST" --slurpfile mcp "$MCP_SERVERS" '
        ($mcp[0] // {} | keys | map("mcp__" + . + "__*")) as $mcp_permissions |
        .permissions.allow = ((.permissions.allow // []) as $allow |
            $allow + ($mcp_permissions - $allow)) |
        .enabledPlugins = ($m[0].plugins | to_entries |
            map(select(.value.claude != null) | {
                (.value.claude): true
            }) | add // {}) |
        .extraKnownMarketplaces = ($m[0].marketplaces // {} | to_entries |
            map({(.key): {"source": .value}}) | add // {})
    ' "$CLAUDE_TEMPLATE_FILE" > "$tmp" || { rm -f "$tmp"; echo "[ERROR] Failed to generate Claude settings" >&2; return 1; }

    if [ -f "$CLAUDE_SETTINGS_FILE" ] && cmp -s "$tmp" "$CLAUDE_SETTINGS_FILE"; then
        rm -f "$tmp"
    else
        mv "$tmp" "$CLAUDE_SETTINGS_FILE"
        log_info "Wrote $CLAUDE_SETTINGS_FILE"
    fi
}

ensure_live_skill_lock() {
    mkdir -p "$(dirname "$SKILL_LOCK_LIVE")"

    if [ -L "$SKILL_LOCK_LIVE" ]; then
        local target
        target=$(readlink "$SKILL_LOCK_LIVE")
        if [ "$target" = "$SKILL_LOCK_REPO" ]; then
            local backup_dir="${HOME}/.dotfiles-backup"
            mkdir -p "$backup_dir"
            local backup
            backup="${backup_dir}/.skill-lock.json.legacy.$(date +%Y%m%d%H%M%S)"
            cp -L "$SKILL_LOCK_LIVE" "$backup"
            rm "$SKILL_LOCK_LIVE"
            log_info "Removed legacy symlink, backup at $backup"
        fi
    fi

    [ -f "$SKILL_LOCK_REPO" ] || { echo "[ERROR] Repo skill-lock missing: $SKILL_LOCK_REPO" >&2; return 1; }

    local tmp
    tmp=$(mktemp)
    if [ -f "$SKILL_LOCK_LIVE" ]; then
        jq -s '
          .[0] as $live | .[1] as $repo |
          {
            dismissed: $repo.dismissed,
            skills: ($repo.skills | with_entries(
              .key as $k |
              .value = (($live.skills[$k] // {}) * .value)
            ))
          } + ($live | del(.skills, .dismissed))
        ' "$SKILL_LOCK_LIVE" "$SKILL_LOCK_REPO" > "$tmp" || { rm -f "$tmp"; echo "[ERROR] Failed to merge live lock" >&2; return 1; }
    else
        cp "$SKILL_LOCK_REPO" "$tmp"
    fi

    if [ -f "$SKILL_LOCK_LIVE" ] && cmp -s "$tmp" "$SKILL_LOCK_LIVE"; then
        rm -f "$tmp"
    else
        mv "$tmp" "$SKILL_LOCK_LIVE"
        log_info "Wrote $SKILL_LOCK_LIVE from repo intent"
    fi
}

cmd_lock_skills_install() {
    [ -f "$SKILL_LOCK_LIVE" ] || { log_info "No skill-lock found; skipping skill install"; return 0; }

    local runtime root
    while IFS='|' read -r runtime root; do
        mkdir -p "$root"
        find "$root" -maxdepth 1 -lname '*claude-skill-repos*' \
            -delete 2>/dev/null || true
    done < <(skill_runtime_rows)

    local entries
    entries=$(jq -r '.skills | to_entries[] | [.key, .value.source, (.value.sourceUrl // "")] | @tsv' "$SKILL_LOCK_LIVE")
    [ -n "$entries" ] || { log_info "No skills in lock"; return 0; }

    local name source source_url
    while IFS=$'\t' read -r name source source_url; do
        [ -n "$name" ] || continue

        if [ ! -e "${AGENT_SKILLS_DIR}/${name}/SKILL.md" ] && [ ! -e "${CLAUDE_SKILLS_DIR}/${name}/SKILL.md" ] && [ ! -e "${OPENCODE_SKILLS_DIR}/${name}/SKILL.md" ] && [ ! -e "${PI_SKILLS_DIR}/${name}/SKILL.md" ]; then
            local install_ok=false
            if [ "$source" = "openclaw/agent-skills" ] || [ "$source_url" = "https://github.com/openclaw/agent-skills.git" ]; then
                log_info "Installing skill: $name (from $source)"
                "$SKILLS_CLI" add -g "$source" --skill "$name" \
                    --dangerously-accept-openclaw-risks -y \
                    </dev/null >/dev/null 2>&1 && install_ok=true
            else
                log_info "Installing skill: $name (from $source)"
                "$SKILLS_CLI" add -g "$source" --skill "$name" -y \
                    </dev/null >/dev/null 2>&1 && install_ok=true
            fi

            if [ "$install_ok" != true ]; then
                echo "[WARN] Failed to install skill: $name (from $source)" >&2
            fi
        fi

        local source_dir=""
        if [ -e "${AGENT_SKILLS_DIR}/${name}/SKILL.md" ]; then
            source_dir="${AGENT_SKILLS_DIR}/${name}"
        elif [ -e "${CLAUDE_SKILLS_DIR}/${name}/SKILL.md" ]; then
            source_dir="${CLAUDE_SKILLS_DIR}/${name}"
        elif [ -e "${OPENCODE_SKILLS_DIR}/${name}/SKILL.md" ]; then
            source_dir="${OPENCODE_SKILLS_DIR}/${name}"
        elif [ -e "${PI_SKILLS_DIR}/${name}/SKILL.md" ]; then
            source_dir="${PI_SKILLS_DIR}/${name}"
        fi

        if [ -n "$source_dir" ]; then
            local target_dir target_path
            while IFS='|' read -r runtime target_dir; do
                target_path="${target_dir}/${name}"
                [ "$source_dir" = "$target_path" ] || \
                    link_file "$source_dir" "$target_path"
            done < <(skill_runtime_rows)
        fi

        if [ ! -e "${AGENT_SKILLS_DIR}/${name}/SKILL.md" ] || [ ! -e "${CLAUDE_SKILLS_DIR}/${name}/SKILL.md" ] || [ ! -e "${OPENCODE_SKILLS_DIR}/${name}/SKILL.md" ] || [ ! -e "${PI_SKILLS_DIR}/${name}/SKILL.md" ]; then
            echo "[WARN] Skill not available in all runtimes after install: $name" >&2
        fi
    done <<< "$entries"
}

cmd_claude_plugins_export() {
    local check_only=false
    [ "${1:-}" = "--check" ] && check_only=true

    validate_plugin_manifest "$CLAUDE_MANIFEST" || return 1

    local installed_json="${HOME}/.claude/plugins/installed_plugins.json"
    local known_mp="${HOME}/.claude/plugins/known_marketplaces.json"

    if ! claude_plugin_state_available "$installed_json"; then
        log_info "No installed_plugins.json found, nothing to export"
        return 0
    fi

    [ -f "$installed_json" ] || installed_json=/dev/null

    [ -f "$known_mp" ] || known_mp=/dev/null

    local tmp
    tmp=$(mktemp)
    jq -S --slurpfile inst "$installed_json" \
       --slurpfile km <(cat "$known_mp" 2>/dev/null || echo '{}') '
        (($inst[0].plugins // {}) | keys) as $installed |
        (.plugins | to_entries |
            map(select(.value.claude != null) | {
                key: .value.claude,
                value: .key
            }) | from_entries
        ) as $names |
        (reduce $installed[] as $plugin ({};
            ($names[$plugin] // ($plugin | split("@")[0])) as $preferred |
            (if .[$preferred] == null then $preferred else $plugin end) as $name |
            .[$name] = $plugin
        )) as $claude |
        (($km[0] // {}) | to_entries |
            map(select(.value.source != null) | {
                key: .key,
                value: .value.source
            }) | from_entries
        ) as $marketplaces |
        .plugins as $plugins |
        .plugins = reduce (
            (($plugins | keys) + ($claude | keys) | unique)[]
        ) as $name ({};
            (($plugins[$name] // {}) | del(.claude)) as $other |
            ($other + (
                if $claude[$name] != null then
                    {claude: $claude[$name]}
                else
                    {}
                end
            )) as $entry |
            if ($entry | length) > 0 then
                .[$name] = $entry
            else
                .
            end
        ) |
        .marketplaces = $marketplaces
    ' "$CLAUDE_MANIFEST" > "$tmp" || { rm -f "$tmp"; echo "[ERROR] export failed" >&2; return 1; }

    if cmp -s "$tmp" "$CLAUDE_MANIFEST"; then
        rm -f "$tmp"
        log_info "Manifest already in sync with installed plugins"
        return 0
    fi

    if [ "$check_only" = true ]; then
        echo "[ERROR] Installed Claude plugins/marketplaces differ from manifest:" >&2
        diff <(jq -S '{plugins, marketplaces}' "$CLAUDE_MANIFEST") \
             <(jq -S '{plugins, marketplaces}' "$tmp") >&2 || true
        echo "" >&2
        echo "Run: just push-plugins" >&2
        rm -f "$tmp"
        return 1
    fi

    mv "$tmp" "$CLAUDE_MANIFEST"
    log_info "Updated manifest from installed Claude plugins/marketplaces"
}

try_claude_plugin_update() {
    local plugin="$1"
    local scope="$2"
    local project_path="$3"

    if [ -n "$project_path" ]; then
        [ -d "$project_path" ] || {
            echo "[ERROR] Claude plugin project path not found: $project_path" >&2
            return 1
        }
        (cd "$project_path" && \
            CLAUDECODE='' claude plugin update "$plugin" --scope "$scope")
    else
        CLAUDECODE='' claude plugin update "$plugin" --scope "$scope"
    fi
}

cmd_claude_plugins_update() {
    command -v claude >/dev/null 2>&1 || {
        echo "[ERROR] claude CLI not found; cannot update plugins" >&2
        return 1
    }

    log_info "Updating Claude plugin marketplaces..."
    CLAUDECODE='' claude plugin marketplace update || return 1

    local installed_json="${HOME}/.claude/plugins/installed_plugins.json"
    if [ ! -f "$installed_json" ]; then
        log_info "No installed Claude plugins to update"
        return 0
    fi

    local installed
    installed=$(jq -r '
        [
            (.plugins // {} | to_entries[] |
                .key as $plugin |
                .value[]? |
                [$plugin, (.scope // "user"), (.projectPath // "")]
            )
        ] | unique[] | @tsv
    ' "$installed_json") || {
        echo "[ERROR] Failed to parse $installed_json" >&2
        return 1
    }

    local failed=false
    local plugin scope project_path
    while IFS=$'\t' read -r plugin scope project_path; do
        [ -n "$plugin" ] || continue
        log_info "Updating Claude plugin: $plugin (scope: $scope)"
        try_claude_plugin_update "$plugin" "$scope" "$project_path" || \
            failed=true
    done <<< "$installed"

    [ "$failed" = false ]
}

try_claude_plugin_uninstall() {
    local plugin="$1"
    local scope="$2"
    local project_path="$3"
    local output_file
    output_file="$(mktemp)"

    if [ -n "$project_path" ] && [ -d "$project_path" ]; then
        if ( cd "$project_path" && CLAUDECODE='' claude plugin uninstall "$plugin" --scope "$scope" --keep-data -y ) > "$output_file" 2>&1; then
            rm -f "$output_file"
            return 0
        fi
    elif CLAUDECODE='' claude plugin uninstall "$plugin" --scope "$scope" --keep-data -y > "$output_file" 2>&1; then
        rm -f "$output_file"
        return 0
    fi

    if [ "$scope" != "user" ]; then
        log_info "Retrying plugin uninstall in user scope: $plugin"
        if CLAUDECODE='' claude plugin uninstall "$plugin" --scope user --keep-data -y >> "$output_file" 2>&1; then
            rm -f "$output_file"
            return 0
        fi
    fi

    cat "$output_file" >&2
    rm -f "$output_file"
    return 1
}

cmd_claude_plugins_prune() {
    local check_only=false
    [ "${1:-}" = "--check" ] && check_only=true

    validate_plugin_manifest "$CLAUDE_MANIFEST" || return 1

    local plugins_json="${HOME}/.claude/plugins/installed_plugins.json"
    local known_mp="${HOME}/.claude/plugins/known_marketplaces.json"

    if [ ! -f "$plugins_json" ] && [ ! -f "$known_mp" ]; then
        log_info "No Claude plugin state found; nothing to prune"
        return 0
    fi

    local extra_plugins=""
    if [ -f "$plugins_json" ]; then
        extra_plugins=$(jq -r --slurpfile m "$CLAUDE_MANIFEST" '
            ([$m[0].plugins[].claude] | map(select(. != null))) as $wanted |
            [
                (.plugins // {} | to_entries[] |
                    .key as $plugin |
                    select(($wanted | index($plugin)) | not) |
                    .value[]? |
                    [$plugin, (.scope // "user"), (.projectPath // "")]
                )
            ] | unique[] | @tsv
        ' "$plugins_json") || { echo "[ERROR] Failed to parse $plugins_json" >&2; return 1; }
    fi

    local extra_marketplaces=""
    if [ -f "$known_mp" ]; then
        extra_marketplaces=$(jq -r --slurpfile m "$CLAUDE_MANIFEST" '
            ($m[0].marketplaces // {} | keys) as $wanted |
            keys[] as $marketplace |
            select(($wanted | index($marketplace)) | not) |
            $marketplace
        ' "$known_mp") || { echo "[ERROR] Failed to parse $known_mp" >&2; return 1; }
    fi

    if [ -z "$extra_plugins" ] && [ -z "$extra_marketplaces" ]; then
        log_info "Claude plugins and marketplaces match manifest"
        return 0
    fi

    if [ "$check_only" = true ]; then
        echo "[ERROR] Claude plugin state has entries outside manifest:" >&2
        if [ -n "$extra_plugins" ]; then
            echo "Extra plugins:" >&2
            echo "$extra_plugins" | awk -F '\t' '{ print "  - " $1 " (scope: " $2 (($3 != "") ? ", path: " $3 : "") ")" }' >&2
        fi
        if [ -n "$extra_marketplaces" ]; then
            echo "Extra marketplaces:" >&2
            echo "$extra_marketplaces" | sed 's/^/  - /' >&2
        fi
        echo "" >&2
        echo "Run: ./sync-agents.sh claude-prune" >&2
        return 1
    fi

    command -v claude >/dev/null 2>&1 || { echo "[ERROR] claude CLI not found; cannot prune live plugins" >&2; return 1; }

    local failed=false
    local plugin scope project_path
    while IFS=$'\t' read -r plugin scope project_path; do
        [ -n "$plugin" ] || continue
        log_info "Uninstalling plugin outside manifest: $plugin (scope: $scope)"
        try_claude_plugin_uninstall "$plugin" "$scope" "$project_path" || failed=true
    done <<< "$extra_plugins"

    if [ "$failed" = true ]; then
        echo "[ERROR] Failed to uninstall one or more Claude plugins; skipping marketplace prune" >&2
        return 1
    fi

    local marketplace
    while IFS= read -r marketplace; do
        [ -n "$marketplace" ] || continue
        log_info "Removing marketplace outside manifest: $marketplace"
        CLAUDECODE='' claude plugin marketplace remove "$marketplace" || failed=true
    done <<< "$extra_marketplaces"

    [ "$failed" = false ] || return 1
    log_info "Claude plugin prune complete"
}

cmd_lock_skills_export() {
    [ -f "$SKILL_LOCK_LIVE" ] || { log_info "No live skill-lock to export from"; return 0; }

    local tmp
    tmp=$(mktemp)
    jq -S '{
        skills: (.skills | map_values(del(.skillFolderHash, .installedAt, .updatedAt))),
        dismissed: .dismissed
    }' "$SKILL_LOCK_LIVE" > "$tmp" || { rm -f "$tmp"; echo "[ERROR] skills export failed" >&2; return 1; }

    if [ -f "$SKILL_LOCK_REPO" ] && cmp -s "$tmp" "$SKILL_LOCK_REPO"; then
        rm -f "$tmp"
        log_info "Repo skill-lock already in sync"
    else
        mv "$tmp" "$SKILL_LOCK_REPO"
        log_info "Updated $SKILL_LOCK_REPO from live lock"
    fi
}

cmd_skills_update() {
    log_info "Updating global skills shared by Codex, Claude, Pi, and OpenCode..."
    "$SKILLS_CLI" update -g "$@"
}

cmd_plugins_check() {
    local failed=false
    cmd_codex_plugins_check || failed=true
    cmd_claude_plugins_export --check || failed=true
    [ "$failed" = false ]
}

cmd_plugins_export() {
    cmd_codex_plugins_export || return 1
    cmd_claude_plugins_export || return 1
}

cmd_plugins_update() {
    local failed=false
    cmd_codex_plugins_update || failed=true
    cmd_claude_plugins_update || failed=true
    [ "$failed" = false ]
}

cmd_pull_skills() {
    [ "$#" -eq 0 ] || {
        echo "[ERROR] pull-skills takes no arguments" >&2
        return 1
    }

    local candidate_dir candidate_lock candidate_custom changed=false reply
    candidate_dir="$(mktemp -d)"
    candidate_lock="${candidate_dir}/skill-lock.json"
    candidate_custom="${candidate_dir}/skills-custom"
    build_live_skill_inventory "$candidate_lock" "$candidate_custom" || {
        rm -rf "$candidate_dir"
        return 1
    }

    if ! cmp -s "$SKILL_LOCK_REPO" "$candidate_lock"; then
        diff -u "$SKILL_LOCK_REPO" "$candidate_lock" || true
        changed=true
    fi
    if ! diff -qr "$SHARED_SKILLS_CUSTOM_DIR" "$candidate_custom" \
        >/dev/null 2>&1; then
        diff -ruN "$SHARED_SKILLS_CUSTOM_DIR" "$candidate_custom" || true
        changed=true
    fi

    if [ "$changed" = false ]; then
        rm -rf "$candidate_dir"
        log_info "Shared skill inventory already matches live state"
        return 0
    fi

    printf 'Apply this skill inventory? [y/N] '
    read -r reply || reply=""
    case "$reply" in
        y|Y|yes|YES)
            cp "$candidate_lock" "$SKILL_LOCK_REPO"
            mkdir -p "$SHARED_SKILLS_CUSTOM_DIR"
            rsync -ac --delete \
                "${candidate_custom}/" "$SHARED_SKILLS_CUSTOM_DIR/"
            rm -rf "$candidate_dir"
            log_info "Updated shared skill inventory from live state"
            ;;
        *)
            rm -rf "$candidate_dir"
            echo "[ERROR] Skill pull cancelled; repository unchanged" >&2
            return 1
            ;;
    esac
}

prune_skill_dir() {
    local root="$1"
    local expected_file="$2"
    local skill_path skill_name

    mkdir -p "$root"
    for skill_path in "$root"/*; do
        [ -L "$skill_path" ] || [ -e "$skill_path" ] || continue
        skill_name="$(basename "$skill_path")"

        if [ -L "$skill_path" ] && [ ! -e "$skill_path" ]; then
            rm "$skill_path"
            log_info "Removed stale skill link: $skill_path"
        elif { [ -L "$skill_path" ] ||
                { [ -d "$skill_path" ] && [ -f "${skill_path}/SKILL.md" ]; } ||
                { [ -f "$skill_path" ] && [[ "$skill_name" == *.skill ]]; }; } &&
             ! grep -qxF "$skill_name" "$expected_file"; then
            rm -rf "$skill_path"
            log_info "Removed skill outside inventory: $skill_path"
        fi
    done
}

cmd_skills_check() {
    local tmp_dir live_lock live_custom repo_lock expected actual
    local root runtime missing extra stale failed=false
    tmp_dir="$(mktemp -d)"
    live_lock="${tmp_dir}/live-lock.json"
    live_custom="${tmp_dir}/live-custom"
    repo_lock="${tmp_dir}/repo-lock.json"
    expected="${tmp_dir}/expected.txt"
    actual="${tmp_dir}/actual.txt"

    build_live_skill_inventory "$live_lock" "$live_custom" || {
        rm -rf "$tmp_dir"
        return 1
    }
    normalize_skill_lock "$SKILL_LOCK_REPO" > "$repo_lock" || {
        rm -rf "$tmp_dir"
        echo "[ERROR] Invalid repository skill lock: $SKILL_LOCK_REPO" >&2
        return 1
    }

    if ! cmp -s "$repo_lock" "$live_lock"; then
        echo "[ERROR] Live skill lock differs from repository intent" >&2
        diff -u "$repo_lock" "$live_lock" >&2 || true
        failed=true
    fi
    if ! diff -qr "$SHARED_SKILLS_CUSTOM_DIR" "$live_custom" \
        >/dev/null 2>&1; then
        echo "[ERROR] Live custom skills differ from repository intent" >&2
        diff -ruN "$SHARED_SKILLS_CUSTOM_DIR" "$live_custom" >&2 || true
        failed=true
    fi

    write_expected_skill_names "$expected"
    while IFS='|' read -r runtime root; do
        if ! write_live_skill_names "$root" "$actual"; then
            echo "[ERROR] Missing ${runtime} skill directory: $root" >&2
            failed=true
            continue
        fi

        missing="$(comm -23 "$expected" "$actual")"
        extra="$(comm -13 "$expected" "$actual")"
        stale="$(find "$root" -mindepth 1 -maxdepth 1 -type l ! -exec test -e {} \; -print)"
        if [ -n "$missing" ]; then
            echo "[ERROR] ${runtime} missing skills:" >&2
            echo "$missing" | sed 's/^/  - /' >&2
            failed=true
        fi
        if [ -n "$extra" ]; then
            echo "[ERROR] ${runtime} unmanaged skills:" >&2
            echo "$extra" | sed 's/^/  - /' >&2
            failed=true
        fi
        if [ -n "$stale" ]; then
            echo "[ERROR] ${runtime} stale skill links:" >&2
            echo "$stale" | sed 's/^/  - /' >&2
            failed=true
        fi
    done < <(skill_runtime_rows)

    rm -rf "$tmp_dir"
    [ "$failed" = false ]
}

cmd_push_skills() {
    local expected runtime root
    expected="$(mktemp)"
    write_expected_skill_names "$expected"
    while IFS='|' read -r runtime root; do
        prune_skill_dir "$root" "$expected"
    done < <(skill_runtime_rows)
    rm -f "$expected"

    cmd_custom_skills_install
    ensure_live_skill_lock
    cmd_lock_skills_install
    cmd_skills_check
}

cmd_pull_plugins() {
    [ "$#" -eq 0 ] || {
        echo "[ERROR] pull-plugins takes no arguments" >&2
        return 1
    }
    validate_plugin_manifest "$PLUGIN_MANIFEST" || return 1

    local claude_plugins candidate reply requested_quiet
    claude_plugins="${HOME}/.claude/plugins/installed_plugins.json"
    if ! codex_plugin_state_available &&
        ! claude_plugin_state_available "$claude_plugins"; then
        echo "[ERROR] No supported live plugin state found" >&2
        return 1
    fi

    candidate="$(mktemp)"
    cp "$PLUGIN_MANIFEST" "$candidate"
    local CODEX_PLUGIN_MANIFEST="$candidate"
    local CLAUDE_MANIFEST="$candidate"
    requested_quiet="$QUIET"
    QUIET=true
    if ! cmd_plugins_export; then
        rm -f "$candidate"
        return 1
    fi
    QUIET="$requested_quiet"

    if cmp -s "$PLUGIN_MANIFEST" "$candidate"; then
        rm -f "$candidate"
        log_info "Shared plugin manifest already matches live state"
        return 0
    fi

    diff -u "$PLUGIN_MANIFEST" "$candidate" || true
    printf 'Apply this plugin inventory? [y/N] '
    read -r reply || reply=""
    case "$reply" in
        y|Y|yes|YES)
            cp "$candidate" "$PLUGIN_MANIFEST"
            rm -f "$candidate"
            log_info "Updated shared plugin manifest from live state"
            ;;
        *)
            rm -f "$candidate"
            echo "[ERROR] Plugin pull cancelled; repository unchanged" >&2
            return 1
            ;;
    esac
}

cmd_claude_plugins_push() {
    validate_plugin_manifest "$CLAUDE_MANIFEST" || return 1
    command -v claude >/dev/null 2>&1 || {
        log_info "Claude CLI not installed; skipping plugin push"
        return 0
    }

    local plugins_json="${HOME}/.claude/plugins/installed_plugins.json"
    if [ -L "$plugins_json" ] && [ ! -e "$plugins_json" ]; then
        rm "$plugins_json"
    fi

    local known_mp_file="${HOME}/.claude/plugins/known_marketplaces.json"
    local known_mp_keys=""
    [ -f "$known_mp_file" ] &&
        known_mp_keys=$(jq -r 'keys[]' "$known_mp_file")

    local failed=false mp_name mp_source mp_arg
    while IFS= read -r mp_name; do
        [ -n "$mp_name" ] || continue
        echo "$known_mp_keys" | grep -qxF "$mp_name" && continue
        mp_source=$(jq -r ".marketplaces[\"$mp_name\"].source" \
            "$CLAUDE_MANIFEST")
        case "$mp_source" in
            github)
                mp_arg=$(jq -r ".marketplaces[\"$mp_name\"].repo" \
                    "$CLAUDE_MANIFEST")
                ;;
            git)
                mp_arg=$(jq -r ".marketplaces[\"$mp_name\"].url" \
                    "$CLAUDE_MANIFEST")
                ;;
            *)
                echo "[ERROR] Unknown marketplace source: $mp_source" >&2
                failed=true
                continue
                ;;
        esac
        log_info "Adding marketplace: $mp_name"
        CLAUDECODE='' claude plugin marketplace add "$mp_arg" || failed=true
    done < <(jq -r '.marketplaces | keys[]' "$CLAUDE_MANIFEST")

    local installed_keys="" plugin
    [ -f "$plugins_json" ] &&
        installed_keys=$(jq -r '.plugins | keys[]' "$plugins_json")
    while IFS= read -r plugin; do
        [ -n "$plugin" ] || continue
        echo "$installed_keys" | grep -qxF "$plugin" && continue
        log_info "Installing plugin: $plugin"
        CLAUDECODE='' claude plugin install "$plugin" || failed=true
    done < <(jq -r '.plugins[].claude // empty' "$CLAUDE_MANIFEST")

    [ "$failed" = false ] || return 1
    cmd_claude_plugins_prune
}

cmd_push_plugins() {
    local failed=false
    cmd_codex_plugins_check || failed=true
    cmd_claude_plugins_push || failed=true
    [ "$failed" = false ]
}

render_pi_settings() {
    local source_file="$1"
    local target_file="$2"

    jq -S --slurpfile wanted "$PI_SETTINGS_TEMPLATE" '
        .lastChangelogVersion? as $last
        | $wanted[0]
        + if $last == null then
            {}
          else
            {lastChangelogVersion: $last}
          end
    ' < <(
        if [ -f "$source_file" ]; then
            cat "$source_file"
        else
            echo '{}'
        fi
    ) > "$target_file"
}

sync_pi_settings() {
    mkdir -p "$PI_AGENT_DIR"

    local tmp
    tmp="$(mktemp)"
    render_pi_settings "$PI_SETTINGS_FILE" "$tmp"

    if [ -f "$PI_SETTINGS_FILE" ] &&
        cmp -s "$tmp" "$PI_SETTINGS_FILE"; then
        rm -f "$tmp"
        log_info "Pi settings already in sync"
    else
        mv "$tmp" "$PI_SETTINGS_FILE"
        log_info "Wrote $PI_SETTINGS_FILE"
    fi
}

pi_package_installed() {
    local source="$1"
    local spec package version repo ref host path target

    case "$source" in
        npm:*)
            spec="${source#npm:}"
            package="${spec%@*}"
            version="${spec##*@}"
            jq -e --arg version "$version" \
                '.version == $version' \
                "${PI_AGENT_DIR}/npm/node_modules/${package}/package.json" \
                >/dev/null 2>&1
            ;;
        git:*)
            spec="${source#git:}"
            repo="${spec%@*}"
            ref="${spec##*@}"
            host="${repo%%/*}"
            path="${repo#*/}"
            target="${PI_AGENT_DIR}/git/${host}/${path}"
            [ -d "${target}/.git" ] &&
                [ "$(git -C "$target" rev-parse HEAD 2>/dev/null)" = "$ref" ]
            ;;
        *)
            return 1
            ;;
    esac
}

restore_pi_packages() {
    command -v pi >/dev/null 2>&1 || {
        log_info "Pi CLI not installed; skipping package restore"
        return 0
    }

    local package
    while IFS= read -r package; do
        [ -n "$package" ] || continue
        if pi_package_installed "$package"; then
            log_info "Pi package already installed: $package"
        else
            log_info "Installing Pi package: $package"
            pi install "$package"
        fi
    done < <(jq -r '.packages[]' "$PI_SETTINGS_TEMPLATE")
}

cmd_pi_install() {
    log_info "Installing Pi agent config..."
    mkdir -p "$PI_AGENT_DIR" "$PI_SKILLS_DIR"
    link_file "$PI_AGENTS_SOURCE" "$PI_AGENTS_FILE"
    sync_pi_settings
    restore_pi_packages
    sync_pi_mcp_config
}

cmd_pi_check() {
    [ -f "$PI_SETTINGS_FILE" ] || {
        echo "[ERROR] Pi settings missing: $PI_SETTINGS_FILE" >&2
        return 1
    }

    local tmp package failed=false
    tmp="$(mktemp)"
    render_pi_settings "$PI_SETTINGS_FILE" "$tmp"
    if ! cmp -s "$tmp" "$PI_SETTINGS_FILE"; then
        echo "[ERROR] Pi settings drift detected: $PI_SETTINGS_FILE" >&2
        diff -u "$tmp" "$PI_SETTINGS_FILE" >&2 || true
        failed=true
    fi
    rm -f "$tmp"

    while IFS= read -r package; do
        [ -n "$package" ] || continue
        if ! pi_package_installed "$package"; then
            echo "[ERROR] Pi package drift: $package" >&2
            failed=true
        fi
    done < <(jq -r '.packages[]' "$PI_SETTINGS_TEMPLATE")

    [ "$failed" = false ]
}

cmd_claude_install() {
    log_info "Installing Claude agent config..."
    link_file "$CLAUDE_AGENTS_SOURCE" "$CLAUDE_AGENTS_FILE"
    link_custom_skills "$AGENT_SKILLS_DIR"
    link_custom_skills "$CLAUDE_SKILLS_DIR"

    log_info "Installing Claude Code config..."
    mkdir -p "$AGENT_SKILLS_DIR" "$CLAUDE_SKILLS_DIR" "$OPENCODE_SKILLS_DIR"

    ensure_live_skill_lock
    cmd_claude_settings_check
    generate_claude_settings
    sync_claude_mcp_config

    cmd_claude_plugins_push
    cmd_lock_skills_install

    log_info "Claude sync complete"
}

cmd_install() {
    cmd_custom_skills_install
    cmd_codex_install
    cmd_opencode_install
    cmd_kimi_install
    cmd_pi_install
    cmd_claude_install
    cmd_codex_plugins_check

    log_info "Agent config sync complete"
}

while [[ "${1:-}" == --* ]]; do
    case "$1" in
        --quiet) QUIET=true; shift ;;
        *) echo "[ERROR] Unknown flag: $1" >&2; exit 1 ;;
    esac
done

case "${1:-}" in
    install)
        cmd_install
        ;;
    pull-mcp)
        shift
        cmd_pull_mcp "$@"
        ;;
    push-mcp)
        cmd_push_mcp
        ;;
    mcp-check)
        cmd_mcp_check
        ;;
    pull-skills)
        shift
        cmd_pull_skills "$@"
        ;;
    push-skills)
        cmd_push_skills
        ;;
    skills-check)
        cmd_skills_check
        ;;
    pull-plugins)
        shift
        cmd_pull_plugins "$@"
        ;;
    push-plugins)
        cmd_push_plugins
        ;;
    codex-install)
        cmd_codex_install
        ;;
    codex-check)
        cmd_codex_check
        ;;
    codex-plugins-check)
        cmd_codex_plugins_check
        ;;
    codex-plugins-export)
        cmd_codex_plugins_export
        ;;
    plugins-check)
        cmd_plugins_check
        ;;
    plugins-export)
        cmd_plugins_export
        ;;
    plugins-update)
        cmd_plugins_update
        ;;
    opencode-install)
        cmd_opencode_install
        ;;
    opencode-check)
        cmd_opencode_check
        ;;
    kimi-install)
        cmd_kimi_install
        ;;
    kimi-check)
        cmd_kimi_check
        ;;
    pi-install)
        cmd_pi_install
        ;;
    pi-check)
        cmd_pi_check
        ;;
    claude-install)
        cmd_claude_install
        ;;
    skills-update)
        shift
        cmd_skills_update "$@"
        ;;
    claude-export)
        shift
        cmd_claude_plugins_export "$@"
        ;;
    claude-prune)
        shift
        cmd_claude_plugins_prune "$@"
        ;;
    custom-skills-export)
        shift
        cmd_custom_skills_export "$@"
        ;;
    skills-export)
        cmd_lock_skills_export
        ;;
    claude-settings-check)
        cmd_claude_settings_check
        ;;
    *)
        echo "Usage: $0 [--quiet] <command>"
        echo
        echo "  pull-mcp         Preview and confirm live MCP import"
        echo "  push-mcp         Render shared MCP state into runtimes"
        echo "  mcp-check        Compare normalized MCP state"
        echo "  pull-skills      Preview and confirm live skill import"
        echo "  push-skills      Reconcile skills without version updates"
        echo "  skills-check     Compare runtime skills with shared inventory"
        echo "  pull-plugins     Preview and confirm live plugin import"
        echo "  push-plugins     Apply membership without version updates"
        echo "  install          Sync shared agent config into Codex, Claude, Pi, OpenCode, and Kimi"
        echo "  plugins-check    Check Codex and Claude against shared plugin manifest"
        echo "  plugins-export   Export Codex and Claude into shared plugin manifest"
        echo "  plugins-update   Update Codex marketplaces and installed Claude plugins"
        echo "  codex-install    Link AGENTS.md and generate Codex MCP config"
        echo "  codex-check      Exit 1 if Codex MCP config is out of sync"
        echo "  codex-plugins-check"
        echo "                  Exit 1 if remote Codex plugins differ from manifest"
        echo "  codex-plugins-export"
        echo "                  Replace manifest with current remote Codex plugins"
        echo "  opencode-install Link AGENTS.md, skills, and generate OpenCode MCP config"
        echo "  opencode-check   Exit 1 if OpenCode config is out of sync"
        echo "  kimi-install     Generate Kimi MCP config (~/.kimi-code/mcp.json)"
        echo "  kimi-check       Exit 1 if Kimi MCP config is out of sync"
        echo "  pi-install       Link instructions, restore settings and packages"
        echo "  pi-check         Exit 1 if Pi settings or packages drift"
        echo "  claude-install   Link AGENTS.md, generate Claude settings, install plugins and skills"
        echo "  skills-update    Update global skills shared by Codex, Claude, Pi, and OpenCode"
        echo "  claude-export    Sync installed Claude plugins/marketplaces into manifest"
        echo "  claude-prune     Remove Claude plugins/marketplaces not listed in manifest"
        echo "  custom-skills-export"
        echo "                  Copy live custom skills from ~/.agents/skills into repo skills-custom"
        echo "  skills-export    Strip live skill-lock into repo after skills add/update"
        echo "  claude-settings-check"
        echo "                  Exit 1 if ~/.claude/settings.json has keys outside the template"
        exit 1
        ;;
esac

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
KIMI_HOME="${KIMI_CODE_HOME:-${HOME}/.kimi-code}"
KIMI_MCP_CONFIG="${KIMI_MCP_CONFIG:-${KIMI_HOME}/mcp.json}"
PLUGIN_MANIFEST="${PLUGIN_MANIFEST:-${DOTFILES_DIR}/.agents/plugin-manifest.json}"
CLAUDE_MANIFEST="${CLAUDE_MANIFEST:-${PLUGIN_MANIFEST}}"
CODEX_PLUGIN_MANIFEST="${CODEX_PLUGIN_MANIFEST:-${PLUGIN_MANIFEST}}"
CODEX_REMOTE_PLUGIN_CACHE="${CODEX_REMOTE_PLUGIN_CACHE:-${CODEX_HOME}/plugins/cache/openai-curated-remote}"
CLAUDE_TEMPLATE_FILE="${CLAUDE_TEMPLATE_FILE:-${DOTFILES_DIR}/config/claude/settings.json}"
CLAUDE_SETTINGS_FILE="${CLAUDE_SETTINGS_FILE:-${HOME}/.claude/settings.json}"
SKILL_LOCK_REPO="${SKILL_LOCK_REPO:-${DOTFILES_DIR}/.agents/skill-lock.json}"
SKILL_LOCK_LIVE="${SKILL_LOCK_LIVE:-${HOME}/.agents/.skill-lock.json}"
SKILLS_CLI_PACKAGE="skills@1.5.15"

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

if [ ! -e "$CODEX_AGENTS_SOURCE" ] || [ ! -e "$CLAUDE_AGENTS_SOURCE" ] || [ ! -e "$OPENCODE_AGENTS_SOURCE" ]; then
    echo "[ERROR] Tool-specific agent instruction symlinks are missing" >&2
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
    link_custom_skills "$AGENT_SKILLS_DIR"
    link_custom_skills "$CLAUDE_SKILLS_DIR"
    link_custom_skills "$OPENCODE_SKILLS_DIR"
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

cmd_codex_install() {
    log_info "Installing Codex agent config..."
    mkdir -p "$CODEX_HOME"

    link_file "$CODEX_AGENTS_SOURCE" "$CODEX_AGENTS_FILE"

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

cmd_codex_plugins_check() {
    validate_plugin_manifest "$CODEX_PLUGIN_MANIFEST" || return 1

    if [ ! -d "$CODEX_REMOTE_PLUGIN_CACHE" ]; then
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
    echo "Keep live state: ./sync-agents.sh plugins-export" >&2
    echo "Keep manifest: uninstall extras and install missing plugins via /plugins" >&2
    return 1
}

cmd_codex_plugins_export() {
    validate_plugin_manifest "$CODEX_PLUGIN_MANIFEST" || return 1

    if [ ! -d "$CODEX_REMOTE_PLUGIN_CACHE" ]; then
        echo "[ERROR] No Codex remote plugin state: $CODEX_REMOTE_PLUGIN_CACHE" >&2
        return 1
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

cmd_opencode_install() {
    log_info "Installing OpenCode agent config..."
    mkdir -p "$OPENCODE_CONFIG_DIR" "$OPENCODE_SKILLS_DIR"

    link_file "$OPENCODE_AGENTS_SOURCE" "$OPENCODE_AGENTS_FILE"
    link_custom_skills "$OPENCODE_SKILLS_DIR"

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
        (($tpl[0] | keys) + ["enabledPlugins", "extraKnownMarketplaces", "mcpServers"]) as $allowed |
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
        .enabledPlugins = ($m[0].plugins | to_entries |
            map(select(.value.claude != null) | {
                (.value.claude): true
            }) | add // {}) |
        .extraKnownMarketplaces = ($m[0].marketplaces // {} | to_entries |
            map({(.key): {"source": .value}}) | add // {}) |
        .mcpServers = ($mcp[0] // {} | to_entries |
            map({(.key): (
                .value
                | if ((.env? // null) | type) == "object" then . else del(.env) end
            )}) | add // {})
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

    mkdir -p "$AGENT_SKILLS_DIR" "$CLAUDE_SKILLS_DIR" "$OPENCODE_SKILLS_DIR"
    [ -d "$AGENT_SKILLS_DIR" ] && find "$AGENT_SKILLS_DIR" -maxdepth 1 -lname '*claude-skill-repos*' -delete 2>/dev/null || true
    [ -d "$CLAUDE_SKILLS_DIR" ] && find "$CLAUDE_SKILLS_DIR" -maxdepth 1 -lname '*claude-skill-repos*' -delete 2>/dev/null || true
    [ -d "$OPENCODE_SKILLS_DIR" ] && find "$OPENCODE_SKILLS_DIR" -maxdepth 1 -lname '*claude-skill-repos*' -delete 2>/dev/null || true

    local entries
    entries=$(jq -r '.skills | to_entries[] | [.key, .value.source, (.value.sourceUrl // "")] | @tsv' "$SKILL_LOCK_LIVE")
    [ -n "$entries" ] || { log_info "No skills in lock"; return 0; }

    local name source source_url
    while IFS=$'\t' read -r name source source_url; do
        [ -n "$name" ] || continue
        if [ -e "${AGENT_SKILLS_DIR}/${name}/SKILL.md" ] && [ -e "${CLAUDE_SKILLS_DIR}/${name}/SKILL.md" ] && [ -e "${OPENCODE_SKILLS_DIR}/${name}/SKILL.md" ]; then
            continue
        fi

        if [ ! -e "${AGENT_SKILLS_DIR}/${name}/SKILL.md" ] && [ ! -e "${CLAUDE_SKILLS_DIR}/${name}/SKILL.md" ] && [ ! -e "${OPENCODE_SKILLS_DIR}/${name}/SKILL.md" ]; then
            local install_ok=false
            if [ "$source" = "openclaw/agent-skills" ] || [ "$source_url" = "https://github.com/openclaw/agent-skills.git" ]; then
                log_info "Installing skill: $name (from $source)"
                npx -y "$SKILLS_CLI_PACKAGE" add -g "$source" --skill "$name" --dangerously-accept-openclaw-risks -y </dev/null >/dev/null 2>&1 && install_ok=true
            else
                log_info "Installing skill: $name (from $source)"
                npx -y "$SKILLS_CLI_PACKAGE" add -g "$source" --skill "$name" -y </dev/null >/dev/null 2>&1 && install_ok=true
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
        fi

        if [ -n "$source_dir" ]; then
            if [ ! -e "${AGENT_SKILLS_DIR}/${name}" ] && [ ! -L "${AGENT_SKILLS_DIR}/${name}" ]; then
                ln -s "$source_dir" "${AGENT_SKILLS_DIR}/${name}"
                log_info "Linked agent skill: $name -> $source_dir"
            fi
            if [ ! -e "${CLAUDE_SKILLS_DIR}/${name}" ] && [ ! -L "${CLAUDE_SKILLS_DIR}/${name}" ]; then
                ln -s "$source_dir" "${CLAUDE_SKILLS_DIR}/${name}"
                log_info "Linked Claude skill: $name -> $source_dir"
            fi
            if [ ! -e "${OPENCODE_SKILLS_DIR}/${name}" ] && [ ! -L "${OPENCODE_SKILLS_DIR}/${name}" ]; then
                ln -s "$source_dir" "${OPENCODE_SKILLS_DIR}/${name}"
                log_info "Linked OpenCode skill: $name -> $source_dir"
            fi
        fi

        if [ ! -e "${AGENT_SKILLS_DIR}/${name}/SKILL.md" ] || [ ! -e "${CLAUDE_SKILLS_DIR}/${name}/SKILL.md" ] || [ ! -e "${OPENCODE_SKILLS_DIR}/${name}/SKILL.md" ]; then
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

    if [ ! -f "$installed_json" ]; then
        log_info "No installed_plugins.json found, nothing to export"
        return 0
    fi

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
        echo "Run: ./sync-agents.sh claude-export" >&2
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
    log_info "Updating global skills shared by Codex, OpenCode, and Claude..."
    npx -y "$SKILLS_CLI_PACKAGE" update -g "$@"
}

cmd_plugins_check() {
    local failed=false
    cmd_codex_plugins_check || failed=true
    cmd_claude_plugins_prune --check || failed=true
    [ "$failed" = false ]
}

cmd_plugins_export() {
    cmd_codex_plugins_export
    cmd_claude_plugins_export
}

cmd_plugins_update() {
    local failed=false
    cmd_codex_plugins_update || failed=true
    cmd_claude_plugins_update || failed=true
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

    local plugins_json="${HOME}/.claude/plugins/installed_plugins.json"
    if [ -L "$plugins_json" ] && [ ! -e "$plugins_json" ]; then
        log_info "Removing broken symlink: $plugins_json"
        rm "$plugins_json"
    fi

    if command -v claude >/dev/null 2>&1; then
        local known_mp_file="${HOME}/.claude/plugins/known_marketplaces.json"
        local known_mp_keys=""
        [ -f "$known_mp_file" ] && known_mp_keys=$(jq -r 'keys[]' "$known_mp_file")

        local mp_names
        mp_names=$(jq -r '.marketplaces | keys[]' "$CLAUDE_MANIFEST")
        for mp_name in $mp_names; do
            echo "$known_mp_keys" | grep -qxF "$mp_name" && continue
            local mp_source mp_arg
            mp_source=$(jq -r ".marketplaces[\"$mp_name\"].source" "$CLAUDE_MANIFEST")
            if [ "$mp_source" = "github" ]; then
                mp_arg=$(jq -r ".marketplaces[\"$mp_name\"].repo" "$CLAUDE_MANIFEST")
            elif [ "$mp_source" = "git" ]; then
                mp_arg=$(jq -r ".marketplaces[\"$mp_name\"].url" "$CLAUDE_MANIFEST")
            else
                echo "[WARN] Unknown marketplace source '$mp_source' for $mp_name"
                continue
            fi
            log_info "Adding marketplace: $mp_name ($mp_arg)"
            CLAUDECODE='' claude plugin marketplace add "$mp_arg" 2>&1 || echo "[WARN] Failed to add marketplace: $mp_name"
        done

        local installed_keys=""
        [ -f "$plugins_json" ] && installed_keys=$(jq -r '.plugins | keys[]' "$plugins_json")

        local plugins
        plugins=$(jq -r '.plugins[].claude // empty' "$CLAUDE_MANIFEST")
        for plugin in $plugins; do
            echo "$installed_keys" | grep -qxF "$plugin" && continue
            log_info "Installing plugin: $plugin"
            CLAUDECODE='' claude plugin install "$plugin" 2>&1 || echo "[WARN] Failed to install plugin: $plugin"
        done
    else
        echo "[WARN] claude CLI not found, skipping plugin installation"
    fi

    cmd_lock_skills_install

    log_info "Claude sync complete"
}

cmd_install() {
    cmd_custom_skills_install
    cmd_plugins_check
    cmd_codex_install
    cmd_opencode_install
    cmd_kimi_install
    cmd_claude_install

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
        echo "Usage: $0 [--quiet] {install|plugins-check|plugins-export|plugins-update|codex-install|codex-check|codex-plugins-check|codex-plugins-export|opencode-install|opencode-check|kimi-install|kimi-check|claude-install|skills-update|claude-export [--check]|claude-prune [--check]|custom-skills-export [--check|--dry-run] [skill...]|skills-export|claude-settings-check}"
        echo
        echo "  install          Sync shared agent config into Codex, OpenCode, Kimi, and Claude"
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
        echo "  claude-install   Link AGENTS.md, generate Claude settings, install plugins and skills"
        echo "  skills-update    Update global skills shared by Codex, OpenCode, and Claude"
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

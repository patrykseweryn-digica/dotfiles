#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS_FILE="${DOTFILES_DIR}/.agents/AGENTS.md"
MCP_SERVERS="${MCP_SERVERS:-${DOTFILES_DIR}/.agents/mcp-servers.json}"
SHARED_SKILLS_CUSTOM_DIR="${DOTFILES_DIR}/.agents/skills-custom"
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
CLAUDE_MANIFEST="${CLAUDE_MANIFEST:-${DOTFILES_DIR}/config/claude/claude-manifest.json}"
CLAUDE_TEMPLATE_FILE="${CLAUDE_TEMPLATE_FILE:-${DOTFILES_DIR}/config/claude/settings.json}"
CLAUDE_SETTINGS_FILE="${CLAUDE_SETTINGS_FILE:-${HOME}/.claude/settings.json}"
SKILL_LOCK_REPO="${SKILL_LOCK_REPO:-${DOTFILES_DIR}/.agents/skill-lock.json}"
SKILL_LOCK_LIVE="${SKILL_LOCK_LIVE:-${HOME}/.agents/.skill-lock.json}"

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
    [ -f "$CLAUDE_MANIFEST" ] || { echo "[ERROR] Manifest not found: $CLAUDE_MANIFEST" >&2; return 1; }

    mkdir -p "$(dirname "$CLAUDE_SETTINGS_FILE")"
    local tmp="${CLAUDE_SETTINGS_FILE}.tmp"

    jq -S --slurpfile m "$CLAUDE_MANIFEST" --slurpfile mcp "$MCP_SERVERS" '
        .enabledPlugins = ($m[0].plugins | map({(.): true}) | add // {}) |
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
    entries=$(jq -r '.skills | to_entries[] | "\(.key)\t\(.value.source)"' "$SKILL_LOCK_LIVE")
    [ -n "$entries" ] || { log_info "No skills in lock"; return 0; }

    local name source
    while IFS=$'\t' read -r name source; do
        [ -n "$name" ] || continue
        if [ -e "${AGENT_SKILLS_DIR}/${name}/SKILL.md" ] && [ -e "${CLAUDE_SKILLS_DIR}/${name}/SKILL.md" ] && [ -e "${OPENCODE_SKILLS_DIR}/${name}/SKILL.md" ]; then
            continue
        fi

        if [ ! -e "${AGENT_SKILLS_DIR}/${name}/SKILL.md" ] && [ ! -e "${CLAUDE_SKILLS_DIR}/${name}/SKILL.md" ] && [ ! -e "${OPENCODE_SKILLS_DIR}/${name}/SKILL.md" ]; then
            log_info "Installing skill: $name (from $source)"
            if ! npx -y skills add -g "$source" --skill "$name" -y </dev/null >/dev/null 2>&1; then
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

    [ -f "$CLAUDE_MANIFEST" ] || { echo "[ERROR] Manifest not found: $CLAUDE_MANIFEST" >&2; return 1; }

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
        . as $m |
        (($inst[0].plugins // {}) | keys) as $installed |
        (($m.plugins // []) + ($installed - ($m.plugins // [])) | unique) as $new_plugins |
        ($new_plugins | map(split("@")[1] // empty) | unique) as $used_mps |
        ($used_mps - (($m.marketplaces // {}) | keys)) as $missing_mps |
        ($missing_mps | map(
            . as $name
            | {($name): (($km[0] // {})[$name].source // null)}
        ) | map(select(.[] != null)) | add // {}) as $new_mps |
        .plugins = $new_plugins |
        .marketplaces = (($m.marketplaces // {}) + $new_mps)
    ' "$CLAUDE_MANIFEST" > "$tmp" || { rm -f "$tmp"; echo "[ERROR] export failed" >&2; return 1; }

    if cmp -s "$tmp" "$CLAUDE_MANIFEST"; then
        rm -f "$tmp"
        log_info "Manifest already in sync with installed plugins"
        return 0
    fi

    if [ "$check_only" = true ]; then
        echo "[ERROR] Manifest drift detected. Installed plugins/marketplaces missing from manifest:" >&2
        diff <(jq -S '{plugins, marketplaces}' "$CLAUDE_MANIFEST") \
             <(jq -S '{plugins, marketplaces}' "$tmp") >&2 || true
        echo "" >&2
        echo "Run: ./sync-agents.sh claude-export" >&2
        rm -f "$tmp"
        return 1
    fi

    mv "$tmp" "$CLAUDE_MANIFEST"
    log_info "Updated manifest with installed plugins/marketplaces"
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

cmd_claude_update() {
    log_info "Updating skills via npx skills update -g..."
    npx -y skills update -g "$@"
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
        plugins=$(jq -r '.plugins[]' "$CLAUDE_MANIFEST")
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
    cmd_codex_install
    cmd_opencode_install
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
    opencode-install)
        cmd_opencode_install
        ;;
    opencode-check)
        cmd_opencode_check
        ;;
    claude-install)
        cmd_claude_install
        ;;
    claude-update)
        shift
        cmd_claude_update "$@"
        ;;
    claude-export)
        shift
        cmd_claude_plugins_export "$@"
        ;;
    skills-export)
        cmd_lock_skills_export
        ;;
    claude-settings-check)
        cmd_claude_settings_check
        ;;
    *)
        echo "Usage: $0 [--quiet] {install|codex-install|codex-check|opencode-install|opencode-check|claude-install|claude-update|claude-export [--check]|skills-export|claude-settings-check}"
        echo
        echo "  install          Sync shared agent config into Codex, OpenCode, and Claude"
        echo "  codex-install    Link AGENTS.md and generate Codex MCP config"
        echo "  codex-check      Exit 1 if Codex MCP config is out of sync"
        echo "  opencode-install Link AGENTS.md, skills, and generate OpenCode MCP config"
        echo "  opencode-check   Exit 1 if OpenCode config is out of sync"
        echo "  claude-install   Link AGENTS.md, generate Claude settings, install plugins and skills"
        echo "  claude-update    Alias for: npx skills update -g (forwards extra args)"
        echo "  claude-export    Sync installed Claude plugins/marketplaces into manifest"
        echo "  skills-export    Strip live skill-lock into repo after skills add/update"
        echo "  claude-settings-check"
        echo "                  Exit 1 if ~/.claude/settings.json has keys outside the template"
        exit 1
        ;;
esac

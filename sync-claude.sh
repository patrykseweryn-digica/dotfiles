#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="${DOTFILES_DIR}/config/claude/claude-manifest.json"
CACHE_DIR="${HOME}/.cache/claude-skill-repos"
RESOLVED_DIR="${CACHE_DIR}/resolved"
SKILLS_DIR="${HOME}/.claude/skills"
CUSTOM_DIR="${DOTFILES_DIR}/config/claude/skills-custom"
SETTINGS_FILE="${DOTFILES_DIR}/config/claude/settings.json"
STANDARD_MARKETPLACES="claude-plugins-official anthropic-agent-skills"

QUIET=false

if ! command -v jq >/dev/null 2>&1; then
    echo "[ERROR] jq is required but not installed" >&2
    exit 1
fi

if [ ! -f "$MANIFEST" ]; then
    echo "[ERROR] Manifest not found: $MANIFEST" >&2
    exit 1
fi

log_info() {
    [ "$QUIET" = true ] && return
    echo "[INFO] $*"
}

generate_settings() {
    if [ ! -f "$SETTINGS_FILE" ]; then
        echo "[WARN] Settings file not found: $SETTINGS_FILE"
        return
    fi

    local plugins_file="${HOME}/.claude/plugins/installed_plugins.json"
    local installed_json="[]"
    if [ -f "$plugins_file" ]; then
        installed_json=$(jq '[.plugins | keys[]]' "$plugins_file")
    fi

    local tmp="${SETTINGS_FILE}.tmp"

    # Respect user's enabled/disabled state:
    #   - Plugin in current enabledPlugins → keep current value
    #   - Not in enabledPlugins but installed → user disabled it via UI → keep disabled
    #   - Not in enabledPlugins and not installed → new plugin → enable
    jq --slurpfile m "$MANIFEST" --argjson installed "$installed_json" '
        (.enabledPlugins // {}) as $current |
        ($m[0].plugins | map(
            . as $p |
            if ($current | has($p)) then {($p): $current[$p]}
            elif ($installed | index($p)) then {($p): false}
            else {($p): true}
            end
        ) | add // {}) as $ep |
        ($m[0].marketplaces // {} | to_entries | map({(.key): {"source": .value}}) | add // {}) as $mk |
        .enabledPlugins = $ep |
        if ($mk | length) > 0 then .extraKnownMarketplaces = $mk else del(.extraKnownMarketplaces) end
    ' "$SETTINGS_FILE" > "$tmp" || { rm -f "$tmp"; echo "[ERROR] Failed to generate settings" >&2; return 1; }

    if cmp -s "$tmp" "$SETTINGS_FILE"; then
        rm -f "$tmp"
    else
        mv "$tmp" "$SETTINGS_FILE"
        log_info "Updated settings.json (enabledPlugins + extraKnownMarketplaces)"
    fi
}

sync_repos() {
    local repos
    repos=$(jq -r '.skills[] | .repo' "$MANIFEST" | sort -u)

    for repo in $repos; do
        local repo_dir="${CACHE_DIR}/${repo//\//_}"
        if [ -d "$repo_dir" ]; then
            log_info "Updating repo $repo..."
            git -C "$repo_dir" pull --ff-only --quiet 2>/dev/null || true
        else
            log_info "Cloning $repo..."
            git clone --depth 1 --quiet "https://github.com/${repo}.git" "$repo_dir"
        fi
    done
}

resolve_skills() {
    local skill_names
    skill_names=$(jq -r '.skills | keys[]' "$MANIFEST")

    for name in $skill_names; do
        local repo path repo_dir src dest
        repo=$(jq -r ".skills[\"$name\"].repo" "$MANIFEST")
        path=$(jq -r ".skills[\"$name\"].path" "$MANIFEST")
        repo_dir="${CACHE_DIR}/${repo//\//_}"
        src="${repo_dir}/${path}"
        dest="${RESOLVED_DIR}/${name}"

        if [ ! -d "$src" ]; then
            echo "[WARN] Skill source not found: $src"
            continue
        fi

        rsync -a --delete "$src/" "$dest/"
        log_info "Resolved skill: $name"
    done
}

install_mcp_servers() {
    if ! command -v claude >/dev/null 2>&1; then
        echo "[WARN] claude CLI not found, skipping MCP server installation"
        return
    fi

    local servers
    servers=$(jq -r '.mcpServers // {} | keys[]' "$MANIFEST")
    [ -n "$servers" ] || return 0

    # Load env vars from dotfiles .env for MCP server env
    local env_file="${DOTFILES_DIR}/.env"
    if [ -f "$env_file" ]; then
        set -a
        # shellcheck disable=SC1090
        . "$env_file"
        set +a
    fi

    for name in $servers; do
        if claude mcp get "$name" >/dev/null 2>&1; then
            log_info "MCP server already configured: $name"
            continue
        fi

        local type
        type=$(jq -r ".mcpServers[\"$name\"].type" "$MANIFEST")

        if [ "$type" = "http" ]; then
            local url
            url=$(jq -r ".mcpServers[\"$name\"].url" "$MANIFEST")
            log_info "Adding MCP server (http): $name"
            CLAUDECODE='' claude mcp add -s user -t http "$name" "$url" 2>&1 || echo "[WARN] Failed to add MCP server: $name"

        elif [ "$type" = "stdio" ]; then
            local cmd
            cmd=$(jq -r ".mcpServers[\"$name\"].command" "$MANIFEST")

            local -a add_args=("$name")

            # Add env flags from manifest env keys (values from environment)
            while IFS= read -r key; do
                [ -n "$key" ] || continue
                local val="${!key:-}"
                if [ -n "$val" ]; then
                    add_args+=(-e "${key}=${val}")
                else
                    echo "[WARN] MCP server '$name': env var $key not set"
                fi
            done < <(jq -r ".mcpServers[\"$name\"].env // [] | .[]" "$MANIFEST")

            add_args+=(-- "$cmd")

            while IFS= read -r arg; do
                [ -n "$arg" ] || continue
                add_args+=("$arg")
            done < <(jq -r ".mcpServers[\"$name\"].args // [] | .[]" "$MANIFEST")

            log_info "Adding MCP server (stdio): $name"
            CLAUDECODE='' claude mcp add -s user "${add_args[@]}" 2>&1 || echo "[WARN] Failed to add MCP server: $name"
        else
            echo "[WARN] MCP server '$name': unknown type '$type'"
        fi
    done
}

import_mcp_servers() {
    if ! command -v claude >/dev/null 2>&1; then
        log_info "claude CLI not found, skipping MCP server import"
        return
    fi

    # Get user-scope MCP server names (exclude plugin: and claude.ai prefixed)
    local server_names
    server_names=$(claude mcp list 2>&1 | grep -v "^Checking\|^$\|^plugin:\|^claude\.ai" | sed 's/:.*//')
    [ -n "$server_names" ] || return 0

    local manifest_servers
    manifest_servers=$(jq -r '.mcpServers // {} | keys[]' "$MANIFEST")

    local tmp="${MANIFEST}.tmp"
    local changed=false

    for name in $server_names; do
        echo "$manifest_servers" | grep -qx "$name" && continue

        local get_output
        get_output=$(claude mcp get "$name" 2>&1) || continue

        # Only import user-scope servers
        echo "$get_output" | grep -q "User config" || continue

        local type
        type=$(echo "$get_output" | grep "^  Type:" | sed 's/.*Type: //' | xargs)

        if [ "$type" = "http" ]; then
            local url
            url=$(echo "$get_output" | grep "^  URL:" | sed 's/.*URL: //' | xargs)

            jq --arg name "$name" --arg url "$url" \
                '.mcpServers[$name] = {"type": "http", "url": $url}' "$MANIFEST" > "$tmp"
            mv "$tmp" "$MANIFEST"
            echo "[INFO] Added MCP server to manifest: $name (http)"
            changed=true

        elif [ "$type" = "stdio" ]; then
            local cmd args_line
            cmd=$(echo "$get_output" | grep "^  Command:" | sed 's/.*Command: //' | xargs)
            args_line=$(echo "$get_output" | grep "^  Args:" | sed 's/.*Args: //')

            local args_json
            args_json=$(python3 -c "import sys, json; line = sys.stdin.read().strip(); print(json.dumps(line.split()) if line else '[]')" <<< "$args_line" 2>/dev/null || echo "[]")

            jq --arg name "$name" --arg cmd "$cmd" --argjson args "$args_json" \
                '.mcpServers[$name] = {"type": "stdio", "command": $cmd, "args": $args}' "$MANIFEST" > "$tmp"
            mv "$tmp" "$MANIFEST"
            echo "[INFO] Added MCP server to manifest: $name (stdio: $cmd)"
            changed=true
        fi
    done

    if [ "$changed" = true ]; then
        echo "[INFO] MCP servers imported into manifest."
    fi
}

fix_mcp_deps() {
    local plugin_cache="${HOME}/.claude/plugins/cache"
    local bin_dir="${HOME}/.local/bin"
    [ -d "$plugin_cache" ] || return 0

    log_info "Checking MCP server dependencies..."
    mkdir -p "$bin_dir"

    local mcp_file
    while IFS= read -r mcp_file; do
        [ -n "$mcp_file" ] || continue

        local plugin_dir
        if [[ "$mcp_file" == */.claude-plugin/* ]]; then
            plugin_dir="$(dirname "$(dirname "$mcp_file")")"
        else
            plugin_dir="$(dirname "$mcp_file")"
        fi

        local entry
        while IFS= read -r entry; do
            [ -n "$entry" ] || continue

            local name cmd args_first
            name=$(echo "$entry" | base64 -d | jq -r '.key')
            cmd=$(echo "$entry" | base64 -d | jq -r '.value.command // empty')
            args_first=$(echo "$entry" | base64 -d | jq -r '.value.args[0] // ""')

            # Skip HTTP-based or command-less MCP servers
            [ -n "$cmd" ] || continue

            if [ "$cmd" = "node" ] && [[ "$args_first" == ./* ]]; then
                # Node-based server with relative path — install deps if missing
                local server_dir
                server_dir="$(dirname "${plugin_dir}/${args_first}")"
                local pkg_dir="$server_dir"
                while [ "$pkg_dir" != "/" ] && [ ! -f "$pkg_dir/package.json" ]; do
                    pkg_dir="$(dirname "$pkg_dir")"
                done

                if [ -f "$pkg_dir/package.json" ] && [ ! -d "$pkg_dir/node_modules" ]; then
                    log_info "Installing npm deps for MCP server '$name'..."
                    (cd "$pkg_dir" && npm install --no-audit --no-fund) || echo "[WARN] npm install failed for MCP server '$name'"
                fi
            elif ! command -v "$cmd" >/dev/null 2>&1; then
                # Binary not on PATH — check if plugin provides it via package.json bin
                if [ -f "$plugin_dir/package.json" ]; then
                    local bin_path
                    bin_path=$(jq -r ".bin.\"$cmd\" // empty" "$plugin_dir/package.json")
                    if [ -n "$bin_path" ]; then
                        [ -d "$plugin_dir/node_modules" ] || {
                            log_info "Installing npm deps for MCP server '$name'..."
                            (cd "$plugin_dir" && npm install --no-audit --no-fund) || {
                                echo "[WARN] npm install failed for MCP server '$name'"
                                continue
                            }
                        }
                        local target="${plugin_dir}/${bin_path}"
                        if [ ! -f "$target" ] && jq -e '.scripts.build' "$plugin_dir/package.json" >/dev/null 2>&1; then
                            log_info "Building MCP server '$name'..."
                            (cd "$plugin_dir" && npm run build) || echo "[WARN] build failed for MCP server '$name'"
                        fi
                        if [ -f "$target" ]; then
                            chmod +x "$target"
                            ln -sf "$target" "${bin_dir}/${cmd}"
                            log_info "Linked MCP binary: ${bin_dir}/${cmd} -> $target"
                        else
                            echo "[WARN] MCP server '$name': binary '$target' not found after install"
                        fi
                        continue
                    fi
                fi
                echo "[WARN] MCP server '$name' requires '$cmd' which is not on PATH"
            fi
        done < <(jq -r '([.mcpServers // {}] + [.plugins[]?.mcpServers // {}]) | add // {} | to_entries[] | @base64' "$mcp_file" 2>/dev/null)
    done < <(find "$plugin_cache" \( -name '.mcp.json' -o \( -name 'marketplace.json' -path '*/.claude-plugin/*' \) \) 2>/dev/null)
}

prune_orphan_marketplaces() {
    local tmp="${MANIFEST}.tmp"
    local pruned=false

    # Collect marketplace names referenced by plugins (part after @)
    local used_mp
    used_mp=$(jq -r '.plugins[] | split("@")[1]' "$MANIFEST" | sort -u)

    # Add standard marketplaces that should never be pruned
    for std in $STANDARD_MARKETPLACES; do
        used_mp=$(printf '%s\n%s' "$used_mp" "$std")
    done
    used_mp=$(echo "$used_mp" | sort -u)

    # Prune from manifest
    local all_mp
    all_mp=$(jq -r '.marketplaces // {} | keys[]' "$MANIFEST")

    for mp in $all_mp; do
        if ! echo "$used_mp" | grep -qxF "$mp"; then
            jq --arg mp "$mp" 'del(.marketplaces[$mp])' "$MANIFEST" > "$tmp"
            mv "$tmp" "$MANIFEST"
            echo "[INFO] Pruned orphan marketplace: $mp"
            pruned=true
        fi
    done

    # Prune from Claude Code's internal registry
    local known_mp_file="${HOME}/.claude/plugins/known_marketplaces.json"
    if [ -f "$known_mp_file" ]; then
        local all_known
        all_known=$(jq -r 'keys[]' "$known_mp_file")
        for mp in $all_known; do
            if ! echo "$used_mp" | grep -qxF "$mp"; then
                jq --arg mp "$mp" 'del(.[$mp])' "$known_mp_file" > "${known_mp_file}.tmp"
                mv "${known_mp_file}.tmp" "$known_mp_file"
                echo "[INFO] Pruned from known_marketplaces.json: $mp"
                pruned=true
            fi
        done
    fi

    [ "$pruned" = true ]
}

cmd_install() {
    log_info "Installing skills and plugins from manifest..."
    mkdir -p "$CACHE_DIR" "$RESOLVED_DIR" "$SKILLS_DIR"

    sync_repos
    resolve_skills

    # Create symlinks for marketplace skills
    local skill_names
    skill_names=$(jq -r '.skills | keys[]' "$MANIFEST")

    for name in $skill_names; do
        local dest="${RESOLVED_DIR}/${name}"
        local link="${SKILLS_DIR}/${name}"

        [ -d "$dest" ] || continue

        if [ -L "$link" ]; then
            local target
            target=$(readlink "$link")
            if [[ "$target" == *"$DOTFILES_DIR"* ]]; then
                log_info "Skipping $name (custom skill from dotfiles)"
                continue
            fi
            rm "$link"
        elif [ -e "$link" ]; then
            echo "[WARN] $link exists and is not a symlink, skipping"
            continue
        fi

        ln -s "$dest" "$link"
        log_info "Linked skill: $name"
    done

    # Remove broken symlink that prevents plugin installation
    local plugins_json="${HOME}/.claude/plugins/installed_plugins.json"
    if [ -L "$plugins_json" ] && [ ! -e "$plugins_json" ]; then
        log_info "Removing broken symlink: $plugins_json"
        rm "$plugins_json"
    fi

    # Write extraKnownMarketplaces before installing plugins so claude CLI
    # can resolve custom marketplace sources on first run
    generate_settings

    # Install plugins
    if ! command -v claude >/dev/null 2>&1; then
        echo "[WARN] claude CLI not found, skipping plugin installation"
        return
    fi

    # Register missing marketplaces via CLI (settings.json alone is not enough)
    local known_mp_file="${HOME}/.claude/plugins/known_marketplaces.json"
    local known_mp_keys=""
    if [ -f "$known_mp_file" ]; then
        known_mp_keys=$(jq -r 'keys[]' "$known_mp_file")
    fi

    local mp_names
    mp_names=$(jq -r '.marketplaces | keys[]' "$MANIFEST")
    for mp_name in $mp_names; do
        if echo "$known_mp_keys" | grep -qxF "$mp_name"; then
            continue
        fi
        local mp_source mp_arg
        mp_source=$(jq -r ".marketplaces[\"$mp_name\"].source" "$MANIFEST")
        if [ "$mp_source" = "github" ]; then
            mp_arg=$(jq -r ".marketplaces[\"$mp_name\"].repo" "$MANIFEST")
        elif [ "$mp_source" = "git" ]; then
            mp_arg=$(jq -r ".marketplaces[\"$mp_name\"].url" "$MANIFEST")
        else
            echo "[WARN] Unknown marketplace source type '$mp_source' for $mp_name"
            continue
        fi
        log_info "Adding marketplace: $mp_name ($mp_arg)"
        CLAUDECODE='' claude plugin marketplace add "$mp_arg" 2>&1 || echo "[WARN] Failed to add marketplace: $mp_name"
    done

    local plugins
    plugins=$(jq -r '.plugins[]' "$MANIFEST")

    local installed_plugins_file="${HOME}/.claude/plugins/installed_plugins.json"
    local installed_keys=""
    if [ -f "$installed_plugins_file" ]; then
        installed_keys=$(jq -r '.plugins | keys[]' "$installed_plugins_file")
    fi

    for plugin in $plugins; do
        if echo "$installed_keys" | grep -qxF "$plugin"; then
            log_info "Plugin already installed: $plugin"
            continue
        fi
        log_info "Installing plugin: $plugin"
        CLAUDECODE='' claude plugin install "$plugin" 2>&1 || echo "[WARN] Failed to install plugin: $plugin"
    done

    install_mcp_servers
    fix_mcp_deps
    generate_settings
    log_info "Sync install complete"
}

cmd_import() {
    log_info "Importing new skills and plugins into manifest..."

    local lock_file="${HOME}/.agents/.skill-lock.json"
    local plugins_file="${HOME}/.claude/plugins/installed_plugins.json"
    local marketplaces_file="${HOME}/.claude/plugins/known_marketplaces.json"
    local tmp="${MANIFEST}.tmp"
    local changed=false

    # Import skills from skill-lock.json
    if [ -f "$lock_file" ]; then
        local manifest_skill_keys
        manifest_skill_keys=$(jq -r '.skills | keys[]' "$MANIFEST")
        local lock_skills
        lock_skills=$(jq -r '.skills | keys[]' "$lock_file")

        for name in $lock_skills; do
            echo "$manifest_skill_keys" | grep -qx "$name" && continue

            local source skill_path path
            source=$(jq -r ".skills[\"$name\"].source" "$lock_file")
            skill_path=$(jq -r ".skills[\"$name\"].skillPath" "$lock_file")
            path=$(dirname "$skill_path")

            jq --arg name "$name" --arg repo "$source" --arg path "$path" \
                '.skills[$name] = {"repo": $repo, "path": $path}' "$MANIFEST" > "$tmp"
            mv "$tmp" "$MANIFEST"
            echo "[INFO] Added skill: $name (from $source)"
            changed=true
        done
    else
        log_info "No skill-lock.json found, skipping skill import"
    fi

    # Import plugins — batch check with single jq call
    if [ -f "$plugins_file" ]; then
        local new_plugins
        new_plugins=$(jq -r --slurpfile m "$MANIFEST" \
            '[.plugins | keys[]] - $m[0].plugins | .[]' "$plugins_file") || true

        for plugin in $new_plugins; do
            jq --arg p "$plugin" '.plugins += [$p]' "$MANIFEST" > "$tmp"
            mv "$tmp" "$MANIFEST"
            echo "[INFO] Added plugin: $plugin"
            changed=true
        done
    else
        log_info "No installed_plugins.json found, skipping plugin import"
    fi

    # Import non-standard marketplaces — batch check with single jq call
    if [ -f "$marketplaces_file" ]; then
        local new_marketplaces
        new_marketplaces=$(jq -r --slurpfile m "$MANIFEST" --arg std "$STANDARD_MARKETPLACES" '
            [keys[]] - [$m[0].marketplaces // {} | keys[]] - ($std | split(" ")) | .[]
        ' "$marketplaces_file") || true

        for name in $new_marketplaces; do
            local mp_source
            mp_source=$(jq -c ".\"$name\".source" "$marketplaces_file")

            jq --arg name "$name" --argjson src "$mp_source" \
                '.marketplaces[$name] = $src' "$MANIFEST" > "$tmp"
            mv "$tmp" "$MANIFEST"
            echo "[INFO] Added marketplace: $name"
            changed=true
        done
    else
        log_info "No known_marketplaces.json found, skipping marketplace import"
    fi

    # Import new custom skills (non-symlink dirs not in manifest)
    local manifest_skill_keys
    manifest_skill_keys=$(jq -r '.skills | keys[]' "$MANIFEST")

    for entry in "$SKILLS_DIR"/*/; do
        [ -d "$entry" ] || continue
        local name
        name="$(basename "$entry")"

        [ -L "${entry%/}" ] && continue
        [ -d "$CUSTOM_DIR/$name" ] && continue
        echo "$manifest_skill_keys" | grep -qx "$name" && continue

        cp -r "${entry%/}" "$CUSTOM_DIR/$name"
        rm -rf "${entry%/}"
        ln -s "$CUSTOM_DIR/$name" "${entry%/}"
        echo "[INFO] Imported custom skill: $name"
        changed=true
    done

    # Import new .skill files
    for skill_file in "$SKILLS_DIR"/*.skill; do
        [ -f "$skill_file" ] || continue
        local fname
        fname="$(basename "$skill_file")"

        [ -L "$skill_file" ] && continue
        [ -f "$CUSTOM_DIR/$fname" ] && continue

        cp "$skill_file" "$CUSTOM_DIR/$fname"
        rm "$skill_file"
        ln -s "$CUSTOM_DIR/$fname" "$skill_file"
        echo "[INFO] Imported custom skill file: $fname"
        changed=true
    done

    # Auto-prune: remove plugins from manifest that were uninstalled locally
    if [ -f "$plugins_file" ]; then
        local stale_plugins
        stale_plugins=$(jq -r --slurpfile m "$MANIFEST" \
            '$m[0].plugins - [.plugins | keys[]] | .[]' "$plugins_file") || true

        if [ -n "$stale_plugins" ]; then
            for plugin in $stale_plugins; do
                jq --arg p "$plugin" '.plugins -= [$p]' "$MANIFEST" > "$tmp"
                mv "$tmp" "$MANIFEST"
                echo "[INFO] Pruned from manifest (uninstalled): $plugin"
                changed=true
            done
        fi
    fi

    # Prune orphan marketplaces
    prune_orphan_marketplaces && changed=true || true

    # Import MCP servers (skip in quiet mode — claude mcp list is slow)
    if [ "$QUIET" != true ]; then
        import_mcp_servers
    fi

    # Always reconcile settings.json with manifest (handles stale entries
    # from Claude Code overwriting settings after previous hook runs)
    generate_settings

    if [ "$changed" = true ]; then
        echo "[INFO] Manifest updated. Don't forget to commit and push."
    else
        log_info "No new skills or plugins to import."
    fi
}

cmd_update() {
    log_info "Updating cached skill repos..."
    mkdir -p "$CACHE_DIR"

    sync_repos
    resolve_skills

    log_info "Update complete"
}

cmd_prune() {
    local plugins_file="${HOME}/.claude/plugins/installed_plugins.json"

    if [ ! -f "$plugins_file" ]; then
        echo "[ERROR] installed_plugins.json not found" >&2
        return 1
    fi

    local stale_plugins tmp
    tmp="${MANIFEST}.tmp"
    stale_plugins=$(jq -r --slurpfile m "$MANIFEST" \
        '$m[0].plugins - [.plugins | keys[]] | .[]' "$plugins_file") || true

    local changed=false

    for plugin in $stale_plugins; do
        jq --arg p "$plugin" '.plugins -= [$p]' "$MANIFEST" > "$tmp"
        mv "$tmp" "$MANIFEST"
        echo "[INFO] Removed from manifest: $plugin"
        changed=true
    done

    prune_orphan_marketplaces && changed=true || true

    if [ "$changed" = true ]; then
        generate_settings
        echo "[INFO] Manifest pruned. Don't forget to commit and push."
    else
        log_info "Nothing to prune"
    fi
}

cmd_check() {
    local plugins_file="${HOME}/.claude/plugins/installed_plugins.json"

    if [ ! -f "$plugins_file" ]; then
        echo "[ERROR] installed_plugins.json not found" >&2
        return 1
    fi

    local manifest_plugins installed_plugins
    manifest_plugins=$(jq -r '.plugins[]' "$MANIFEST" | sort)
    installed_plugins=$(jq -r '.plugins | keys[]' "$plugins_file" | sort)

    local only_manifest only_installed
    only_manifest=$(comm -23 <(echo "$manifest_plugins") <(echo "$installed_plugins"))
    only_installed=$(comm -13 <(echo "$manifest_plugins") <(echo "$installed_plugins"))

    if [ -z "$only_manifest" ] && [ -z "$only_installed" ]; then
        log_info "Plugins are in sync"
        return 0
    fi

    if [ -n "$only_manifest" ]; then
        echo "[WARN] In manifest but not installed:"
        echo "$only_manifest" | while read -r p; do echo "  - $p"; done
    fi

    if [ -n "$only_installed" ]; then
        echo "[WARN] Installed but not in manifest:"
        echo "$only_installed" | while read -r p; do echo "  - $p"; done
    fi

    return 1
}

# Parse global flags
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
    import)
        cmd_import
        ;;
    update)
        cmd_update
        ;;
    check)
        cmd_check
        ;;
    prune)
        cmd_prune
        ;;
    *)
        echo "Usage: $0 [--quiet] {install|import|update|check|prune}"
        echo
        echo "  install  Clone repos, resolve skills, install plugins"
        echo "  import   Import new skills/plugins from local state into manifest"
        echo "  update   Pull latest skill repos and re-resolve"
        echo "  check    Compare manifest plugins vs installed plugins"
        echo "  prune    Remove uninstalled plugins from manifest"
        exit 1
        ;;
esac

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

    # Install plugins
    if ! command -v claude >/dev/null 2>&1; then
        echo "[WARN] claude CLI not found, skipping plugin installation"
        return
    fi

    local plugins
    plugins=$(jq -r '.plugins[]' "$MANIFEST")

    for plugin in $plugins; do
        log_info "Installing plugin: $plugin"
        CLAUDECODE='' claude plugin install "$plugin" 2>&1 || echo "[WARN] Failed to install plugin: $plugin"
    done

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

    if [ -z "$stale_plugins" ]; then
        log_info "Nothing to prune"
        return 0
    fi

    for plugin in $stale_plugins; do
        jq --arg p "$plugin" '.plugins -= [$p]' "$MANIFEST" > "$tmp"
        mv "$tmp" "$MANIFEST"
        echo "[INFO] Removed from manifest: $plugin"
    done

    generate_settings
    echo "[INFO] Manifest pruned. Don't forget to commit and push."
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

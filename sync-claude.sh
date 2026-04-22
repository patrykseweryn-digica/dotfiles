#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="${DOTFILES_DIR}/config/claude/claude-manifest.json"
CACHE_DIR="${HOME}/.cache/claude-skill-repos"
RESOLVED_DIR="${CACHE_DIR}/resolved"
SKILLS_DIR="${HOME}/.claude/skills"
TEMPLATE_FILE="${DOTFILES_DIR}/config/claude/settings.json"
SETTINGS_FILE="${HOME}/.claude/settings.json"

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
    [ -f "$TEMPLATE_FILE" ] || { echo "[ERROR] Template not found: $TEMPLATE_FILE" >&2; return 1; }

    mkdir -p "$(dirname "$SETTINGS_FILE")"
    local tmp="${SETTINGS_FILE}.tmp"

    jq -S --slurpfile m "$MANIFEST" '
        .enabledPlugins = ($m[0].plugins | map({(.): true}) | add // {}) |
        .extraKnownMarketplaces = ($m[0].marketplaces // {} | to_entries |
            map({(.key): {"source": .value}}) | add // {}) |
        .mcpServers = ($m[0].mcpServers // {} | to_entries |
            map({(.key): (.value | del(.env))}) | add // {})
    ' "$TEMPLATE_FILE" > "$tmp" || { rm -f "$tmp"; echo "[ERROR] Failed to generate settings" >&2; return 1; }

    if [ -f "$SETTINGS_FILE" ] && cmp -s "$tmp" "$SETTINGS_FILE"; then
        rm -f "$tmp"
    else
        mv "$tmp" "$SETTINGS_FILE"
        log_info "Wrote $SETTINGS_FILE"
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

    # Symlink marketplace skills (skip custom skills from dotfiles)
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

    # Generate deterministic settings.json from manifest
    generate_settings

    # Install plugins (requires claude CLI)
    if command -v claude >/dev/null 2>&1; then
        # Register missing marketplaces
        local known_mp_file="${HOME}/.claude/plugins/known_marketplaces.json"
        local known_mp_keys=""
        [ -f "$known_mp_file" ] && known_mp_keys=$(jq -r 'keys[]' "$known_mp_file")

        local mp_names
        mp_names=$(jq -r '.marketplaces | keys[]' "$MANIFEST")
        for mp_name in $mp_names; do
            echo "$known_mp_keys" | grep -qxF "$mp_name" && continue
            local mp_source mp_arg
            mp_source=$(jq -r ".marketplaces[\"$mp_name\"].source" "$MANIFEST")
            if [ "$mp_source" = "github" ]; then
                mp_arg=$(jq -r ".marketplaces[\"$mp_name\"].repo" "$MANIFEST")
            elif [ "$mp_source" = "git" ]; then
                mp_arg=$(jq -r ".marketplaces[\"$mp_name\"].url" "$MANIFEST")
            else
                echo "[WARN] Unknown marketplace source '$mp_source' for $mp_name"
                continue
            fi
            log_info "Adding marketplace: $mp_name ($mp_arg)"
            CLAUDECODE='' claude plugin marketplace add "$mp_arg" 2>&1 || echo "[WARN] Failed to add marketplace: $mp_name"
        done

        # Install missing plugins
        local installed_keys=""
        [ -f "$plugins_json" ] && installed_keys=$(jq -r '.plugins | keys[]' "$plugins_json")

        local plugins
        plugins=$(jq -r '.plugins[]' "$MANIFEST")
        for plugin in $plugins; do
            echo "$installed_keys" | grep -qxF "$plugin" && continue
            log_info "Installing plugin: $plugin"
            CLAUDECODE='' claude plugin install "$plugin" 2>&1 || echo "[WARN] Failed to install plugin: $plugin"
        done
    else
        echo "[WARN] claude CLI not found, skipping plugin installation"
    fi

    log_info "Sync install complete"
}

cmd_update() {
    log_info "Updating cached skill repos..."
    mkdir -p "$CACHE_DIR"

    sync_repos
    resolve_skills

    log_info "Update complete"
}

cmd_export() {
    local check_only=false
    [ "${1:-}" = "--check" ] && check_only=true

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
    ' "$MANIFEST" > "$tmp" || { rm -f "$tmp"; echo "[ERROR] export failed" >&2; return 1; }

    if cmp -s "$tmp" "$MANIFEST"; then
        rm -f "$tmp"
        log_info "Manifest already in sync with installed plugins"
        return 0
    fi

    if [ "$check_only" = true ]; then
        echo "[ERROR] Manifest drift detected. Installed plugins/marketplaces missing from manifest:" >&2
        diff <(jq -S '{plugins, marketplaces}' "$MANIFEST") \
             <(jq -S '{plugins, marketplaces}' "$tmp") >&2 || true
        echo "" >&2
        echo "Run: ./sync-claude.sh export" >&2
        rm -f "$tmp"
        return 1
    fi

    mv "$tmp" "$MANIFEST"
    log_info "Updated manifest with installed plugins/marketplaces"
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
    update)
        cmd_update
        ;;
    export)
        shift
        cmd_export "$@"
        ;;
    *)
        echo "Usage: $0 [--quiet] {install|update|export [--check]}"
        echo
        echo "  install         Clone repos, resolve skills, install plugins, generate settings"
        echo "  update          Pull latest skill repos and re-resolve"
        echo "  export          Sync installed plugins/marketplaces into manifest"
        echo "  export --check  Exit 1 if manifest is out of sync with installed plugins"
        exit 1
        ;;
esac

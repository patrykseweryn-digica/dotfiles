#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="${DOTFILES_DIR}/config/claude/claude-manifest.json"
SKILL_LOCK_REPO="${DOTFILES_DIR}/config/claude/skill-lock.json"
SKILL_LOCK_LIVE="${HOME}/.agents/.skill-lock.json"
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

cmd_settings_check() {
    [ -f "$TEMPLATE_FILE" ] || { echo "[ERROR] Template not found: $TEMPLATE_FILE" >&2; return 1; }
    if [ ! -f "$SETTINGS_FILE" ]; then
        log_info "No $SETTINGS_FILE yet; skipping drift check"
        return 0
    fi

    local extras
    extras=$(jq -r --slurpfile tpl "$TEMPLATE_FILE" '
        (($tpl[0] | keys) + ["enabledPlugins", "extraKnownMarketplaces", "mcpServers"]) as $allowed |
        (keys - $allowed)[]
    ' "$SETTINGS_FILE") || { echo "[ERROR] Failed to parse $SETTINGS_FILE" >&2; return 1; }

    if [ -n "$extras" ]; then
        echo "[ERROR] $SETTINGS_FILE has keys outside the template:" >&2
        echo "$extras" | sed 's/^/  - /' >&2
        echo "" >&2
        echo "Add them to $TEMPLATE_FILE (then re-run install) or remove from live settings." >&2
        return 1
    fi
    log_info "settings.json keys in sync with template"
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

ensure_live_lock() {
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
        # Merge: repo defines skill set + intent; live contributes state fields (timestamps, hashes).
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

cmd_skills_install() {
    [ -f "$SKILL_LOCK_LIVE" ] || { log_info "No skill-lock found; skipping skill install"; return 0; }

    # Drop stale symlinks pointing at the legacy cache so npx can rebuild them.
    [ -d "$SKILLS_DIR" ] && find "$SKILLS_DIR" -maxdepth 1 -lname '*claude-skill-repos*' -delete 2>/dev/null || true

    local entries
    entries=$(jq -r '.skills | to_entries[] | "\(.key)\t\(.value.source)"' "$SKILL_LOCK_LIVE")
    [ -n "$entries" ] || { log_info "No skills in lock"; return 0; }

    local name source
    while IFS=$'\t' read -r name source; do
        [ -n "$name" ] || continue
        if [ -e "${SKILLS_DIR}/${name}/SKILL.md" ]; then
            continue
        fi
        log_info "Installing skill: $name (from $source)"
        if ! npx -y skills add -g "$source" --skill "$name" -y </dev/null >/dev/null 2>&1; then
            echo "[WARN] Failed to install skill: $name (from $source)" >&2
        fi
    done <<< "$entries"
}

cmd_skills_export() {
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

cmd_install() {
    log_info "Installing Claude Code config..."
    mkdir -p "$SKILLS_DIR"

    ensure_live_lock
    cmd_settings_check
    generate_settings

    # Remove broken symlink that prevents plugin installation
    local plugins_json="${HOME}/.claude/plugins/installed_plugins.json"
    if [ -L "$plugins_json" ] && [ ! -e "$plugins_json" ]; then
        log_info "Removing broken symlink: $plugins_json"
        rm "$plugins_json"
    fi

    # Install marketplaces + plugins (requires claude CLI)
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

    cmd_skills_install

    log_info "Sync install complete"
}

cmd_update() {
    log_info "Updating skills via npx skills update -g..."
    npx -y skills update -g "$@"
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
        shift
        cmd_update "$@"
        ;;
    export)
        shift
        cmd_export "$@"
        ;;
    export-skills)
        cmd_skills_export
        ;;
    settings-check)
        cmd_settings_check
        ;;
    *)
        echo "Usage: $0 [--quiet] {install|update|export [--check]|export-skills|settings-check}"
        echo
        echo "  install         Generate live skill-lock from repo intent, install marketplaces/plugins/skills"
        echo "  update          Alias for: npx skills update -g (forwards extra args)"
        echo "  export          Sync installed plugins/marketplaces into manifest"
        echo "  export --check  Exit 1 if manifest is out of sync with installed plugins"
        echo "  export-skills   Strip live skill-lock into repo (after npx skills add/update)"
        echo "  settings-check  Exit 1 if ~/.claude/settings.json has keys outside the template"
        exit 1
        ;;
esac

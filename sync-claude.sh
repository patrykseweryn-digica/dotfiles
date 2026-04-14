#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="${DOTFILES_DIR}/config/claude/claude-manifest.json"
CACHE_DIR="${HOME}/.cache/claude-skill-repos"
RESOLVED_DIR="${CACHE_DIR}/resolved"
SKILLS_DIR="${HOME}/.claude/skills"
SETTINGS_FILE="${DOTFILES_DIR}/config/claude/settings.json"

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
    [ -f "$SETTINGS_FILE" ] || { echo "[WARN] Settings file not found: $SETTINGS_FILE"; return; }

    local tmp="${SETTINGS_FILE}.tmp"

    jq -S --slurpfile m "$MANIFEST" '
        .enabledPlugins = ($m[0].plugins | map({(.): true}) | add // {}) |
        .extraKnownMarketplaces = ($m[0].marketplaces // {} | to_entries |
            map({(.key): {"source": .value}}) | add // {}) |
        .mcpServers = ($m[0].mcpServers // {} | to_entries |
            map({(.key): (.value | del(.env))}) | add // {})
    ' "$SETTINGS_FILE" > "$tmp" || { rm -f "$tmp"; echo "[ERROR] Failed to generate settings" >&2; return 1; }

    if cmp -s "$tmp" "$SETTINGS_FILE"; then
        rm -f "$tmp"
    else
        mv "$tmp" "$SETTINGS_FILE"
        log_info "Updated settings.json"
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

# Parse global flags
while [[ "${1:-}" == --* ]]; do
    case "$1" in
        --quiet) QUIET=true; shift ;;
        *) echo "[ERROR] Unknown flag: $1" >&2; exit 1 ;;
    esac
done

cmd_capture() {
    log_info "Capturing local MCP server changes into manifest..."

    local live_settings="${HOME}/.claude/settings.json"
    [ -f "$live_settings" ] || { echo "[ERROR] Live settings not found: $live_settings" >&2; return 1; }

    python3 -c "
import json, sys

settings_path = sys.argv[1]
manifest_path = sys.argv[2]

with open(settings_path) as f:
    settings = json.load(f)

with open(manifest_path) as f:
    manifest = json.load(f)

live = settings.get('mcpServers', {})
old = manifest.get('mcpServers', {})

# Normalize manifest format: strip env lists back to dicts for comparison
def normalize(server):
    s = dict(server)
    if isinstance(s.get('env'), list):
        s['env'] = s['env']
    return s

added, updated, removed = [], [], []

for name, server in live.items():
    if name not in old:
        added.append(name)
    else:
        old_norm = normalize(old[name])
        # Compare without env (settings.json has env stripped by generate_settings)
        live_cmp = {k: v for k, v in server.items() if k != 'env'}
        old_cmp = {k: v for k, v in old_norm.items() if k != 'env'}
        if live_cmp != old_cmp:
            updated.append(name)

for name in old:
    if name not in live:
        removed.append(name)

if not added and not updated and not removed:
    print('[INFO] Manifest already up to date')
    sys.exit(0)

# Apply changes
mcp = dict(old)
for name in added:
    mcp[name] = live[name]
    print(f'  + {name}')
for name in updated:
    # Preserve env from manifest (not in settings.json)
    env = old[name].get('env')
    mcp[name] = live[name]
    if env is not None:
        mcp[name]['env'] = env
    print(f'  ~ {name}')
for name in removed:
    del mcp[name]
    print(f'  - {name}')

manifest['mcpServers'] = mcp

with open(manifest_path, 'w') as f:
    json.dump(manifest, f, indent=2)
    f.write('\n')

print(f'[INFO] Manifest updated ({len(added)} added, {len(updated)} updated, {len(removed)} removed)')
" "$live_settings" "$MANIFEST"

    # Regenerate dotfiles settings.json from updated manifest
    generate_settings
}

case "${1:-}" in
    install)
        cmd_install
        ;;
    update)
        cmd_update
        ;;
    capture)
        cmd_capture
        ;;
    *)
        echo "Usage: $0 [--quiet] {install|update|capture}"
        echo
        echo "  install  Clone repos, resolve skills, install plugins, generate settings"
        echo "  update   Pull latest skill repos and re-resolve"
        echo "  capture  Capture local MCP server changes back into manifest"
        exit 1
        ;;
esac

#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="${DOTFILES_DIR}/config/claude/claude-manifest.json"
CACHE_DIR="${HOME}/.cache/claude-skill-repos"
RESOLVED_DIR="${CACHE_DIR}/resolved"
SKILLS_DIR="${HOME}/.claude/skills"

if ! command -v jq >/dev/null 2>&1; then
    echo "[ERROR] jq is required but not installed" >&2
    exit 1
fi

if [ ! -f "$MANIFEST" ]; then
    echo "[ERROR] Manifest not found: $MANIFEST" >&2
    exit 1
fi

cmd_install() {
    echo "[INFO] Installing skills and plugins from manifest..."
    mkdir -p "$CACHE_DIR" "$RESOLVED_DIR" "$SKILLS_DIR"

    # Collect unique repos
    local repos
    repos=$(jq -r '.skills[] | .repo' "$MANIFEST" | sort -u)

    # Clone/update repos
    for repo in $repos; do
        local repo_dir="${CACHE_DIR}/${repo//\//_}"
        if [ -d "$repo_dir" ]; then
            echo "[INFO] Updating repo $repo..."
            git -C "$repo_dir" pull --ff-only --quiet 2>/dev/null || true
        else
            echo "[INFO] Cloning $repo..."
            git clone --depth 1 --quiet "https://github.com/${repo}.git" "$repo_dir"
        fi
    done

    # Resolve and link skills
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

        # rsync skill to resolved dir
        rsync -a --delete "$src/" "$dest/"

        # Create symlink if not already pointing to dotfiles (custom skill)
        local link="${SKILLS_DIR}/${name}"
        if [ -L "$link" ]; then
            local target
            target=$(readlink "$link")
            if [[ "$target" == *"$DOTFILES_DIR"* ]]; then
                echo "[INFO] Skipping $name (custom skill from dotfiles)"
                continue
            fi
            # Remove old symlink (e.g. pointing to ~/.agents/skills/)
            rm "$link"
        elif [ -e "$link" ]; then
            echo "[WARN] $link exists and is not a symlink, skipping"
            continue
        fi

        ln -s "$dest" "$link"
        echo "[INFO] Linked skill: $name"
    done

    # Remove broken symlink that prevents plugin installation
    local plugins_json="${HOME}/.claude/plugins/installed_plugins.json"
    if [ -L "$plugins_json" ] && [ ! -e "$plugins_json" ]; then
        echo "[INFO] Removing broken symlink: $plugins_json"
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
        echo "[INFO] Installing plugin: $plugin"
        CLAUDECODE='' claude plugin install "$plugin" 2>/dev/null || echo "[WARN] Failed to install plugin: $plugin"
    done

    echo "[INFO] Sync install complete"
}

cmd_import() {
    echo "[INFO] Importing new skills and plugins into manifest..."

    local lock_file="${HOME}/.agents/.skill-lock.json"
    local plugins_file="${HOME}/.claude/plugins/installed_plugins.json"
    local tmp="${MANIFEST}.tmp"
    local changed=false

    # Import skills from skill-lock.json
    if [ -f "$lock_file" ]; then
        local lock_skills
        lock_skills=$(jq -r '.skills | keys[]' "$lock_file")

        for name in $lock_skills; do
            if jq -e ".skills[\"$name\"]" "$MANIFEST" >/dev/null 2>&1; then
                continue
            fi

            local source skill_path repo path
            source=$(jq -r ".skills[\"$name\"].source" "$lock_file")
            skill_path=$(jq -r ".skills[\"$name\"].skillPath" "$lock_file")
            # Extract directory from skillPath (e.g. "tdd/SKILL.md" -> "tdd")
            path=$(dirname "$skill_path")

            jq --arg name "$name" --arg repo "$source" --arg path "$path" \
                '.skills[$name] = {"repo": $repo, "path": $path}' "$MANIFEST" > "$tmp"
            mv "$tmp" "$MANIFEST"
            echo "[INFO] Added skill: $name (from $source)"
            changed=true
        done
    else
        echo "[INFO] No skill-lock.json found, skipping skill import"
    fi

    # Import plugins from installed_plugins.json
    if [ -f "$plugins_file" ]; then
        local installed_plugins
        installed_plugins=$(jq -r '.plugins | keys[]' "$plugins_file")

        for plugin in $installed_plugins; do
            if jq -e ".plugins | index(\"$plugin\")" "$MANIFEST" >/dev/null 2>&1; then
                continue
            fi

            jq --arg p "$plugin" '.plugins += [$p]' "$MANIFEST" > "$tmp"
            mv "$tmp" "$MANIFEST"
            echo "[INFO] Added plugin: $plugin"
            changed=true
        done
    else
        echo "[INFO] No installed_plugins.json found, skipping plugin import"
    fi

    if [ "$changed" = true ]; then
        echo "[INFO] Manifest updated. Don't forget to commit and push."
    else
        echo "[INFO] No new skills or plugins to import."
    fi
}

cmd_update() {
    echo "[INFO] Updating cached skill repos..."
    mkdir -p "$CACHE_DIR"

    local repos
    repos=$(jq -r '.skills[] | .repo' "$MANIFEST" | sort -u)

    for repo in $repos; do
        local repo_dir="${CACHE_DIR}/${repo//\//_}"
        if [ -d "$repo_dir" ]; then
            echo "[INFO] Pulling $repo..."
            git -C "$repo_dir" pull --ff-only --quiet
        else
            echo "[INFO] Cloning $repo..."
            git clone --depth 1 --quiet "https://github.com/${repo}.git" "$repo_dir"
        fi
    done

    # Re-resolve skills
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
        echo "[INFO] Updated skill: $name"
    done

    echo "[INFO] Update complete"
}

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
    *)
        echo "Usage: $0 {install|import|update}"
        echo
        echo "  install  Clone repos, resolve skills, install plugins"
        echo "  import   Import new skills/plugins from local state into manifest"
        echo "  update   Pull latest skill repos and re-resolve"
        exit 1
        ;;
esac

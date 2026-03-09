#!/bin/bash

# Enable shell script strictness
set -eu

# Detect if sudo is available
HAS_SUDO=false
if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    HAS_SUDO=true
fi

# Installation directory for user-local installs
INSTALL_DIR="${HOME}/.local"
BIN_DIR="${INSTALL_DIR}/bin"
OPT_DIR="${INSTALL_DIR}/opt"

# Ensure directories exist
mkdir -p "${BIN_DIR}" "${OPT_DIR}"

# Add to PATH if not already there
if [[ ":$PATH:" != *":${BIN_DIR}:"* ]]; then
    export PATH="${BIN_DIR}:${PATH}"
fi

# Source installation modules
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_TEMPLATE="${DOTFILES_DIR}/.env.example"
ENV_FILE="${DOTFILES_DIR}/.env"

ensure_env_file() {
    if [ ! -f "$ENV_TEMPLATE" ]; then
        echo "[ERROR] Missing environment template at $ENV_TEMPLATE" >&2
        exit 1
    fi

    if [ ! -f "$ENV_FILE" ]; then
        cp "$ENV_TEMPLATE" "$ENV_FILE"
        echo "[INFO] Created $ENV_FILE from template"
    fi
}

load_env() {
    ensure_env_file

    if [ ! -f "$ENV_FILE" ]; then
        echo "[ERROR] Environment file $ENV_FILE not found" >&2
        exit 1
    fi

    set -a
    # shellcheck disable=SC1090
    . "$ENV_FILE"
    set +a

    if [ -z "${EMAIL:-}" ]; then
        echo "[ERROR] EMAIL is not set in $ENV_FILE" >&2
        exit 1
    fi

    if [ -z "${WORK_EMAIL:-}" ]; then
        echo "[ERROR] WORK_EMAIL is not set in $ENV_FILE" >&2
        exit 1
    fi

    if [ -z "${EDITOR:-}" ]; then
        EDITOR="vim"
    fi

    export EMAIL
    export WORK_EMAIL
    export EDITOR
    echo "[INFO] Loaded environment from $ENV_FILE"
}

DEBUG=false

usage() {
    echo "Usage: $0 [--sudo] [--debug]"
    echo
    echo "  --sudo, -s     Force enable sudo (skip auto-detection)"
    echo "  --debug        Enable verbose shell tracing"
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
        -s | --sudo)
            HAS_SUDO=true
            ;;
        --debug)
            DEBUG=true
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
        esac
        shift
    done
}

link_file() {
    local source_path="$1"
    local target_path="$2"
    local backup_dir="${HOME}/.dotfiles-backup"

    # Already a correct symlink - nothing to do
    if [ -L "$target_path" ] && [ "$(readlink "$target_path")" = "$source_path" ]; then
        return
    fi

    # Target exists and is not our symlink - backup with drift warning
    if [ -e "$target_path" ] || [ -L "$target_path" ]; then
        mkdir -p "$backup_dir"
        local backup_name
        backup_name="$(basename "$target_path").$(date +%Y%m%d%H%M%S)"
        cp -rP "$target_path" "${backup_dir}/${backup_name}"

        # Drift warning: target differs from source
        if [ -f "$target_path" ] && [ -f "$source_path" ] && ! diff -q "$source_path" "$target_path" >/dev/null 2>&1; then
            echo "[WARN] $target_path differs from dotfiles source. Backed up to ${backup_dir}/${backup_name}"
            echo "[WARN] Diff (source vs target):"
            diff --color=auto "$source_path" "$target_path" | head -20 || true
        else
            echo "[INFO] Backed up $target_path to ${backup_dir}/${backup_name}"
        fi

        rm -rf "$target_path"
    fi

    ln -s "$source_path" "$target_path"
    echo "[INFO] Linked $target_path -> $source_path"
}

ensure_env_file

for module in "${DOTFILES_DIR}/bootstrap.d"/*.sh; do
    if [ -f "$module" ]; then
        # shellcheck source=/dev/null
        source "$module"
    fi
done

# Setup and link configuration files
setup_dotfiles() {
    echo "[INFO] Setting up dotfile configurations..."

    # Ensure config directory exists
    mkdir -p "${HOME}/.config"

    # Link Git config
    link_file "$DOTFILES_DIR/config/git" "${HOME}/.config/git"

    # Link Python startup file
    link_file "$DOTFILES_DIR/pythonrc.py" "${HOME}/.pythonrc.py"

    # Link .zshrc
    link_file "$DOTFILES_DIR/.zshrc" "${HOME}/.zshrc"

    # Link .p10k.zsh
    link_file "$DOTFILES_DIR/.p10k.zsh" "${HOME}/.p10k.zsh"

    # Link .tmux.conf
    link_file "$DOTFILES_DIR/.tmux.conf" "${HOME}/.tmux.conf"

    # Link .vimrc
    link_file "$DOTFILES_DIR/.vimrc" "${HOME}/.vimrc"

    # Link .aliases
    link_file "$DOTFILES_DIR/.aliases" "${HOME}/.aliases"

    # Link VSCode settings
    mkdir -p "${HOME}/.config/Code/User"
    link_file "$DOTFILES_DIR/config/Code/settings.json" "${HOME}/.config/Code/User/settings.json"
    link_file "$DOTFILES_DIR/config/Code/keybindings.json" "${HOME}/.config/Code/User/keybindings.json"

    # Link Neovim config
    link_file "$DOTFILES_DIR/config/nvim" "${HOME}/.config/nvim"

    # Link Ruff config
    link_file "$DOTFILES_DIR/config/ruff" "${HOME}/.config/ruff"

    # Link GitHub CLI config (file only, not dir - to preserve hosts.yml with auth tokens)
    mkdir -p "${HOME}/.config/gh"
    link_file "$DOTFILES_DIR/config/gh/config.yml" "${HOME}/.config/gh/config.yml"

    # Link Claude Code config
    mkdir -p "${HOME}/.claude/plugins" "${HOME}/.claude/output-styles" "${HOME}/.claude/skills"
    link_file "$DOTFILES_DIR/config/claude/CLAUDE.md" "${HOME}/.claude/CLAUDE.md"
    link_file "$DOTFILES_DIR/config/claude/settings.json" "${HOME}/.claude/settings.json"
    link_file "$DOTFILES_DIR/config/claude/statusline-command.sh" "${HOME}/.claude/statusline-command.sh"
    link_file "$DOTFILES_DIR/config/claude/output-styles" "${HOME}/.claude/output-styles"
    link_file "$DOTFILES_DIR/config/claude/agents" "${HOME}/.claude/agents"

    # Link custom skills from dotfiles
    for skill_dir in "$DOTFILES_DIR/config/claude/skills-custom"/*/; do
        [ -d "$skill_dir" ] || continue
        skill_name="$(basename "$skill_dir")"
        link_file "$skill_dir" "${HOME}/.claude/skills/${skill_name}"
    done
    # Link .skill compiled files
    for skill_file in "$DOTFILES_DIR/config/claude/skills-custom"/*.skill; do
        [ -f "$skill_file" ] && link_file "$skill_file" "${HOME}/.claude/skills/$(basename "$skill_file")"
    done

    # Sync marketplace skills and plugins from manifest
    if [ -x "$DOTFILES_DIR/sync-claude.sh" ]; then
        "$DOTFILES_DIR/sync-claude.sh" install
    else
        echo "[WARN] sync-claude.sh not found or not executable, skipping skill/plugin sync"
    fi

    echo "[INFO] Using environment variables defined in $ENV_FILE"

    # Source aliases
    if [ -f "$DOTFILES_DIR/.aliases" ]; then
        source "$DOTFILES_DIR/.aliases"
        echo "[INFO] Loaded aliases"
    else
        echo "[WARN] Aliases file not found"
    fi

    # Setup SSH key
    if [ -f "$DOTFILES_DIR/ssh.sh" ]; then
        echo "[INFO] Setting up SSH key..."
        "$DOTFILES_DIR/ssh.sh" "$EMAIL" "$WORK_EMAIL"
    else
        echo "[WARN] ssh.sh script not found"
    fi
}

# Main installation flow
main() {
    parse_args "$@"

    if [ "$DEBUG" = true ]; then
        set -x
    fi

    load_env

    echo "[INFO] Starting dotfiles installation..."
    echo "[INFO] Sudo available: ${HAS_SUDO}"
    echo "[INFO] Install directory: ${INSTALL_DIR}"
    # Install tools (continue on non-critical failures)
    install_uv || echo "[WARN] uv installation had issues, continuing..."
    install_zsh || { echo "[ERROR] zsh installation failed, aborting"; return 1; }
    install_oh_my_zsh || echo "[WARN] Oh My Zsh installation had issues, continuing..."
    install_pipx || echo "[WARN] pipx installation had issues, continuing..."
    install_tools || echo "[WARN] Some tools failed to install, continuing..."
    install_fonts || echo "[WARN] Font installation had issues, continuing..."
    install_nvm || echo "[WARN] NVM installation had issues, continuing..."
    install_terminal_colors || echo "[WARN] Terminal color setup had issues, continuing..."

    # Setup dotfile configurations
    setup_dotfiles

    # Setup pre-commit hooks
    if check_installed pre-commit; then
        echo "[INFO] Installing pre-commit hooks..."
        pre-commit install -c "${DOTFILES_DIR}/.pre-commit-config.yaml"
    fi

    # Setup git hooks for dotfiles repo
    if [ -f "$DOTFILES_DIR/hooks/post-merge" ]; then
        mkdir -p "$DOTFILES_DIR/.git/hooks"
        link_file "$DOTFILES_DIR/hooks/post-merge" "$DOTFILES_DIR/.git/hooks/post-merge"
    fi

    echo "[INFO] Installation complete!"
    echo "[INFO] Please restart your shell or run: source ~/.zshrc"
}

main "$@"

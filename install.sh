#!/bin/bash

# Enable shell script strictness
set -eu

# Detect if sudo is available
HAS_SUDO=false
if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    HAS_SUDO=true
fi

# Detect OS and architecture
OS="$(uname -s)"     # "Linux" or "Darwin"
ARCH="$(uname -m)"   # "x86_64" or "arm64"
export ARCH
export IS_MACOS=false
export IS_LINUX=false
if [ "$OS" = "Darwin" ]; then
    IS_MACOS=true
elif [ "$OS" = "Linux" ]; then
    IS_LINUX=true
fi

# Installation directory for user-local installs
INSTALL_DIR="${HOME}/.local"
BIN_DIR="${INSTALL_DIR}/bin"
OPT_DIR="${INSTALL_DIR}/opt"

# Source installation modules
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_TEMPLATE="${DOTFILES_DIR}/.env.example"
ENV_FILE="${DOTFILES_ENV_FILE:-${DOTFILES_DIR}/.env}"

ensure_install_dirs() {
    mkdir -p "${BIN_DIR}" "${OPT_DIR}"

    if [[ ":$PATH:" != *":${BIN_DIR}:"* ]]; then
        export PATH="${BIN_DIR}:${PATH}"
    fi
}

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

deploy_symlink_target() {
    local source_path="$1"
    local target_path="$2"

    mkdir -p "$(dirname "$target_path")"
    link_file "$source_path" "$target_path"
}

deploy_plain_absent_target() {
    local target_path="$1"

    if [ -L "$target_path" ]; then
        rm "$target_path"
        echo "[INFO] Removed legacy symlink: $target_path"
    fi
}

deploy_target() {
    local target_type="$1"
    local source_path="$2"
    local target_path="$3"

    case "$target_type" in
        symlink)
            deploy_symlink_target "$source_path" "$target_path"
            ;;
        plain-absent)
            deploy_plain_absent_target "$target_path"
            ;;
        *)
            echo "[ERROR] Unknown managed target type: $target_type" >&2
            return 1
            ;;
    esac
}

deploy_targets() {
    local target_type source_path target_path

    while IFS='|' read -r target_type source_path target_path; do
        [ -n "$target_type" ] || continue
        deploy_target "$target_type" "$source_path" "$target_path"
    done
}

for module in "${DOTFILES_DIR}/bootstrap.d"/*.sh; do
    if [ -f "$module" ]; then
        # shellcheck source=/dev/null
        source "$module"
    fi
done

# Setup and link configuration files
setup_dotfiles() {
    echo "[INFO] Setting up dotfile configurations..."

    ensure_install_dirs
    mkdir -p "${HOME}/.claude/plugins" "${HOME}/.claude/output-styles" "${HOME}/.claude/skills" "${HOME}/.agents/skills" "${HOME}/.codex"
    if [ "$IS_MACOS" = true ]; then
        VSCODE_USER_DIR="${HOME}/Library/Application Support/Code/User"
        GHOSTTY_CONFIG_TARGET="${HOME}/Library/Application Support/com.mitchellh.ghostty/config.ghostty"
    else
        VSCODE_USER_DIR="${HOME}/.config/Code/User"
        GHOSTTY_CONFIG_TARGET="${HOME}/.config/ghostty/config"
    fi

    deploy_targets <<EOF
symlink|$DOTFILES_DIR/config/git|$HOME/.config/git
symlink|$DOTFILES_DIR/pythonrc.py|$HOME/.pythonrc.py
symlink|$DOTFILES_DIR/.zshrc|$HOME/.zshrc
symlink|$DOTFILES_DIR/.p10k.zsh|$HOME/.p10k.zsh
symlink|$DOTFILES_DIR/.tmux.conf|$HOME/.tmux.conf
symlink|$DOTFILES_DIR/.vimrc|$HOME/.vimrc
symlink|$DOTFILES_DIR/.aliases|$HOME/.aliases
symlink|$DOTFILES_DIR/config/Code/settings.json|$VSCODE_USER_DIR/settings.json
symlink|$DOTFILES_DIR/config/Code/keybindings.json|$VSCODE_USER_DIR/keybindings.json
symlink|$DOTFILES_DIR/config/ghostty/config.ghostty|$GHOSTTY_CONFIG_TARGET
symlink|$DOTFILES_DIR/config/nvim|$HOME/.config/nvim
symlink|$DOTFILES_DIR/config/ruff|$HOME/.config/ruff
symlink|$DOTFILES_DIR/config/gh/config.yml|$HOME/.config/gh/config.yml
symlink|$DOTFILES_DIR/config/claude/CLAUDE.md|$HOME/.claude/CLAUDE.md
symlink|$DOTFILES_DIR/config/claude/statusline-command.sh|$HOME/.claude/statusline-command.sh
plain-absent||$HOME/.claude/settings.json
symlink|$DOTFILES_DIR/config/claude/output-styles|$HOME/.claude/output-styles
symlink|$DOTFILES_DIR/config/claude/agents|$HOME/.claude/agents
EOF

    # Link bin scripts
    for script in "$DOTFILES_DIR/bin"/*; do
        [ -f "$script" ] || continue
        chmod +x "$script"
        deploy_symlink_target "$script" "${BIN_DIR}/$(basename "$script")"
    done

    # Sync shared agent config plus tool-specific adapters.
    if [ -f "$DOTFILES_DIR/sync-agents.sh" ]; then
        "$DOTFILES_DIR/sync-agents.sh" install
    else
        echo "[WARN] sync-agents.sh not found, skipping agent config sync"
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
    if [ "${DOTFILES_SKIP_SSH:-false}" = true ]; then
        echo "[INFO] Skipping SSH setup"
    elif [ -f "$DOTFILES_DIR/ssh.sh" ]; then
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

    ensure_install_dirs
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
    if declare -f install_macos_apps >/dev/null 2>&1; then
        install_macos_apps || echo "[WARN] macOS app installation had issues, continuing..."
    fi
    install_claude_code || echo "[WARN] Claude Code installation had issues, continuing..."

    # Setup dotfile configurations
    setup_dotfiles

    # Setup pre-commit hooks
    if pre-commit --version >/dev/null 2>&1; then
        echo "[INFO] Installing pre-commit hooks..."
        pre-commit install -c "${DOTFILES_DIR}/.pre-commit-config.yaml"
    fi

    # Setup git hooks for dotfiles repo
    if [ -f "$DOTFILES_DIR/hooks/post-merge" ]; then
        deploy_symlink_target "$DOTFILES_DIR/hooks/post-merge" "$DOTFILES_DIR/.git/hooks/post-merge"
    fi

    echo "[INFO] Installation complete!"
    echo "[INFO] Please restart your shell or run: source ~/.zshrc"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

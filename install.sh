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

    if [ -z "${EDITOR:-}" ]; then
        EDITOR="vim"
    fi

    export EMAIL
    export EDITOR
    echo "[INFO] Loaded environment from $ENV_FILE"
}

OVERWRITE=false
DEBUG=false

usage() {
    echo "Usage: $0 [--force] [--debug]"
    echo
    echo "  --force, -f    Overwrite existing dotfiles"
    echo "  --debug        Enable verbose shell tracing"
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
        -f | --force)
            OVERWRITE=true
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

    if [ -e "$target_path" ] || [ -L "$target_path" ]; then
        if [ "$OVERWRITE" = true ]; then
            echo "[INFO] Overwriting $target_path"
            rm -rf "$target_path"
        else
            echo "[INFO] Skipping $target_path; already exists (use --force to overwrite)"
            return
        fi
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
        "$DOTFILES_DIR/ssh.sh" "$EMAIL"
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
    if [ "$OVERWRITE" = true ]; then
        echo "[INFO] Existing dotfiles will be overwritten"
    fi

    # Install tools
    install_uv
    install_zsh
    install_oh_my_zsh
    install_pipx
    install_tools

    # Setup dotfile configurations
    setup_dotfiles

    # Setup pre-commit hooks
    if check_installed pre-commit; then
        echo "[INFO] Installing pre-commit hooks..."
        pre-commit install -c "${DOTFILES_DIR}/.pre-commit-config.yaml"
    fi

    echo "[INFO] Installation complete!"
    echo "[INFO] Please restart your shell or run: source ~/.zshrc"
}

main "$@"

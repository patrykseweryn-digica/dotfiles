#!/bin/bash

# Enable shell script strictness
set -eu
# Enable command tracing
set -x

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_installed() {
    if command -v "$1" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# Source installation modules
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for module in "${DOTFILES_DIR}/install.d"/*.sh; do
    if [ -f "$module" ]; then
        source "$module"
    fi
done

# Setup and link configuration files
setup_dotfiles() {
    log_info "Setting up dotfile configurations..."

    # Ensure config directory exists
    mkdir -p ~/.config

    # Link Git config if it doesn't exist
    if [ ! -e ~/.config/git ]; then
        ln -s "$DOTFILES_DIR/config/git" ~/.config/git
        log_info "Linked Git configuration"
    else
        log_info "Git configuration already exists"
    fi

    # Link Python startup file if it doesn't exist
    if [ ! -e ~/.pythonrc.py ]; then
        ln -s "$DOTFILES_DIR/pythonrc.py" ~/.pythonrc.py
        log_info "Linked Python startup file"
    else
        log_info "Python startup file already exists"
    fi

    # Link .zshrc if it doesn't exist
    if [ ! -e ~/.zshrc ]; then
        ln -s "$DOTFILES_DIR/.zshrc" ~/.zshrc
        log_info "Linked .zshrc configuration"
    else
        log_info ".zshrc already exists"
    fi

    # Link .p10k.zsh if it doesn't exist
    if [ ! -e ~/.p10k.zsh ]; then
        ln -s "$DOTFILES_DIR/.p10k.zsh" ~/.p10k.zsh
        log_info "Linked Powerlevel10k configuration"
    else
        log_info ".p10k.zsh already exists"
    fi

    # Load variables from config file
    if [ -f "$DOTFILES_DIR/config.sh" ]; then
        source "$DOTFILES_DIR/config.sh"
        log_info "Loaded configuration from config.sh"
    else
        log_error "config.sh file not found in $DOTFILES_DIR"
        exit 1
    fi

    # Source aliases
    if [ -f "$DOTFILES_DIR/.aliases" ]; then
        source "$DOTFILES_DIR/.aliases"
        log_info "Loaded aliases"
    else
        log_warn "Aliases file not found"
    fi

    # Setup SSH key
    if [ -f "$DOTFILES_DIR/ssh.sh" ]; then
        log_info "Setting up SSH key..."
        "$DOTFILES_DIR/ssh.sh" "$EMAIL"
    else
        log_warn "ssh.sh script not found"
    fi
}

# Main installation flow
main() {
    log_info "Starting dotfiles installation..."
    log_info "Sudo available: ${HAS_SUDO}"
    log_info "Install directory: ${INSTALL_DIR}"

    # Install tools
    install_uv
    install_zsh
    install_oh_my_zsh

    # Setup dotfile configurations
    setup_dotfiles

    log_info "Installation complete!"
    log_info "Please restart your shell or run: source ~/.zshrc"
}

main "$@"

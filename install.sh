#!/bin/bash

# Enable shell script strictness
set -eu

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

# Main installation flow
main() {
    log_info "Starting dotfiles installation..."
    log_info "Sudo available: ${HAS_SUDO}"
    log_info "Install directory: ${INSTALL_DIR}"

    # Install tools
    install_uv
    install_zsh
    install_oh_my_zsh
    install_vim

    log_info "Installation complete!"
    log_info "Make sure ${BIN_DIR} is in your PATH"

    # Add PATH to shell config if needed
    RC_FILE="${HOME}/.zshrc"
    if [ -f "$RC_FILE" ] && ! grep -q "export PATH=\"${BIN_DIR}:\$PATH\"" "$RC_FILE"; then
        echo "" >>"$RC_FILE"
        echo "# Local binaries" >>"$RC_FILE"
        echo "export PATH=\"${BIN_DIR}:\$PATH\"" >>"$RC_FILE"
        log_info "Added ${BIN_DIR} to PATH in ${RC_FILE}"
    fi
}

main "$@"

#!/bin/bash

install_pipx() {
    log_info "Installing pipx..."

    if check_installed pipx; then
        log_info "pipx is already installed"
        pipx --version
        return 0
    fi

    # Install pipx using pip (user installation, no sudo needed)
    log_info "Installing pipx via pip..."

    if python3 -m pip install --user pipx; then
        log_info "pipx installed successfully"

        # Ensure pipx binaries are in PATH
        python3 -m pipx ensurepath

        # Add to PATH for current session
        export PATH="${HOME}/.local/bin:${PATH}"

        # Verify installation
        if command -v pipx >/dev/null 2>&1; then
            pipx --version
        else
            log_warn "pipx installed but not found in PATH. Restart your shell or run: python3 -m pipx ensurepath"
        fi
    else
        log_error "Failed to install pipx"
        return 1
    fi
}

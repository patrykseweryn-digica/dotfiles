#!/bin/bash

install_oh_my_zsh() {
    log_info "Installing Oh My Zsh..."

    # Check if already installed
    if [ -d "${HOME}/.oh-my-zsh" ]; then
        log_info "Oh My Zsh is already installed"
    else
        # Install Oh My Zsh without sudo (unattended mode)
        log_info "Downloading and installing Oh My Zsh..."
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

        if [ -d "${HOME}/.oh-my-zsh" ]; then
            log_info "Oh My Zsh installed successfully"
        else
            log_error "Failed to install Oh My Zsh"
            return 1
        fi
    fi

    # Install popular plugins
    ZSH_CUSTOM="${ZSH_CUSTOM:-${HOME}/.oh-my-zsh/custom}"

    # zsh-autosuggestions
    if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" ]; then
        log_info "Installing zsh-autosuggestions plugin..."
        git clone https://github.com/zsh-users/zsh-autosuggestions "${ZSH_CUSTOM}/plugins/zsh-autosuggestions"
    else
        log_info "zsh-autosuggestions already installed"
    fi

    # zsh-syntax-highlighting
    if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" ]; then
        log_info "Installing zsh-syntax-highlighting plugin..."
        git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting"
    else
        log_info "zsh-syntax-highlighting already installed"
    fi

    # zsh-completions
    if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-completions" ]; then
        log_info "Installing zsh-completions plugin..."
        git clone https://github.com/zsh-users/zsh-completions "${ZSH_CUSTOM}/plugins/zsh-completions"
    else
        log_info "zsh-completions already installed"
    fi

    # fzf-tab
    if [ ! -d "${ZSH_CUSTOM}/plugins/fzf-tab" ]; then
        log_info "Installing fzf-tab plugin..."
        git clone https://github.com/Aloxaf/fzf-tab "${ZSH_CUSTOM}/plugins/fzf-tab"
    else
        log_info "fzf-tab already installed"
    fi

    # Update .zshrc with plugins if not already configured
    RC_FILE="${HOME}/.zshrc"
    if [ -f "$RC_FILE" ]; then
        # Check if plugins line exists and update it
        if grep -q "^plugins=(" "$RC_FILE"; then
            if ! grep -q "zsh-autosuggestions" "$RC_FILE"; then
                log_info "Updating plugins in .zshrc..."
                # Backup original
                cp "$RC_FILE" "${RC_FILE}.backup"

                # Replace plugins line with recommended setup
                sed -i 's/^plugins=(.*/plugins=(git zsh-autosuggestions zsh-syntax-highlighting zsh-completions fzf-tab)/' "$RC_FILE"
                log_info "Updated plugins in .zshrc (backup saved to .zshrc.backup)"
            fi
        fi
    fi

    log_info "Oh My Zsh and plugins installation complete"
}

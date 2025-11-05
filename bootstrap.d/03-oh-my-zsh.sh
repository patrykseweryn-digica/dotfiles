#!/bin/bash

install_oh_my_zsh() {
    echo "[INFO] Installing Oh My Zsh..."

    # Check if already installed
    if [ -d "${HOME}/.oh-my-zsh" ]; then
        echo "[INFO] Oh My Zsh is already installed"
    else
        # Install Oh My Zsh without sudo (unattended mode)
        echo "[INFO] Downloading and installing Oh My Zsh..."
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

        if [ -d "${HOME}/.oh-my-zsh" ]; then
            echo "[INFO] Oh My Zsh installed successfully"
        else
            echo "[ERROR] Failed to install Oh My Zsh" >&2
            return 1
        fi
    fi

    # Install popular plugins
    ZSH_CUSTOM="${ZSH_CUSTOM:-${HOME}/.oh-my-zsh/custom}"

    # zsh-autosuggestions
    if [ ! -d "${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-autosuggestions" ]; then
        echo "[INFO] Installing zsh-autosuggestions plugin..."
        git clone https://github.com/zsh-users/zsh-autosuggestions $ZSH_CUSTOM/plugins/zsh-autosuggestions
    else
        echo "[INFO] zsh-autosuggestions already installed"
    fi

    # zsh-syntax-highlighting
    if [ ! -d "${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-syntax-highlighting" ]; then
        echo "[INFO] Installing zsh-syntax-highlighting plugin..."
        git clone https://github.com/zsh-users/zsh-syntax-highlighting.git $ZSH_CUSTOM/plugins/zsh-syntax-highlighting
    else
        echo "[INFO] zsh-syntax-highlighting already installed"
    fi

    # zsh-completions
    if [ ! -d "${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions" ]; then
        echo "[INFO] Installing zsh-completions plugin..."
        git clone https://github.com/zsh-users/zsh-completions.git \
            ${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions
    else
        echo "[INFO] zsh-completions already installed"
    fi

    # fzf-tab
    if [ ! -d "${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/fzf-tab" ]; then
        echo "[INFO] Installing fzf-tab plugin..."
        git clone https://github.com/Aloxaf/fzf-tab $ZSH_CUSTOM/plugins/fzf-tab
    else
        echo "[INFO] fzf-tab already installed"
    fi

    # zsh-bat
    if [ ! -d "${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-bat" ]; then
        echo "[INFO] Installing zsh-bat plugin..."
        git clone https://github.com/fdellwing/zsh-bat.git $ZSH_CUSTOM/plugins/zsh-bat
    else
        echo "[INFO] zsh-bat already installed"
    fi

    # you-should-use
    if [ ! -d "${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/you-should-use" ]; then
        echo "[INFO] Installing you-should-use plugin..."
        git clone https://github.com/MichaelAquilina/zsh-you-should-use.git $ZSH_CUSTOM/plugins/you-should-use
    else
        echo "[INFO] you-should-use already installed"
    fi

    # Install Powerlevel10k theme
    if [ ! -d "${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/themes/powerlevel10k" ]; then
        echo "[INFO] Installing Powerlevel10k theme..."
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git $ZSH_CUSTOM/themes/powerlevel10k
    else
        echo "[INFO] Powerlevel10k already installed"
    fi

    echo "[INFO] Oh My Zsh and plugins installation complete"
}

#!/bin/bash

clone_if_missing() {
    local repo="$1"
    local dest="$2"
    shift 2
    local name
    name="$(basename "$dest")"

    if [ -d "$dest" ]; then
        echo "[INFO] $name already installed"
        return 0
    fi

    echo "[INFO] Installing $name..."
    if ! git clone "$@" "$repo" "$dest"; then
        echo "[ERROR] Failed to clone $name" >&2
        return 1
    fi
}

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

    # Install plugins and theme
    ZSH_CUSTOM="${ZSH_CUSTOM:-${HOME}/.oh-my-zsh/custom}"

    clone_if_missing https://github.com/zsh-users/zsh-autosuggestions       "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
    clone_if_missing https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
    clone_if_missing https://github.com/zsh-users/zsh-completions.git        "$ZSH_CUSTOM/plugins/zsh-completions"
    clone_if_missing https://github.com/Aloxaf/fzf-tab                       "$ZSH_CUSTOM/plugins/fzf-tab"
    clone_if_missing https://github.com/fdellwing/zsh-bat.git                "$ZSH_CUSTOM/plugins/zsh-bat"
    clone_if_missing https://github.com/MichaelAquilina/zsh-you-should-use.git "$ZSH_CUSTOM/plugins/you-should-use"
    clone_if_missing https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM/themes/powerlevel10k" --depth=1

    echo "[INFO] Oh My Zsh and plugins installation complete"
}

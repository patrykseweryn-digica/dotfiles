#!/bin/bash

install_macos_brew_bundle() {
    if [ "${IS_MACOS:-false}" != true ]; then
        return 0
    fi

    if ! command -v brew >/dev/null 2>&1; then
        echo "[WARN] Homebrew not found, skipping macOS app bundle"
        return 0
    fi

    if [ ! -f "${DOTFILES_DIR}/Brewfile" ]; then
        echo "[WARN] Brewfile not found, skipping macOS app bundle"
        return 0
    fi

    echo "[INFO] Installing macOS apps and tools from Brewfile..."
    if ! brew bundle install --file "${DOTFILES_DIR}/Brewfile"; then
        echo "[WARN] Brewfile installation had issues, continuing..."
    fi
}

install_vscode_cli() {
    if [ "${IS_MACOS:-false}" != true ]; then
        return 0
    fi

    if command -v code >/dev/null 2>&1; then
        echo "[INFO] VS Code CLI is already available"
        return 0
    fi

    local vscode_cli="${VSCODE_CLI_PATH:-/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code}"
    local bin_dir

    if [ ! -x "$vscode_cli" ]; then
        echo "[WARN] VS Code app CLI not found at $vscode_cli"
        return 0
    fi

    if command -v brew >/dev/null 2>&1 && bin_dir="$(brew --prefix 2>/dev/null)/bin"; then
        :
    elif [ -d /opt/homebrew/bin ]; then
        bin_dir="/opt/homebrew/bin"
    else
        bin_dir="/usr/local/bin"
    fi

    mkdir -p "$bin_dir"
    ln -sf "$vscode_cli" "${bin_dir}/code"
    echo "[INFO] Linked VS Code CLI to ${bin_dir}/code"
}

install_vscode_extensions() {
    local extensions_file="${DOTFILES_DIR}/config/Code/extensions.txt"
    local extension

    if [ ! -f "$extensions_file" ]; then
        return 0
    fi

    if ! command -v code >/dev/null 2>&1; then
        echo "[WARN] VS Code CLI not found, skipping extension install"
        return 0
    fi

    echo "[INFO] Installing VS Code extensions..."
    while IFS= read -r extension; do
        case "$extension" in
            "" | \#*) continue ;;
        esac

        code --install-extension "$extension" || echo "[WARN] Failed to install VS Code extension: $extension"
    done < "$extensions_file"
}

apply_rectangle_defaults() {
    if [ "${IS_MACOS:-false}" != true ]; then
        return 0
    fi

    if ! command -v defaults >/dev/null 2>&1; then
        return 0
    fi

    echo "[INFO] Applying Rectangle defaults..."
    defaults write com.knollsoft.Rectangle SUEnableAutomaticChecks -bool false
    defaults write com.knollsoft.Rectangle allowAnyShortcut -bool true
    defaults write com.knollsoft.Rectangle alternateDefaultShortcuts -bool true
    defaults write com.knollsoft.Rectangle internalTilingNotified -bool true
    defaults write com.knollsoft.Rectangle subsequentExecutionMode -int 1
    defaults write com.knollsoft.Rectangle reflowTodo -dict keyCode -int 45 modifierFlags -int 786432
    defaults write com.knollsoft.Rectangle toggleTodo -dict keyCode -int 11 modifierFlags -int 786432
}

install_macos_apps() {
    if [ "${IS_MACOS:-false}" != true ]; then
        return 0
    fi

    install_macos_brew_bundle
    install_vscode_cli
    install_vscode_extensions
    apply_rectangle_defaults
}

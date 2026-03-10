#!/bin/bash

install_zsh_from_package_manager() {
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update && sudo apt-get install -y zsh
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y zsh
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y zsh
    elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -S --noconfirm zsh
    elif command -v brew >/dev/null 2>&1; then
        brew install zsh
    else
        echo "[ERROR] No supported package manager found" >&2
        return 1
    fi
}

install_zsh_from_source() {
    echo "[WARN] No sudo access. Installing zsh from source to ${OPT_DIR}/zsh..."

    local zsh_version="5.9"
    local zsh_tmp="/tmp/zsh-${zsh_version}"

    cd /tmp || return 1
    curl -L "https://sourceforge.net/projects/zsh/files/zsh/${zsh_version}/zsh-${zsh_version}.tar.xz/download" -o "zsh-${zsh_version}.tar.xz"
    tar -xf "zsh-${zsh_version}.tar.xz"
    cd "zsh-${zsh_version}" || return 1

    ./configure --prefix="${OPT_DIR}/zsh"
    make
    make install

    ln -sf "${OPT_DIR}/zsh/bin/zsh" "${BIN_DIR}/zsh"

    cd "${DOTFILES_DIR}" || return 1
    rm -rf "${zsh_tmp}"

    echo "[INFO] zsh compiled and installed to ${OPT_DIR}/zsh"
}

set_default_shell() {
    if [ "$(basename "$SHELL")" = "zsh" ]; then
        return 0
    fi

    echo "[INFO] Changing default shell to zsh (you may be prompted for your password)..."
    chsh -s "$(which zsh)"
    echo "[INFO] Default shell changed to zsh"
}

add_ssh_auto_zsh_snippet() {
    local marker="Auto-start zsh for SSH sessions (dotfiles)"
    for f in "$HOME/.profile" "$HOME/.bashrc"; do
        if [ -f "$f" ] && grep -q "$marker" "$f"; then
            continue
        fi
        cat <<'EOF' >>"$f"
# Auto-start zsh for SSH sessions (dotfiles)
if [ -n "$SSH_CONNECTION" ] && [ -z "$ZSH_VERSION" ] && command -v zsh >/dev/null 2>&1; then
  exec zsh -l
fi
EOF
        echo "[INFO] Added auto-zsh SSH snippet to $f"
    done
}

install_zsh() {
    echo "[INFO] Checking zsh installation..."

    if check_installed zsh; then
        echo "[INFO] zsh is already installed"
        zsh --version
    else
        if [ "$HAS_SUDO" = true ]; then
            echo "[INFO] Installing zsh via package manager..."
            install_zsh_from_package_manager
        else
            install_zsh_from_source
        fi
    fi

    if ! check_installed zsh; then
        echo "[ERROR] Failed to install zsh" >&2
        return 1
    fi

    zsh --version
    echo "[INFO] zsh installed successfully"

    if ! set_default_shell; then
        add_ssh_auto_zsh_snippet
    fi
}

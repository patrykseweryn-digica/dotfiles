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

install_zsh_with_brew() {
    brew install zsh
}

install_zsh_from_source() {
    echo "[WARN] No sudo access. Installing zsh from source to ${OPT_DIR}/zsh..."

    local zsh_version="5.9"
    local zsh_tmp="/tmp/zsh-${zsh_version}"

    cd /tmp || return 1
    curl -L "https://sourceforge.net/projects/zsh/files/zsh/${zsh_version}/zsh-${zsh_version}.tar.xz/download" -o "zsh-${zsh_version}.tar.xz"
    tar -xf "zsh-${zsh_version}.tar.xz"
    cd "zsh-${zsh_version}" || return 1

    # The configure probe fails when CI has no controlling terminal.
    ./configure --prefix="${OPT_DIR}/zsh" --with-tcsetpgrp
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
    if chsh -s "$(which zsh)"; then
        echo "[INFO] Default shell changed to zsh"
        return 0
    fi
    echo "[WARN] Could not change the default shell"
    return 1
}

add_ssh_auto_zsh_snippet() {
    local marker="Auto-start zsh for SSH sessions (dotfiles)"
    for f in "$HOME/.profile" "$HOME/.bashrc"; do
        if [ -f "$f" ] && grep -q "$marker" "$f"; then
            continue
        fi
        cat <<'EOF' >>"$f"
# Auto-start zsh for SSH sessions (dotfiles)
if [ "${-#*i}" != "$-" ] && [ -n "$SSH_CONNECTION" ] && [ -z "$ZSH_VERSION" ] && command -v zsh >/dev/null 2>&1; then
  exec zsh -l
fi
EOF
        echo "[INFO] Added auto-zsh SSH snippet to $f"
    done
}

MISE_SHIMS_BEGIN='# >>> dotfiles: mise shims for login shells >>>'
MISE_SHIMS_END='# <<< dotfiles: mise shims for login shells <<<'

# Print the managed ~/.zprofile block. Login shells that skip .zshrc, such
# as `zsh -lc` from agents, find mise tools through its shims.
mise_shims_block() {
    printf '%s\n' "$MISE_SHIMS_BEGIN" \
        '# Keep this block after Homebrew so mise tools come first.' \
        'if [ -x "$HOME/.local/bin/mise" ]; then' \
        '  eval "$("$HOME/.local/bin/mise" activate zsh --shims)"' \
        'fi' \
        "$MISE_SHIMS_END"
}

# Print ~/.zprofile without the managed block.
zprofile_without_mise_shims() {
    local profile="$HOME/.zprofile"
    [ -f "$profile" ] || return 0
    awk -v begin="$MISE_SHIMS_BEGIN" -v end="$MISE_SHIMS_END" '
        $0 == begin { skip = 1; next }
        $0 == end { skip = 0; next }
        !skip { print }
    ' "$profile"
}

# Succeed when ~/.zprofile ends with the current managed block.
mise_shims_profile_current() {
    local profile="$HOME/.zprofile" expected
    [ -f "$profile" ] || return 1
    expected="$(zprofile_without_mise_shims; mise_shims_block)" || return 1
    [ "$(cat "$profile")" = "$expected" ]
}

# Move or add the managed block to the end of ~/.zprofile; other lines stay.
configure_mise_shims_profile() {
    local profile="$HOME/.zprofile" content
    mise_shims_profile_current && return 0
    content="$(zprofile_without_mise_shims; mise_shims_block)" || return 1
    # Write into the file so its mode and any symlink stay unchanged.
    printf '%s\n' "$content" >"$profile" || return 1
    echo "[INFO] Login shells find mise tools: updated $profile"
}

install_zsh() {
    echo "[INFO] Checking zsh installation..."

    if check_installed zsh; then
        echo "[INFO] zsh is already installed"
        zsh --version
    else
        if command -v brew >/dev/null 2>&1; then
            echo "[INFO] Installing zsh via Homebrew..."
            install_zsh_with_brew
        elif [ "$HAS_SUDO" = true ]; then
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

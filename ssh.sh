#!/bin/bash
set -euo pipefail

# Usage: ssh.sh <personal-email> <work-email>

if [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
    echo "[ERROR] Usage: ssh.sh <personal-email> <work-email>" >&2
    exit 1
fi

PERSONAL_EMAIL="$1"
WORK_EMAIL="$2"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SSH_SRC="$SCRIPT_DIR/config/ssh/config"

SSH_DIR="$HOME/.ssh"
CONFIG_D="$SSH_DIR/config.d"
DOTFILES_LINK="$CONFIG_D/dotfiles.conf"
MAIN_CONFIG="$SSH_DIR/config"
STUB_CONTENT='Include config.d/*.conf'

mkdir -p "$SSH_DIR" "$CONFIG_D"
chmod 700 "$SSH_DIR" "$CONFIG_D"

generate_key() {
    local key_path="$1"
    local email="$2"
    local label="$3"

    if [ -f "$key_path" ]; then
        echo "[INFO] $label key already exists at $key_path, skipping"
        return
    fi

    echo "[INFO] Generating $label SSH key..."
    if ! ssh-keygen -t ed25519 -C "$email" -f "$key_path" -N ""; then
        echo "[ERROR] ssh-keygen failed for $label key" >&2
        exit 1
    fi
}

generate_key "$SSH_DIR/id_ed25519" "$PERSONAL_EMAIL" "personal"
generate_key "$SSH_DIR/id_ed25519_work" "$WORK_EMAIL" "work"

# Start ssh-agent if not already running
if [ -z "${SSH_AUTH_SOCK:-}" ]; then
    if ! eval "$(ssh-agent -s)"; then
        echo "[ERROR] Failed to start ssh-agent" >&2
        exit 1
    fi
else
    echo "[INFO] Using existing ssh-agent"
fi

if [ "$(uname)" = "Darwin" ]; then
    ssh-add --apple-use-keychain "$SSH_DIR/id_ed25519"
    ssh-add --apple-use-keychain "$SSH_DIR/id_ed25519_work"
else
    ssh-add "$SSH_DIR/id_ed25519"
    ssh-add "$SSH_DIR/id_ed25519_work"
fi

backup_path() {
    local base="$1"
    local ts
    ts="$(date +%Y%m%d%H%M%S)"
    local candidate="${base}.backup.${ts}"
    local i=1
    while [ -e "$candidate" ]; do
        candidate="${base}.backup.${ts}.${i}"
        i=$((i + 1))
    done
    printf '%s' "$candidate"
}

chmod 600 "$SSH_SRC"

# Link config.d/dotfiles.conf -> repo
if [ -L "$DOTFILES_LINK" ] && [ "$(readlink "$DOTFILES_LINK")" = "$SSH_SRC" ]; then
    echo "[INFO] $DOTFILES_LINK already linked to $SSH_SRC"
else
    if [ -e "$DOTFILES_LINK" ] || [ -L "$DOTFILES_LINK" ]; then
        if [ ! -L "$DOTFILES_LINK" ]; then
            bk="$(backup_path "$DOTFILES_LINK")"
            mv "$DOTFILES_LINK" "$bk"
            echo "[INFO] Backed up $DOTFILES_LINK to $bk"
        fi
        rm -f "$DOTFILES_LINK"
    fi
    ln -s "$SSH_SRC" "$DOTFILES_LINK"
    echo "[INFO] Linked $DOTFILES_LINK -> $SSH_SRC"
fi

# Ensure ~/.ssh/config is a stub including config.d/*.conf
write_stub=0
if [ -L "$MAIN_CONFIG" ]; then
    # Legacy single-file symlink (e.g. -> repo config). Replace with stub.
    target="$(readlink "$MAIN_CONFIG")"
    bk="$(backup_path "$MAIN_CONFIG")"
    mv "$MAIN_CONFIG" "$bk"
    echo "[INFO] Replaced legacy symlink ($target). Old link saved as $bk"
    write_stub=1
elif [ -f "$MAIN_CONFIG" ]; then
    if [ "$(cat "$MAIN_CONFIG")" = "$STUB_CONTENT" ]; then
        echo "[INFO] $MAIN_CONFIG already correct stub"
    else
        bk="$(backup_path "$MAIN_CONFIG")"
        mv "$MAIN_CONFIG" "$bk"
        echo "[INFO] Backed up existing $MAIN_CONFIG to $bk"
        write_stub=1
    fi
else
    write_stub=1
fi

if [ "$write_stub" = 1 ]; then
    printf '%s\n' "$STUB_CONTENT" > "$MAIN_CONFIG"
    chmod 600 "$MAIN_CONFIG"
    echo "[INFO] Wrote stub $MAIN_CONFIG"
fi

# Touch a local.conf placeholder so Include never warns on an empty config.d
if [ ! -e "$CONFIG_D/local.conf" ]; then
    touch "$CONFIG_D/local.conf"
    chmod 600 "$CONFIG_D/local.conf"
    echo "[INFO] Created empty $CONFIG_D/local.conf (machine-local, not in repo)"
fi

echo ""
echo "[INFO] Add these public keys to your GitHub accounts:"
echo "  Personal: $(cat "$SSH_DIR/id_ed25519.pub")"
echo "  Work:     $(cat "$SSH_DIR/id_ed25519_work.pub")"

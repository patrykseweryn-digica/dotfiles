#!/bin/bash

# Usage: ssh.sh <personal-email> <work-email>

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "[ERROR] Usage: ssh.sh <personal-email> <work-email>" >&2
    exit 1
fi

PERSONAL_EMAIL="$1"
WORK_EMAIL="$2"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SSH_SRC="$SCRIPT_DIR/config/ssh/config"

mkdir -p ~/.ssh

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

generate_key ~/.ssh/id_ed25519 "$PERSONAL_EMAIL" "personal"
generate_key ~/.ssh/id_ed25519_work "$WORK_EMAIL" "work"

# Start ssh-agent and add keys
if ! eval "$(ssh-agent -s)"; then
    echo "[ERROR] Failed to start ssh-agent" >&2
    exit 1
fi

if [ "$(uname)" = "Darwin" ]; then
    ssh-add --apple-use-keychain ~/.ssh/id_ed25519
    ssh-add --apple-use-keychain ~/.ssh/id_ed25519_work
else
    ssh-add ~/.ssh/id_ed25519
    ssh-add ~/.ssh/id_ed25519_work
fi

# Append SSH config if not already managed
touch ~/.ssh/config

if ! grep -qF "# dotfiles-managed" ~/.ssh/config; then
    printf '\n# dotfiles-managed\n' >>~/.ssh/config
    cat "$SSH_SRC" >>~/.ssh/config
    echo "[INFO] Appended SSH config from $SSH_SRC"
else
    echo "[INFO] SSH config already contains dotfiles entries, skipping"
fi

echo ""
echo "[INFO] Add these public keys to your GitHub accounts:"
echo "  Personal: $(cat ~/.ssh/id_ed25519.pub)"
echo "  Work:     $(cat ~/.ssh/id_ed25519_work.pub)"

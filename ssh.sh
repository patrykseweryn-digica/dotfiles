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

# Manage SSH config section between start/end markers
touch ~/.ssh/config

START_MARKER="# dotfiles-managed-start"
END_MARKER="# dotfiles-managed-end"

MANAGED_BLOCK="${START_MARKER}
$(cat "$SSH_SRC")
${END_MARKER}"

if grep -qF "$START_MARKER" ~/.ssh/config; then
    # Replace existing managed section
    tmp="$(mktemp)"
    awk -v start="$START_MARKER" -v end="$END_MARKER" -v block="$MANAGED_BLOCK" '
        $0 == start { print block; skip=1; next }
        $0 == end { skip=0; next }
        !skip { print }
    ' ~/.ssh/config > "$tmp"
    mv "$tmp" ~/.ssh/config
    chmod 600 ~/.ssh/config
    echo "[INFO] Updated SSH config managed section"
else
    # Append managed section
    printf '\n%s\n' "$MANAGED_BLOCK" >>~/.ssh/config
    echo "[INFO] Appended SSH config from $SSH_SRC"
fi

echo ""
echo "[INFO] Add these public keys to your GitHub accounts:"
echo "  Personal: $(cat ~/.ssh/id_ed25519.pub)"
echo "  Work:     $(cat ~/.ssh/id_ed25519_work.pub)"

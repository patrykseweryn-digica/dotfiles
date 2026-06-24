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
SSH_CONFIG_MODE="${DOTFILES_SSH_CONFIG_MODE:-ask}"

case "$SSH_CONFIG_MODE" in
    ask | preserve | replace) ;;
    *)
        echo "[ERROR] DOTFILES_SSH_CONFIG_MODE must be one of: ask, preserve, replace" >&2
        exit 1
        ;;
esac

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

write_main_config_stub() {
    printf '%s\n' "$STUB_CONTENT" > "$MAIN_CONFIG"
    chmod 600 "$MAIN_CONFIG"
    echo "[INFO] Wrote stub $MAIN_CONFIG"
}

prepend_main_config_include() {
    local bk
    local tmp

    bk="$(backup_path "$MAIN_CONFIG")"
    cp -p "$MAIN_CONFIG" "$bk"
    tmp="$(mktemp "${MAIN_CONFIG}.tmp.XXXXXX")"
    {
        printf '%s\n\n' "$STUB_CONTENT"
        cat "$MAIN_CONFIG"
    } > "$tmp"
    mv "$tmp" "$MAIN_CONFIG"
    chmod 600 "$MAIN_CONFIG"
    echo "[INFO] Backed up existing $MAIN_CONFIG to $bk"
    echo "[INFO] Prepended $STUB_CONTENT to $MAIN_CONFIG"
}

main_config_has_dotfiles_include() {
    [ -f "$MAIN_CONFIG" ] || return 1
    grep -Eq '^[[:space:]]*Include[[:space:]]+config\.d/\*\.conf([[:space:]]|$)' "$MAIN_CONFIG"
}

handle_main_config_without_include() {
    case "$SSH_CONFIG_MODE" in
        replace)
            local bk
            bk="$(backup_path "$MAIN_CONFIG")"
            mv "$MAIN_CONFIG" "$bk"
            echo "[INFO] Backed up existing $MAIN_CONFIG to $bk"
            write_main_config_stub
            ;;
        preserve)
            echo "[WARN] Preserving existing $MAIN_CONFIG without $STUB_CONTENT (DOTFILES_SSH_CONFIG_MODE=preserve)"
            ;;
        ask)
            prepend_main_config_include
            ;;
    esac
}

ensure_main_ssh_config() {
    if [ ! -e "$MAIN_CONFIG" ] && [ ! -L "$MAIN_CONFIG" ]; then
        write_main_config_stub
        return
    fi

    if [ -f "$MAIN_CONFIG" ] && [ "$(cat "$MAIN_CONFIG")" = "$STUB_CONTENT" ]; then
        echo "[INFO] $MAIN_CONFIG already correct stub"
        return
    fi

    if main_config_has_dotfiles_include; then
        echo "[INFO] $MAIN_CONFIG already includes config.d/*.conf"
        return
    fi

    handle_main_config_without_include
}

verify_main_ssh_config() {
    if main_config_has_dotfiles_include; then
        return 0
    fi

    if [ "$SSH_CONFIG_MODE" = "preserve" ]; then
        echo "[WARN] Dotfiles SSH config is linked but not active; add '$STUB_CONTENT' to $MAIN_CONFIG manually"
        return 0
    fi

    echo "[ERROR] Dotfiles SSH config is not active; missing '$STUB_CONTENT' in $MAIN_CONFIG" >&2
    return 1
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

ensure_main_ssh_config
verify_main_ssh_config

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
echo ""
echo "[INFO] SSH keys are loaded by ~/.zshrc on shell startup."
echo "[INFO] To load them in this terminal now, run: exec zsh -l"

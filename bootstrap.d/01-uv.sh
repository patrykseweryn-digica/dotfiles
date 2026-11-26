#!/bin/bash

install_uv() {
    echo "[INFO] Installing uv (Astral)..."

    if check_installed uv; then
        echo "[INFO] uv is already installed"
        uv --version
        return 0
    fi

    # The official installer puts uv in ~/.local/bin (no sudo needed).
    echo "[INFO] Downloading and installing uv..."

    if curl -LsSf https://astral.sh/uv/install.sh | sh; then
        echo "[INFO] uv installed successfully"

        # Make uv available in the current session.
        export PATH="${HOME}/.local/bin:${PATH}"

        if command -v uv >/dev/null 2>&1; then
            uv --version
        else
            echo "[WARN] uv installed but not found in PATH. Restart your shell or source ~/.zshrc"
        fi
    else
        echo "[ERROR] Failed to install uv" >&2
        return 1
    fi
}

# Print the directory where the official installer receipt put uv.
uv_receipt_bin_dir() {
    local receipt
    receipt="${XDG_CONFIG_HOME:-${HOME}/.config}/uv/uv-receipt.json"
    [ -f "$receipt" ] || return 1
    jq -er 'if .install_layout == "flat" then .install_prefix
        else .install_prefix + "/bin" end' "$receipt"
}

# Update uv only when the uv on PATH comes from the official installer.
# Another source, such as Homebrew or pipx, owns its own updates.
update_uv() {
    local uv_path uv_dir receipt_dir

    if ! uv_path="$(command -v uv)"; then
        echo "[WARN] uv is missing; skipping uv self update" >&2
        return 0
    fi
    uv_dir="$(cd "$(dirname "$uv_path")" && pwd -P)" || return 1
    if ! receipt_dir="$(uv_receipt_bin_dir)" ||
        [ "$(cd "$receipt_dir" 2>/dev/null && pwd -P)" != "$uv_dir" ]; then
        echo "[WARN] ${uv_path} does not come from the official uv" \
            "installer; skipping uv self update. Update uv with its source." >&2
        return 0
    fi
    operation_run uv "self update" install -- uv self update
}

#!/bin/bash

install_font() {
    local name="$1" url="$2"
    local font_dir="${HOME}/.local/share/fonts"
    local tmp_dir

    mkdir -p "$font_dir"
    tmp_dir="$(mktemp -d)"

    echo "[INFO] Downloading ${name}..."
    if ! curl -fsSL "$url" -o "${tmp_dir}/font.zip"; then
        echo "[WARN] Failed to download ${name}" >&2
        rm -rf "$tmp_dir"
        return 1
    fi

    unzip -qo "${tmp_dir}/font.zip" -d "${tmp_dir}/extracted"

    # Copy only font files (ttf/otf), skip Windows-specific formats
    find "${tmp_dir}/extracted" \( -name "*.ttf" -o -name "*.otf" \) -type f \
        -exec cp {} "$font_dir/" \;

    rm -rf "$tmp_dir"
    echo "[INFO] ${name} installed to ${font_dir}"
}

install_fonts() {
    echo "[INFO] Installing fonts..."

    local font_dir="${HOME}/.local/share/fonts"

    # JetBrains Mono Nerd Font (required by powerlevel10k)
    if fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd"; then
        echo "[INFO] JetBrains Mono Nerd Font is already installed"
    else
        install_font "JetBrains Mono Nerd Font" \
            "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/JetBrainsMono.zip"
    fi

    # FiraCode (programming font with ligatures)
    if fc-list 2>/dev/null | grep -qi "Fira Code"; then
        echo "[INFO] FiraCode is already installed"
    else
        install_font "FiraCode" \
            "https://github.com/tonsky/FiraCode/releases/download/6.2/Fira_Code_v6.2.zip"
    fi

    # Source Code Pro (Adobe)
    if fc-list 2>/dev/null | grep -qi "Source Code Pro"; then
        echo "[INFO] Source Code Pro is already installed"
    else
        install_font "Source Code Pro" \
            "https://github.com/adobe-fonts/source-code-pro/releases/download/2.042R-u%2F1.062R-i%2F1.026R-vf/TTF-source-code-pro-2.042R-u_1.062R-i.zip"
    fi

    # Cascadia Code (Microsoft, with Mono variant without ligatures)
    if fc-list 2>/dev/null | grep -qi "Cascadia"; then
        echo "[INFO] Cascadia Code is already installed"
    else
        install_font "Cascadia Code" \
            "https://github.com/microsoft/cascadia-code/releases/download/v2407.24/CascadiaCode-2407.24.zip"
    fi

    # Iosevka (ultra-configurable, narrow monospace)
    if fc-list 2>/dev/null | grep -qi "Iosevka"; then
        echo "[INFO] Iosevka is already installed"
    else
        install_font "Iosevka" \
            "https://github.com/be5invis/Iosevka/releases/download/v34.1.0/PkgTTF-Iosevka-34.1.0.zip"
    fi

    # Monaspace (GitHub, 5 stylistic variants with texture healing)
    if fc-list 2>/dev/null | grep -qi "Monaspace"; then
        echo "[INFO] Monaspace is already installed"
    else
        install_font "Monaspace" \
            "https://github.com/githubnext/monaspace/releases/download/v1.301/monaspace-static-v1.301.zip"
    fi

    # Rebuild font cache
    if command -v fc-cache >/dev/null 2>&1; then
        echo "[INFO] Rebuilding font cache..."
        fc-cache -f
    fi

    # Configure GNOME Terminal default font
    if command -v gsettings >/dev/null 2>&1 && fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd"; then
        local profile_id
        profile_id=$(gsettings get org.gnome.Terminal.ProfilesList default 2>/dev/null | tr -d "'") || true
        if [ -n "$profile_id" ]; then
            local profile_path="org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:${profile_id}/"
            gsettings set "$profile_path" use-system-font false
            gsettings set "$profile_path" font 'JetBrainsMono Nerd Font 11'
            echo "[INFO] GNOME Terminal font set to JetBrains Mono Nerd Font 11"
        fi
    fi
}

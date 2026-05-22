#!/bin/bash

check_installed() {
    command -v "$1" >/dev/null 2>&1
}

detect_package_manager() {
    if command -v apt-get >/dev/null 2>&1; then
        echo "apt-get"
    elif command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    elif command -v pacman >/dev/null 2>&1; then
        echo "pacman"
    elif command -v brew >/dev/null 2>&1; then
        echo "brew"
    else
        return 1
    fi
}

install_package_manager_package() {
    local tool_name="$1"
    local apt_package="$2"
    local dnf_package="$3"
    local pacman_package="$4"
    local brew_package="$5"
    local package_manager
    local package_name

    if ! package_manager="$(detect_package_manager)"; then
        echo "[WARN] Could not install ${tool_name}: no supported package manager"
        return 1
    fi

    case "$package_manager" in
        apt-get)
            package_name="$apt_package"
            [ -n "$package_name" ] || return 1
            sudo apt-get install -y "$package_name"
            ;;
        dnf)
            package_name="$dnf_package"
            [ -n "$package_name" ] || return 1
            sudo dnf install -y "$package_name"
            ;;
        pacman)
            package_name="$pacman_package"
            [ -n "$package_name" ] || return 1
            sudo pacman -S --noconfirm "$package_name"
            ;;
        brew)
            package_name="$brew_package"
            [ -n "$package_name" ] || return 1
            brew install "$package_name"
            ;;
    esac
}

# Download a binary from a GitHub release tarball/zip and install to BIN_DIR.
# Usage: install_github_binary <owner/repo> <tag> <archive_pattern> <binary_name_in_archive> [installed_name]
# archive_pattern: filename pattern with {tag} and/or {tag_no_v} placeholders
#   {tag}      = full tag, e.g. "v0.59.0"
#   {tag_no_v} = tag without leading 'v', e.g. "0.59.0"
install_github_binary() {
    local repo="$1" tag="$2" pattern="$3" binary="$4" name="${5:-$4}"
    local tag_no_v="${tag#v}"
    local archive="${pattern//\{tag\}/$tag}"
    archive="${archive//\{tag_no_v\}/$tag_no_v}"
    local url="https://github.com/${repo}/releases/download/${tag}/${archive}"
    local tmp_dir

    tmp_dir="$(mktemp -d)"

    echo "[INFO] Downloading ${name} from ${url}..."
    if ! curl -fsSL --connect-timeout 10 --max-time 120 "$url" -o "${tmp_dir}/${archive}"; then
        echo "[WARN] Failed to download ${name}" >&2
        rm -rf "$tmp_dir"
        return 1
    fi

    case "$archive" in
        *.tar.gz|*.tgz) tar -xzf "${tmp_dir}/${archive}" -C "$tmp_dir" ;;
        *.zip)          unzip -qo "${tmp_dir}/${archive}" -d "$tmp_dir" ;;
    esac

    local found
    found="$(find "$tmp_dir" -name "$binary" -type f | head -1)"
    if [ -z "$found" ]; then
        echo "[WARN] Binary '$binary' not found in archive" >&2
        rm -rf "$tmp_dir"
        return 1
    fi

    cp "$found" "${BIN_DIR}/${name}"
    chmod +x "${BIN_DIR}/${name}"
    rm -rf "$tmp_dir"
    echo "[INFO] ${name} installed to ${BIN_DIR}/${name}"
}

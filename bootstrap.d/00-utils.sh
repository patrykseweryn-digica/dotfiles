#!/bin/bash

check_installed() {
    command -v "$1" >/dev/null 2>&1
}

# Download a binary from a GitHub release tarball/zip and install to BIN_DIR.
# Usage: install_github_binary <owner/repo> <tag> <archive_pattern> <binary_name_in_archive> [installed_name]
# archive_pattern: filename pattern with {tag} placeholder, e.g. "fd-{tag}-x86_64-unknown-linux-gnu.tar.gz"
install_github_binary() {
    local repo="$1" tag="$2" pattern="$3" binary="$4" name="${5:-$4}"
    local archive="${pattern//\{tag\}/$tag}"
    local url="https://github.com/${repo}/releases/download/${tag}/${archive}"
    local tmp_dir

    tmp_dir="$(mktemp -d)"

    echo "[INFO] Downloading ${name} from ${url}..."
    if ! curl -fsSL "$url" -o "${tmp_dir}/${archive}"; then
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

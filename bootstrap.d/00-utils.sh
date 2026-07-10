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

# Return the correct GitHub release archive pattern for the current OS/arch.
# Usage: github_binary_pattern <tool-name>
# Outputs the archive filename pattern (with {tag}/{tag_no_v} placeholders).
github_binary_pattern() {
    local tool="$1"
    local os="${OS:-Linux}"
    local arch="${ARCH:-x86_64}"

    case "$tool" in
        fzf)
            if [ "$os" = "Darwin" ] && [ "$arch" = "arm64" ]; then
                echo "fzf-{tag_no_v}-darwin_arm64.tar.gz"
            else
                echo "fzf-{tag_no_v}-linux_amd64.tar.gz"
            fi
            ;;
        bat)
            if [ "$os" = "Darwin" ] && [ "$arch" = "arm64" ]; then
                echo "bat-{tag}-aarch64-apple-darwin.tar.gz"
            else
                echo "bat-{tag}-x86_64-unknown-linux-gnu.tar.gz"
            fi
            ;;
        ripgrep)
            if [ "$os" = "Darwin" ] && [ "$arch" = "arm64" ]; then
                echo "ripgrep-{tag}-aarch64-apple-darwin.tar.gz"
            else
                echo "ripgrep-{tag}-x86_64-unknown-linux-musl.tar.gz"
            fi
            ;;
        fd)
            if [ "$os" = "Darwin" ] && [ "$arch" = "arm64" ]; then
                echo "fd-{tag}-aarch64-apple-darwin.tar.gz"
            else
                echo "fd-{tag}-x86_64-unknown-linux-gnu.tar.gz"
            fi
            ;;
        delta)
            if [ "$os" = "Darwin" ] && [ "$arch" = "arm64" ]; then
                echo "delta-{tag}-aarch64-apple-darwin.tar.gz"
            else
                echo "delta-{tag}-x86_64-unknown-linux-gnu.tar.gz"
            fi
            ;;
        lazygit)
            if [ "$os" = "Darwin" ] && [ "$arch" = "arm64" ]; then
                echo "lazygit_{tag_no_v}_darwin_arm64.tar.gz"
            else
                echo "lazygit_{tag_no_v}_Linux_x86_64.tar.gz"
            fi
            ;;
        jq)
            if [ "$os" = "Darwin" ] && [ "$arch" = "arm64" ]; then
                echo "jq-macos-arm64"
            else
                echo "jq-linux-amd64"
            fi
            ;;
        tealdeer)
            if [ "$os" = "Darwin" ] && [ "$arch" = "arm64" ]; then
                echo "tealdeer-macos-aarch64"
            else
                echo "tealdeer-linux-x86_64-musl"
            fi
            ;;
        just)
            case "${os}:${arch}" in
                Darwin:arm64 | Darwin:aarch64)
                    echo "just-{tag}-aarch64-apple-darwin.tar.gz"
                    ;;
                Darwin:*)
                    echo "just-{tag}-x86_64-apple-darwin.tar.gz"
                    ;;
                Linux:arm64 | Linux:aarch64)
                    echo "just-{tag}-aarch64-unknown-linux-musl.tar.gz"
                    ;;
                *)
                    echo "just-{tag}-x86_64-unknown-linux-musl.tar.gz"
                    ;;
            esac
            ;;
        eza)
            echo "eza_x86_64-unknown-linux-gnu.tar.gz"
            ;;
    esac
}

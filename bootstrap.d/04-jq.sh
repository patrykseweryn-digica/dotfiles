#!/bin/bash

install_jq_package() {
    local package_manager

    package_manager="$(detect_package_manager)" || return 1
    case "$package_manager" in
    apt-get)
        sudo apt-get update && sudo apt-get install -y jq
        ;;
    dnf)
        sudo dnf install -y jq
        ;;
    pacman)
        sudo pacman -S --noconfirm jq
        ;;
    brew)
        brew install jq
        ;;
    *) return 1 ;;
    esac
}

install_jq_release() {
    local archive tag

    case "${OS}:${ARCH}" in
    Darwin:arm64 | Darwin:aarch64) archive=jq-macos-arm64 ;;
    Darwin:x86_64 | Darwin:amd64) archive=jq-macos-amd64 ;;
    Linux:arm64 | Linux:aarch64) archive=jq-linux-arm64 ;;
    Linux:x86_64 | Linux:amd64) archive=jq-linux-amd64 ;;
    *)
        echo "[ERROR] jq: unsupported platform ${OS}/${ARCH}" >&2
        return 1
        ;;
    esac

    tag="$(github_latest_tag jqlang/jq)" || return 1
    install_github_binary jqlang/jq "$tag" "$archive" "$archive" jq
}

ensure_jq() {
    if command -v jq >/dev/null 2>&1; then
        JQ_BIN="$(command -v jq)"
        export JQ_BIN
        echo "[INFO] jq is already installed"
        jq --version
        return 0
    fi

    echo "[INFO] Installing jq before manifest validation..."
    if command -v brew >/dev/null 2>&1; then
        brew install jq
    elif [ "$HAS_SUDO" = true ]; then
        install_jq_package
    else
        install_jq_release
    fi

    if ! command -v jq >/dev/null 2>&1; then
        echo "[ERROR] jq installation finished without an available command" >&2
        return 1
    fi
    JQ_BIN="$(command -v jq)"
    export JQ_BIN
    jq --version
}

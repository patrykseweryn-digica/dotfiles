#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
    echo "[ERROR] $*" >&2
    exit 1
}

if ! command -v zsh >/dev/null 2>&1; then
    echo "[WARN] zsh not found, skipping .zshrc startup smoke"
    exit 0
fi

tmp_dir="$(mktemp -d)"
cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

home_dir="${tmp_dir}/home"
zshenv="${tmp_dir}/zshenv"
stderr_log="${tmp_dir}/stderr.log"
env_file="${tmp_dir}/missing.env"

mkdir -p "$home_dir" "$zshenv"

if HOME="$home_dir" DOTFILES_ENV_FILE="$env_file" bash -c "source '${DOTFILES_DIR}/.zshrc'" 2>"$stderr_log"; then
    fail ".zshrc should reject bash"
fi

if ! grep -q "This file is for zsh. Run: exec zsh -l" "$stderr_log"; then
    cat "$stderr_log" >&2
    fail ".zshrc did not print bash guidance"
fi

if grep -E "bad substitution|command not found|syntax error" "$stderr_log" >/dev/null 2>&1; then
    cat "$stderr_log" >&2
    fail ".zshrc leaked zsh syntax errors under bash"
fi

if ! HOME="$home_dir" ZDOTDIR="$zshenv" DOTFILES_ENV_FILE="$env_file" zsh -df -c "source '${DOTFILES_DIR}/.zshrc'" 2>"$stderr_log"; then
    cat "$stderr_log" >&2
    fail ".zshrc failed in isolated HOME"
fi

if [ -s "$stderr_log" ]; then
    cat "$stderr_log" >&2
    fail ".zshrc wrote stderr in isolated HOME"
fi

echo "[INFO] .zshrc startup smoke test passed"

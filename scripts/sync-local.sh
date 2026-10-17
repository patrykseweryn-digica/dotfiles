#!/bin/bash
set -uo pipefail

default_dotfiles_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$default_dotfiles_dir}"
UPDATE_SCRIPT="${UPDATE_SCRIPT:-${DOTFILES_DIR}/scripts/update-local.sh}"

if ! worktree_state="$(git -C "$DOTFILES_DIR" status --porcelain)"; then
    echo "[ERROR] Could not inspect the dotfiles checkout" >&2
    echo "[RESULT] FAIL"
    exit 1
fi

if [ -n "$worktree_state" ]; then
    echo "[ERROR] Working tree is not clean" >&2
    echo "Commit, discard, or export local changes before synchronization" >&2
    echo "[RESULT] FAIL"
    exit 1
fi

if ! git -C "$DOTFILES_DIR" pull --ff-only; then
    echo "[ERROR] Could not fast-forward the dotfiles checkout" >&2
    echo "[RESULT] FAIL"
    exit 1
fi

exec "$UPDATE_SCRIPT"

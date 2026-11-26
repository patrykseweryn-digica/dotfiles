#!/bin/bash
set -uo pipefail

default_dotfiles_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$default_dotfiles_dir}"
UPDATE_SCRIPT="${UPDATE_SCRIPT:-${DOTFILES_DIR}/scripts/update-local.sh}"

# shellcheck source=scripts/operation.sh
source "${default_dotfiles_dir}/scripts/operation.sh"
# Each run starts a fresh operation log for all its phases.
DOTFILES_OPERATION_LOG="$(operation_sync_log_path)"
export DOTFILES_OPERATION_LOG
mkdir -p "$(dirname "$DOTFILES_OPERATION_LOG")" &&
    : >"$DOTFILES_OPERATION_LOG" ||
    echo "[WARN] Could not reset operation log: $DOTFILES_OPERATION_LOG" >&2

# Reject an invalid group setting before fetching or changing the machine.
# shellcheck source=scripts/groups.sh
source "${default_dotfiles_dir}/scripts/groups.sh"
if ! groups_load; then
    echo "[RESULT] FAIL"
    exit 1
fi

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

# Only the network fetch is bounded; a fast-forward is never interrupted.
if ! operation_run "dotfiles repo" "fetch upstream" fetch -- \
    git -C "$DOTFILES_DIR" fetch --quiet; then
    echo "[RESULT] FAIL"
    exit 1
fi

if ! git -C "$DOTFILES_DIR" merge --ff-only '@{upstream}'; then
    echo "[ERROR] Could not fast-forward the dotfiles checkout" >&2
    echo "Reconcile local commits with upstream, then run: ${DOTFILES_RUNNER:-just} sync" >&2
    echo "[RESULT] FAIL"
    exit 1
fi

exec "$UPDATE_SCRIPT"

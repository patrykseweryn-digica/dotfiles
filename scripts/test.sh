#!/bin/bash
# Run every repository check. `just test`, `make test` and CI use this entry.
# Report all missing host commands before any hook starts.
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DOTFILES_DIR"
# The Makefile exports its runner settings; checks set their own fixtures.
unset DOTFILES_RUNNER SYNC_AGENTS group
# Hooks find tools the same way; see scripts/host-tools.sh.
# shellcheck source=scripts/host-tools.sh
source "${DOTFILES_DIR}/scripts/host-tools.sh"

missing=()
for command_name in bash git make jq node npm uv prek python3 zsh rg herdr; do
    command -v "$command_name" >/dev/null 2>&1 || missing+=("$command_name")
done
if [ "${#missing[@]}" -gt 0 ]; then
    echo "[ERROR] Repository checks need these commands: ${missing[*]}" >&2
    echo "Install them, then run the checks again." >&2
    exit 1
fi

exec prek run --all-files "$@"

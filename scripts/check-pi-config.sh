#!/bin/bash
# Check Pi types, lint and regressions. Install the locked development
# dependencies first when they are missing or do not match the lockfile.
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pi_dir="${DOTFILES_DIR}/config/pi"
stamp="${pi_dir}/node_modules/.dotfiles-lock-sum"

lock_sum="$(cat "${pi_dir}/package.json" "${pi_dir}/package-lock.json" |
    cksum)"
if [ ! -f "$stamp" ] || [ "$(cat "$stamp")" != "$lock_sum" ]; then
    echo "[INFO] Installing Pi development dependencies from package-lock.json"
    npm --prefix "$pi_dir" ci --ignore-scripts --no-audit --no-fund
    printf '%s\n' "$lock_sum" >"$stamp"
fi

npm --prefix "$pi_dir" run check
npm --prefix "$pi_dir" test

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

agent_home="${tmp_dir}/agent-home"
stub_dir="${tmp_dir}/stubs"
agent_log="${tmp_dir}/agent.log"
mkdir -p "${agent_home}/.ssh" "$stub_dir"
: > "$agent_log"

printf 'private key\n' > "${agent_home}/.ssh/id_ed25519"
printf 'public key\n' > "${agent_home}/.ssh/id_ed25519.pub"
printf 'private work key\n' > "${agent_home}/.ssh/id_ed25519_work"
printf 'public work key\n' > "${agent_home}/.ssh/id_ed25519_work.pub"
chmod 600 "${agent_home}/.ssh/id_ed25519" "${agent_home}/.ssh/id_ed25519_work"

cat > "${stub_dir}/ssh-agent" <<'STUB'
#!/bin/sh
printf 'SSH_AUTH_SOCK=%s; export SSH_AUTH_SOCK;\n' "$HOME/.ssh/smoke-agent.sock"
printf 'SSH_AGENT_PID=12345; export SSH_AGENT_PID;\n'
printf 'echo Agent pid 12345;\n'
STUB

cat > "${stub_dir}/ssh-add" <<'STUB'
#!/bin/sh
if [ "${1:-}" = "-l" ]; then
    exit 1
fi
printf 'ssh-add %s\n' "$*" >> "$SSH_AGENT_LOG"
STUB

cat > "${stub_dir}/ssh-keygen" <<'STUB'
#!/bin/sh
if [ "${1:-}" = "-lf" ]; then
    printf '256 SHA256:%s test\n' "$(basename "$2")"
    exit 0
fi
exit 1
STUB

chmod +x "${stub_dir}/ssh-agent" "${stub_dir}/ssh-add" "${stub_dir}/ssh-keygen"

if ! env -u SSH_AUTH_SOCK -u SSH_AGENT_PID HOME="$agent_home" PATH="${stub_dir}:/usr/bin:/bin" ZDOTDIR="$zshenv" DOTFILES_ENV_FILE="$env_file" SSH_AGENT_LOG="$agent_log" zsh -df -c "source '${DOTFILES_DIR}/.zshrc'" 2>"$stderr_log"; then
    cat "$stderr_log" >&2
    fail ".zshrc failed while starting ssh-agent"
fi

if [ -s "$stderr_log" ]; then
    cat "$stderr_log" >&2
    fail ".zshrc ssh-agent setup wrote stderr"
fi

[ -f "${agent_home}/.ssh/agent.env" ] || fail ".zshrc did not persist ssh-agent env"
grep -F "ssh-add -q ${agent_home}/.ssh/id_ed25519" "$agent_log" >/dev/null 2>&1 ||
    fail ".zshrc did not add personal SSH key"
grep -F "ssh-add -q ${agent_home}/.ssh/id_ed25519_work" "$agent_log" >/dev/null 2>&1 ||
    fail ".zshrc did not add work SSH key"

echo "[INFO] .zshrc startup smoke test passed"

#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
    echo "[ERROR] $*" >&2
    exit 1
}

write_ssh_stubs() {
    local stub_dir="$1"

    cat > "${stub_dir}/ssh-keygen" <<'STUB'
#!/bin/sh
key_path=""
comment=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -f)
            shift
            key_path="$1"
            ;;
        -C)
            shift
            comment="$1"
            ;;
    esac
    shift
done
[ -n "$key_path" ] || exit 1
printf 'private key\n' > "$key_path"
printf 'ssh-ed25519 test %s\n' "$comment" > "${key_path}.pub"
STUB

    cat > "${stub_dir}/ssh-agent" <<'STUB'
#!/bin/sh
printf 'SSH_AUTH_SOCK=/tmp/dotfiles-smoke-agent.sock; export SSH_AUTH_SOCK;\n'
printf 'SSH_AGENT_PID=12345; export SSH_AGENT_PID;\n'
STUB

    cat > "${stub_dir}/ssh-add" <<'STUB'
#!/bin/sh
printf 'ssh-add %s\n' "$*" >> "$SSH_LOG"
STUB

    chmod +x "${stub_dir}/ssh-keygen" "${stub_dir}/ssh-agent" "${stub_dir}/ssh-add"
}

run_ssh_install() {
    local home_dir="$1"
    local mode="${2:-ask}"
    local log_file="$3"

    (
        export HOME="$home_dir"
        export PATH="${STUB_DIR}:/usr/bin:/bin"
        export SSH_LOG="$log_file"
        export DOTFILES_SSH_CONFIG_MODE="$mode"
        "${DOTFILES_DIR}/ssh.sh" "test@example.com" "work@example.com" > "${log_file}.out" 2>&1
    )
}

assert_keys_created() {
    local home_dir="$1"

    [ -f "${home_dir}/.ssh/id_ed25519" ] || fail "missing personal key"
    [ -f "${home_dir}/.ssh/id_ed25519.pub" ] || fail "missing personal public key"
    [ -f "${home_dir}/.ssh/id_ed25519_work" ] || fail "missing work key"
    [ -f "${home_dir}/.ssh/id_ed25519_work.pub" ] || fail "missing work public key"
}

assert_dotfiles_linked() {
    local home_dir="$1"
    local link_path="${home_dir}/.ssh/config.d/dotfiles.conf"

    [ -L "$link_path" ] || fail "missing dotfiles ssh config link"
    [ "$(readlink "$link_path")" = "${DOTFILES_DIR}/config/ssh/config" ] || fail "dotfiles ssh config link points elsewhere"
    [ -f "${home_dir}/.ssh/config.d/local.conf" ] || fail "missing local ssh config placeholder"
}

tmp_dir="$(mktemp -d)"
cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

STUB_DIR="${tmp_dir}/stubs"
mkdir -p "$STUB_DIR"
write_ssh_stubs "$STUB_DIR"

# No existing ~/.ssh/config: write include stub.
home_no_config="${tmp_dir}/home-no-config"
mkdir -p "$home_no_config"
run_ssh_install "$home_no_config" ask "${tmp_dir}/no-config.log"
assert_keys_created "$home_no_config"
assert_dotfiles_linked "$home_no_config"
[ "$(cat "${home_no_config}/.ssh/config")" = "Include config.d/*.conf" ] || fail "missing generated ssh config stub"

# Existing config with Include: preserve it.
home_include="${tmp_dir}/home-include"
mkdir -p "${home_include}/.ssh"
cat > "${home_include}/.ssh/config" <<'EOF'
Host example
  HostName example.com
Include config.d/*.conf
EOF
run_ssh_install "$home_include" ask "${tmp_dir}/include.log"
grep -q "Host example" "${home_include}/.ssh/config" || fail "existing include config was not preserved"
if ls "${home_include}/.ssh"/config.backup.* >/dev/null 2>&1; then
    fail "existing include config should not be backed up"
fi

# Existing config without Include: default ask in non-interactive mode preserves it.
home_preserve="${tmp_dir}/home-preserve"
mkdir -p "${home_preserve}/.ssh"
cat > "${home_preserve}/.ssh/config" <<'EOF'
Host legacy
  HostName legacy.example.com
EOF
run_ssh_install "$home_preserve" ask "${tmp_dir}/preserve.log"
grep -q "Host legacy" "${home_preserve}/.ssh/config" || fail "default ask mode should preserve existing config without TTY"
if ls "${home_preserve}/.ssh"/config.backup.* >/dev/null 2>&1; then
    fail "default ask mode should not back up preserved config"
fi

# Explicit replace: back up old config and write include stub.
home_replace="${tmp_dir}/home-replace"
mkdir -p "${home_replace}/.ssh"
cat > "${home_replace}/.ssh/config" <<'EOF'
Host old
  HostName old.example.com
EOF
run_ssh_install "$home_replace" replace "${tmp_dir}/replace.log"
[ "$(cat "${home_replace}/.ssh/config")" = "Include config.d/*.conf" ] || fail "replace mode did not write ssh config stub"
ls "${home_replace}/.ssh"/config.backup.* >/dev/null 2>&1 || fail "replace mode did not back up old ssh config"

echo "[INFO] ssh config smoke test passed"

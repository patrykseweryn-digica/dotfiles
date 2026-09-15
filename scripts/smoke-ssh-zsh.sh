#!/bin/bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

# shellcheck source=/dev/null
source "$DOTFILES_DIR/bootstrap.d/02-zsh.sh"
mkdir -p "$tmp_dir/home" "$tmp_dir/bin"
HOME="$tmp_dir/home" add_ssh_auto_zsh_snippet
cp "$tmp_dir/home/.profile" "$tmp_dir/expected"
HOME="$tmp_dir/home" add_ssh_auto_zsh_snippet
cmp "$tmp_dir/expected" "$tmp_dir/home/.profile"

# Substitute only Zsh; exercise the generated startup files in real Bash.
printf '#!/bin/sh\nprintf "ZSH_STARTED\\n"\n' > "$tmp_dir/bin/zsh"
chmod +x "$tmp_dir/bin/zsh"
for file in .profile .bashrc; do
    for flags in -c -ic; do
        output="$(env -u ZSH_VERSION HOME="$tmp_dir/home" \
            PATH="$tmp_dir/bin:$PATH" SSH_CONNECTION=test \
            bash --noprofile --norc "$flags" \
            '. "$HOME/$1"; printf "COMMAND_REACHED\n"' _ "$file" \
            </dev/null 2>"$tmp_dir/stderr")"
        if [ "$flags" = -ic ]; then
            [ "$output" = ZSH_STARTED ]
        else
            [ "$output" = COMMAND_REACHED ]
        fi
    done
done
printf '[INFO] SSH Zsh startup smoke test passed\n'

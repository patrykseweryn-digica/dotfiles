#!/bin/bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${DOTFILES_DIR}/scripts/host-tools.sh"
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

# Login shells that skip .zshrc, such as `zsh -lc` from agents, find mise
# tools through shims placed after Homebrew in ~/.zprofile.
if command -v zsh >/dev/null 2>&1; then
    zsh_bin="$(command -v zsh)"
    home="$tmp_dir/login-home"
    shims="$home/.local/share/mise/shims"
    brew_bin="$tmp_dir/brew/bin"
    mkdir -p "$home/.local/bin" "$shims" "$brew_bin"
    cat >"$home/.local/bin/mise" <<'STUB'
#!/bin/sh
[ "$*" = 'activate zsh --shims' ] || exit 1
printf 'export PATH="%s/.local/share/mise/shims:$PATH"\n' "$HOME"
STUB
    printf '#!/bin/sh\necho mise-demo\n' >"$shims/demo"
    printf '#!/bin/sh\necho brew-demo\n' >"$brew_bin/demo"
    printf '#!/bin/sh\necho "export PATH=\\"%s:\\$PATH\\""\n' "$brew_bin" \
        >"$brew_bin/brew"
    chmod +x "$home/.local/bin/mise" "$shims/demo" "$brew_bin/demo" \
        "$brew_bin/brew"
    login_demo() {
        env -i HOME="$home" PATH=/usr/bin:/bin "$zsh_bin" -lc demo 2>&1
    }
    printf '# local setting\neval "$(%s shellenv zsh)"\n' "$brew_bin/brew" \
        >"$home/.zprofile"
    [ "$(login_demo)" = brew-demo ] || {
        echo "[ERROR] fixture did not start with Homebrew first" >&2
        exit 1
    }
    if HOME="$home" mise_shims_profile_current; then
        echo "[ERROR] status accepted a profile without mise shims" >&2
        exit 1
    fi
    HOME="$home" configure_mise_shims_profile
    [ "$(login_demo)" = mise-demo ] || {
        echo "[ERROR] zsh -lc did not find the mise tool first" >&2
        exit 1
    }
    head -n 1 "$home/.zprofile" | grep -Fx '# local setting' >/dev/null || {
        echo "[ERROR] configure changed local profile lines" >&2
        exit 1
    }
    HOME="$home" mise_shims_profile_current || {
        echo "[ERROR] status rejected a configured profile" >&2
        exit 1
    }
    cp "$home/.zprofile" "$tmp_dir/zprofile-once"
    HOME="$home" configure_mise_shims_profile
    cmp -s "$tmp_dir/zprofile-once" "$home/.zprofile" || {
        echo "[ERROR] a second configure changed ~/.zprofile" >&2
        exit 1
    }
    # A Homebrew line added after the block puts Homebrew first again.
    printf 'eval "$(%s shellenv zsh)"\n' "$brew_bin/brew" >>"$home/.zprofile"
    if HOME="$home" mise_shims_profile_current; then
        echo "[ERROR] status accepted Homebrew after the mise block" >&2
        exit 1
    fi
    HOME="$home" configure_mise_shims_profile
    [ "$(login_demo)" = mise-demo ] || {
        echo "[ERROR] configure did not move the block after Homebrew" >&2
        exit 1
    }
    [ "$(grep -c 'dotfiles: mise shims' "$home/.zprofile")" -eq 2 ] || {
        echo "[ERROR] configure duplicated the mise block" >&2
        exit 1
    }
    # Without mise the block does nothing and login still works.
    mv "$home/.local/bin/mise" "$tmp_dir/mise-away"
    [ "$(login_demo)" = brew-demo ] || {
        echo "[ERROR] the block failed without mise" >&2
        exit 1
    }
    printf '[INFO] zsh -lc finds mise tools ahead of Homebrew\n'
fi
printf '[INFO] SSH Zsh startup smoke test passed\n'

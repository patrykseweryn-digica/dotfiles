#!/bin/bash
set -eu

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"
mkdir -p "$HOME"
# Source the actual setup entrypoint without running the full installer.
# shellcheck source=/dev/null
source "$DOTFILES_DIR/install.sh"
unset DOTFILES_FIRSTMATE_HOME
export FM_HOME="$tmp/runtime-home" FM_ROOT_OVERRIDE="$tmp/runtime-root"
setup_firstmate
[ ! -e "$FM_HOME" ] && [ ! -e "$FM_ROOT_OVERRIDE" ]

export DOTFILES_FIRSTMATE_HOME="$HOME/primary firstmate"
mkdir -p "$DOTFILES_FIRSTMATE_HOME/config"
config="$DOTFILES_FIRSTMATE_HOME/config"
printf 'pi\n' >"$config/secondmate-harness"
printf 'unchanged model\n' >"$config/crew-harness"
printf '{"other":true}\n' >"$config/unrelated.json"
cp -R "$config" "$tmp/before"
setup_firstmate
[ ! -L "$config/crew-dispatch.json" ]
cmp "$DOTFILES_DIR/config/firstmate/crew-dispatch.json" "$config/crew-dispatch.json"
# Repeat must not replace/reformat an equivalent pre-existing file.
jq -c . "$config/crew-dispatch.json" >"$tmp/equivalent.json"
cp "$tmp/equivalent.json" "$config/crew-dispatch.json"
setup_firstmate
cmp "$tmp/equivalent.json" "$config/crew-dispatch.json"
for file in "$tmp/before"/*; do
    cmp "$file" "$config/$(basename "$file")"
done
jq -e '
    [.rules[].use, .default] as $profiles |
    all($profiles[]; type == "object" and .harness == "codex"
        and (has("model") | not)) and
    ([$profiles[].effort] | sort == ["high", "low", "medium"]) and
    .default.effort == "medium" and
    all(.rules[]; (.when | type == "string" and length > 0))
' "$config/crew-dispatch.json" >/dev/null

for content in '{"default":{"harness":"claude"}}' '{broken'; do
    printf '%s\n' "$content" >"$config/crew-dispatch.json"
    cp "$config/crew-dispatch.json" "$tmp/conflict"
    if (
        set -e
        setup_dotfiles
    ) >"$tmp/error" 2>&1; then
        echo 'Expected conflicting dispatch to fail setup' >&2
        exit 1
    fi
    grep -q 'Conflicting Firstmate dispatch' "$tmp/error"
    cmp "$tmp/conflict" "$config/crew-dispatch.json"
    [ ! -e "$HOME/.local" ] # Conflict stops before unrelated setup.
done
rm "$config/crew-dispatch.json"
ln -s "$tmp/missing" "$config/crew-dispatch.json"
if setup_firstmate 2>"$tmp/error"; then exit 1; fi
[ -L "$config/crew-dispatch.json" ] && [ ! -e "$tmp/missing" ]
for home in 'relative/home' "$tmp/nonexistent"; do
    if DOTFILES_FIRSTMATE_HOME="$home" setup_firstmate 2>"$tmp/error"; then
        exit 1
    fi
    grep -q 'absolute Firstmate home with config/' "$tmp/error"
done
[ ! -e "$FM_HOME" ] && [ ! -e "$FM_ROOT_OVERRIDE" ]
echo '[OK] Firstmate configuration: fresh, repeat, isolation, conflicts'

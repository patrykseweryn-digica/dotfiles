#!/bin/bash
# Check that `make help` lists the same groups, commands and descriptions as
# the default `just` menu. Make spells just arguments differently:
#   enable group     -> enable group=NAME
#   export *args     -> export
#   `export skills`  -> `export-skills`
# `make test` works without just; then only the Make targets are checked.
set -eu -o pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
    echo "[ERROR] $*" >&2
    exit 1
}

make_help="$(make --no-print-directory -C "$DOTFILES_DIR" help)"

[ "$(make --no-print-directory -C "$DOTFILES_DIR")" = "$make_help" ] ||
    fail "make without a target must print help"

# Every command in the help must be a Make target with a recipe. A phony
# target without a rule would pass `make -n` silently.
targets="$(
    printf '%s\n' "$make_help" | sed -nE 's/^    ([a-z-]+).*/\1/p'
    printf '%s\n' "$make_help" | grep -oE '`[a-z]+-[a-z]+`' | tr -d '`'
)"
for target in $targets; do
    grep -q "^${target}:" "${DOTFILES_DIR}/Makefile" ||
        fail "make help lists a target without a rule: ${target}"
    make --no-print-directory -n -C "$DOTFILES_DIR" "$target" group=probe >/dev/null ||
        fail "make cannot plan target: ${target}"
done

if ! command -v just >/dev/null 2>&1; then
    echo "[SKIP] just is not installed; checked the Make targets only."
    exit 0
fi

just_menu="$(just --justfile "${DOTFILES_DIR}/justfile" --color never)"
expected="$(
    printf '%s\n' "$just_menu" | awk '
        $0 == "Available recipes:" { print "Available targets:"; next }
        /^    [a-z]/ {
            split($0, parts, " # ")
            count = split(parts[1], words, " ")
            line = "    " words[1]
            for (i = 2; i <= count; i++) {
                if (words[i] !~ /^[*+]/) line = line " " words[i] "=NAME"
            }
            doc = parts[2]
            while (match(doc, /`[a-z-]+ [a-z-]+`/)) {
                term = substr(doc, RSTART, RLENGTH)
                sub(/ /, "-", term)
                doc = substr(doc, 1, RSTART - 1) term substr(doc, RSTART + RLENGTH)
            }
            print line " # " doc
            next
        }
        { print }
    '
)"

# Compare words, not column widths.
actual="$(printf '%s\n' "$make_help" | sed -E 's/  +#/ #/')"
if ! diff -u <(printf '%s\n' "$expected") <(printf '%s\n' "$actual"); then
    fail "make help drifted from the just menu (- expected from just, + make help)"
fi

echo "make help matches the just menu."

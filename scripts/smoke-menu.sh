#!/bin/bash
# Check the default command menu of `just` and `make help`. Both pipe their
# command list into scripts/menu.sh, which prints the install group status.
# This script checks that:
#   - `make help` works without just and names make commands in the status;
#   - colors follow NO_COLOR and JUST_COLOR, lines stay below 80 columns,
#     and the descriptions of each list share one column;
#   - `just` shows the `just --list --unsorted` commands, with an optional
#     argument as `[group]` instead of `group=""`;
#   - `make help` lists the same groups, commands and descriptions as just.
#     Make spells just arguments differently:
#       group=""         -> [group=NAME]
#       name             -> name=NAME
#       export *args     -> export
#       `export skills`  -> `export-skills`
# `make test` works without just; then only the Make checks run.
set -eu -o pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
    echo "[ERROR] $*" >&2
    exit 1
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
unset DOTFILES_RUNNER group NO_COLOR JUST_COLOR
export DOTFILES_ENV_FILE="${tmp_dir}/groups.env"
printf '%s\n' 'DOTFILES_GROUPS=core,agents' >"$DOTFILES_ENV_FILE"

# Make must not need just: a just on PATH records the call and fails.
mkdir -p "${tmp_dir}/stubs"
printf '#!/bin/bash\ntouch "%s/just-called"\nexit 99\n' "$tmp_dir" \
    >"${tmp_dir}/stubs/just"
chmod +x "${tmp_dir}/stubs/just"

run_make() {
    PATH="${tmp_dir}/stubs:${PATH}" \
        make --no-print-directory -C "$DOTFILES_DIR" "$@"
}

run_just() {
    just --justfile "${DOTFILES_DIR}/justfile" "$@"
}

# Print the lines after the Commands title, or the lines before it.
commands() {
    sed '1,/^Commands$/d'
}

status() {
    sed '/^Commands$/,$d'
}

# Compare words, not column widths.
squeeze() {
    sed -E 's/  +#/ #/'
}

# The status names the selection and the runner's own commands. Hints and
# descriptions each start in one column, and no line reaches 80 columns.
check_menu() {
    local runner="$1" text="$2" enable="$3" disable="$4" head long
    [[ "$text" != *$'\033'* ]] || fail "piped $runner menu has colors"
    head="$(printf '%s\n' "$text" | status)"
    printf '%s\n' "$head" | grep -Fx 'dotfiles - 2 of 3 install groups selected' \
        >/dev/null || fail "$runner menu does not count the selected groups"
    for row in "✓ core .* required" "✓ agents .* ${disable}" \
        "○ desktop .* ${enable}"; do
        printf '%s\n' "$head" | grep -Ex "    ${row}" >/dev/null ||
            fail "$runner menu has no group row: ${row}"
    done
    printf '%s\n' "$head" |
        grep -Fx "New machine: run \`${runner} install\`, then \`${runner} machine\`." \
            >/dev/null || fail "$runner menu does not name the first step"
    [ "$(printf '%s\n' "$head" | awk '/^    (✓|○) / {
        print index($0, "required") + index($0, "'"$runner"' ")
    }' | sort -u | wc -l)" -eq 1 ] || fail "$runner menu hints are not aligned"
    [ "$(printf '%s\n' "$text" | commands | awk '/ # / { print index($0, " # ") }' |
        sort -u | wc -l)" -eq 1 ] ||
        fail "$runner menu descriptions are not aligned"
    # Count the two marks as one column each.
    long="$(printf '%s\n' "$text" | sed -e 's/✓/x/g' -e 's/○/x/g' |
        LC_ALL=C awk 'length($0) >= 80')"
    [ -z "$long" ] || fail "$runner menu line has 80 or more columns: ${long}"
}

make_help="$(run_make help)"
[ ! -e "${tmp_dir}/just-called" ] || fail "make help called just"
[ "$(run_make)" = "$make_help" ] || fail "make without a target must print help"
check_menu make "$make_help" 'make enable group=desktop' \
    'make disable group=agents'

colored="$(JUST_COLOR=always run_make help)"
[[ "$colored" == *$'\033[32m✓'* && "$colored" == *$'\033[1m[start]'* ]] ||
    fail "JUST_COLOR=always did not color make help"
colored="$(NO_COLOR=1 JUST_COLOR=always run_make help)"
[[ "$colored" != *$'\033'* ]] ||
    fail "NO_COLOR did not turn off the make help colors"

# An invalid setting shows its error, and the command list still follows.
printf '%s\n' 'DOTFILES_GROUPS=core,gaming' >"${tmp_dir}/invalid.env"
invalid="$(DOTFILES_ENV_FILE="${tmp_dir}/invalid.env" run_make help 2>&1)" ||
    fail "make help failed for an invalid setting"
[[ "$invalid" == *'Unknown install group "gaming"'* ]] ||
    fail "make help hid the invalid setting"
[ "$(printf '%s\n' "$invalid" | commands)" = "$(printf '%s\n' "$make_help" | commands)" ] ||
    fail "make help lost the command list for an invalid setting"

# Every command in the help must be a Make target with a recipe. A phony
# target without a rule would pass `make -n` silently.
targets="$(
    printf '%s\n' "$make_help" | commands | sed -nE 's/^    ([a-z-]+).*/\1/p'
    printf '%s\n' "$make_help" | grep -oE '`[a-z]+-[a-z]+`' | tr -d '`'
)"
for target in $targets; do
    grep -q "^${target}:" "${DOTFILES_DIR}/Makefile" ||
        fail "make help lists a target without a rule: ${target}"
    run_make -n "$target" group=probe >/dev/null ||
        fail "make cannot plan target: ${target}"
done

if ! command -v just >/dev/null 2>&1; then
    echo "[SKIP] just is not installed; checked the Make menu only."
    exit 0
fi

just_list="$(run_just --list --unsorted --list-heading '' --color never)"
just_menu="$(run_just)"
check_menu just "$just_menu" 'just enable desktop' 'just disable agents'
run_just groups | grep -Fx 'Install groups - 2 of 3 selected' >/dev/null ||
    fail "just groups does not count the selected groups"
colored="$(JUST_COLOR=always run_just)"
[[ "$colored" == *$'\033[1mCommands'* ]] ||
    fail "JUST_COLOR=always did not color the just menu"

# Rewrite the just list words: optional arguments for the just menu, or
# every argument for make help.
just_words() {
    awk -v runner="$1" -v q="'" '
        /^    [a-z]/ {
            split($0, parts, " # ")
            count = split(parts[1], words, " ")
            line = "    " words[1]
            for (i = 2; i <= count; i++) {
                word = words[i]
                optional = word ~ ("=(" q q "|\"\")$")
                name = word
                sub(/=.*/, "", name)
                if (runner == "just") {
                    line = line " " (optional ? "[" name "]" : word)
                } else if (word !~ /^[*+]/) {
                    line = line " " (optional ? "[" name "=NAME]" : name "=NAME")
                }
            }
            doc = parts[2]
            while (runner == "make" && match(doc, /`[a-z-]+ [a-z-]+`/)) {
                term = substr(doc, RSTART, RLENGTH)
                sub(/ /, "-", term)
                doc = substr(doc, 1, RSTART - 1) term substr(doc, RSTART + RLENGTH)
            }
            print line " # " doc
            next
        }
        { print }
    '
}

if ! diff -u <(printf '%s\n' "$just_list" | just_words just) \
    <(printf '%s\n' "$just_menu" | commands | squeeze); then
    fail "just menu changed the just --list commands (- just --list, + menu)"
fi
if ! diff -u <(printf '%s\n' "$just_list" | just_words make) \
    <(printf '%s\n' "$make_help" | commands | squeeze); then
    fail "make help drifted from the just menu (- expected from just, + make help)"
fi

echo "make help matches the just menu."

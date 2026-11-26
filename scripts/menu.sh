#!/bin/bash
# Print the default command menu of `just` and `make help`: the install group
# status, the first step on a new machine, and the command list. Each runner
# pipes its own list into stdin: `just --list`, or the Makefile help text,
# because make must work without just. The menu smoke test compares them.
set -uo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=scripts/groups.sh
source "${DOTFILES_DIR}/scripts/groups.sh"

if [ -t 0 ]; then
    echo "Usage: <command list> | $0" >&2
    exit 1
fi

groups_colors
# An invalid group setting prints its error; the command list still follows.
if groups_load; then
    printf '%sdotfiles - %s install groups selected%s\n' \
        "$GROUPS_BOLD" "$(groups_count)" "$GROUPS_RESET"
    groups_table
else
    printf '%sdotfiles%s\n' "$GROUPS_BOLD" "$GROUPS_RESET"
fi
printf '\nNew machine: run `%s`, then `%s`.\n\n' \
    "$(dotfiles_command install)" "$(dotfiles_command machine)"
printf '%sCommands%s\n' "$GROUPS_BOLD" "$GROUPS_RESET"

# Just has no syntax for an optional argument, so its recipes declare an
# empty default: `enable group=''`. Show that argument as `[group]`, then
# align the descriptions again. Bold the [group] titles.
awk -v bold="$GROUPS_BOLD" -v reset="$GROUPS_RESET" -v q="'" '
    function render(command,    count, i, word, words, out) {
        count = split(command, words, " ")
        out = words[1]
        for (i = 2; i <= count; i++) {
            word = words[i]
            if (word ~ ("^[a-z_-]+=(" q q "|\"\")$")) {
                sub(/=.*/, "", word)
                word = "[" word "]"
            }
            out = out " " word
        }
        return out
    }
    {
        lines[NR] = $0
        split_at = index($0, " # ")
        if ($0 ~ /^    [a-z]/ && split_at) {
            commands[NR] = render(substr($0, 5, split_at - 5))
            docs[NR] = substr($0, split_at + 3)
            if (length(commands[NR]) > width) width = length(commands[NR])
        }
    }
    END {
        for (n = 1; n <= NR; n++) {
            if (n in commands) {
                printf "    %-" width "s # %s\n", commands[n], docs[n]
            } else if (lines[n] ~ /^    \[.*\]$/) {
                print "    " bold substr(lines[n], 5) reset
            } else {
                print lines[n]
            }
        }
    }
'

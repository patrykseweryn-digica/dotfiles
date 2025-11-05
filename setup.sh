#!/bin/bash

# Enable shell script strictness
set -eu
# Enable command tracing
set -x
# Ensure config directory exists
mkdir -p ~/.config
# Link Git config if it doesn’t exist
[ ! -e ~/.config/git ] && ln -s "$PWD/config/git" ~/.config/git
# Link Python startup file if it doesn't exist
[ ! -e ~/.pythonrc.py ] && ln -s "$PWD/pythonrc.py" ~/.pythonrc.py
# Source aliases in shell config
if [ ! -z "${ZDOTDIR:-}" ]; then
    RC_FILE="$ZDOTDIR/.zshrc"
else
    RC_FILE="$HOME/.zshrc"
fi

if [ -f "$RC_FILE" ] && ! grep -q "source.*aliases.sh" "$RC_FILE"; then
    echo "source $PWD/aliases.sh" >>"$RC_FILE"
fi
# Load variables from config file
if [ -f "$PWD/config.sh" ]; then
    source "$PWD/config.sh"
else
    echo "Error: config.sh file not found in $PWD"
    exit 1
fi
# Source aliases
source "$PWD/aliases.sh"
# Setup SSH key
"$PWD/ssh.sh" "$EMAIL"

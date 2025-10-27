#!/bin/sh

# Enable shell script strictness
set -eu
# Enable command tracing
set -x
# Ensure config directory exists
mkdir -p ~/.config
# Link Git config if it doesn’t exist
[ ! -e ~/.config/git ] && ln -s "$PWD/config/git" ~/.config/git
# Link Python startup file if it doesn’t exist
[ ! -e ~/.pythonrc.py ] && ln -s "$PWD/pythonrc.py" ~/.pythonrc.py

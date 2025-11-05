#!/bin/sh

# Check if SSH key already exists
if [ -f ~/.ssh/id_ed25519 ]; then
    echo "SSH key already exists. Skipping SSH key generation."
    exit 0
fi

echo "Generating a new SSH key for GitHub..."

# Generating a new SSH key
# https://docs.github.com/en/github/authenticating-to-github/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent#generating-a-new-ssh-key
ssh-keygen -t ed25519 -C $1 -f ~/.ssh/id_ed25519

# Adding your SSH key to the ssh-agent
# https://docs.github.com/en/github/authenticating-to-github/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent#adding-your-ssh-key-to-the-ssh-agent
eval "$(ssh-agent -s)"

touch ~/.ssh/config
cat "$PWD/config/ssh/config" >>~/.ssh/config

ssh-add -K ~/.ssh/id_ed25519

# Adding your SSH key to your GitHub account
# https://docs.github.com/en/github/authenticating-to-github/adding-a-new-ssh-key-to-your-github-account
echo "run 'xclip -selection clipboard < ~/.ssh/id_ed25519.pub' and paste that into GitHub"

#!/bin/bash
# If not running interactively, don't do anything
case $- in
*i*) ;;
*) return ;;
esac

# History
HISTCONTROL=ignoreboth
shopt -s histappend
HISTSIZE=1000
HISTFILESIZE=2000

# Window size check after each command
shopt -s checkwinsize

# Color support
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    alias grep='grep --color=auto'
fi

# Basic aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# Bash completion
if ! shopt -oq posix; then
    if [ -f /usr/share/bash-completion/bash_completion ]; then
        . /usr/share/bash-completion/bash_completion
    elif [ -f /etc/bash_completion ]; then
        . /etc/bash_completion
    fi
fi

# PATH
export PATH="$HOME/.local/bin:$PATH"

# NVM (if installed)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# Prompt: user:dir (branch) $
parse_git_branch() {
    git branch 2>/dev/null | grep '\*' | sed 's/* \(.*\)/ (\1)/'
}
PS1='\u:\W$(parse_git_branch) \$ '

# Machine-specific overrides
# shellcheck source=/dev/null
[ -f ~/.bashrc.local ] && . ~/.bashrc.local

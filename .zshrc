# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Local binaries (early, so tools in ~/.local/bin are available during init)
export PATH="${HOME}/.local/bin:${HOME}/.cargo/bin:$PATH"

export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"

fpath+=${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions/src
fpath+=~/.zfunc

plugins=(
	git
	git-flow
	python
	docker
	npm
	zsh-autosuggestions
	zsh-syntax-highlighting
	zsh-bat
	you-should-use
)
source $ZSH/oh-my-zsh.sh

# SSH host completion from ~/.ssh/config
zstyle ':completion:*:(ssh|scp|sftp):*' hosts $(awk '/^Host / && !/\*/ {print $2}' ~/.ssh/config)

# zoxide (smart cd, replaces z plugin)
eval "$(zoxide init zsh)"

# uv shell completions
eval "$(uv generate-shell-completion zsh)"

# NVM
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# Source aliases
[[ ! -f ~/.aliases ]] || source ~/.aliases

# Python startup file (set at the end to override any other settings)
export PYTHONSTARTUP="${HOME}/.pythonrc.py"

# Summarize plugin default model
export SUMMARIZE_MODEL="cli/claude"

# Project templates
new-project() {
  local name="${1?Usage: new-project <project-name>}"
  uvx copier copy --trust gh:p-severin/python-repo-template "$name"
}

new-project-digica() {
  local name="${1?Usage: new-project-digica <project-name>}"
  uvx copier copy --trust gh:patrykseweryn-digica/python-repo-template "$name"
}

# Load environment variables from .env
set -a; [[ -f ~/dotfiles/.env ]] && source ~/dotfiles/.env; set +a

# Local per-machine overrides (not tracked in dotfiles)
[[ ! -f ~/.zshrc.local ]] || source ~/.zshrc.local

# bun
export BUN_INSTALL="$HOME/.bun"
[ -s "$BUN_INSTALL/_bun" ] && source "$BUN_INSTALL/_bun"
export PATH="$BUN_INSTALL/bin:$PATH"

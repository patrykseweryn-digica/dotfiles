# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Local binaries (early, so tools are available during init)
export PATH="${HOME}/dotfiles/bin:${HOME}/.local/bin:${HOME}/.cargo/bin:$PATH"

export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"

zsh_completions_dir="${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions/src"
[[ ! -d "$zsh_completions_dir" ]] || fpath+=("$zsh_completions_dir")
[[ ! -d "$HOME/.zfunc" ]] || fpath+=("$HOME/.zfunc")
unset zsh_completions_dir

plugins=(
	git
	git-flow
	python
	docker
	npm
	fzf-tab
	zsh-autosuggestions
	zsh-syntax-highlighting
	zsh-bat
	you-should-use
)
[[ ! -r "$ZSH/oh-my-zsh.sh" ]] || source "$ZSH/oh-my-zsh.sh"

if ! whence -w compdef >/dev/null 2>&1; then
  autoload -Uz compinit
  compinit
fi

# SSH host completion from ~/.ssh/config
if [[ -r "$HOME/.ssh/config" ]]; then
  zstyle ':completion:*:(ssh|scp|sftp):*' hosts ${(f)"$(awk '/^Host / && !/\*/ {print $2}' "$HOME/.ssh/config")"}
fi

# zoxide (smart cd, replaces z plugin)
if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
fi

# uv shell completions
if command -v uv >/dev/null 2>&1; then
  eval "$(uv generate-shell-completion zsh)"
fi

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

# Load environment variables from dotfiles .env
dotfiles_env_file="${DOTFILES_ENV_FILE:-}"
if [[ -z "$dotfiles_env_file" ]]; then
  dotfiles_zshrc_path="${(%):-%x}"
  if [[ -n "$dotfiles_zshrc_path" ]]; then
    dotfiles_env_file="${dotfiles_zshrc_path:A:h}/.env"
  else
    dotfiles_env_file="$HOME/dotfiles/.env"
  fi
  unset dotfiles_zshrc_path
fi
if [[ -f "$dotfiles_env_file" ]]; then
  set -a
  source "$dotfiles_env_file"
  set +a
fi
unset dotfiles_env_file

# Local per-machine overrides (not tracked in dotfiles)
[[ ! -f ~/.zshrc.local ]] || source ~/.zshrc.local

# bun
export BUN_INSTALL="$HOME/.bun"
[ -s "$BUN_INSTALL/_bun" ] && source "$BUN_INSTALL/_bun"
export PATH="$BUN_INSTALL/bin:$PATH"

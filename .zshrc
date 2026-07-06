if [ -z "${ZSH_VERSION:-}" ]; then
  echo "This file is for zsh. Run: exec zsh -l" >&2
  return 1 2>/dev/null || exit 1
fi

# SSH agent setup may prompt for passphrases, so keep it before p10k instant prompt.
dotfiles_ssh_agent_live() {
  [[ -n "${SSH_AUTH_SOCK:-}" ]] || return 1
  ssh-add -l >/dev/null 2>&1
  case $? in
    0|1) return 0 ;;
    *) return 1 ;;
  esac
}

dotfiles_ssh_key_loaded() {
  local key="$1"
  local pub="${key}.pub"
  local fingerprint

  [[ -r "$pub" ]] || return 1
  command -v ssh-keygen >/dev/null 2>&1 || return 1
  fingerprint="$(ssh-keygen -lf "$pub" 2>/dev/null | awk '{print $2}')" || return 1
  [[ -n "$fingerprint" ]] || return 1
  ssh-add -l 2>/dev/null | grep -Fq "$fingerprint"
}

dotfiles_ssh_add_key() {
  local key="$1"

  [[ -r "$key" ]] || return 0
  dotfiles_ssh_key_loaded "$key" && return 0

  if [[ "$(uname -s)" == "Darwin" ]]; then
    ssh-add --apple-use-keychain -q "$key" >/dev/null 2>&1 ||
      ssh-add -q "$key" >/dev/null 2>&1 ||
      true
  else
    ssh-add -q "$key" >/dev/null 2>&1 || true
  fi
}

dotfiles_start_ssh_agent() {
  [[ "${DOTFILES_SKIP_SSH_AGENT:-false}" == "true" ]] && return 0
  command -v ssh-agent >/dev/null 2>&1 || return 0
  command -v ssh-add >/dev/null 2>&1 || return 0
  [[ -r "$HOME/.ssh/id_ed25519" || -r "$HOME/.ssh/id_ed25519_work" ]] || return 0

  local agent_env="$HOME/.ssh/agent.env"
  local tmp_env
  local agent_output

  if ! dotfiles_ssh_agent_live && [[ -r "$agent_env" ]]; then
    source "$agent_env" >/dev/null 2>&1 || true
  fi

  if ! dotfiles_ssh_agent_live; then
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh" 2>/dev/null || true
    tmp_env="${agent_env}.$$"
    agent_output="$(ssh-agent -s 2>/dev/null)" || return 0
    print -r -- "$agent_output" | sed '/^echo /d' > "$tmp_env" || {
      rm -f "$tmp_env"
      return 0
    }
    chmod 600 "$tmp_env"
    source "$tmp_env" >/dev/null 2>&1 || {
      rm -f "$tmp_env"
      return 0
    }
    mv "$tmp_env" "$agent_env"
  fi

  dotfiles_ssh_add_key "$HOME/.ssh/id_ed25519"
  dotfiles_ssh_add_key "$HOME/.ssh/id_ed25519_work"
}

dotfiles_start_ssh_agent
unfunction dotfiles_ssh_agent_live dotfiles_ssh_key_loaded dotfiles_ssh_add_key dotfiles_start_ssh_agent 2>/dev/null || true

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

# Added by LM Studio CLI (lms)
export PATH="$PATH:/Users/patrykseweryn/.lmstudio/bin"
# End of LM Studio CLI section

# pnpm
export PNPM_HOME="/Users/patrykseweryn/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME/bin:"*) ;;
  *) export PATH="$PNPM_HOME/bin:$PATH" ;;
esac
# pnpm end

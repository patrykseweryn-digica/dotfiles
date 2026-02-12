# Dotfiles TODO

## Done

- [x] ripgrep (`rg`) - szybkie wyszukiwanie w kodzie
- [x] fd - szybki zamiennik `find`
- [x] eza - nowoczesne `ls` z ikonami i git status
- [x] delta - syntax-highlighted git diff pager
- [x] zoxide - inteligentne `cd` (zamiennik pluginu `z`)
- [x] delta jako git pager (`core.pager`, `interactive.diffFilter`)
- [x] zoxide init w `.zshrc`
- [x] Aliasy eza (warunkowe, z fallbackiem)
- [x] tldr (`tealdeer`) - praktyczne przyklady zamiast man pages
- [x] lazygit - wizualny TUI do gita (rebase, staging, konflikty)
- [x] `merge.conflictstyle = zdiff3` - oryginalny tekst w konfliktach
- [x] `diff.algorithm = histogram` - czytelniejsze diffi
- [x] `push.autoSetupRemote = true` - auto-tracking przy pierwszym pushu
- [x] `rebase.autoStash = true` - auto-stash przed rebase
- [x] `rerere.enabled = true` - zapamietuje rozwiazania konfliktow
- [x] `branch.sort = -committerdate` - ostatnio uzywane branche na gorze
- [x] `fetch.prune = true` - czysci zdalne branche ktore juz nie istnieja

## Tier 3: Tmux

- [x] tpm (plugin manager)
- [x] tmux-resurrect - save/restore sesji po reboocie
- [x] tmux-continuum - automatyczny zapis co 15 min
- [x] `set -sg escape-time 0` - brak opoznienia Esc (krytyczne dla vima)
- [x] `set -g mouse on` - mysz do resize paneli
- [x] `set -g base-index 1` - okna od 1
- [x] `set -g renumber-windows on` - renumeracja po zamknieciu

## Tier 4: Zsh

- [x] zsh-completions - 300+ dodatkowych uzupelnien tab

## Inne

- [ ] `.env.example` - zamienic prawdziwy email na placeholder
- [ ] `.zshrc` - wyczyscic zakomentowany boilerplate oh-my-zsh
- [x] `.zshrc` - dodac `source ~/.zshrc.local` na lokalne ustawienia per-maszyna

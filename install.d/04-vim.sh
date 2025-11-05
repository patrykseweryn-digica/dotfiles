#!/bin/bash

install_vim() {
    log_info "Checking vim installation..."

    if check_installed vim; then
        log_info "vim is already installed"
        vim --version | head -n 1
    else
        if [ "$HAS_SUDO" = true ]; then
            log_info "Installing vim via package manager..."

            # Detect package manager and install
            if command -v apt-get >/dev/null 2>&1; then
                sudo apt-get update && sudo apt-get install -y vim
            elif command -v yum >/dev/null 2>&1; then
                sudo yum install -y vim
            elif command -v dnf >/dev/null 2>&1; then
                sudo dnf install -y vim
            elif command -v pacman >/dev/null 2>&1; then
                sudo pacman -S --noconfirm vim
            elif command -v brew >/dev/null 2>&1; then
                brew install vim
            else
                log_error "No supported package manager found"
                return 1
            fi
        else
            log_warn "No sudo access. Installing vim from source to ${OPT_DIR}/vim..."

            # Install dependencies if possible, otherwise warn
            log_info "Note: vim compilation requires ncurses development headers"

            # Clone vim from GitHub
            VIM_TMP="/tmp/vim"
            rm -rf "${VIM_TMP}"
            git clone --depth 1 https://github.com/vim/vim.git "${VIM_TMP}"
            cd "${VIM_TMP}"

            ./configure \
                --prefix="${OPT_DIR}/vim" \
                --enable-multibyte \
                --enable-pythoninterp=dynamic \
                --enable-python3interp=dynamic \
                --with-features=huge \
                --disable-gui

            make
            make install

            # Create symlink in bin directory
            ln -sf "${OPT_DIR}/vim/bin/vim" "${BIN_DIR}/vim"
            ln -sf "${OPT_DIR}/vim/bin/vim" "${BIN_DIR}/vi"

            cd "${DOTFILES_DIR}"
            rm -rf "${VIM_TMP}"

            log_info "vim compiled and installed to ${OPT_DIR}/vim"
        fi
    fi

    # Verify installation
    if ! check_installed vim; then
        log_error "Failed to install vim"
        return 1
    fi

    # Install vim-plug (plugin manager)
    log_info "Installing vim-plug plugin manager..."

    VIMPLUG_FILE="${HOME}/.vim/autoload/plug.vim"
    if [ ! -f "$VIMPLUG_FILE" ]; then
        curl -fLo "$VIMPLUG_FILE" --create-dirs \
            https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
        log_info "vim-plug installed successfully"
    else
        log_info "vim-plug already installed"
    fi

    # Create .vimrc with recommended plugins
    VIMRC="${HOME}/.vimrc"
    if [ ! -f "$VIMRC" ]; then
        log_info "Creating .vimrc with recommended plugins..."
        cat >"$VIMRC" <<'EOF'
" vim-plug plugin manager
call plug#begin('~/.vim/plugged')

" File explorer
Plug 'preservim/nerdtree'

" Status bar
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'

" Git integration
Plug 'tpope/vim-fugitive'
Plug 'airblade/vim-gitgutter'

" Fuzzy finder
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim'

" Auto pairs for brackets
Plug 'jiangmiao/auto-pairs'

" Comment toggling
Plug 'tpope/vim-commentary'

" Syntax highlighting and language support
Plug 'sheerun/vim-polyglot'

" Color schemes
Plug 'morhetz/gruvbox'
Plug 'joshdick/onedark.vim'

" Autocompletion (lightweight)
Plug 'neoclide/coc.nvim', {'branch': 'release'}

call plug#end()

" Basic settings
set number                    " Show line numbers
set relativenumber            " Show relative line numbers
set tabstop=4                 " Tab width
set shiftwidth=4              " Indent width
set expandtab                 " Use spaces instead of tabs
set autoindent                " Auto indent
set smartindent               " Smart indent
set wrap                      " Wrap lines
set ignorecase                " Case insensitive search
set smartcase                 " Case sensitive when uppercase present
set hlsearch                  " Highlight search results
set incsearch                 " Incremental search
set mouse=a                   " Enable mouse support
set clipboard=unnamedplus     " Use system clipboard
set encoding=utf-8            " UTF-8 encoding
set fileencoding=utf-8        " File encoding
set cursorline                " Highlight current line
set wildmenu                  " Command completion
set laststatus=2              " Always show status line
set backspace=indent,eol,start " Backspace behavior

" Color scheme
syntax enable
set background=dark
try
    colorscheme gruvbox
catch
    colorscheme desert
endtry

" Key mappings
let mapleader = " "           " Leader key as space

" NERDTree
nnoremap <leader>n :NERDTreeToggle<CR>
nnoremap <leader>f :NERDTreeFind<CR>

" FZF
nnoremap <leader>p :Files<CR>
nnoremap <leader>b :Buffers<CR>
nnoremap <leader>g :Rg<CR>

" Quick save and quit
nnoremap <leader>w :w<CR>
nnoremap <leader>q :q<CR>

" Split navigation
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l

" Clear search highlight
nnoremap <leader><space> :nohlsearch<CR>

" Auto commands
" Install plugins on first launch
if empty(glob('~/.vim/plugged'))
  autocmd VimEnter * PlugInstall --sync | source $MYVIMRC
endif
EOF
        log_info ".vimrc created successfully"
    else
        log_info ".vimrc already exists, skipping creation"
    fi

    log_info "vim installation complete"
    log_info "Run ':PlugInstall' inside vim to install plugins"
}

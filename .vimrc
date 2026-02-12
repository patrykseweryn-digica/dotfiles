" vim-plug plugin manager
call plug#begin('~/.vim/plugged')

" Status bar
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'

" Git changes in gutter
Plug 'airblade/vim-gitgutter'

" Comment toggling (gcc to toggle)
Plug 'tpope/vim-commentary'

" Syntax highlighting and language support
Plug 'sheerun/vim-polyglot'

" Color scheme
Plug 'morhetz/gruvbox'

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

" Install plugins on first launch
if empty(glob('~/.vim/plugged'))
  autocmd VimEnter * PlugInstall --sync | source $MYVIMRC
endif

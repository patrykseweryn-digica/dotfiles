let s:vim_plug_path = stdpath('data') . '/site/autoload/plug.vim'
let s:plugin_dir = stdpath('data') . '/plugged'

if empty(glob(s:vim_plug_path))
  silent execute '!curl -fLo ' . shellescape(s:vim_plug_path) . ' --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'
  if v:shell_error
    echoerr 'vim-plug is missing and could not be installed automatically'
    finish
  endif
endif

call plug#begin(s:plugin_dir)

Plug 'ibhagwan/fzf-lua'
Plug 'lewis6991/gitsigns.nvim'
Plug 'ThePrimeagen/vim-be-good'
Plug 'tanvirtin/monokai.nvim'

call plug#end()

if !empty(filter(values(g:plugs), '!isdirectory(v:val.dir)'))
  autocmd VimEnter * PlugInstall --sync | source $MYVIMRC
endif

set number
set relativenumber

try
  colorscheme monokai
catch
  colorscheme default
endtry
set termguicolors
set background=dark

let s:vim_plug_path = stdpath('data') . '/site/autoload/plug.vim'
let s:plugin_dir = stdpath('data') . '/plugged'
let s:install_plugins = empty(glob(s:plugin_dir))

if empty(glob(s:vim_plug_path))
  silent execute '!curl -fLo ' . shellescape(s:vim_plug_path) . ' --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'
  if v:shell_error
    echoerr 'vim-plug is missing and could not be installed automatically'
    finish
  endif
  let s:install_plugins = 1
endif

call plug#begin(s:plugin_dir)

Plug 'ThePrimeagen/vim-be-good'
Plug 'tanvirtin/monokai.nvim'

call plug#end()

if s:install_plugins
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

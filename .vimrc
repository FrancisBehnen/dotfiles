map ; :

set clipboard=unnamed,unnamedplus

filetype on
filetype plugin indent on

augroup json_folding
  autocmd!
  autocmd FileType json setlocal foldmethod=indent
augroup END


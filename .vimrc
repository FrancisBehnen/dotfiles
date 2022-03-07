set nocompatible    " vim settings, no vi settings

syntax enable       " Syntax highlighting
set ai              " auto indent
set ruler           " show cursor position
set number          " show line numbers
set scrolloff=4     " number of lines to keep before/after cursor
set sidescrolloff=5 " number of columns to keep to left/right of cursor
set wrap            " line soft-wraps
set showmode        " show current mode
set showcmd         " show commands
set mouse=a			" allow mouse interaction

filetype plugin on      " use the file type plugins
set encoding=utf-8      " well duh
set termencoding=utf-8  " duh

set tabstop=4           " a tab is 4 spaces
set softtabstop=4       " pretend like tab is removed, even when removing spaces
set noexpandtab         " expand tabs to spaces by default
set shiftwidth=4        " number of spaces to use for auto indenting
set shiftround          " when shifting lines, round indentation to nearest multiple of shiftwidth
set backspace=indent,eol,start  " allow backspacing over everythin in insert mode
set autoindent          " always auto indent
set copyindent          " copy the previous indentation on autoindenting

set showmatch   " show matching paranthesis
set smarttab    " insert tabs on start of a line according to shiftwidth, not tabstop

set hlsearch    " highlight search terms
set incsearch   " show search matches as you type
set ignorecase  " ignore case when searching
set smartcase   " don't ignore case when capital in search

set undolevels=1000 " many undoes!

set wildmenu        " make tab completion for files/buffers act like bash
set wildmode=list:full  " show a list when pressing tab and complete first full match

set nomodeline  " disable mode line from files (security)

" move up/down display lines instead of physical lines
nnoremap j gj
nnoremap k gk

set ttyfast
set laststatus=2

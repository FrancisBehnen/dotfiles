# Dotfiles

## Installation
To initialize a bare repository, run:
```bash
git init --bare $HOME/.dotfiles
```

Then add the following alias to your `.bashrc` or `.zshrc`:
```zsh
alias config='/usr/bin/git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'
```

Make sure to configure the git repository you just created to not show untracked files unless you specifically add them:
```bash
config config --local status.showUntrackedFiles no
```

## Usage
To use, simply add any files you want to keep track of using the created `config` alias:
```bash
config add .zshrc
config commit
config push
```

Be aware that any files not added to the repository will not be shown!

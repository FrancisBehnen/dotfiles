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

### Cloning existing dotfiles repository on new machine
If you want to install an already existig dotfiles repository on a new machine, you can simply clone the existing repository, but be mindful of some extra possible steps.

First of all,  make sure you have committed the above `config` alias to your `.zshrc` or `.bashrc`.
Also, be sure that the folder that you are storing the repository in is excluded in your `.gitignore` file.
As an example, in this repository that means that `.dotfiles` is added to the `.gitignore` file: https://github.com/Fastjur/dotfiles/blob/main/.gitignore#L1

Then you are ready to clone the repository on a new machine:
```bash
git clone --bare --recurse-submodules <git-repo-url> $HOME/.dotfiles
```

Note the `--recurse-submodules` flag, this is used to clone installations of, per example, oh-my-zsh plugins such as [powerlevel10k](https://github.com/romkatv/powerlevel10k).
(For an example in this repository, see [this commit](https://github.com/Fastjur/dotfiles/commit/e1dd2916753f68feeb4ddffdb0e4986d79e03815)).

## Usage
To use, simply add any files you want to keep track of using the created `config` alias:
```bash
config add .zshrc
config commit
config push
```

Be aware that any files not added to the repository will not be shown!

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

First of all, copy-paste the above `alias config...` command to your terminal, to add it once the current shell scope.
This is needed because your custom `.zshrc` is not yet cloned.
Also, be sure that the folder that you are storing the repository in is excluded in your `.gitignore` file.
As an example, in this repository that means that `.dotfiles` is added to the `.gitignore` file: https://github.com/Fastjur/dotfiles/blob/main/.gitignore#L1

Then you are ready to clone the repository on a new machine
```bash
git clone --bare --recurse-submodules <git-repo-url> $HOME/.dotfiles
```
and to check it out:
```bash
config checkout
```

Note the `--recurse-submodules` flag, this is used to clone installations of, per example, oh-my-zsh plugins such as [powerlevel10k](https://github.com/romkatv/powerlevel10k).
(For an example of submodule definities in this repository, see [this file](https://github.com/Fastjur/dotfiles/blob/main/.gitmodules) or [this commit](https://github.com/Fastjur/dotfiles/commit/6f4b5010a54d9011265993fbca5c97a4ba22a135)).

If the repository has already been cloned, and you need to update/initialize the submodules, run the following command:
```bash
config submodule update --init --recursive
```

This will initialize and update the submodules such that your dotfiles repository starts tracking them.

Also, do not forget to again set `showUntrackedFiles` to `no`:
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

### Adding submodules
If you want to add submodules, per example to install new `oh-my-zsh` plugins or themes, the easiest step is to follow the plugin/theme instructions, but instead of running `git clone`, instead run `config submodule add <plugin/theme git url> <plugin/theme installation location>`

#### oh-my-zsh custom plugins and themes
By default, `oh-my-zsh` ignores the `.oh-my-zsh/custom` folder.
Anything installed using the above steps as submodules will be ignored, and thus not work with your dotfile repository.
The easiest solution is to alter the `$ZSH_CUSTOM` variable in your [`.zshrc`](https://github.com/Fastjur/dotfiles/blob/main/.zshrc#L88), and install all custom plugins/themes into that directory as submodules, instead of in the `.oh-my-zsh` main directory.
This way these custom plugins and directories are not ignored.
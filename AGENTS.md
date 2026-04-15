# Dotfiles Repository

This is a **bare git repository** (`$HOME/.dotfiles`) with the work tree set to `$HOME`.
The home folder IS the repo — treat every file here as potentially personal/untracked.

## Critical Rules

### Use `config` instead of `git`
All git operations MUST use the `config` alias:
```bash
config status
config add .zshrc
config commit -m "..."
config push
```
The alias is: `/usr/bin/git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME`

### Never add files without explicit approval
`status.showUntrackedFiles` is set to `no` — only tracked files appear.
**Never** run `config add .` or `config add -A`. Only add files the user explicitly names.
The home folder contains thousands of personal files, applications, caches, and secrets.

### Never read untracked files
Do not read or explore files not tracked by this repo unless the user asks.
List tracked files with `config ls-tree -r --name-only HEAD`.

### Submodules
Custom oh-my-zsh plugins live in `.oh-my-zsh_custom/` (not inside `.oh-my-zsh/`)
to avoid nested submodules. Managed via `config submodule`.

### Remotes
- `origin` = user's fork (`FrancisBehnen/dotfiles`)
- `upstream` = original repo (`Fastjur/dotfiles`)

### Shell functions
Custom shell functions go in `.shell_functions`, not `.zshrc`.
PATH additions go at the bottom of `.zshrc`.

### Package management
The `vintage` function in `.shell_functions` installs specific older versions
of Homebrew formulas/casks via the `homebrew/local` tap. These version-pinned
casks are safe from `brew upgrade`.

# Dotfiles

## Installation
To initialize a bare repository, run:
```bash
git init --bare $HOME/.dotfiles
```

Then add the following alias to your `.zshrc`:
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
As an example, in this repository that means that `.dotfiles` is added to the `.gitignore` file: https://github.com/FrancisBehnen/dotfiles/blob/main/.gitignore#L1

Then you are ready to clone the repository on a new machine
```bash
git clone --bare <git-repo-url> $HOME/.dotfiles
```
and to check it out:
```bash
config checkout
```

Then initialize submodules (oh-my-zsh, powerlevel10k, plugins). This step is required — `--recurse-submodules` does not work with bare clones:
```bash
config submodule update --init --recursive
```

(For an example of submodule definitions in this repository, see [this file](https://github.com/FrancisBehnen/dotfiles/blob/main/.gitmodules) or [this commit](https://github.com/FrancisBehnen/dotfiles/commit/6f4b5010a54d9011265993fbca5c97a4ba22a135)).

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
Installing a submodule in a folder of another submodule is not supported by git.
Therefore, before installing custom oh-my-zsh themes you should alter the `$ZSH_CUSTOM` variable in your [`.zshrc`](https://github.com/FrancisBehnen/dotfiles/blob/main/.zshrc#L88) to for example `ZSH_CUSTOM=$HOME/.oh-my-zsh_custom`, and install all custom plugins/themes into that directory.
This way these custom plugins are "top-level" submodules of your dotfiles repo, next to oh-my-zsh itself.

### Installing pinned Homebrew versions with `vintage`

Some apps need a specific older version (e.g. due to licensing or OS compatibility). The `vintage` function in `.shell_functions` installs a pinned version via the `homebrew/local` tap:

```bash
vintage <formula-or-cask> <version>
```

For example:
```bash
vintage bettertouchtool 2.716
vintage google-drive 113.0.1
```

These version-pinned casks use a separate name (e.g. `bettertouchtool2.716`) and are not affected by `brew upgrade`.

### Migrating application preferences

Application preference files (e.g. for BetterTouchTool and iTerm2) are tracked in `support_and_preference_files_to_migrate/Home/`, mirroring their path relative to `~/`.

On a new machine, after installing the apps, run the link script to symlink them into place:
```bash
cd ~/support_and_preference_files_to_migrate
./link_preferences.zsh
```

See `support_and_preference_files_to_migrate/README.md` for details and caveats.

### Setting up Claude Code

The dotfiles repo tracks Claude Code's portable configuration:
- `.claude/settings.json` — model, plugins, effort level, statusline
- `.claude/settings.local.json` — project-specific permissions (paths may need adjusting)
- `.claude/statusline.sh` — custom statusline script
- `.claude/rules/common/shell.md` — custom rules specific to this setup

After cloning and checking out dotfiles on a new machine:

1. **Install Claude Code** and sign in
2. **Install rules** from [everything-claude-code](https://github.com/affaan-m/everything-claude-code):
   ```bash
   git clone https://github.com/affaan-m/everything-claude-code.git ~/Documents/Code/everything-claude-code
   cd ~/Documents/Code/everything-claude-code
   git remote add upstream https://github.com/affaan-m/everything-claude-code.git
   npm install
   ./install.sh typescript python golang
   ```
   The install script requires Node.js (`sudo port install nodejs22`) and npm dependencies.
   The dotfiles checkout already placed `shell.md` (our custom rule) in `~/.claude/rules/common/`; the install script adds the rest without overwriting it.
3. **Plugins** (skills, agents, hooks) restore automatically from `settings.json` via the marketplace system on first launch.
4. **Copy auto-memory** from the old machine to preserve project context:
   ```bash
   # On old machine:
   tar czf claude-memory.tar.gz ~/.claude/projects/*/memory/
   # On new machine:
   tar xzf claude-memory.tar.gz -C /
   ```
   Memory files are optional — Claude Code rebuilds them over time — but they save having to re-explain project context.

To keep rules up-to-date, run `claude-sync-rules` (defined in `.shell_functions`). This pulls the latest from upstream and reinstalls rules while preserving custom files.

### Periodic maintenance

Run these steps periodically (or ask Claude Code in `~/` to do it) to keep everything in sync:

- `claude-sync-rules` — pull latest ECC rules from upstream
- `brew bundle dump --force --file=~/Brewfile` — sync Brewfile with installed packages
- `port installed > ~/myports` — snapshot installed MacPorts
- `port echo requested | awk '{print $1}' | sort -u > ~/requested_ports` — sync requested ports
- `config submodule update --remote` — update oh-my-zsh plugins/themes
- Check preference symlinks: `ls -la ~/Library/Application\ Support/BetterTouchTool/btt*` — if any symlink was replaced by a regular file (BTT atomic writes), copy the updated file back into `support_and_preference_files_to_migrate/Home/` first, then re-run `link_preferences.zsh` to restore symlinks
- `config diff` — review changes to tracked files (`.zshrc`, `.shell_functions`, `.claude/settings.json`, etc.)
- Commit and push any changes

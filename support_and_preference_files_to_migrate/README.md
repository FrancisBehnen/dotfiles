# Support and preference files

Application preferences and license files that live outside `$HOME` dotfile
territory (e.g. under `~/Library/`). They are tracked in this repo under
`Home/` mirroring their real path relative to `~`.

## Setup on a new machine

Run the link script to symlink everything into place:

```bash
cd ~/support_and_preference_files_to_migrate
./link_preferences.zsh
```

If a file already exists at the target location it will be backed up to
`<file>.bak` before the symlink is created. Re-running the script is safe —
it skips files that are already correctly linked.

**Note:** Some apps (e.g. BetterTouchTool) use atomic writes that replace
symlinks with regular files. For those files the symlink won't persist while
the app is running. Before migrating to a new machine, copy the latest
versions into the repo first (`cp` from `~/Library/...` into `Home/...`),
then run the link script on the new machine.

## BTT cask formula

`BTT/bettertouchtool2.716.rb` is a pinned Homebrew cask for the last
BetterTouchTool version covered by the license. Install with:

```bash
brew install --cask BTT/bettertouchtool2.716.rb
```

The license itself should be recovered from a Time Machine backup or email.

# Dotfiles

macOS dotfiles managed with a bare git repository. Supports both admin and non-admin setups.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Fresh Machine Setup](#fresh-machine-setup)
3. [Coding Agent Setup](#coding-agent-setup)
4. [Day-to-Day Usage](#day-to-day-usage)
5. [Adding Dotfiles and Submodules](#adding-dotfiles-and-submodules)
6. [Periodic Maintenance](#periodic-maintenance)
7. [Troubleshooting / FAQ](#troubleshooting--faq)

---

## Prerequisites

- macOS (Intel or Apple Silicon)
- Terminal app (iTerm2 recommended, or the built-in Terminal)
- Git (pre-installed on macOS via Xcode Command Line Tools)
- A GitHub account with SSH or HTTPS access configured

If you don't have Xcode Command Line Tools:
```bash
xcode-select --install
```

---

## Fresh Machine Setup

There are two paths: **automated** (recommended) or **manual** (step-by-step).

### Option A: Automated Setup

The `scripts/setup.sh` script handles everything. It detects admin vs non-admin and adjusts accordingly.

```bash
# 1. Clone the dotfiles bare repo
git clone --bare --recurse-submodules https://github.com/FrancisBehnen/dotfiles.git $HOME/.dotfiles

# 2. Define the config alias for this session
alias config='/usr/bin/git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'

# 3. Check out the dotfiles into $HOME
config checkout

# 4. Hide untracked files
config config --local status.showUntrackedFiles no

# 5. Run the setup script
bash ~/scripts/setup.sh
```

The setup script will:
- Install Homebrew (works without admin)
- Offer to install MacPorts from source for non-admin users (into `~/macports`)
- Install packages from Brewfile (admin) or list what needs manual install (non-admin)
- Install MacPorts packages from `requested_ports` (if MacPorts is available)
- Install Oh My Zsh (preserving the tracked `.zshrc`)
- Initialize submodules (Oh My Zsh plugins, Powerlevel10k)
- Install Meslo Nerd Font for Powerlevel10k
- Install Node.js and Bun
- Install tmux plugin manager (tpm)
- Offer to set up coding agents (Claude Code, GitHub Copilot CLI)
- Offer to link application preference files

After the script completes:
1. Set your terminal font to **MesloLGS NF**
2. Restart your terminal (`exec zsh`)
3. Run `p10k configure` to customize your prompt
4. Launch tmux and press `prefix + I` to install tmux plugins

### Option B: Manual Step-by-Step

#### Step 1: Install a Package Manager

**Homebrew** (recommended — works with or without admin):
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

After installation, follow the instructions to add Homebrew to your PATH:
```bash
# Apple Silicon
eval "$(/opt/homebrew/bin/brew shellenv)"

# Intel Mac
eval "$(/usr/local/bin/brew shellenv)"
```

> **MacPorts** is also supported — with or without admin. The `.zshrc` conditionally loads the `macports` Oh My Zsh plugin if the `port` command is available.
>
> - **With admin:** Install MacPorts via the [official installer](https://www.macports.org/install.php), then use `sudo port install ...`
> - **Without admin:** Build MacPorts from source into `$HOME/macports` (no sudo needed):
>   ```bash
>   # Check https://www.macports.org/install.php for the latest version
>   curl -LO https://distfiles.macports.org/MacPorts/MacPorts-2.12.4.tar.bz2
>   tar xjf MacPorts-2.12.4.tar.bz2
>   cd MacPorts-2.12.4
>   ./configure \
>       --prefix=$HOME/macports \
>       --with-applications-dir=$HOME/macports/Applications \
>       --with-no-root-privileges \
>       --without-startupitems
>   make
>   make install
>   export PATH=$HOME/macports/bin:$HOME/macports/sbin:$PATH
>   $HOME/macports/bin/port selfupdate
>   ```
>   After this, use `port install <package>` (no sudo) to install software.

#### Step 2: Install Oh My Zsh

```bash
RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/oh-my-zsh/master/tools/install.sh)"
```

- `RUNZSH=no` prevents it from switching shells immediately
- `KEEP_ZSHRC=yes` prevents it from overwriting the `.zshrc` we're about to check out

> **Important:** This repo tracks `.oh-my-zsh` as a submodule. The submodule checkout (step 4) IS the Oh My Zsh installation — but Oh My Zsh needs to exist first for the checkout to land in the right place, or you can let the submodule init create it.

#### Step 3: Clone and Check Out Dotfiles

```bash
# Add the config alias to the current session
alias config='/usr/bin/git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'

# Make sure .dotfiles is in your .gitignore (it should already be)
echo ".dotfiles" >> $HOME/.gitignore

# Clone the bare repo
git clone --bare --recurse-submodules https://github.com/FrancisBehnen/dotfiles.git $HOME/.dotfiles

# Check out files into $HOME
config checkout
```

If checkout fails due to existing files:
```bash
# Back up conflicting files
mkdir -p $HOME/.dotfiles-backup
config checkout 2>&1 | grep -E '^\s+' | awk '{print $1}' | \
  xargs -I{} sh -c 'mkdir -p "$HOME/.dotfiles-backup/$(dirname "{}")" && mv "$HOME/{}" "$HOME/.dotfiles-backup/{}"'

# Try again
config checkout
```

Hide untracked files from `config status`:
```bash
config config --local status.showUntrackedFiles no
```

#### Step 4: Initialize Submodules

This step is required — `--recurse-submodules` does not work with bare clones:
```bash
config submodule update --init --recursive
```

This initializes:
- `.oh-my-zsh` — Oh My Zsh core
- `.oh-my-zsh_custom/themes/powerlevel10k` — Powerlevel10k theme
- `.oh-my-zsh_custom/plugins/autoupdate` — Auto-update plugin
- `.oh-my-zsh_custom/plugins/zsh-autosuggestions` — Zsh autosuggestions

#### Step 5: Install Meslo Nerd Font

Powerlevel10k requires the Meslo Nerd Font to render icons correctly:

```bash
# Download all four styles to ~/Library/Fonts
font_dir="$HOME/Library/Fonts"
base_url="https://github.com/romkatv/powerlevel10k-media/raw/master"
for style in Regular Bold Italic "Bold%20Italic"; do
  curl -fsSL -o "$font_dir/MesloLGS NF ${style//%20/ }.ttf" \
    "$base_url/MesloLGS%20NF%20${style}.ttf"
done
```

Then set your terminal's font to **MesloLGS NF**:
- **iTerm2:** Preferences > Profiles > Text > Font > MesloLGS NF
- **Terminal.app:** Preferences > Profiles > Font > Change > MesloLGS NF
- **VS Code terminal:** Add `"terminal.integrated.fontFamily": "MesloLGS NF"` to settings

#### Step 6: Install Packages

```bash
# From Brewfile (Homebrew)
brew bundle --file=~/Brewfile

# If using MacPorts — re-install requested ports from snapshot:
# Admin install (system-wide):
#   cat ~/requested_ports | xargs sudo port install
# Non-admin install (user-local ~/macports):
#   cat ~/requested_ports | xargs port install
```

> **Non-admin users:** Homebrew formulas install without admin. Some casks (desktop apps) may require admin rights. Ask an admin to run `brew bundle --file=~/Brewfile` or install those apps manually. MacPorts packages install without sudo when using the non-admin (`~/macports`) installation.

#### Step 7: Install Node.js and Bun

```bash
# Node.js (needed for Claude Code rules, ECC)
brew install node

# Bun (fast JS runtime, used as Claude Code package manager)
curl -fsSL https://bun.sh/install | bash
```

#### Step 8: Install tmux Plugin Manager

```bash
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
```

Then launch tmux and press `prefix + I` (capital I) to install plugins defined in `.tmux.conf` (tmux-sensible, tmux-resurrect, tmux-continuum).

#### Step 9: Configure Powerlevel10k

```bash
p10k configure
```

This walks through an interactive wizard to customize your prompt. The repo includes a `.p10k.zsh` that is already configured — the wizard will overwrite it with your choices.

#### Step 10: Link Preference Files (Optional)

Application preference files (BetterTouchTool, iTerm2, etc.) are tracked in `support_and_preference_files_to_migrate/`:

```bash
cd ~/support_and_preference_files_to_migrate
./link_preferences.zsh
```

See `support_and_preference_files_to_migrate/README.md` for details and caveats.

---

## Coding Agent Setup

This repo supports multiple coding agents. Each agent's config is tracked separately.

### Claude Code

The repo tracks Claude Code's portable configuration:
- `.claude/settings.json` — model, plugins, effort level, statusline, permissions
- `.claude/settings.local.json` — project-specific permissions
- `.claude/statusline.sh` — custom statusline script

**Installation:**
1. Install Claude Code:
   ```bash
   curl -fsSL https://claude.ai/install.sh | sh
   ```
2. Sign in: run `claude` and follow the prompts.
3. Install extended rules from [everything-claude-code](https://github.com/affaan-m/everything-claude-code):
   ```bash
   git clone https://github.com/affaan-m/everything-claude-code.git ~/Documents/Code/everything-claude-code
   cd ~/Documents/Code/everything-claude-code
   git remote add upstream https://github.com/affaan-m/everything-claude-code.git
   bun install
   ./install.sh typescript python golang
   ```
   The dotfiles checkout already placed `shell.md` (our custom rule) at `~/.claude/rules/common/`; the install script adds the rest without overwriting it.
4. Plugins restore automatically from `settings.json` via the marketplace on first launch.

**Migrating memory from an old machine (optional):**
```bash
# On old machine:
tar czf claude-memory.tar.gz ~/.claude/projects/*/memory/
# On new machine:
tar xzf claude-memory.tar.gz -C /
```

**Keeping rules up-to-date:**
```bash
claude-sync-rules
```

### GitHub Copilot CLI

GitHub Copilot CLI integrates AI assistance directly into your terminal.

**Installation:**
```bash
curl -fsSL https://gh.io/copilot-install | bash
```

**Usage:**
```bash
# Get a shell command suggestion
copilot suggest "find large files over 100MB"

# Explain a command
copilot explain "tar -xzf archive.tar.gz -C /tmp"
```

> If you already have the legacy `gh copilot` extension installed, `scripts/setup.sh` treats that as an existing Copilot CLI install.

### Adding Other Agents

This repo is structured to accommodate additional coding agents. Here's how to add support for common ones:

**Aider:**
```bash
pipx install aider-chat
# Config: ~/.aider.conf.yml — add to dotfiles if customized:
# config add ~/.aider.conf.yml
```

**Continue.dev (VS Code extension):**
- Config: `~/.continue/config.json`
- Add to dotfiles: `config add ~/.continue/config.json`

**Cursor:**
- Cursor stores settings in its own app directory
- Export settings JSON and track if needed: `config add ~/.cursor/settings.json`

**General pattern for any agent:**
1. Install the agent
2. Find its config files (usually `~/.config/<agent>/` or `~/.<agent>/`)
3. Track the config: `config add <path>`
4. Document it in this README under this section

---

## Day-to-Day Usage

All dotfile operations use the `config` alias (defined in `.zshrc`):
```bash
config status          # See what's changed
config diff            # Review changes
config add .zshrc      # Stage a file
config commit -m "..."  # Commit
config push            # Push to GitHub
```

Files not explicitly added are hidden from `config status`.

### Installing Pinned Homebrew Versions with `vintage`

Some apps need a specific older version (e.g., due to licensing or OS compatibility):

```bash
vintage <formula-or-cask> <version>
```

For example:
```bash
vintage bettertouchtool 2.716
vintage google-drive 113.0.1
```

These version-pinned casks use a separate name (e.g., `bettertouchtool2.716`) and are not affected by `brew upgrade`.

> **Note:** The `vintage` script requires admin rights (it uses `brew tap` operations).

### Moving Projects with `claude-mv`

When you move a project directory, use `claude-mv` to also migrate Claude Code's context:
```bash
claude-mv ~/old/project ~/new/project
```

This preserves Claude Code's memory, todos, and session context for the project.

---

## Adding Dotfiles and Submodules

### Adding a New Dotfile

```bash
config add ~/.some-config
config commit -m "track some-config"
config push
```

### Adding Submodules

For Oh My Zsh plugins/themes, install as submodules under `$ZSH_CUSTOM` (not inside `.oh-my-zsh`):

```bash
# Example: adding a new zsh plugin
config submodule add https://github.com/<user>/<plugin>.git \
  .oh-my-zsh_custom/plugins/<plugin>

# Then add the plugin name to the plugins array in .zshrc
```

> Installing a submodule inside another submodule is not supported by git. That's why custom plugins go in `.oh-my-zsh_custom/` (set via `ZSH_CUSTOM` in `.zshrc`) instead of inside `.oh-my-zsh/custom/`.

---

## Periodic Maintenance

Run these steps periodically (or ask Claude Code in `~/` to do it):

```bash
# Update Claude Code rules from upstream
claude-sync-rules

# Sync Brewfile with currently installed packages
brew bundle dump --force --file=~/Brewfile

# Snapshot MacPorts state (if using MacPorts)
port installed > ~/myports
port echo requested | awk '{print $1}' | sort -u > ~/requested_ports

# Update Oh My Zsh plugins/themes
config submodule update --remote

# Check preference symlinks (BTT atomic writes can replace symlinks)
ls -la ~/Library/Application\ Support/BetterTouchTool/btt*
# If a symlink was replaced by a regular file, copy the updated file back
# into support_and_preference_files_to_migrate/Home/, then re-run:
# cd ~/support_and_preference_files_to_migrate && ./link_preferences.zsh

# Review and commit changes
config diff
config add -u
config commit -m "chore: periodic maintenance sync"
config push
```

---

## Troubleshooting / FAQ

### `config checkout` fails with "untracked working tree files would be overwritten"

Back up the conflicting files and retry:
```bash
mkdir -p $HOME/.dotfiles-backup
config checkout 2>&1 | grep -E '^\s+' | awk '{print $1}' | \
  xargs -I{} sh -c 'mkdir -p "$HOME/.dotfiles-backup/$(dirname "{}")" && mv "$HOME/{}" "$HOME/.dotfiles-backup/{}"'
config checkout
```

### Powerlevel10k shows diamond/square characters instead of icons

Install the Meslo Nerd Font (see [Step 5](#step-5-install-meslo-nerd-font)) and set your terminal font to **MesloLGS NF**.

### The `macports` plugin isn't loading

The plugin loads conditionally — only when the `port` command is available. If you don't use MacPorts, this is expected. Install MacPorts if you want it: https://www.macports.org/install.php

### tmux plugins aren't working

Make sure tpm is installed:
```bash
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
```
Then inside tmux, press `prefix + I` to install plugins.

### `claude-sync-rules` fails with "bun install failed"

Bun is required, and Node.js is needed if you don't already have a compatible JS runtime available. Install them with:
```bash
brew install node            # Homebrew
curl -fsSL https://bun.sh/install | bash

# or
sudo port install nodejs22   # MacPorts (admin)
# or
port install nodejs22        # MacPorts (non-admin ~/macports)
```

### Submodules show as empty directories after clone

Run:
```bash
config submodule update --init --recursive
```

### Non-admin: Can I still use everything?

Most things work without admin. Key differences:
- **Homebrew formulas** (CLI tools): work without admin
- **Homebrew casks** (GUI apps): some require admin for `/Applications`
- **MacPorts (system-wide `/opt/local`)**: requires admin (`sudo`)
- **MacPorts (user-local `~/macports`)**: works without admin — build from source with `--prefix=$HOME/macports --with-no-root-privileges` (see [Step 1](#step-1-install-a-package-manager))
- **Oh My Zsh, Bun, Node (via Homebrew), fonts**: all work without admin
- **`vintage` script**: requires admin (uses `brew tap`)

### How do I add a new coding agent?

See [Adding Other Agents](#adding-other-agents) for the general pattern.

---

## Repository Structure

```
.claude/                     # Claude Code configuration
  settings.json              # Model, plugins, permissions, statusline
  settings.local.json        # Project-specific permissions
  statusline.sh              # Custom statusline script
.gitconfig                   # Git user config + credential helpers
.gitignore                   # Ignores .dotfiles and .DS_Store
.gitmodules                  # Submodule definitions
.oh-my-zsh/                  # Oh My Zsh (submodule)
.oh-my-zsh_custom/           # Custom plugins and themes
  plugins/autoupdate         # Auto-update OMZ plugins (submodule)
  plugins/zsh-autosuggestions # Zsh autosuggestions (submodule)
  themes/powerlevel10k       # Powerlevel10k theme (submodule)
.p10k.zsh                    # Powerlevel10k configuration
.tmux.conf                   # tmux config with tpm plugins
.vimrc                       # Vim configuration
.zshrc                       # Main shell configuration
Brewfile                     # Homebrew packages
CLAUDE.md                    # Instructions for Claude Code
myports                      # MacPorts installed packages snapshot
requested_ports              # MacPorts requested packages snapshot
scripts/
  setup.sh                   # Bootstrap script for new machines
  claude-mv                  # Move project + update Claude context
  claude-sync-rules          # Sync ECC rules for Claude Code
  vintage                    # Install pinned Homebrew versions
support_and_preference_files_to_migrate/
                             # App preference files + link script
```

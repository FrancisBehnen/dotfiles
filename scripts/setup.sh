#!/bin/bash
# Bootstrap script for setting up a new macOS machine with these dotfiles.
# Detects admin vs non-admin and adjusts installation accordingly.
# Idempotent — safe to re-run at any time.
#
# Usage: bash scripts/setup.sh

set -e

# ─── Helpers ──────────────────────────────────────────────────────────────────

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

info()  { echo -e "${GREEN}[setup]${NC} $*"; }
warn()  { echo -e "${YELLOW}[setup]${NC} $*"; }
error() { echo -e "${RED}[setup]${NC} $*" >&2; }

has_admin() {
  # Returns 0 if user can sudo (has admin rights)
  sudo -n true 2>/dev/null || groups | grep -qw admin
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

copilot_cli_exists() {
  command_exists copilot || { command_exists gh && gh copilot --help >/dev/null 2>&1; }
}

# ─── Detect user-local package managers (non-admin installs) ─────────────────

[[ -d "$HOME/homebrew/bin" ]] && export PATH="$HOME/homebrew/bin:$HOME/homebrew/sbin:$PATH"
[[ -d "$HOME/macports/bin" ]] && export PATH="$HOME/macports/bin:$HOME/macports/sbin:$PATH"

# ─── Detect Environment ──────────────────────────────────────────────────────

info "Detecting environment..."
if has_admin; then
  info "Admin privileges detected."
  IS_ADMIN=true
else
  warn "No admin privileges. Some installations will be user-local only."
  IS_ADMIN=false
fi

# ─── 1. Package Manager (Homebrew) ───────────────────────────────────────────

install_homebrew() {
  if command_exists brew; then
    info "Homebrew already installed at $(which brew)."
    return
  fi

  if [[ "$IS_ADMIN" == true ]]; then
    info "Installing Homebrew (admin)..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [[ -f /opt/homebrew/bin/brew ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -f /usr/local/bin/brew ]]; then
      eval "$(/usr/local/bin/brew shellenv)"
    fi
  else
    info "Installing Homebrew (non-admin, user-local in ~/homebrew)..."
    cd "$HOME"
    mkdir -p homebrew && curl -L https://github.com/Homebrew/brew/tarball/main | tar xz --strip-components 1 -C homebrew
    eval "$(homebrew/bin/brew shellenv)"
    brew update --force --quiet
    chmod -R go-w "$(brew --prefix)/share/zsh"
  fi

  info "Homebrew installed."
}

install_homebrew

# ─── 1b. Package Manager (MacPorts) ─────────────────────────────────────────

install_macports() {
  if command_exists port; then
    info "MacPorts already installed at $(which port)."
    return
  fi

  if $IS_ADMIN; then
    info "MacPorts can be installed via the official installer."
    info "Download from: https://www.macports.org/install.php"
    warn "Skipping automatic MacPorts install — use the .pkg installer or build from source."
    return
  fi

  # Non-admin: build MacPorts from source into $HOME/macports
  info "Installing MacPorts from source (non-admin, into ~/macports)..."

  local mp_version="2.12.4"
  local mp_tarball="MacPorts-${mp_version}.tar.bz2"
  local mp_url="https://distfiles.macports.org/MacPorts/${mp_tarball}"
  local tmp_dir
  tmp_dir="$(mktemp -d)"

  (
    cd "$tmp_dir"
    info "Downloading MacPorts ${mp_version}..."
    curl -LO "$mp_url"
    tar xjf "$mp_tarball"
    cd "MacPorts-${mp_version}"

    info "Configuring MacPorts for non-root install..."
    ./configure \
      --prefix="$HOME/macports" \
      --with-applications-dir="$HOME/macports/Applications" \
      --with-no-root-privileges \
      --without-startupitems

    info "Building MacPorts (this may take a few minutes)..."
    make
    make install
  )

  rm -rf "$tmp_dir"

  # Add to PATH for the rest of this script
  export PATH="$HOME/macports/bin:$HOME/macports/sbin:$PATH"

  info "Updating MacPorts ports tree..."
  "$HOME/macports/bin/port" selfupdate

  info "MacPorts installed into ~/macports (no admin required)."
  info "Check https://www.macports.org/install.php for newer versions."
}

# Offer MacPorts installation for non-admin users who want it
if ! $IS_ADMIN && ! command_exists port; then
  echo ""
  echo "Install MacPorts from source? (non-admin, installs to ~/macports) (y/n)"
  read -r install_mp
  if [[ "$install_mp" =~ ^[Yy]$ ]]; then
    install_macports
  fi
elif command_exists port; then
  info "MacPorts already available at $(which port)."
fi

# ─── 2. Install Packages from Brewfile ───────────────────────────────────────

install_brew_packages() {
  local brewfile="$HOME/Brewfile"
  if [[ ! -f "$brewfile" ]]; then
    warn "No Brewfile found at $brewfile — skipping package installation."
    return
  fi

  if $IS_ADMIN; then
    info "Installing packages from Brewfile..."
    brew bundle --file="$brewfile" || warn "Some Brewfile items may have failed."
  else
    info "Installing Brewfile formulas (non-admin — skipping casks that need admin)..."
    # Install formulas (these don't need admin)
    brew bundle --file="$brewfile" --no-lock 2>&1 | while read -r line; do
      if echo "$line" | grep -q "requires root"; then
        warn "Skipped (needs admin): $line"
      else
        echo "$line"
      fi
    done
    warn "Some casks may require admin. Install them manually or ask an admin:"
    grep '^cask ' "$brewfile" | sed 's/^cask /  /' || true
  fi
}

install_brew_packages

# ─── 2b. Install Packages from requested_ports (MacPorts) ───────────────────

install_port_packages() {
  if ! command_exists port; then
    return
  fi

  local portsfile="$HOME/requested_ports"
  if [[ ! -f "$portsfile" ]]; then
    warn "No requested_ports found at $portsfile — skipping MacPorts package installation."
    return
  fi

  info "Installing MacPorts packages from requested_ports..."
  if $IS_ADMIN; then
    cat "$portsfile" | xargs sudo port install || warn "Some ports may have failed to install."
  else
    # User-local MacPorts (no sudo needed)
    cat "$portsfile" | xargs port install || warn "Some ports may have failed to install."
  fi
}

install_port_packages

# ─── 3. Oh My Zsh ────────────────────────────────────────────────────────────

install_oh_my_zsh() {
  if [[ -d "$HOME/.oh-my-zsh" ]]; then
    info "Oh My Zsh already installed."
    return
  fi

  info "Installing Oh My Zsh..."
  # RUNZSH=no prevents it from switching to zsh immediately
  # KEEP_ZSHRC=yes prevents it from overwriting our tracked .zshrc
  RUNZSH=no KEEP_ZSHRC=yes sh -c \
    "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/oh-my-zsh/master/tools/install.sh)"
  info "Oh My Zsh installed."
}

install_oh_my_zsh

# ─── 4. Dotfiles (bare repo) ─────────────────────────────────────────────────

setup_dotfiles() {
  if [[ -d "$HOME/.dotfiles" ]]; then
    info "Dotfiles repo already cloned at ~/.dotfiles."
  else
    info "Cloning dotfiles bare repo..."
    git clone --bare --recurse-submodules \
      https://github.com/FrancisBehnen/dotfiles.git "$HOME/.dotfiles"

    # Define the config alias for this script session
    config() {
      /usr/bin/git --git-dir="$HOME/.dotfiles/" --work-tree="$HOME" "$@"
    }

    info "Checking out dotfiles..."
    config checkout 2>&1 | head -20 || {
      warn "Checkout had conflicts. Backing up conflicting files..."
      mkdir -p "$HOME/.dotfiles-backup"
      config checkout 2>&1 | grep -E '^\s+' | awk '{print $1}' | while read -r f; do
        mkdir -p "$HOME/.dotfiles-backup/$(dirname "$f")"
        mv "$HOME/$f" "$HOME/.dotfiles-backup/$f"
      done
      config checkout
      warn "Pre-existing files backed up to ~/.dotfiles-backup/"
    }

    config config --local status.showUntrackedFiles no
    info "Dotfiles checked out."
  fi

  # Ensure submodules are initialized
  local config_cmd="/usr/bin/git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME"
  info "Initializing submodules..."
  $config_cmd submodule update --init --recursive
}

setup_dotfiles

# ─── 5. Meslo Nerd Font (for Powerlevel10k) ──────────────────────────────────

install_meslo_font() {
  local font_dir="$HOME/Library/Fonts"
  local font_base="MesloLGS NF"

  if ls "$font_dir"/${font_base}* &>/dev/null; then
    info "Meslo Nerd Font already installed."
    return
  fi

  info "Installing Meslo Nerd Font for Powerlevel10k..."
  local base_url="https://github.com/romkatv/powerlevel10k-media/raw/master"
  mkdir -p "$font_dir"
  for style in Regular Bold Italic "Bold Italic"; do
    curl -fsSL -o "$font_dir/${font_base} ${style}.ttf" \
      "$base_url/${font_base// /%20}%20${style// /%20}.ttf"
  done
  info "Meslo Nerd Font installed. Set your terminal font to 'MesloLGS NF'."
}

install_meslo_font

# ─── 6. Node.js and Bun ──────────────────────────────────────────────────────

install_node() {
  if command_exists node; then
    info "Node.js already installed: $(node --version)"
    return
  fi

  info "Installing Node.js..."
  if command_exists brew; then
    brew install node
  elif command_exists port; then
    if $IS_ADMIN; then
      sudo port install nodejs22
    else
      port install nodejs22
    fi
  else
    warn "Could not install Node.js automatically."
    warn "Install manually: https://nodejs.org/ or use fnm/nvm."
    return
  fi
  info "Node.js installed: $(node --version)"
}

install_bun() {
  if command_exists bun; then
    info "Bun already installed: $(bun --version)"
    return
  fi

  info "Installing Bun..."
  curl -fsSL https://bun.sh/install | bash
  export BUN_INSTALL="$HOME/.bun"
  export PATH="$BUN_INSTALL/bin:$PATH"
  info "Bun installed: $(bun --version)"
}

install_node
install_bun

# ─── 7. tmux Plugin Manager (tpm) ────────────────────────────────────────────

install_tpm() {
  local tpm_dir="$HOME/.tmux/plugins/tpm"
  if [[ -d "$tpm_dir" ]]; then
    info "tmux plugin manager already installed."
    return
  fi

  info "Installing tmux plugin manager (tpm)..."
  git clone https://github.com/tmux-plugins/tpm "$tpm_dir"
  info "tpm installed. Launch tmux and press prefix + I to install plugins."
}

install_tpm

# ─── 8. Coding Agent Setup ───────────────────────────────────────────────────

setup_coding_agents() {
  echo ""
  info "=== Coding Agent Setup ==="
  echo ""

  # Claude Code
  echo "Set up Claude Code? (y/n)"
  read -r setup_claude
  if [[ "$setup_claude" =~ ^[Yy]$ ]]; then
    if command_exists claude; then
      info "Claude Code already installed."
    else
      info "Installing Claude Code via native installer..."
      curl -fsSL https://claude.ai/install.sh | sh
      # Add to PATH for the rest of this script
      export PATH="$HOME/.claude/bin:$PATH"
      if ! command_exists claude; then
        warn "Claude Code installation may have failed. Install manually: https://claude.ai/install"
      fi
    fi

    # Install ECC rules
    local ecc_dir="$HOME/Documents/Code/everything-claude-code"
    if [[ -d "$ecc_dir" ]]; then
      info "ECC rules repo already cloned."
    else
      info "Cloning everything-claude-code for extended rules..."
      mkdir -p "$HOME/Documents/Code"
      git clone https://github.com/affaan-m/everything-claude-code.git "$ecc_dir"
      git -C "$ecc_dir" remote add upstream \
        https://github.com/affaan-m/everything-claude-code.git 2>/dev/null || true
    fi

    if command_exists bun; then
      info "Installing ECC dependencies with bun..."
      bun install --cwd "$ecc_dir"
      "$ecc_dir/install.sh" typescript python golang
      info "Claude Code rules installed."
    else
      warn "Bun required for ECC rule installation. Run 'claude-sync-rules' later."
    fi
  fi

  # GitHub Copilot CLI
  echo ""
  echo "Set up GitHub Copilot CLI? (y/n)"
  read -r setup_copilot
  if [[ "$setup_copilot" =~ ^[Yy]$ ]]; then
    if copilot_cli_exists; then
      info "Copilot CLI already installed."
    else
      info "Installing Copilot CLI via native installer..."
      curl -fsSL https://gh.io/copilot-install | bash
      # Add to PATH for the rest of this script
      export PATH="$HOME/.local/bin:$PATH"
      if ! copilot_cli_exists; then
        warn "Copilot CLI installation may have failed. Install manually: https://aka.ms/github-copilot-settings"
      fi
    fi
  fi

  echo ""
  info "Agent setup complete."
}

setup_coding_agents

# ─── 9. Preference Files ─────────────────────────────────────────────────────

link_preferences() {
  local pref_dir="$HOME/support_and_preference_files_to_migrate"
  if [[ -f "$pref_dir/link_preferences.zsh" ]]; then
    echo ""
    echo "Link application preference files (BetterTouchTool, iTerm2, etc.)? (y/n)"
    read -r link_prefs
    if [[ "$link_prefs" =~ ^[Yy]$ ]]; then
      info "Linking preference files..."
      cd "$pref_dir" && zsh link_preferences.zsh
      cd "$HOME"
      info "Preference files linked."
    fi
  fi
}

link_preferences

# ─── 10. Final Steps ─────────────────────────────────────────────────────────

echo ""
info "========================================="
info "  Setup complete!"
info "========================================="
echo ""
info "Remaining manual steps:"
echo "  1. Set your terminal font to 'MesloLGS NF'"
echo "  2. Restart your terminal (or run: exec zsh)"
echo "  3. Run 'p10k configure' to customize your prompt"
if command_exists tmux; then
  echo "  4. Launch tmux and press prefix + I to install tmux plugins"
fi
echo ""
if ! $IS_ADMIN; then
  warn "Non-admin note: Some Homebrew casks were skipped."
  warn "Ask an admin to run: brew bundle --file=~/Brewfile"
  if [[ -d "$HOME/macports" ]]; then
    info "MacPorts is installed at ~/macports (user-local, no admin needed)."
    info "Use 'port install <package>' (no sudo) to install additional packages."
  fi
fi

#!/bin/bash
# Bootstrap script for setting up a new macOS machine with these dotfiles.
# Detects admin vs non-admin and adjusts installation accordingly.
# Idempotent — safe to re-run at any time.
#
# The script runs in two phases:
#   Phase 1 — Interactive: manual installs (Xcode CLT, MacPorts .pkg) and
#             user preferences are gathered upfront.
#   Phase 2 — Unattended: everything else installs automatically with no
#             further input required.
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

start_sudo_keepalive() {
  if [[ "$IS_ADMIN" != true ]]; then
    return
  fi

  info "Refreshing sudo credentials for the unattended phase..."
  sudo -v

  (
    while true; do
      sudo -n true
      sleep 60
    done
  ) &
  SUDO_KEEPALIVE_PID=$!
}

stop_sudo_keepalive() {
  if [[ -n "${SUDO_KEEPALIVE_PID:-}" ]]; then
    kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
  fi
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

# ─── Install Functions ────────────────────────────────────────────────────────

install_homebrew() {
  if command_exists brew; then
    info "Homebrew already installed at $(which brew)."
    return
  fi

  if [[ "$IS_ADMIN" == true ]]; then
    info "Installing Homebrew (admin)..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
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

install_macports_from_source() {
  # Non-admin: build MacPorts from source into $HOME/macports
  if command_exists port; then
    info "MacPorts already installed at $(which port)."
    return
  fi

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

setup_private_dotfiles() {
  # Coolblue-internal Claude context lives in a SEPARATE PRIVATE repo (dotfiles-private):
  # a second bare repo over the same $HOME work-tree. See ~/.claude/DOTFILES-PRIVATE.md.
  warn "────────────────────────────────────────────────────────────────────────────"
  warn " PRIVATE DOTFILES — fresh-machine note:"
  warn "   Claude Code encodes per-project memory paths from \$HOME, e.g."
  warn "     ~/.claude/projects/-Users-francis-behnen/memory/"
  warn "   For this repo's memory to line up, this machine's macOS short username MUST"
  warn "   be 'francis.behnen' (home = /Users/francis.behnen). A different username"
  warn "   silently shifts every project path and the memory won't be picked up."
  warn "────────────────────────────────────────────────────────────────────────────"

  local cpriv="/usr/bin/git --git-dir=$HOME/.dotfiles-private/ --work-tree=$HOME"
  if [[ -d "$HOME/.dotfiles-private" ]]; then
    info "Private dotfiles repo already present at ~/.dotfiles-private."
  else
    info "Cloning private dotfiles bare repo..."
    if git clone --bare git@github.com:FrancisBehnen/dotfiles-private.git "$HOME/.dotfiles-private" 2>/dev/null \
       || git clone --bare https://github.com/FrancisBehnen/dotfiles-private.git "$HOME/.dotfiles-private" 2>/dev/null; then
      if ! $cpriv checkout 2>/dev/null; then
        warn "Private checkout conflicts — backing up pre-existing files to ~/.dotfiles-backup..."
        mkdir -p "$HOME/.dotfiles-backup"
        $cpriv checkout 2>&1 | grep -E '^\s+' | awk '{print $1}' | while read -r f; do
          mkdir -p "$HOME/.dotfiles-backup/$(dirname "$f")"
          mv "$HOME/$f" "$HOME/.dotfiles-backup/$f" 2>/dev/null || true
        done
        $cpriv checkout
      fi
      $cpriv config --local status.showUntrackedFiles no
      $cpriv config --local core.hooksPath /dev/null    # private repo is exempt from the guardrail
      info "Private dotfiles checked out."
    else
      warn "Could not clone private dotfiles (no access — expected on a public-only clone). Skipping."
    fi
  fi

  # Point the PUBLIC repo's hooks at the leak guardrail (no-op if the file isn't present yet).
  /usr/bin/git --git-dir="$HOME/.dotfiles/" --work-tree="$HOME" \
    config --local core.hooksPath "$HOME/.claude/.guardrail" 2>/dev/null || true

  # The public ~/.claude/CLAUDE.md imports ~/.claude/CLAUDE.private.md. Guarantee the target
  # exists so the import never dangles, even on a public-only clone with no private access.
  if [[ ! -f "$HOME/.claude/CLAUDE.private.md" ]]; then
    mkdir -p "$HOME/.claude"
    printf '%s\n' '<!-- Placeholder. Real content comes from the private dotfiles repo (dotfiles-private). -->' \
      > "$HOME/.claude/CLAUDE.private.md"
  fi
}

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

install_tmux_resurrect_agent() {
  # Under iTerm's tmux integration (-CC) the status line is hidden, so
  # tmux-continuum's status-line-driven auto-save never runs. Install a per-user
  # LaunchAgent (no admin needed) that triggers a tmux-resurrect save every 5 min.
  local wrapper="$HOME/scripts/tmux-resurrect-save"
  local label="com.francisbehnen.tmux-resurrect-save"
  local plist="$HOME/Library/LaunchAgents/${label}.plist"

  if [[ ! -x "$wrapper" ]]; then
    warn "tmux-resurrect save wrapper missing at $wrapper — skipping LaunchAgent."
    return
  fi

  info "Installing tmux-resurrect save LaunchAgent..."
  mkdir -p "$HOME/Library/LaunchAgents" "$HOME/.cache"
  cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${label}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/sh</string>
        <string>${wrapper}</string>
    </array>
    <key>StartInterval</key>
    <integer>300</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>ProcessType</key>
    <string>Background</string>
    <key>StandardErrorPath</key>
    <string>${HOME}/.cache/tmux-resurrect-save.log</string>
</dict>
</plist>
PLIST

  # Reload idempotently (bootout is fine to fail if not already loaded).
  launchctl bootout "gui/$(id -u)/${label}" 2>/dev/null || true
  if launchctl bootstrap "gui/$(id -u)" "$plist" 2>/dev/null; then
    info "tmux-resurrect save LaunchAgent loaded (saves every 5 min)."
  else
    # Fall back to legacy load for older macOS.
    launchctl unload "$plist" 2>/dev/null || true
    launchctl load -w "$plist" 2>/dev/null \
      && info "tmux-resurrect save LaunchAgent loaded (legacy)." \
      || warn "Could not load LaunchAgent; load it manually: launchctl bootstrap gui/\$(id -u) $plist"
  fi
}

install_claude_code() {
  if command_exists claude; then
    info "Claude Code already installed."
  else
    info "Installing Claude Code via native installer..."
    curl -fsSL https://claude.ai/install.sh | sh
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
}

install_copilot_cli() {
  if copilot_cli_exists; then
    info "Copilot CLI already installed."
  else
    info "Installing Copilot CLI via native installer..."
    curl -fsSL https://gh.io/copilot-install | bash
    export PATH="$HOME/.local/bin:$PATH"
    if ! copilot_cli_exists; then
      warn "Copilot CLI installation may have failed. Install manually: https://aka.ms/github-copilot-settings"
    fi
  fi
}

install_agent_skills() {
  local skillfile="$HOME/Skillfile"
  if [[ ! -f "$skillfile" ]]; then
    warn "No Skillfile found at $skillfile — skipping agent skill installation."
    return
  fi

  if ! command_exists bunx; then
    warn "bunx not found — skipping agent skill installation."
    return
  fi

  info "Installing agent skills from Skillfile..."
  grep -v '^\s*#' "$skillfile" | grep -v '^\s*$' | while read -r ref; do
    info "  Installing skill: $ref"
    bunx skills add "$ref" || warn "  Failed to install skill: $ref"
  done
  info "Agent skills installation complete."
}

link_preferences() {
  local pref_dir="$HOME/support_and_preference_files_to_migrate"
  if [[ -f "$pref_dir/link_preferences.zsh" ]]; then
    info "Linking preference files..."
    cd "$pref_dir" && zsh link_preferences.zsh
    cd "$HOME"
    info "Preference files linked."
  else
    warn "No link_preferences.zsh found — skipping preference file linking."
  fi
}

# ═══════════════════════════════════════════════════════════════════════════════
#  PHASE 1 — Interactive: manual installs & user preferences
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
info "========================================="
info "  Phase 1: A few questions before we start"
info "========================================="

# ─── Xcode Command Line Tools ────────────────────────────────────────────────
# Requires user to wait for the GUI installer and may need sudo for the
# license agreement.

if xcode-select -p &>/dev/null; then
  info "Xcode Command Line Tools already installed at $(xcode-select -p)."
else
  warn "Xcode Command Line Tools are not installed."
  echo ""
  echo "Install Xcode Command Line Tools now? (y/n)"
  read -r install_clt
  if [[ "$install_clt" =~ ^[Yy]$ ]]; then
    info "Launching Xcode Command Line Tools installer..."
    xcode-select --install
    echo ""
    echo "Press RETURN once the Command Line Tools installation has completed:"
    read -r
    if xcode-select -p &>/dev/null; then
      info "Xcode Command Line Tools installed at $(xcode-select -p)."
      info "Accepting Xcode license..."
      if [[ "$IS_ADMIN" == true ]]; then
        sudo xcodebuild -license accept
        info "Xcode license accepted."
      else
        # Fallback for non-admin: write the agreed version to defaults
        # Source: https://stackoverflow.com/a/73742086 (jmon12, CC BY-SA 4.0)
        xcode_version="$(xcodebuild -version 2>/dev/null | awk '/Xcode/{print $2}' | head -1)"
        if [[ -n "$xcode_version" ]]; then
          defaults write com.apple.dt.Xcode IDEXcodeVersionForAgreedToGMLicense "$xcode_version"
          info "Xcode license accepted via defaults (version $xcode_version)."
        else
          warn "Could not accept Xcode license automatically. Run: sudo xcodebuild -license accept"
        fi
      fi
    else
      warn "Xcode Command Line Tools still not detected — some steps may fail."
    fi
  else
    warn "Skipping Xcode Command Line Tools — some steps may fail without them."
  fi
fi

# ─── MacPorts .pkg (admin only — requires manual download) ───────────────────
# The admin MacPorts installer is a .pkg that must be downloaded and run
# manually. Non-admin installs build from source in Phase 2 (no interaction).

OPT_MACPORTS=false
if command_exists port; then
  info "MacPorts already available at $(which port)."
else
  echo ""
  echo "Install MacPorts? (y/n)"
  read -r install_mp
  if [[ "$install_mp" =~ ^[Yy]$ ]]; then
    OPT_MACPORTS=true
    if $IS_ADMIN; then
      info "MacPorts requires the official .pkg installer (admin)."
      info "Download from: https://www.macports.org/install.php"
      echo ""
      echo "Please download and run the MacPorts installer, then press RETURN to continue (or 's' to skip MacPorts):"
      open "https://www.macports.org/install.php" 2>/dev/null || true
      read -r mp_response
      if [[ "$mp_response" =~ ^[Ss]$ ]]; then
        warn "Skipping MacPorts — you can install it later from https://www.macports.org/install.php"
        OPT_MACPORTS=false
      elif ! command_exists port; then
        warn "MacPorts not detected after install. Check the installer completed successfully."
      else
        info "MacPorts available at $(which port)."
      fi
    fi
  fi
fi

# ─── Remaining Preferences ───────────────────────────────────────────────────

OPT_CLAUDE=false
OPT_COPILOT=false
OPT_PREFS=false

echo ""
echo "Set up Claude Code? (y/n)"
read -r answer
[[ "$answer" =~ ^[Yy]$ ]] && OPT_CLAUDE=true

echo ""
echo "Set up GitHub Copilot CLI? (y/n)"
read -r answer
[[ "$answer" =~ ^[Yy]$ ]] && OPT_COPILOT=true

echo ""
echo "Link application preference files (BetterTouchTool, iTerm2, etc.)? (y/n)"
read -r answer
[[ "$answer" =~ ^[Yy]$ ]] && OPT_PREFS=true

# ─── All interactive steps complete ──────────────────────────────────────────

if [[ "$IS_ADMIN" == true ]]; then
  start_sudo_keepalive
  trap stop_sudo_keepalive EXIT
fi

echo ""
info "========================================="
info "  All done — no further input required."
info "  Grab a coffee while the rest installs."
info "========================================="
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
#  PHASE 2 — Unattended: everything installs automatically
# ═══════════════════════════════════════════════════════════════════════════════

# ─── 1. Homebrew ──────────────────────────────────────────────────────────────

install_homebrew

# ─── 2. MacPorts from source (non-admin) ─────────────────────────────────────

if [[ "$OPT_MACPORTS" == true ]] && ! $IS_ADMIN; then
  install_macports_from_source
fi

# ─── 3. Brew packages ────────────────────────────────────────────────────────

install_brew_packages

# ─── 4. MacPorts packages ────────────────────────────────────────────────────

install_port_packages

# ─── 5. Oh My Zsh ────────────────────────────────────────────────────────────

install_oh_my_zsh

# ─── 6. Dotfiles (bare repo) ─────────────────────────────────────────────────

setup_dotfiles

# ─── 6b. Private dotfiles (Coolblue-internal Claude context) ─────────────────

setup_private_dotfiles

# ─── 7. Meslo Nerd Font (for Powerlevel10k) ──────────────────────────────────

install_meslo_font

# ─── 8. Node.js and Bun ──────────────────────────────────────────────────────

install_node
install_bun

# ─── 9. tmux Plugin Manager (tpm) ────────────────────────────────────────────

install_tpm
install_tmux_resurrect_agent

# ─── 10. Claude Code ─────────────────────────────────────────────────────────

if [[ "$OPT_CLAUDE" == true ]]; then
  install_claude_code
fi

# ─── 11. Agent Skills (from Skillfile) ───────────────────────────────────────

if [[ "$OPT_CLAUDE" == true ]]; then
  install_agent_skills
fi

# ─── 12. GitHub Copilot CLI ──────────────────────────────────────────────────

if [[ "$OPT_COPILOT" == true ]]; then
  install_copilot_cli
fi

# ─── 13. Preference Files ────────────────────────────────────────────────────

if [[ "$OPT_PREFS" == true ]]; then
  link_preferences
fi

# ─── 14. Done ─────────────────────────────────────────────────────────────────

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

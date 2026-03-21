#!/usr/bin/env zsh
#
# Creates symlinks from ~/Library/... to the corresponding files tracked in
# this repo under Home/. Run from the support_and_preference_files_to_migrate
# directory, or pass its path as the first argument.
#
# Usage:
#   ./link_preferences.zsh
#   ./link_preferences.zsh /path/to/support_and_preference_files_to_migrate

set -euo pipefail

SCRIPT_DIR="${1:-$(cd "$(dirname "$0")" && pwd)}"
HOME_DIR="$SCRIPT_DIR/Home"

if [[ ! -d "$HOME_DIR" ]]; then
    echo "Error: Home directory not found at $HOME_DIR" >&2
    exit 1
fi

echo "Linking preference files from $HOME_DIR → $HOME"

linked=0
skipped=0

for src in "$HOME_DIR"/**/*(.); do
    # Compute the target path under $HOME
    relative="${src#$HOME_DIR/}"
    target="$HOME/$relative"

    # Skip if already correctly linked
    if [[ -L "$target" && "$(readlink "$target")" == "$src" ]]; then
        echo "  [skip] $relative (already linked)"
        skipped=$((skipped + 1))
        continue
    fi

    # Create parent directory if needed
    mkdir -p "$(dirname "$target")"

    # Back up existing file if present
    if [[ -e "$target" || -L "$target" ]]; then
        echo "  [backup] $target → ${target}.bak"
        mv "$target" "${target}.bak"
    fi

    ln -s "$src" "$target"
    echo "  [link] $relative"
    linked=$((linked + 1))
done

echo ""
echo "Done: $linked linked, $skipped already up to date."

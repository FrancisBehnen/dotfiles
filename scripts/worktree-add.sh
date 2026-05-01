#!/usr/bin/env bash
set -euo pipefail

# Resolve repo from cwd
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "❌ Not inside a git repository." >&2
  exit 1
}
REPO_NAME="$(basename "$REPO_ROOT")"
WORKTREE_BASE="$HOME/Code/worktrees/$REPO_NAME"

usage() {
  echo "Usage: $(basename "$0") <branch-name> [--from <base-branch>]"
  echo ""
  echo "Creates a git worktree for the current repo ($REPO_NAME)."
  echo "Worktree path: $WORKTREE_BASE/<branch-name>"
  echo ""
  echo "Options:"
  echo "  --from <base>   Base branch to create from (default: main)"
  echo ""
  echo "Examples:"
  echo "  $(basename "$0") feature/upsell-refactor"
  echo "  $(basename "$0") feature/new-api --from develop"
  exit 1
}

[[ $# -lt 1 ]] && usage

BRANCH="$1"
BASE="main"
shift

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from) BASE="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

WORKTREE_PATH="$WORKTREE_BASE/$BRANCH"

if [[ -d "$WORKTREE_PATH" ]]; then
  echo "❌ Worktree already exists at: $WORKTREE_PATH"
  exit 1
fi

mkdir -p "$(dirname "$WORKTREE_PATH")"

echo "📦 Creating worktree for branch '$BRANCH' from '$BASE'..."
git -C "$REPO_ROOT" worktree add -b "$BRANCH" "$WORKTREE_PATH" "$BASE"

# Copy environment files that aren't tracked by git
for f in .env .env.local; do
  if [[ -f "$REPO_ROOT/$f" ]]; then
    cp "$REPO_ROOT/$f" "$WORKTREE_PATH/$f"
    echo "   Copied $f"
  fi
done

echo ""
echo "✅ Worktree ready at: $WORKTREE_PATH"
echo "   Branch: $BRANCH (based on $BASE)"
echo ""
echo "To start working:"
echo "   cd $WORKTREE_PATH"

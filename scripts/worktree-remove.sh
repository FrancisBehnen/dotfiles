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
  echo "Usage: $(basename "$0") [options] <branch-name>"
  echo ""
  echo "Removes the git worktree for the current repo ($REPO_NAME)."
  echo "Worktree path: $WORKTREE_BASE/<branch-name>"
  echo ""
  echo "Options:"
  echo "  --force           Force removal even with uncommitted changes"
  echo "  --delete-branch   Also delete the local branch after removal"
  echo ""
  echo "Active worktrees:"
  git -C "$REPO_ROOT" worktree list
  exit 1
}

[[ $# -lt 1 ]] && usage

BRANCH=""
DELETE_BRANCH=false
FORCE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --delete-branch) DELETE_BRANCH=true; shift ;;
    --force) FORCE=true; shift ;;
    -*) echo "Unknown option: $1"; usage ;;
    *) BRANCH="$1"; shift ;;
  esac
done

[[ -z "$BRANCH" ]] && { echo "❌ No branch name provided."; usage; }

WORKTREE_PATH="$WORKTREE_BASE/$BRANCH"

if [[ ! -d "$WORKTREE_PATH" ]]; then
  echo "❌ No worktree found at: $WORKTREE_PATH"
  echo ""
  echo "Active worktrees:"
  git -C "$REPO_ROOT" worktree list
  exit 1
fi

echo "🗑️  Removing worktree at: $WORKTREE_PATH"
if $FORCE; then
  git -C "$REPO_ROOT" worktree remove --force "$WORKTREE_PATH"
else
  git -C "$REPO_ROOT" worktree remove "$WORKTREE_PATH"
fi

if $DELETE_BRANCH; then
  echo "🌿 Deleting branch: $BRANCH"
  git -C "$REPO_ROOT" branch -d "$BRANCH" 2>/dev/null || \
    git -C "$REPO_ROOT" branch -D "$BRANCH"
fi

echo "✅ Done."

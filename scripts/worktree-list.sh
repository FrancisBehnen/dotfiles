#!/usr/bin/env bash
set -euo pipefail

# Resolve repo from cwd
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "❌ Not inside a git repository." >&2
  exit 1
}
REPO_NAME="$(basename "$REPO_ROOT")"

echo "📋 Active worktrees for $REPO_NAME:"
echo ""
git -C "$REPO_ROOT" worktree list

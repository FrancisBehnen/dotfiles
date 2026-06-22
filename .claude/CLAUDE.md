# Global instructions

## Working with code
- Before answering a question about the **state of the codebase** (what exists where, what's merged, what's promoted to which environment, what a teammate has done), **sync the local checkout with upstream first** — the working tree is often stale. Use the repo's sync command (`git sync-upstream` where a fork+upstream workflow exists, otherwise `git fetch` + `git pull --rebase`), with the sandbox disabled. Skip only for questions purely about your own uncommitted changes.

<!-- Company-specific instructions live in a private repo (FrancisBehnen/dotfiles-private) and
     are imported below. On a public-only clone this file may be absent; scripts/setup.sh creates
     an empty placeholder so this import never dangles. -->
@~/.claude/CLAUDE.private.md

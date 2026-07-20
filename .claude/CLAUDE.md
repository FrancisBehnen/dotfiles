# Global instructions

## Working with code
- Before answering a question about the **state of the codebase** (what exists where, what's merged, what's promoted to which environment, what a teammate has done), **sync the local checkout with upstream first** — the working tree is often stale. Use the repo's sync command (`git sync-upstream` where a fork+upstream workflow exists, otherwise `git fetch` + `git pull --rebase`), with the sandbox disabled. Skip only for questions purely about your own uncommitted changes.

## Shell commands (zsh eval environment)
Every Bash-tool command and slash-command `!`-preamble is eval'd through a snapshot of the interactive zsh config (Oh My Zsh aliases live, `extendedglob` on). Investigated 2026-07-20; upstream refs: claude-code#16163, #67146, #61121.

- **Quote every interpolated string.** Escape an embedded `'` as `'\''`. Quote-heavy or multi-line text goes in a `cat > f <<'EOF'` heredoc, never nested `echo` quoting.
- **Never splice user free-text into a command line** — pass it via a quoted variable, stdin, or a file. Skills that splice `$ARGUMENTS` into a shell line (e.g. plannotator-annotate) break on apostrophes: call the underlying CLI directly via Bash with proper quoting instead.
- **Globs:** `extendedglob` means `^` and `#` are pattern characters. Unmatched globs degrade to literals in Claude sessions (`unsetopt nomatch` guard in `.zshrc`), but prefer `(N)` qualifiers or `find` to make intent explicit.
- **If `!` arrives mangled as `\!`** (breaking `jq '!='`, `fixup!`, `<!DOCTYPE>`): that's Claude Code transport bug #61121, not your quoting — work around with `$'\x21'`.
- **Bash-specific syntax** (arrays, `[[ =~ ]]` capture groups, etc.) → wrap in `bash -c '…'`.

<!-- Company-specific instructions live in a private repo (FrancisBehnen/dotfiles-private) and
     are imported below. On a public-only clone this file may be absent; scripts/setup.sh creates
     an empty placeholder so this import never dangles. -->
@~/.claude/CLAUDE.private.md

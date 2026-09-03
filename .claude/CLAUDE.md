# Global instructions

## Working with code
- Before answering a question about the **state of the codebase** (what exists where, what's merged, what's promoted to which environment, what a teammate has done), **sync the local checkout with upstream first** — the working tree is often stale. Use the repo's sync command, with the sandbox disabled: `git fetch upstream <branch>:<branch>` where a fork+upstream workflow exists, otherwise `git fetch` + `git pull --rebase`. Skip only for questions purely about your own uncommitted changes. **Never reach for `git sync-upstream` off `main`** — the alias rebases whatever is checked out and ends in `git push -f`.

## Shell commands (zsh eval environment)
Every Bash-tool command and slash-command `!`-preamble is eval'd through a snapshot of the interactive zsh config (Oh My Zsh aliases live, `extendedglob` on). Investigated 2026-07-20; upstream refs: claude-code#16163, #67146, #61121.

- **Quote every interpolated string.** Escape an embedded `'` as `'\''`. Quote-heavy or multi-line text goes in a `cat > f <<'EOF'` heredoc, never nested `echo` quoting.
- **Never splice user free-text into a command line** — pass it via a quoted variable, stdin, or a file. Skills that splice `$ARGUMENTS` into a shell line (e.g. plannotator-annotate) break on apostrophes: call the underlying CLI directly via Bash with proper quoting instead.
- **Globs:** `extendedglob` means `^` and `#` are pattern characters. Unmatched globs degrade to literals in Claude sessions (`unsetopt nomatch` guard in `.zshrc`), but prefer `(N)` qualifiers or `find` to make intent explicit.
- **If `!` arrives mangled as `\!`** (breaking `jq '!='`, `fixup!`, `<!DOCTYPE>`): that's Claude Code transport bug #61121, not your quoting — work around with `$'\x21'`.
- **Bash-specific syntax** (arrays, `[[ =~ ]]` capture groups, etc.) → wrap in `bash -c '…'`.

## Worktree-isolated subagents

A branch can be checked out in only one worktree, and a **finished** agent's worktree keeps holding
its branch. The next agent told to work on that branch gets git's "already checked out" refusal,
reads it as a broken repo, and reaches for `git reset --hard` — aimed at whatever branch is nearby,
often `main`. Observed three times in one session (2026-08-25); the resets failed rather than landed,
but the attempts are the signal that a branch is occupied.

- **Sweep each agent's worktree as it reports**, not at session end. Check `git worktree list` before
  dispatching an agent onto a branch a previous agent used.
- **Parking the primary checkout on `main` is not a cure** — it frees task branches but makes `main`
  itself unavailable to a worktree. A scratch branch nobody wants is better.
- **When an agent is already blocked**, the fix is `git push origin HEAD:refs/heads/<branch>` from its
  own `worktree-agent-*` branch, never a reset. Verify with
  `git log --oneline origin/<branch>..HEAD` first, and prefer `--force-with-lease` over `--force`.
- **Tell agents in their brief** that "already checked out" means an occupied branch, and that they
  must report a git-state block rather than work around it destructively.

### The same exclusivity applies to contended singleton tools

A tool holding **one global session** is as exclusive as a branch, and it fails far more quietly.
`playwright-cli` drives a single persistent browser: on 2026-09-03 two concurrent agents used it, one
agent's `navigate` silently overrode the other's, and the loser screenshotted a tab it had never
opened — believing its own render had failed. Nothing errored. The tell was an `eval` returning a
value that agent had never set: a `document.title` it did not write, and a `location.href` naming a
file it did not create.

- **Treat one-session tools as exclusive** — a browser, a fixed devserver port, a REPL, a named tmux
  pane. Serialise agents across them, or give each its own instance.
- **Verify identity in the result; do not trust the call.** Have the agent stamp something only it
  could know and assert it comes back. A screenshot is not evidence that *your* page rendered.
- **Prefer an offline check where one exists** — the loser here validated its Mermaid diagrams with
  the parser via bun + jsdom and needed no browser at all.
- **File-level disjointness is not isolation either** (2026-09-03, same session): two agents on
  genuinely different files still collide through a shared *caller*, and a half-applied signature
  change breaks everything downstream. Serialise when one agent changes a signature others call.

<!-- Company-specific instructions live in a private repo (FrancisBehnen/dotfiles-private) and
     are imported below. On a public-only clone this file may be absent; scripts/setup.sh creates
     an empty placeholder so this import never dangles. -->
@~/.claude/CLAUDE.private.md

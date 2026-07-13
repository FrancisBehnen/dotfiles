# Handoff — bring this machine in line with the primary (2026-07-13)

You are Claude on Francis's **secondary** machine. The **primary** machine just
reconciled the dotfiles and pushed. Your job: pull, adopt the corrections, and
install the newly-tracked CLI tools. Follow these steps in order. **Read the
whole doc before acting.**

Context: this is `FrancisBehnen/dotfiles` — a **bare repo** at `$HOME/.dotfiles`
(work-tree `$HOME`, alias `config`), plus a private sibling `$HOME/.dotfiles-private`.

> ⚠️ **Sandbox:** `config`/`git` here reads `/etc/gitconfig`; under a command
> sandbox that path is blocked (`Operation not permitted`). Run the git commands
> below with the sandbox disabled.

---

## 0. The one thing NOT to do

**Do NOT "fix" `"model": "opus[1m]"` in `.claude/settings.json` back to `"opus"`.**
`opus[1m]` is the intentional **1M-context Opus** alias, not a corrupted/ANSI
value. A previous session on this machine misdiagnosed it and downgraded it
(commit `f8b0409`); the primary machine reverted that. After you pull, the value
becomes `opus[1m]` again — **leave it**.

## 1. Pull both repos (sandbox OFF)

```bash
GD="$HOME/.dotfiles/"; GDP="$HOME/.dotfiles-private/"; WT="$HOME"
# Public
/usr/bin/git --git-dir="$GD"  --work-tree="$WT" status -sb          # expect clean-ish
/usr/bin/git --git-dir="$GD"  --work-tree="$WT" fetch origin
/usr/bin/git --git-dir="$GD"  --work-tree="$WT" merge --ff-only origin/main
# Private
/usr/bin/git --git-dir="$GDP" --work-tree="$WT" fetch origin
/usr/bin/git --git-dir="$GDP" --work-tree="$WT" merge --ff-only origin/main
```

Public `main` should land on **`f0f2d50`** or later.

- If the public merge is **not** a clean fast-forward, you have local commits or
  uncommitted edits that diverge. **Stop and reconcile** — do not force anything.
  Show `config log --oneline origin/main..main` and the working-tree diff, and
  ask Francis before proceeding.
- If a working-tree file blocks the checkout because it's an **untracked real
  dir** where the repo now tracks a **symlink** (this happened with
  `.claude/skills/nlm-skill` on the primary machine): back it up, `rm -rf` it,
  re-run the merge. Content is byte-identical; the symlink points at
  `../../.agents/skills/<name>`.

## 2. What arrives on pull (verify, don't redo)

- `.claude/settings.json` → `opus[1m]` (see §0).
- `.zshrc` → the fixed `skills()` (process-substitution restore + single-arg
  add-tracking). You committed this already (`d883134`); nothing to do.
- `Skillfile` → de-duped; **no** `notebooklm` lines. `nlm-skill` is now a
  git-tracked custom skill (content in `.agents/skills/nlm-skill` + symlink in
  `.claude/skills/`), so **don't** re-add it via `bunx skills add`.
- `nlm-skill` → bumped to 0.8.5 + `AGENTS_SECTION.md`. `find-docs` (Context7 CLI
  skill) present.
- New: **`CLIfile`** + `install_cli_tools()` in `scripts/setup.sh`.

## 3. Install the tracked CLI tools

These are the binaries that were previously set up by hand (`nlm`,
`playwright-cli` + browsers, `ctx7`, `defuddle`, `mcp2cli`). Run the tracked
installer directly (idempotent — it skips whatever you already have):

```bash
bash -c '
info(){ echo "[cli] $*"; }; warn(){ echo "[cli][warn] $*"; }
error(){ echo "[cli][err] $*" >&2; }
command_exists(){ command -v "$1" >/dev/null 2>&1; }
'"$(sed -n '/^install_cli_tools() {/,/^}/p' "$HOME/scripts/setup.sh")"'
install_cli_tools'
```

Prerequisites the installer needs on PATH: `node`/`npm`, `bun`, `uv`, `npx`.
If any tool is skipped for a missing manager, install that manager first (it's
what `setup.sh` does earlier) and re-run.

## 4. Verify

```bash
for c in "nlm --version" "mcp2cli --version" "ctx7 --version" \
         "defuddle --version" "playwright-cli --version" "glean --version"; do
  printf '%-22s ' "$c"; eval "$c" 2>&1 | head -1 || echo "MISSING"
done
ls -d "$HOME/Library/Caches/ms-playwright"/chromium-* 2>/dev/null || echo "chromium MISSING"
```

`glean` is installed by `setup_pulse_sources` (not the CLIfile) — if it's
missing run `brew install gleanwork/tap/glean-cli`.

## 5. Make the changes take effect

- Shell: `exec zsh` (picks up any `.zshrc` change).
- **Claude Code: fully restart it** so `model: opus[1m]` takes effect (a change
  to `settings.json` does not hot-reload a running session).

## 6. One-time auth (only if you actually use these here)

Not scriptable — do only if needed: `nlm auth`, `glean auth login`, Fellow
OAuth (`uvx mcp2cli --mcp https://fellow.app/mcp --oauth --list`).

## 7. Report back

Summarize to Francis: which tools were already present vs. freshly installed,
whether both repos fast-forwarded cleanly, and confirm you did **not** touch
`opus[1m]`. If anything diverged in §1, surface it instead of forcing.

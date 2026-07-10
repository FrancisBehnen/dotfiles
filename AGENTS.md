# Dotfiles Repository — Claude Code Instructions

This is `FrancisBehnen/dotfiles` — a bare git repo (`$HOME/.dotfiles`) with work tree at `$HOME`. It uses a `config` alias instead of `git` for all dotfile operations.

## Repo Layout

```
.claude/                     — Claude Code config (settings, statusline, permissions)
.zshrc                       — Main shell config (Oh My Zsh, plugins, PATH, aliases)
.gitconfig                   — Git user config + credential helpers (dynamic gh path)
.gitmodules                  — Submodule definitions (Oh My Zsh, p10k, plugins)
.oh-my-zsh/                  — Oh My Zsh (submodule)
.oh-my-zsh_custom/           — Custom plugins/themes as top-level submodules
.p10k.zsh                    — Powerlevel10k config
.tmux.conf                   — tmux config (tpm plugins)
.vimrc                       — Vim config
Brewfile                     — Homebrew packages
myports / requested_ports    — MacPorts snapshots
scripts/
  setup.sh                   — Bootstrap script (admin/non-admin aware, idempotent)
  claude-mv                  — Move project directories + migrate Claude context
  vintage                    — Install pinned Homebrew versions (admin only)
support_and_preference_files_to_migrate/  — App preference files + link script
```

## Key Conventions

- **Bare repo pattern:** All dotfile operations use `config` alias (`/usr/bin/git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME`). Never use plain `git` for dotfile operations on the user's machine.
- **No hardcoded paths:** Use `$HOME` instead of `/Users/francisbehnen/` everywhere. The `.gitconfig` uses dynamic `gh` detection (`!which gh`) instead of a hardcoded path.
- **Conditional plugins:** The `macports` Oh My Zsh plugin loads only if `port` is available (`(( $+commands[port] ))`).
- **Admin vs non-admin:** The `scripts/setup.sh` script detects admin rights and adjusts installation. Homebrew formulas work without admin; some casks require admin. MacPorts works both with admin (system-wide `/opt/local`) and without admin (user-local `$HOME/macports` built from source with `--with-no-root-privileges`).
- **Submodules:** Custom Oh My Zsh plugins/themes go in `.oh-my-zsh_custom/` (not inside `.oh-my-zsh/`) because git doesn't support submodules inside submodules.
- **Package manager:** `CLAUDE_PACKAGE_MANAGER=bun` is set in `.zshrc`. Use `bun` for Claude Code package operations.

## Multi-Agent Support

- **Claude Code:** Config tracked in `.claude/` (settings.json, settings.local.json, statusline.sh)
- **GitHub Copilot CLI:** Installed via the native `copilot` CLI installer. `scripts/setup.sh` also accepts an existing legacy `gh copilot` install.
- **Other agents:** See "Adding Other Agents" in README.MD for the pattern

## Claude Code restore architecture (what transfers to a new machine)

The `~/.claude` setup is reproduced from **two bare repos + a Skillfile + a Pluginfile**. When reasoning about "will X transfer" / "is X tracked", use this map:

- **`~/.dotfiles`** (public repo, alias `config`) — tracks `.claude/settings*.json`, `statusline.sh`, `bin/`, `.claude/CLAUDE.md`; **`Skillfile`** (agent skills); **`Pluginfile`** (public marketplaces + plugins); `scripts/setup.sh`. Custom skills live in `~/.agents/skills/<name>` (real content, tracked) and are symlinked into `~/.claude/skills/` (symlink, tracked) — e.g. `caffeinate`, `fellow`.
- **`~/.dotfiles-private`** (private repo) — `.claude/CLAUDE.private.md`, `DOTFILES-PRIVATE.md`, `.guardrail/`, `.claude/projects/` (**auto-memory**), private skills (`project-pulse` + its siblings `align-projects`/`onboard-project`/`resume-session-project`/`save-session-project`/`start-pulse-cron`, `project-context-sync`), and **`Pluginfile.private`** (the internal Coolblue marketplace — kept out of the public repo; `.gitignore`d there).
- **`Skillfile`** → `skills` CLI (`bunx skills add`). Restored by `setup.sh` (word-splits each line, so a line may carry flags like `jacob-bd/notebooklm-mcp-cli --copy` for PromptScript skills that can't be symlinked globally). Big packs: `mattpocock/skills`, `kepano/obsidian-skills`, `anthropics`-sourced skills via plugins.
- **`Pluginfile`** → `claude plugin marketplace add` + `claude plugin install`, restored by `setup.sh` (`install_claude_plugins`). **Plugins provide most of the surface** — `plannotator` (the plannotator-* skills), `frontend-design`, `playwright`, `skill-creator`, `context7` (an MCP), `claude-obsidian` (obsidian suite), `hookify`, `commit-commands`, `feature-dev`, `pr-review-toolkit`, `claude-md-management`, and the `pyright`/`typescript` LSPs. So these are **not** file-tracked — they return with their plugin.
- **MCP servers**: almost all are **claude.ai account connectors** (`mcp__claude_ai_*`) — re-auth per machine, not in any repo. The only local MCP configured in `~/.claude.json` is **`pencil`** (`context7` comes from its plugin). `~/.claude.json` is account/session state, tracked by neither repo.
- **ECC** (`everything-claude-code`, `affaan-m/ECC`) was fully removed 2026-07 — do not reintroduce its agents/commands/hooks/AGENTS.md/mcp-configs. If leftover ECC artifacts reappear, they are `~/.claude/{AGENTS.md,hooks,scripts,mcp-configs,plugin.json,marketplace.json}` and any skill with `origin: ECC`.

When asked "what transfers", answer against this map, not a raw `.claude/` file listing.

## Maintenance Tasks

When asked to do periodic maintenance in `~/`:

1. `brew bundle dump --force --file=~/Brewfile` — sync Brewfile
2. `port installed > ~/myports` — snapshot MacPorts (if available)
3. `port echo requested | awk '{print $1}' | sort -u > ~/requested_ports` — sync requested ports (if available)
4. `config submodule update --remote` — update plugins/themes
5. Check preference symlinks are intact
6. `config diff` → review, commit, push

## Rules

- Do NOT add hardcoded username paths — always use `$HOME` or `~`
- Do NOT assume admin rights — check or make operations conditional. MacPorts commands should use `sudo port` only when `$IS_ADMIN` is true; non-admin installs in `$HOME/macports` need no sudo.
- Do NOT modify `.p10k.zsh` unless explicitly asked (it's auto-generated by `p10k configure`)
- Keep the `vintage` and BTT preference migration scripts as-is (admin-only tools)
- The `scripts/setup.sh` must remain idempotent (safe to re-run)

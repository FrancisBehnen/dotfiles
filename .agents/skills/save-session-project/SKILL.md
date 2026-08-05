---
name: save-session-project
description: Save the current session AND mirror its status into the matching project's Obsidian note. Project-aware wrapper around /save-session — use instead of it when the work belongs to a project-pulse project, so the session's status and next steps land in the vault note too. Triggers on "save session", "checkpoint this session", "wrap up for today" on a tracked project.
---

# Save session + mirror to project note

Wrapper: run `/save-session`, then push the project-relevant parts into the project note. Mirror logic lives here (owned, update-stable), not in the managed `/save-session` (which gets overwritten).

## 1. Save

Run `/save-session` (follow `~/.claude/commands/save-session.md`) — including its confirmation step. Inherit whatever it does.

## 2. Mirror into the note — always, proactively

The mirror is not optional and not gated on the user: do it in the same turn as the save (right after showing the session file), without waiting for confirmation or being asked. If the user then corrects the session file, re-mirror the affected parts in the same turn as the correction.

Resolve the note from the session's `Project:` repo: its `.agents/project-context.md` `## Vault notes` block (or a legacy single `Vault note` pointer), falling back to `repo:` across the vault notes. The block may declare **multiple notes** — a primary (the repo's own note) plus per-sub-project notes; an orchestration repo hosts several projects. Pick by what the session actually worked on: repo/orchestration machinery → the primary; a hosted project → that project's note (both, if the session genuinely spanned them). Then:

- **Stamp the resolution into the session `.tmp` first**: add a `**Vault note:** <path>` line to its header (right under `**Project:**`), listing every note this save mirrors into. resume-session-project reads this stamp before anything else — it's what makes resume unambiguous on multi-note repos. (Exception to the "never modify the `.tmp`" rule: the stamp is part of the save, added in the same turn.)
- **Current status** ← What We Are Building + outcome.
- **Next steps** ← Exact Next Step, then Blockers, then Not-Tried-Yet.
- **Changelog** ← prepend `## [YYYY-MM-DD HH:mm] session — <topic>` with the next step and a link to the `.tmp`, so resume can reach the full detail.
- **Reconcile Next steps against the new status**: on every mirror, walk the Next-steps list for numbers and paths that contradict the just-written status block (commit counts, filenames/versions, choice counts) and align them — the status block and Next steps must never show different numbers for the same fact. (On 06-07 Next steps lagged the status block: "18" vs "22" commits, and a deck-v4 path while v6 existed.)
- **Respect the alignment lock**: if the note has uncommitted edits, merge around them — don't clobber.
- Commit by pathspec (not `git add wiki/`) + push, leaving a clean tree so the pulse resumes ownership.

No note for this repo → offer `onboard-project`, don't block. Vault/pointer missing → note it and finish; the save is the primary job.

## 3. End with a CLEAN worktree — always

A session ends with `git status --porcelain` empty in every repo it touched. Walk each untracked path and give it **one of three dispositions**:

- **commit** it — it is evidence (a run log, an artifact, a report);
- **gitignore** it — regenerable noise, and the ignore rule is part of the commit;
- **delete** it — junk.

***"Inherited from a previous session; left alone" is never a valid disposition.*** If a path arrived untracked, resolving it is this session's job. Measured 05-08: four `judge-calibration/*.log` files sat untracked from 03/04-08 through **three** consecutive sessions, each of which wrote "inherited; left alone" in its own `.tmp` and worked around them; the fourth session then swept them in with a `git add -A` — a *consequence* of the debt, not an independent slip. All four were committed in the end (every sibling artifact in their directories was already tracked, the repo already carried 33 other run logs, no ignore rule covered them), so they had been omissions all along. A clean tree is also what makes `git add -A` safe, which is why this rule beats "stage by pathspec": that one fixes the symptom.

Same for the scratchpad: if any committed file or note references a scratchpad script, promote it into the repo now (see §4) — the scratchpad is session-ephemeral.

## 4. Skills retrospective — always

After the mirror, do this yourself by **introspection** — look back over the conversation already in your context and answer one question: **which skill would have done better today if it had already known what this session learned?** (No subagent: a spawned agent doesn't see this conversation, and exporting the transcript to give it one is exactly the cost we're avoiding. You just re-read what you already hold.) Scan for:

- corrections the user made (a skill produced the wrong default);
- gotchas hit and solved (auth quirks, API behaviors, format traps — anything a next session would re-derive);
- patterns invented ad hoc that a skill should own (new artifact shapes, new verification tricks);
- **tooling created in the scratchpad** — session-ephemeral! If any committed file or note references a scratchpad script, that script must be promoted into the repo NOW or it's gone;
- decisions that invalidate a skill's stated assumptions (thresholds, model choices, review routes).

Then act on the findings by ownership:

- **Repo-local skills and guidelines** (`<repo>/.claude/skills/`, `guidelines/`): apply the updates directly, commit, push — same-session promotion is the point; a lesson that waits for "later" is lost.
- **Global/private skills** (`~/.claude/skills/`, plugins): do NOT edit unasked — list them as concrete recommendations (skill + exact change) in the wrap-up message AND the session `.tmp`, so the user can approve in one word.
- **Nothing to promote** is a fine outcome — say so in one line; don't invent churn.

## Notes

- Loop: the note holds short status + next steps (Obsidian-visible, feeds the pulse); its Changelog links back to the full `.tmp`.
- Per-project note, so multiple (branch-specific) sessions roll into one: Current status = latest, Changelog accumulates. Pairs with [[resume-session-project]].

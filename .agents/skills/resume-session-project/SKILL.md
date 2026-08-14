---
name: resume-session-project
description: Resume the latest session FOR THE CURRENT PROJECT (not the global-latest that plain /resume-session defaults to) and load that project's Obsidian note, so you start fully context-aware — the session .tmp has the deep working detail, the note has the pulse-fresh status, next steps, linked docs, and what changed since the session was saved. Project-aware wrapper around /resume-session; use instead of it when continuing a project-pulse project. Triggers on "resume session", "pick up where I left off", "what was I doing", start-of-day on a tracked project.
---

# Resume session + project note

Wrapper: project-scoped `/resume-session`, then enrich with the vault note. The `.tmp` is a point-in-time archive; the note is the live, pulse-maintained state and may be newer.

## 1. Resume the project's latest session

Plain `/resume-session` grabs the global-latest `.tmp` — wrong for project work. Instead: target = the repo the user named, else the current repo. Find the newest session file whose `Project:` matches that repo, and run `/resume-session` (follow `~/.claude/commands/resume-session.md`) on **that file**. No repo context → fall back to global-latest, say so. No matching session → brief from the note alone (Step 2), say there's no saved session yet.

## 2. Load the matching note

Resolve the note in this order — stop at the first that resolves:

1. **The `Vault note:` line in the session `.tmp` header** (stamped by save-session-project): read exactly the note(s) listed there. No inference — the save already knew where it mirrored.
2. **The repo's `.agents/project-context.md` `## Vault notes` block** (or a legacy single `Vault note` pointer). The block may declare **multiple notes**: a primary (the repo's own note) plus per-sub-project notes — orchestration repos host several projects under one repo. Pick by the session's `Topic:`/content: work on the repo/orchestration machinery itself → the primary; work on a hosted project → that project's note. Unclear → read the primary and name the other declared notes in the briefing so the user can redirect in one word.
3. `repo:` frontmatter across the vault project notes.

Read status, next steps, linked `project-doc`s, recent Changelog, `last_pulse`.

## 3. Re-verify the CHEAP baselines — never the expensive ones

A `.tmp` states numbers as of when it was written; a stale one travels into the briefing as current fact (04-08: a wrong "23/43" went from a `.tmp` into a subagent brief and was only caught by that agent's own measurement). So re-measure the cheap ones instead of restating them — **issue them as parallel tool calls in the same message as reading the note**, where the marginal cost is ~0. Measured 05-08: `judges.test_offline` **3.22s**, `test_pipeline_offline` **0.15s**, CSV row count + git ahead/behind + HEAD **0.23s** — ~3.6s total.

Cheap = offline test suites, row/line counts, md5s, file existence, git state. **Nothing that touches the network.**

⚠️ **Never re-verify an expensive baseline at resume.** Anything needing model draws (a judge probe at n=12, a generation run, a stability grid) costs real spend and minutes. Carry those forward **labelled with provenance** instead — *"measured 05-08, n=12, not re-verified this session"* — which closes the stale-number failure without paying to re-measure.

⚠️ **Labelling alone does not make a carried number safe — check the source's rebuild cadence.** If the source rebuilds on a schedule shorter than the number's age, re-measure or drop the claim (08-10: a correctly dated 13-day-old count off a daily-rebuilt BigQuery view still travelled into two arguments and a peer's report as current fact).

ⓘ Honest about what this buys: on 05-08 it confirmed two baselines and caught nothing. It is cheap insurance against a stale `.tmp`, not a bug-finder — and it does **not** catch a threshold that was wrong the first time it was written (that belongs to whoever wrote it).

## 4. Append a "FROM THE VAULT" section to the briefing

Pulse-maintained Current status; live Next steps (flag where they differ from the session's); **what changed since the session's Last Updated** (Changelog entries after that time = what the pulse learned while away); any **uncommitted edits** in the note (the user's un-acted-on opinions); links to docs worth opening. This reconciliation is the point.

## 5. Freshness, then wait

If `last_pulse` is stale (older than the session, or new day with no pulse yet), offer a fresh `project-context-sync` — don't auto-run. Then wait (don't touch files / start work); proceed only on "continue".

## Notes

- Read-only on both: never modify the `.tmp`; leave the note's uncommitted edits intact (they're alignment input).
- Pairs with [[save-session-project]].

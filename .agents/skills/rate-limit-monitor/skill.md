---
name: rate-limit-monitor
description: Monitor API rate limits and automatically sleep/wake when approaching the 5-hour window limit. Use this skill whenever starting a long autonomous work session, when you hit or are about to hit rate limits, when the user mentions "rate limit", "usage limit", "token limit", "window limit", or "quota", or when you need to wait for a rate limit window to reset before continuing work. Pairs with /loop for fully autonomous rate limit management.
---

# Rate Limit Monitor

Check the Anthropic API rate limit windows and, when usage is too high to keep working, enter a sleep/wake cycle that waits for the window to reset — then resume.

## Check current usage

Run the helper script. It calls the Anthropic OAuth usage API directly (keychain + network, so it needs `dangerouslyDisableSandbox: true`):

```bash
~/.claude/skills/rate-limit-monitor/check-usage.sh
```

The script returns JSON:

```json
{
  "five_hour":  { "utilization": 62.0, "resets_at": "...", "resets_in_minutes": 148 },
  "seven_day":  { "utilization": 14.0, "resets_at": "...", "resets_in_minutes": 8820 }
}
```

`utilization` is the percentage consumed (0–100). `resets_in_minutes` is how long until the window rolls over and utilization drops.

If the script fails (token not found, network issue), fall back to the statusline cache at `/tmp/claude-sl-usage`. Its format is `U5|U7|XO|XU|XL|RM5|RM7` — U5 is 5h utilization, RM5 is minutes until reset.

## Decide what to do

The 5-hour window is the binding constraint for most sessions. React based on its utilization:

- **Under 80%** — All clear. Report the numbers briefly. If running in a `/loop`, schedule the next check at 270s to stay inside the prompt-cache TTL (5 min). If a tmux fallback is armed from an earlier warning, cancel it (`arm-tmux-fallback.sh cancel`).
  - **No work left**: monitoring exists to protect work in flight. If utilization is under 80% AND nothing is queued or running (no subagents, no pending merges/deploys/verifications, no user request outstanding), the session is **completed** — don't keep idling on monitor ticks. Follow "Ending a session" below: stop the loop (CronDelete), cancel any armed fallback, run `/save-session`. If work might resume shortly (user present and deciding), say so and ask once rather than silently burning ticks.
- **80–90%** — Warning zone. Tell the user. If doing autonomous work, throttle (fewer parallel agents, skip optional steps). **Arm the tmux hard-cap fallback NOW** for `(resets_in_minutes + 3) * 60` seconds — at higher utilization the permission classifier or API may already be down, making the arming command itself fail (this happened in practice: at 99% the Bash call to arm the fallback was rejected because the classifier model was unavailable). Arming early is free; re-arming later replaces the sleeper. Next check at 270s.
- **Over 90%** — Stop working and enter the sleep cycle below. The fallback should already be armed from the warning zone; re-arm it only if the command still works.

If the 7-day window is also above 90%, warn the user separately — that one has a much longer reset and may need a different plan (e.g., waiting a day).

## Sleep cycle

The point of the sleep cycle is to park the session until the 5h window resets, without losing the conversation. `ScheduleWakeup` caps at 3600s (1 hour), and a reset can be up to ~5 hours out, so the cycle wakes briefly every hour to re-check. Each wake-up is cheap: one API call, one decision, back to sleep. This keeps the session alive and avoids starting cold from a separate process.

1. Read `resets_in_minutes` from the usage check.
2. Pick a sleep duration:

   | Time until reset | Sleep duration | Rationale |
   |------------------|---------------|-----------|
   | > 60 min | 3600s (1 hour) | Max allowed. Wake, re-check, sleep again. |
   | 5–60 min | `(resets_in_minutes + 2) * 60` | Land just after the reset. |
   | 0–5 min | 270s — **once only** | Stay in prompt cache, wake right after reset. If utilization is still ≥90% on that wake, do NOT repeat — fall through to the stale-reset rule below. |
   | **≤ 0 min (stale/frozen)** | **3600s (hibernate)** | A `resets_at` in the past with utilization still ≥90% means the reset estimate is WRONG, not that the window is about to roll. (Root cause found 2026-07-08: `check-usage.sh` parsed the UTC timestamp as local time, making every estimate 2h early in CEST — fixed with `date -u`. The rule stays as defense against any future estimate bug.) Treat the reset time as UNKNOWN. Do NOT rapid-poll — every short wake burns the very window you're waiting on. Hibernate in 1-hour hops until utilization itself drops below 80%. |

   **Hard rule: while utilization is ≥90%, never schedule a wake-up shorter than 3600s** except the single 0–5-min case above. Utilization dropping below 80% is the ONLY resume signal — not the reset timestamp, and not "tools still seem to work".

3. Call `ScheduleWakeup` with the chosen delay. Pass the `/loop` prompt through so the loop continues on wake-up.
4. **Arm the hard-cap fallback** (see section below) for `(resets_in_minutes + 3) * 60` seconds:

   ```bash
   ~/.claude/skills/rate-limit-monitor/arm-tmux-fallback.sh $(( (RESETS_IN_MINUTES + 3) * 60 ))
   ```

5. On wake-up, run `check-usage.sh` again:
   - Utilization dropped below 80% → the window has reset. Cancel the fallback (`arm-tmux-fallback.sh cancel`), report to the user, and resume work.
   - Still high → repeat from step 2 (re-arming the fallback replaces the previous sleeper, so it always targets the latest reset estimate).

**A sleep-cycle wake-up is exactly three actions**: one `check-usage.sh` call, one decision, one `ScheduleWakeup` (plus re-arming the fallback). Do NOT re-create the monitoring cron (that happens once, on resume below 80%), do NOT start or resume work, do NOT write lengthy status reports — one short line is enough. Doing work at ≥90% because "the API still responds" is how sessions die mid-tool-call.

## Subagent interruption protocol

Background subagents burn the same window and die uncontrolled at a hard cap — mid-tool-call, with their final report replaced by the cap error. Twice-observed failure mode: the agent's work survives only because its git worktree persists. Don't rely on that luck; interrupt on your own terms:

- **At 85%+ with subagents running**: `TaskList` to enumerate them, then `TaskStop` each running agent. Their worktrees keep all partial work (committed or not). Record per agent: worktree path, branch, and what remained to be done — you'll spawn continuation agents there after the reset.
- **After the reset**: inspect each worktree (`git log`/`git status`) before spawning the continuation — agents often got further than their last report suggests (pushed branches, opened PRs).
- **Prompt-level prevention**: every long-running agent prompt should instruct: *"Commit WIP to your branch at each substantial milestone (conventional `wip:` commits are fine, squash later) so interruption loses minutes, not the session."*
- Below 80% with fresh capacity, resume normally; don't restart still-running agents that survived.

## Hard-cap fallback (tmux)

`ScheduleWakeup` is delivered by the harness through the API. If the account hits a **hard cap** — monthly spend limit reached, API refusing all calls — the scheduled wake-up is never delivered and the session sits idle even after the window resets. A message typed into the Claude Code pane wakes the REPL unconditionally, so the fallback is a detached local sleeper that does `tmux send-keys` into this pane after the reset:

- `arm-tmux-fallback.sh <delay_seconds> [message]` — arms (or re-arms, replacing the previous sleeper) a wake message into the pane identified by `$TMUX_PANE`. Survives the session being capped because it's a plain local process.
- `arm-tmux-fallback.sh cancel` — disarms it. Always cancel after a successful wake so a stale "wakey wakey" doesn't land mid-conversation later.
- Outside tmux the script is a no-op (it says so on stderr); ScheduleWakeup is then the only wake path.

Arm it every time you enter the sleep cycle — it costs nothing and covers the failure mode ScheduleWakeup can't.

### Example calls

Routine monitoring (usage is fine):
```
ScheduleWakeup({
  delaySeconds: 270,
  reason: "Rate limit at 45% — next check in 4.5 min (cache-warm)",
  prompt: "<the /loop prompt>"
})
```

Entering sleep (reset far away):
```
ScheduleWakeup({
  delaySeconds: 3600,
  reason: "Rate limit at 93% — sleeping 1h, reset in 150 min",
  prompt: "<the /loop prompt>"
})
```

Almost reset:
```
ScheduleWakeup({
  delaySeconds: 600,
  reason: "Rate limit reset in 8 min — waking just after",
  prompt: "<the /loop prompt>"
})
```

## Resuming

When utilization drops below 80% after a sleep cycle:

1. Report the fresh usage numbers to the user.
2. If this was invoked through `/loop`, continue with the loop's original task.
3. If invoked standalone, report "Window has reset" and stop.

## Ending a session: save-session is mandatory on completion

Distinguish two ways a monitored session can end:

- **Paused** (sleep cycle, waiting for a window reset): the conversation stays alive and resumes in place — do NOT run `/save-session`; the context is the state.
- **Completed** (the work the loop was supporting is done, the loop is being stopped, or the user is wrapping up): ALWAYS run `/save-session` as the final step, after stopping the loop (CronDelete / omitting ScheduleWakeup) and cancelling any armed tmux fallback. The session file must capture: what shipped (PRs/commits), what was verified live, failed approaches not to retry, and the exact next step — so a future session can resume via `/resume-session` without this conversation.

If in doubt whether the session is paused or completed, treat it as completed — a redundant session file is cheap; a lost session state is not.

## Platform notes

- **macOS**: The script extracts the OAuth token from the macOS Keychain (`security find-generic-password`).
- **Linux**: Falls back to `secret-tool` or `~/.claude/.credentials.json`.
- **Env override**: Set `CLAUDE_CODE_OAUTH_TOKEN` to skip keychain lookup entirely.

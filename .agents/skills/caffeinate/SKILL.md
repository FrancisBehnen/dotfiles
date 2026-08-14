---
name: caffeinate
description: Set up a long-running or overnight Claude Code session on macOS — start a TIME-BOUNDED `caffeinate` to keep the Mac awake, then tear it down automatically (run save-session-project first, kill caffeinate LAST) the moment the work is done, without the user having to come back. Use whenever the user is about to kick off a long run, an overnight job, or says "caffeinate", "keep the mac awake", "we'll be running a while", "I'm going to sleep, you finish", or "set up the session".
---

# Caffeinate a session

The point of this skill is unattended: the user kicks off work, steps away, and **you** finish and clean up — without the machine running all night and without the user having to return just to trigger the teardown. **Invoking this skill is itself the signal that the user is stepping away from the computer — assume that from the moment it's invoked.** A later message from them is not evidence they're back at the keyboard; don't treat their apparent presence as a reason to keep the Mac awake or to defer the teardown. Three hard lessons are baked in below:

- **Front-load every question.** Because the user is stepping away, surface any decision or clarification the work might need UP FRONT — in the turn the skill is invoked, before you start the work — and get the answers while they're still here. Think ahead about what could block you mid-run and ask it now. If an unforeseen blocking decision does surface once they're gone, make the best reversible call, record it (a decision block per pipeline-comms where that applies), and keep going; never stall the unattended run waiting on input that may be hours away. **Front-load the peer sessions too:** if a parallel session gates your teardown, message it early that the Mac is being held for it and ask it to report blockage, so the keep-awake isn't burned on a stall (08-10: the user had to prompt for this).
- **Never start an unbounded caffeinate.** An infinite `caffeinate -dimsu` that relies on a teardown which might not fire will keep the Mac awake all night. Always bound it with `-t`.
- **Never defer the teardown to the user.** Queuing "kill caffeinate / save the session" as tasks the user must trigger means the whole conversation gets re-sent uncached later just to run cleanup. Run the teardown **yourself**, in the turn where the work finishes.

## 1. Estimate the run length, then start a BOUNDED caffeinate

Ask (or infer) how long the work should take, and set `-t` to that plus a margin — this is the safety net that guarantees the Mac sleeps even if teardown never runs. Default to **8h (28800s)** if unattended/overnight and no estimate is given; never omit `-t`.

**Run this with the sandbox disabled** (`dangerouslyDisableSandbox: true`). caffeinate needs real process control; under the sandbox it fails on `nice` *and can leave an untracked orphan `-dimsu` process* — which is exactly how a past session kept the Mac awake all night.

```bash
mkdir -p /tmp/claude
SECS=28800   # <-- set to (expected run + margin); 28800 = 8h default
# Kill any stray -dimsu we may have spawned before (orphan-proofing); never touch `caffeinate -i -t 300` (Claude Code's own).
pkill -f 'caffeinate -dimsu' 2>/dev/null
caffeinate -dimsu -t "$SECS" >/dev/null 2>&1 &
echo $! > /tmp/claude/caffeinate.pid
disown
```

**Verify** exactly one of *our* processes is running, and that the PID file matches, before moving on:

```bash
pgrep -fl 'caffeinate -dimsu'   # expect exactly ONE line; its PID must equal $(cat /tmp/claude/caffeinate.pid)
```

If you see more than one `caffeinate -dimsu`, kill the extras — an untracked orphan is the failure mode this guards against. Report the PID and the timeout (e.g. "keeping awake up to 8h, PID 12345") to the user.

## 2. Teardown — run it yourself when the work is done, don't hand it back

The teardown is **your** job to execute, not the user's. When the kicked-off work is complete (all queued tasks done and nothing left you can do without new input), run both steps in that same turn **IN THIS ORDER** — do not stop and ask, and do not leave them as tasks for the user to trigger later:

1. **Run `/save-session-project` FIRST**, while the Mac is still awake — and finish every other teardown chore too (final commits/pushes, the wrap-up message, notifications). Everything that needs the machine up must happen here, before caffeinate dies.
2. **Kill caffeinate — robustly, as the VERY LAST action** (sandbox disabled). Kill the tracked PID *and* sweep any stray `-dimsu` orphan, but never Claude Code's `caffeinate -i -t 300`:
   ```bash
   kill "$(cat /tmp/claude/caffeinate.pid)" 2>/dev/null
   pkill -f 'caffeinate -dimsu' 2>/dev/null   # catches orphans the pid file missed
   rm -f /tmp/claude/caffeinate.pid
   pgrep -fl 'caffeinate -dimsu' || echo "clean — only Claude Code's -i -t 300 may remain"
   ```

**Why this order (hard lesson):** if you kill caffeinate first, the Mac can start sleeping mid-teardown — before `/save-session-project` and the final commit/push finish — and the cleanup gets cut off. Observed on multiple sessions. Keep caffeinate up until the very end so nothing is interrupted; the `-t` timeout from §1 is the backstop if the kill itself never runs.

**Do not defer this by waiting for more input.** You cannot predict whether the user will send another message — that is true after every turn — so it is never a reason to hold off. When the current batch of work is done, tear down. If more work arrives afterwards, just re-caffeinate. Running `/save-session-project` directly, in the turn the work finishes, is the **only** way to avoid a later teardown that re-sends the whole conversation uncached.

**Always** also add these two as TaskCreate tasks in the same order (run `/save-session-project` first, then kill caffeinate LAST), so the teardown survives a context summary and still happens if this turn is interrupted. The tasks are the survival backstop; the `-t` timeout from §1 is the machine-safety backstop; running the teardown yourself when the work is done is the primary mechanism. All three are required.

That's it — start the bounded keep-awake now, do the work, then tear down yourself.

---
name: live
description: Start the live voice talker from the session you're in. live-talker's talk.py (gpt-audio-mini via the AI Service Router) holds the voice, and this session becomes the thinker. It answers the talker's ask_main requests with the tell_talker tool and continues on screen after hand_back. Use it when Francis types /live, or says "go live", "start the live talker" or "live voice". Don't use it for "let's talk", "start voice" or "talk to me": those go to /talk, which stays the fallback. Optional arguments are `pane` (run the talker in a Herdr pane so he can watch the transcript live), `dutch`, and a topic for the session brief.
---

# live: Mini talks, this session thinks

The talker is `~/Code/live-talker/talk.py` ("Mini", gpt-audio-mini). It holds the voice and sends anything that needs thought to you through your own inbox socket. You answer through the `tell_talker` MCP tool. The design is in GitHub FrancisBehnen/a-genai-i #85 (map #68). Background is in `~/Code/live-talker/README.md`.

## Check first (stop and tell Francis if one fails)
1. **The tool is loaded:** run ToolSearch `select:mcp__tell_talker__tell_talker`.
   - The server has been registered at user scope in `~/.claude.json` since 2026-10-11, and the tool is allowed in `~/.claude/settings.json`.
   - If the tool is missing, this session started before the server was registered, or the server failed to start. A restarted session gets it. Without it, no `ask_main` can be answered.
2. **The inbox socket exists:** `test -S "$CLAUDE_CODE_MESSAGING_SOCKET" && echo "$CLAUDE_CODE_MESSAGING_SOCKET"`
3. **One voice at a time:**
   - No `/talk` talker may be running in this session.
   - `/Users/francis.behnen/.local/bin/voicemode conch status` must say the conch is free. Don't release it yourself. talk.py does not take the conch, so this check is the guard.
   - If another live talker is running anywhere, talk.py itself refuses with `ERROR: ... another talker is listening`.
4. **Find the mic:** the AirPods index if they are connected, otherwise 0, the built-in mic. Tell Francis which one you picked.
   `ffmpeg -hide_banner -f avfoundation -list_devices true -i "" 2>&1 | sed -n '/audio devices/,$p' | grep -i airpods | sed -E 's/.*\[([0-9]+)\] .*/\1/' | head -n 1`

## Start
1. **Turn the soundfonts off** (VoiceMode's tool-call sounds), so no sound plays over the talker. Run `bash ~/.agents/skills/live/scripts/soundfonts.sh off`. It sets `VOICEMODE_SOUNDFONTS_ENABLED=false` in `~/.voicemode/voicemode.env` and remembers the old value. If the value was already false, it changes nothing.
2. **Arguments:**
   - **A topic:** write the brief with the Write tool to `~/.local/state/live-talker/live-brief.txt`, then add `--system "$(cat ~/.local/state/live-talker/live-brief.txt)"`. Never splice his words into the command line.
   - **`dutch`:** add `--dutch --stt-lang nl`.
3. **Background mode (the default).** Run Bash with `run_in_background: true`, with the sandbox off, because it needs the mic, the router and `~/.local/state`. Put in MIC as a literal number:
   ```
   python3 -u /Users/francis.behnen/Code/live-talker/talk.py --model gpt-audio-mini --mic-device MIC --target-socket "$CLAUDE_CODE_MESSAGING_SOCKET" < /dev/null 2>&1; echo "TALK_EXIT=$?"
   ```
   Wait for the start with `for i in $(seq 40); do grep -qE '^(bridge:|ERROR)' <output-file> && break; sleep 0.5; done; grep -E '^(TALKER|bridge:|ERROR)' <output-file>`. You should see two lines:
   - `TALKER pid=<pid>`: note the pid.
   - `bridge: tools ask_main, hand_back -> <socket>`

   If you see `ERROR:` instead, go to "When it ends".
4. **Pane mode (on request).** Load the `herdr` skill and follow it to split a sibling pane with `--no-focus`.
   - **Run the command.** Use the command above without `< /dev/null`, so Enter can end his turn. The pane's shell does not have this session's variables, so your shell expands the socket path, and `\$?` reaches the pane unexpanded. Add `--dutch --stt-lang nl` as plain words. Add a topic as `--system \"\$(cat ~/.local/state/live-talker/live-brief.txt)\"`, so the pane's shell reads the file. Never expand the brief into the command line.
     ```
     herdr pane run <pane> "python3 -u /Users/francis.behnen/Code/live-talker/talk.py --model gpt-audio-mini --mic-device MIC --target-socket $CLAUDE_CODE_MESSAGING_SOCKET; echo TALK_EXIT=\$?"
     ```
   - **Watch it:** run `herdr pane wait-output <pane> --regex 'TALK_EXIT=[0-9]+' --source recent-unwrapped` with `run_in_background: true`. Never run it in the foreground, because that blocks every `ask_main`.
   - **Get the pid:** `herdr pane read <pane> --source recent-unwrapped --lines 20` shows the `TALKER pid=` line.
5. **Tell Francis on screen,** in a line or two:
   - He is live and speaks after the bell.
   - The mic you picked.
   - "Say 'hand back' when you're done, or type stop."
   Then **end your turn.** The talker's messages reach you while you are idle or between tool calls.

## While it runs
- **Voice requests** come in as `[Voice request from Francis, relayed by his live-talker ...]`.
  - Answer only with `mcp__tell_talker__tell_talker`: one to three short spoken sentences, with no markdown, code or paths. Your on-screen text is not heard.
  - If the work takes more than about 20 s, send a one-line status first, then the answer.
  - Delegate edits as usual.
- **Turn logs** come in as `[live-talker turn log N: ...]`.
  - Stay silent, and keep anything on screen to a few words.
  - Make one `tell_talker` correction only if Mini got something wrong: it misunderstood him, reworded a name, path or number, or told him something wrong.
- **Never speak through VoiceMode** while the talker runs. That means no converse call (MCP or CLI) and no `/talk`.
- **What only Francis can approve goes on screen.** For anything auto-mode blocks, or that needs his approval: end your turn so the screen text shows, and tell him by `tell_talker` that something is waiting on screen.

## Stopping
- **By voice:** Francis tells Mini he is done, or asks it to hand back or stop. Mini calls `hand_back` at once, with no second confirmation; it asks "Shall I hand back to Opus?" only when it is unclear whether he wants to end. The hand-back message reaches you, and talk.py exits 0. `hand_back` only hands back: Mini sends no summary and says at most a short goodbye.
- **He asks you, typed or through `ask_main`:**
  1. Through `ask_main`, first `tell_talker` one short goodbye. Wait for that turn's log, which arrives after the goodbye has played.
  2. Check the pid with `ps -p <pid> -o command= | grep -q 'live-talker/talk.py'`, then run `kill -TERM <pid>`.
  3. talk.py stops the way Ctrl-C does: it closes the mic, player and voice socket, prints `STOPPED signal=SIGTERM` and the exit lines, and exits 0.
- **Last resort,** if it is still running about 10 s later:
  - Background mode: TaskStop on the job.
  - Pane mode: `herdr pane send-keys <pane> ctrl+c`.

## When it ends
The trigger is the background job's exit notification. In pane mode it is the watcher job; then read the pane's last 40 lines. The hand-back message and the exit can arrive in either order. Act on whichever comes first; the steps are safe to repeat.
1. **Always restore the soundfonts first:** `bash ~/.agents/skills/live/scripts/soundfonts.sh restore`
2. **Read the ending from the output:**
   - **`HAND_BACK delivered=yes`, then `TALK_EXIT=0`:** a clean ending. The hand-back message in your inbox has no summary, only the last turn (his words and Mini's goodbye). The turn logs you already have carry the rest of the conversation. Carry on on screen.
   - **`HAND_BACK delivered=no`:** the hand-back message did not reach you. The turn logs up to the previous turn are already in your inbox; read the last exchange from the talker output (its `you:` and `>>` lines).
   - **`STOPPED signal=SIGTERM`:** you stopped it on request.
   - **`BUDGET_STOP session|month ...`, then `TALK_EXIT=3`:** a cap was hit (EUR 5 per session, EUR 100 per month). Offer `/talk` as the fallback.
   - **`ERROR: ...`, then `TALK_EXIT=1`:** report the line. Typical causes are another talker already listening, the mic capture ending (wrong `--mic-device` or no microphone permission), or a router error.
3. **Report on screen in a few lines:**
   - How it ended.
   - Turns and spend, from the `bye.` line.
   - Euros per hour against the EUR 1/h bar, from `BUDGET_RATE` (`over_bar=`).
   - The `PLAYER` line only if `underruns` or `respawns` is above 0.
   Then continue the work.

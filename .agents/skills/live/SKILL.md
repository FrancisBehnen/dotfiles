---
name: live
description: Start the live voice talker from the session you're in. live-talker's talk.py (gpt-audio-mini via the AI Service Router) holds the voice, and this session becomes the thinker. It answers the talker's ask_main requests with the tell_talker tool and continues on screen after hand_back. Use it when Francis types /live, or says "go live", "start the live talker" or "live voice". Don't use it for "let's talk", "start voice" or "talk to me": those go to /talk, which stays the fallback. Optional arguments are `pane` (run the talker in a Herdr pane so he can watch the transcript live), `dutch`, and a topic for the session brief.
---

# live: Mini talks, this session thinks

The talker is `~/Code/live-talker/talk.py` ("Mini", gpt-audio-mini). It holds the voice and sends anything that needs thought to you, through the `tell_talker` channel when this session was started with `claude-live`, otherwise through your own inbox socket. You answer through the `tell_talker` MCP tool. The design is in GitHub FrancisBehnen/a-genai-i #85 (map #68). Background is in `~/Code/live-talker/README.md`.

## Check first (stop and tell Francis if one fails)
1. **The tool is loaded:** run ToolSearch `select:mcp__tell_talker__tell_talker`.
   - The server has been registered at user scope in `~/.claude.json` since 2026-10-11, and the tool is allowed in `~/.claude/settings.json`.
   - If the tool is missing, this session started before the server was registered, or the server failed to start. A restarted session gets it. Without it, no `ask_main` can be answered.
2. **Pick the route** (a-genai-i #87). The talker reaches you through the `tell_talker` channel when this session has one, and otherwise through your inbox socket:
   ```
   CH="$HOME/.local/state/live-talker/thinker-$(basename "$CLAUDE_CODE_MESSAGING_SOCKET" .sock).sock"; if test -S "$CH"; then echo "ROUTE --channel-socket $CH"; elif test -S "$CLAUDE_CODE_MESSAGING_SOCKET"; then echo "ROUTE --target-socket $CLAUDE_CODE_MESSAGING_SOCKET"; else echo "NO ROUTE"; fi
   ```
   - **`--channel-socket`:** this session was started with `claude-live` (`claude --dangerously-load-development-channels server:tell_talker`). Messages arrive as `<channel source="tell_talker" kind=... turn=...>`, wrapping the same labels. Known gap (2026-10-12): a request that arrives during one of your tool calls is attached to that tool result, and Opus declined one there as untrusted. If you leave one unanswered, say so on screen.
   - **`--target-socket`:** a plain `claude` session. Tell Francis once that messages go through the inbox socket, because the session was not started with `claude-live`. Messages arrive as "Another Claude session sent a message", with the same labels.
   - **`NO ROUTE`:** stop and tell him.
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
3. **Background mode (the default).** Run Bash with `run_in_background: true`, with the sandbox off, because it needs the mic, the router and `~/.local/state`. Put in MIC as a literal number, and ROUTE as the flag and path from "Pick the route", spelled out literally:
   ```
   python3 -u /Users/francis.behnen/Code/live-talker/talk.py --model gpt-audio-mini --mic-device MIC ROUTE < /dev/null 2>&1; echo "TALK_EXIT=$?"
   ```
   Wait for the start with `for i in $(seq 40); do grep -qE '^(bridge:|ERROR)' <output-file> && break; sleep 0.5; done; grep -E '^(TALKER|bridge:|ERROR)' <output-file>`. You should see two lines:
   - `TALKER pid=<pid>`: note the pid.
   - `bridge: tools ask_main, hand_back -> <socket>` (`-> channel <socket>` on the channel route)

   If you see `ERROR:` instead, go to "When it ends".
4. **Pane mode (on request).** Load the `herdr` skill and follow it to split a sibling pane with `--no-focus`.
   - **Run the command.** Use the command above without `< /dev/null`, so Enter can end his turn. The pane's shell does not have this session's variables, so ROUTE goes in with its path spelled out, and `\$?` reaches the pane unexpanded. Add `--dutch --stt-lang nl` as plain words. Add a topic as `--system \"\$(cat ~/.local/state/live-talker/live-brief.txt)\"`, so the pane's shell reads the file. Never expand the brief into the command line.
     ```
     herdr pane run <pane> "python3 -u /Users/francis.behnen/Code/live-talker/talk.py --model gpt-audio-mini --mic-device MIC ROUTE; echo TALK_EXIT=\$?"
     ```
   - **Watch it:** run `herdr pane wait-output <pane> --regex 'TALK_EXIT=[0-9]+' --source recent-unwrapped` with `run_in_background: true`. Never run it in the foreground, because that blocks every `ask_main`.
   - **Get the pid:** `herdr pane read <pane> --source recent-unwrapped --lines 20` shows the `TALKER pid=` line.
5. **Tell Francis on screen,** in a line or two:
   - He is live and speaks after the bell.
   - The mic you picked.
   - "Say 'hand back' when you're done, or type stop."
   Then **end your turn.** The talker's messages reach you while you are idle or between tool calls.

## While it runs
You read along with the transcript of Francis's conversation with Mini, and you correct Mini only when it is going in a wrong direction. Each message from the talker is a label plus its content, nothing else. In the content, `Francis (whisper):` is his own words as the local whisper transcript has them, and `Mini:` is what Mini said aloud. Whisper can mishear words, especially names.
- **Transcripts** come in as `[live transcript, turn N]`, after every turn. `Mini asked you:` is there when Mini sent you a request that turn.
  - They are read only. Stay silent, and keep anything on screen to a few words, because it is not heard.
  - Make one short `tell_talker` correction, one or two spoken sentences, only if Mini got something wrong: it misunderstood him, reworded a name, path or number into something different, or told him something wrong.
  - Mini heard his audio, so a word that only whisper gets wrong is not Mini's mistake.
  - Each message you sent unprompted shows up in the next transcript as `Opus (unprompted): "..."` plus `Mini relayed (word for word|reworded): "..."`. Mini is told to speak these word for word. `reworded` is a hint, not a verdict (it counts "3" against "three"): correct again only if the meaning changed.
- **Requests** come in as `[live request from Francis, turn N: answer via tell_talker]`. `Mini's question:` is Mini's phrasing of what he asked, and `Francis (whisper):` follows when his words were ready within a second.
  - Answer only with `mcp__tell_talker__tell_talker`: one to three short spoken sentences, plain text with no markdown, code or file paths. Your on-screen text is not heard.
  - Francis's words beat Mini's paraphrase on names, paths and numbers. Where they differ, go by his words and check the spelling against what exists.
  - If the work takes more than about 20 s, send a one-line status first, then the answer.
  - Delegate edits as usual.
- **The hand-back** comes in as `[live hand-back: the voice session is over]`. See "When it ends".
- **Never speak through VoiceMode** while the talker runs. That means no converse call (MCP or CLI) and no `/talk`.
- **What only Francis can approve goes on screen.** For anything auto-mode blocks, or that needs his approval: end your turn so the screen text shows, and tell him by `tell_talker` that something is waiting on screen.

## Stopping
- **By voice:** Francis tells Mini he is done, or asks it to hand back or stop. Mini calls `hand_back` at once, with no second confirmation; it asks "Shall I hand back to Opus?" only when it is unclear whether he wants to end. The hand-back message reaches you, and talk.py exits 0. `hand_back` only hands back: Mini sends no summary and says at most a short goodbye.
- **He asks you, typed or through `ask_main`:**
  1. Through `ask_main`, first `tell_talker` one short goodbye. Wait for that turn's transcript, which arrives after the goodbye has played.
  2. Check the pid with `ps -p <pid> -o command= | grep -q 'live-talker/talk.py'`, then run `kill -TERM <pid>`.
  3. talk.py stops the way Ctrl-C does: it closes the mic, player and voice socket, prints `STOPPED signal=SIGTERM` and the exit lines, and exits 0.
- **Last resort,** if it is still running about 10 s later:
  - Background mode: TaskStop on the job.
  - Pane mode: `herdr pane send-keys <pane> ctrl+c`.

## When it ends
The trigger is the background job's exit notification. In pane mode it is the watcher job; then read the pane's last 40 lines. The hand-back message and the exit can arrive in either order. Act on whichever comes first; the steps are safe to repeat.
1. **Always restore the soundfonts first:** `bash ~/.agents/skills/live/scripts/soundfonts.sh restore`
2. **Read the ending from the output:**
   - **`HAND_BACK delivered=yes`, then `TALK_EXIT=0`:** a clean ending. The hand-back message has no summary, only the last turn (his words and Mini's goodbye). The transcripts you already have carry the rest of the conversation. `tell_talker` reaches no one now. Carry on on screen. A line ending in `inferred=yes` means Mini only said it was handing back without making the call, and talk.py made it; note that for #86, because the prompt alone should get the call (`finish tool_calls` on that turn line).
   - **`HAND_BACK delivered=no`:** the hand-back message did not reach you. You already have the transcripts up to the previous turn; read the last exchange from the talker output (its `you:` and `>>` lines).
   - **`STOPPED signal=SIGTERM`:** you stopped it on request.
   - **`BUDGET_STOP session|month ...`, then `TALK_EXIT=3`:** a cap was hit (EUR 5 per session, EUR 100 per month). Offer `/talk` as the fallback.
   - **`ERROR: ...`, then `TALK_EXIT=1`:** report the line. Typical causes are another talker already listening, the mic capture ending (wrong `--mic-device` or no microphone permission), or a router error.
3. **Report on screen in a few lines:**
   - How it ended.
   - Turns and spend, from the `bye.` line.
   - Euros per hour against the EUR 1/h bar, from `BUDGET_RATE` (`over_bar=`).
   - The `PLAYER` line only if `underruns` or `respawns` is above 0.
   Then continue the work.

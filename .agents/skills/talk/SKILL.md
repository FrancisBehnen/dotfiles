---
name: talk
description: Start a voice conversation with Francis in the talker-plus-thinker setup. This session stays the orchestrator and thinker, and a background Sonnet subagent (the talker) holds the voice through the VoiceMode CLI run as background Bash jobs, relaying decisions and questions back without waiting. Use it when Francis types /talk, or says "let's talk", "start voice", "voice conversation" or "talk to me". Prefer it over voicemode:converse whenever he asks for one of these by name. An optional argument gives the topic or opening line; a voice id (af_*, am_*, bf_*, bm_*) as the argument overrides the talker's default voice.
---

# talk: Sonnet talks, this session thinks

Voice turns feel slow when the thinker also holds the voice. So a Sonnet talker holds the voice, and you stay the orchestrator. Background, the test rounds and their lessons are in `~/Code/a-genai-i/docs/ideas/2026-10-08-realtime-voice-conversation.md`. Read it if something below seems arbitrary.

## Start
1. **Argument.** A voice id (`af_*`, `am_*`, `bf_*`, `bm_*`) sets VOICE. Anything else is the TOPIC. The default VOICE is `af_heart`. Your own voice is `af_sky`; the alternatives are af_bella, af_nicole and bf_emma.
2. **Warm-up and conch.** Before spawning, always make one converse call: `tts_provider: "kokoro"`, voice VOICE, a two-word message such as "Starting voice.", `wait_for_response: false`, no `hold_conch`. It takes Kokoro's cold start (6-19 s after more than 5 min idle) off the talker's opening line, and it releases the conch if you hold it. Let it finish before the spawn, so the talker never finds the conch taken.
3. **Spawn** a background Agent with `subagent_type: "general-purpose"`, `model: "sonnet"` and `effort: "medium"` (Francis's choice). Paste the brief below verbatim, with VOICE and TOPIC filled in. Add the session context the talker needs (files, open questions, recent decisions) and any name mishearings you know from memory.
Open point: whether background Bash jobs re-invoke a subagent the way they re-invoke a top-level session is untested (the 2026-10-10 test ran top-level, in a pane), so the brief keeps MCP converse as the fallback.

## While it runs
- **One voice at a time.** Don't call converse yourself (MCP or CLI) until the talker has ended.
- **Act on every DECISION** it relays. Delegate edits to agents under this session's own rules (a voice session uses one scribe agent).
- **Answer ESCALATIONs** with SendMessage to the talker: short, factual, and ready to say aloud. It gets them mid-listen, while its background voice job runs.
- **Anything auto-mode blocks goes to Francis on screen**, never through the talker. Screen text shows only once your turn ends, so end the turn to show it.
- When the talker's final summary arrives, confirm on screen what was recorded and what is still open.

## Talker brief (paste verbatim)
```
You are the talker in a voice conversation with Francis. The main session ("main") is the orchestrator: it thinks and edits. You hold the voice.
Setup: re-read ~/.claude/CLAUDE.md first (shell quoting; print the VoiceMode echo lines after each call returns). Load tools with ToolSearch "select:SendMessage,TaskStop,mcp__plugin_voicemode_voicemode__converse" (MCP converse is the fallback only).
Your voice is the VoiceMode CLI, run with Bash run_in_background: true, not the MCP converse tool: messages from main then reach you mid-listen, while an MCP call blocks until its turn ends. You are re-invoked when the job exits; his words follow "🎤 Heard:" in the output (possibly over several lines). It costs about 1.5 s more per turn than MCP; accept that.
One-sentence turn (keep double quotes, $ and backticks out of the text; speak-only: add --skip-stt):
/usr/bin/time -p /Users/francis.behnen/.local/bin/voicemode converse -m "<text>" --voice {VOICE} --tts-provider kokoro -d 60 2>&1 | grep -E "Heard|Timing|rror|^real" -A3
Split every reply of two or more sentences, with a short first chunk (under 80 chars) so the voice starts sooner:
/usr/bin/time -p /Users/francis.behnen/.local/bin/voicemode converse --script - --pause-after-ms 0 --voice {VOICE} --tts-provider kokoro -d 60 2>&1 <<'EOF' | grep -E '"reply"|"status"|rror|^real' -A2
[{"say": "<first sentence>"}, {"ask": "<the rest>"}]
EOF
That returns survey JSON: his words are the ask turn's "reply" (null means no speech). "status": "tts_failed" on a turn means re-send that part as a single -m call.
Rules: one CLI converse at a time (a message from main that lands mid-listen waits for that job's notification; don't start another call), never an MCP converse while one runs, never --skip-conch. Keep -d 60 as the listen cap. If a job runs past 90 s, or never notifies you, stop it (TaskStop) and fall back to MCP converse (tts_provider "kokoro", voice "{VOICE}", listen_duration_max 60). A Kokoro error is now the real one (no OpenAI fallback): retry once.
Speak two or three sentences per turn. If he speaks Dutch, answer in Dutch.
Speech-to-text is noisy, and Whisper invents text from silence. Repair from context, like a human listener would. Read back only when the reading changes what you'll do or relay, and re-ask only when nothing usable came through. "Selma" often means "Sonnet". Never act on an empty reply. A question back from him is a request to explain, not an answer: explain, then ask again.
Relay without waiting. Send main a one-liner the moment something is settled: "DECISION: ..." for decisions and edit requests, "ESCALATION: ..." for a question you can't answer from the files. Send the SendMessage in the same message as your next voice call (two parallel tool calls), never before it. Say that you're checking ("I'm checking that with Opus"), then move to a different point or park this one. Never re-ask the question you just escalated. When the answer lands, go back to the open point.
You are read-only. You may read files to answer him and use Bash only for the voice commands: no file edits, no git, no vault writes and no Slack or email. Main does all of that.
Ending: when he is done or wants main back, send main a final summary that quotes his exact words on the important points. Then speak a last line with --skip-stt (no listen), so the conch is free.
Topic: {TOPIC}
```

---
name: talk
description: Start a voice conversation with Francis in the talker-plus-thinker setup. This session stays the orchestrator and thinker, and a background Sonnet subagent (the talker) holds the voice through the VoiceMode CLI run as background Bash jobs, relaying decisions and questions back without waiting. Use it when Francis types /talk, or says "let's talk", "start voice", "voice conversation" or "talk to me". Prefer it over voicemode:converse whenever he asks for one of these by name. An optional argument gives the topic or opening line; a voice id (af_*, am_*, bf_*, bm_*, nl_*) as the argument overrides the talker's default voice; `dutch` as the first word starts a Dutch session (local Dutch voice, Dutch speech recognition).
---

# talk: Sonnet talks, this session thinks

Voice turns feel slow when the thinker also holds the voice. So a Sonnet talker holds the voice, and you stay the orchestrator. Background, the test rounds and their lessons are in `~/Code/a-genai-i/docs/ideas/2026-10-08-realtime-voice-conversation.md`. Read it if something below seems arbitrary.

## Start
1. **Argument.** If the first word is `dutch`, LANGUAGE is Dutch; otherwise English. Then a voice id (`af_*`, `am_*`, `bf_*`, `bm_*`, `nl_*`) sets VOICE. Anything left is the TOPIC.
   - English: the default VOICE is `af_heart` (Kokoro). Your own voice is `af_sky`; the alternatives are af_bella, af_nicole and bf_emma. LANGRULE is "Speak English, even when he drops in a Dutch word." ENV is empty.
   - Dutch: the default VOICE is `nl_NL-claire-enhanced` (the macOS voice Claire (Enhanced), Francis's pick); the alternative is `nl_NL-xander` (the macOS voice Xander, male, from the Netherlands). LANGRULE is "Speak Dutch throughout; English product and tool names (Ground Truth, Slack) stay as they are." ENV is `VOICEMODE_WHISPER_LANGUAGE=nl ` (with the trailing space): each CLI call is its own VoiceMode process and the environment beats voicemode.env, so this makes Whisper transcribe Dutch for that call only.
   - Dutch needs the local Dutch TTS server on port 8893, `dutch-tts`, which renders the macOS voices with `say` (Kokoro has no Dutch). Check `curl -fsS http://127.0.0.1:8893/health`. If it fails, start it with Bash `run_in_background: true`: `nohup ~/scripts/dutch-tts/dutch-tts >> ~/.voicemode/logs/dutch-tts.log 2>&1` (ready in about 2 s). Dutch also needs `http://127.0.0.1:8893/v1` as the second `VOICEMODE_TTS_BASE_URLS` entry in `~/.voicemode/voicemode.env`, after Kokoro; Kokoro rejects the nl_* voice and VoiceMode falls through to that server. If it is missing, tell Francis on screen; don't edit the file.
2. **Warm-up and conch.** Before spawning, always make one converse call: voice VOICE (English) or `af_heart` (Dutch: the 8893 server's cold start is under a second, and the MCP server may predate its entry), a two-word message such as "Starting voice.", `wait_for_response: false`, no `hold_conch`. It takes Kokoro's cold start (6-19 s after more than 5 min idle) off the talker's opening line, and it releases the conch if you hold it. Let it finish before the spawn, so the talker never finds the conch taken.
3. **Spawn** a background Agent with `subagent_type: "general-purpose"`, `model: "sonnet"` and `effort: "medium"` (Francis's choice). Paste the brief below verbatim, with VOICE, ENV, LANGRULE and TOPIC filled in. Add the session context the talker needs (what the relevant files say, open questions, recent decisions) and any name mishearings you know from memory. The talker answers only from that context and from what Francis says, and escalates everything else to you, so put in what it will need.
Tested 2026-10-10: a background subagent is re-invoked both when its background Bash job exits and when main messages it mid-job, so the talker stays a subagent; no Herdr pane needed (Francis: pane only if subagents could not). MCP converse remains the fallback.

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
{ENV}/usr/bin/time -p /Users/francis.behnen/.local/bin/voicemode converse -m "<text>" --voice {VOICE} -d 60 2>&1 | grep -E "Heard|Timing|rror|^real" -A3
Split every reply of two or more sentences, with a short first chunk (under 80 chars) so the voice starts sooner:
{ENV}/usr/bin/time -p /Users/francis.behnen/.local/bin/voicemode converse --script - --pause-after-ms 0 --voice {VOICE} -d 60 2>&1 <<'EOF' | grep -E '"reply"|"status"|"stopped_at"|rror|^real' -A2
[{"say": "<first sentence>"}, {"ask": "<the rest>"}]
EOF
That returns survey JSON: his words are the ask turn's "reply" (null means no speech). "status": "tts_failed" on a turn means re-send that part as a single -m call.
Rules: one CLI converse at a time (a message from main that lands mid-listen waits for that job's notification; don't start another call), never an MCP converse while one runs, never --skip-conch. Keep -d 60 as the listen cap. If a job runs past 90 s, or never notifies you, stop it (TaskStop) and fall back to MCP converse (voice "{VOICE}", listen_duration_max 60; it hears English only, since its language is fixed when VoiceMode starts). A TTS error is the real one (no OpenAI fallback): retry once; for an nl_* voice, tell main that the Dutch TTS server on port 8893 may be down.
Speak two or three sentences per turn. {LANGRULE}
Speech-to-text is noisy, and Whisper invents text from silence. Repair from context, like a human listener would. Read back only when the reading changes what you'll do or relay, and re-ask only when nothing usable came through. "Selma" often means "Sonnet". Never act on an empty reply. A question back from him is a request to explain, not an answer: explain, then ask again.
Relay without waiting. Send main a one-liner the moment something is settled: "DECISION: ..." for decisions and edit requests, "ESCALATION: ..." for a question you can't answer from what he said or from the session context in this brief. Send the SendMessage in the same message as your next voice call (two parallel tool calls), never before it. Say that you're checking ("I'm checking that with Opus"), then move to a different point or park this one. Never re-ask the question you just escalated. When the answer lands, go back to the open point.
You do no research. Answer only from what he says and from the session context main gave you in this brief. Anything else, including how code works or what a file says, goes to main as an ESCALATION, even when you could look it up yourself. Use Bash only for the voice commands, and apart from re-reading ~/.claude/CLAUDE.md at setup, make no Read, Grep or Glob calls: no other file reads, no file edits, no git, no vault writes and no Slack or email. Main does all of that.
Ending: when he is done or wants main back, send main a final summary that quotes his exact words on the important points. Then speak a last line with --skip-stt (no listen), so the conch is free.
Topic: {TOPIC}
```

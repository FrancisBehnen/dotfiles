---
name: talk
description: Start a voice conversation with Francis in the talker-plus-thinker setup. This session stays the orchestrator and thinker, and a background Sonnet subagent (the talker) holds the voice through the voicemode converse tool and relays decisions and questions back without waiting. Use it when Francis types /talk, or says "let's talk", "start voice", "voice conversation" or "talk to me". Prefer it over voicemode:converse whenever he asks for one of these by name. An optional argument gives the topic or opening line; a voice id (af_*, am_*, bf_*, bm_*) as the argument overrides the talker's default voice.
---

# talk: Sonnet talks, this session thinks

Voice turns feel slow when the thinker also holds the voice. So a Sonnet talker holds the voice, and you stay the orchestrator. Background, the three test rounds and their lessons are in `~/Code/a-genai-i/docs/ideas/2026-10-08-realtime-voice-conversation.md`. Read it if something below seems arbitrary.

## Start
1. **Argument.** A voice id (`af_*`, `am_*`, `bf_*`, `bm_*`) sets VOICE. Anything else is the TOPIC. The default VOICE is `af_heart`. Your own voice is `af_sky`; the alternatives are af_bella, af_nicole and bf_emma.
2. **Warm-up and conch.** Before spawning, always make one converse call: `tts_provider: "kokoro"`, voice VOICE, a two-word message such as "Starting voice.", `wait_for_response: false`, no `hold_conch`. It takes Kokoro's cold start (6-19 s after more than 5 min idle) off the talker's opening line, and it releases the conch if you hold it. Let it finish before the spawn, so the talker never finds the conch taken.
3. **Spawn** a background Agent with `subagent_type: "general-purpose"`, `model: "sonnet"` and `effort: "medium"` (Francis's choice). Paste the brief below verbatim, with VOICE and TOPIC filled in. Add the session context the talker needs (files, open questions, recent decisions) and any name mishearings you know from memory.

## While it runs
- **One voice at a time.** Don't call converse yourself until the talker has ended.
- **Act on every DECISION** it relays. Delegate edits to agents under this session's own rules (a voice session uses one scribe agent).
- **Answer ESCALATIONs** with SendMessage to the talker: short, factual, and ready to say aloud. Messages reach it only between its converse calls.
- **Anything auto-mode blocks goes to Francis on screen**, never through the talker. Screen text shows only once your turn ends, so end the turn to show it.
- When the talker's final summary arrives, confirm on screen what was recorded and what is still open.

## Talker brief (paste verbatim)
```
You are the talker in a voice conversation with Francis. The main session ("main") is the orchestrator: it thinks and edits. You hold the voice.
Setup: re-read ~/.claude/CLAUDE.md first (VoiceMode: call converse first, print the echo lines after). Load tools with ToolSearch "select:mcp__plugin_voicemode_voicemode__converse,SendMessage".
Every converse call: tts_provider "kokoro", voice "{VOICE}", listen_duration_max 60. Messages from main land only between tool calls, so the 60 s cap is what bounds relay latency. Don't raise it.
Speak two or three sentences per turn. A long TTS plus a long listen pushes a call past 120 s, and then it gets backgrounded. If he speaks Dutch, answer in Dutch.
Split every reply of two or more sentences: converse with pause_after_ms 0 and turns [{"say": "<first sentence, short, under 80 chars>"}, {"ask": "<the rest>"}], not message. A short first chunk starts the voice about 0.5 s sooner. Such a call returns JSON: his words are in survey.turns[1].reply (null means no speech), and a non-null survey.stopped_at means he said "stop" or "break" on its own. A one-sentence reply goes in message as usual.
Speech-to-text is noisy, and Whisper invents text from silence. Repair from context, like a human listener would. Read back only when the reading changes what you'll do or relay, and re-ask only when nothing usable came through. "Selma" often means "Sonnet". Never act on an empty reply. A question back from him is a request to explain, not an answer: explain, then ask again.
Relay without waiting. Send main a one-liner the moment something is settled: "DECISION: ..." for decisions and edit requests, "ESCALATION: ..." for a question you can't answer from the files. Send the SendMessage in the same message as your next converse call (two parallel tool calls), never before it. Say that you're checking ("I'm checking that with Opus"), then move to a different point or park this one. Never re-ask the question you just escalated. When the answer lands, go back to the open point.
You are read-only. You may read files to answer him, but you make no file edits, no git, no vault writes and no Slack or email. Main does all of that.
Ending: when he is done or wants main back, send main a final summary that quotes his exact words on the important points. Then make a last converse call with message (not turns, which ignores wait_for_response), wait_for_response false and no hold_conch, so the conch goes back.
Topic: {TOPIC}
```

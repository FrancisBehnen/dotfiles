"""dutch-tts server: macOS `say` voices (Dutch) behind an OpenAI-compatible
/v1/audio/speech endpoint, so VoiceMode can use them as a second TTS_BASE_URLS entry
after Kokoro. Stdlib only; runs on the system Python (/usr/bin/python3).

Why it works with VoiceMode: VoiceMode tries each VOICEMODE_TTS_BASE_URLS entry
in order. Kokoro (8880) answers HTTP 400 for a voice it doesn't know (it checks the
part before the first "-", so "nl_NL-claire-enhanced" is unknown to it), and VoiceMode
falls through to this server. English Kokoro voices never reach here.

Voices (SAY_VOICES): "nl_NL-claire-enhanced" is the installed system voice
"Claire (Enhanced)", Francis's default Dutch voice since 2026-10-14. "nl_NL-xander" is
the system voice "Xander" (male, from the Netherlands), an alternative. A voice is only
offered if `say -v '?'` lists it at start. Every name keeps an "nl_NL-" prefix so Kokoro
rejects it. Claire says Coolblue, Slack and Jira right as written (Whisper round trip,
2026-10-14), so no respelling table is applied.

Rendering: each sentence is rendered silently to a temp WAV file
(`say -o <tmp> --data-format=LEI16@24000 -f -`, text on stdin, never on the command
line, never played through the speakers) and streamed as soon as it is ready; one worker
renders the next sentence meanwhile. A `say` call costs ~0.6 s whatever the sentence
length (process start plus voice load), so sentence 1 renders alone.

Wire format (matches what VoiceMode 8.12 sends and decodes):
  - response_format "pcm" (VoiceMode's default): raw 16-bit little-endian mono at
    24000 Hz, streamed one sentence per HTTP chunk.
  - response_format "wav": the same audio as one WAV file (24000 Hz).
  - "model" and the Authorization header are ignored; "speed" maps to `say -r`.
  - Unknown voice or unsupported format: HTTP 400 with an OpenAI-shaped error.

Run it via the `dutch-tts` launcher next to this file.
"""

from __future__ import annotations

import argparse
import io
import json
import logging
import re
import subprocess
import tempfile
import time
import wave
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

OUT_RATE = 24000  # VoiceMode decodes pcm as 16-bit mono at 24 kHz (config.SAMPLE_RATE)
SENTENCE_GAP_S = 0.12  # silence between sentences

log = logging.getLogger("dutch-tts")

SAY = "/usr/bin/say"
SAY_WPM = 175  # approximate default rate of the system voices; speed s -> say -r SAY_WPM*s
# requestable name -> macOS voice name, default voice first.
SAY_VOICES = {
    "nl_NL-claire-enhanced": "Claire (Enhanced)",
    "nl_NL-xander": "Xander",
}
SAY_ACTIVE: dict[str, str] = {}  # the SAY_VOICES installed on this Mac, in SAY_VOICES order


def load_say_voices() -> None:
    """Offer each SAY_VOICES entry that `say -v '?'` lists, and warm it up once."""
    listing = subprocess.run([SAY, "-v", "?"], capture_output=True, text=True, timeout=20).stdout
    installed = {re.split(r"\s{2,}", line.strip())[0] for line in listing.splitlines() if line.strip()}
    for name, mac_voice in SAY_VOICES.items():
        if mac_voice not in installed:
            log.warning("say voice '%s' is not installed; %s is not offered", mac_voice, name)
            continue
        SAY_ACTIVE[name] = mac_voice
        t0 = time.perf_counter()
        say_render(mac_voice, "Hallo.", None)  # warm-up: the first call loads the voice from disk
        log.info("say voice %s -> '%s' (warm-up %.2fs)", name, mac_voice, time.perf_counter() - t0)
    if not SAY_ACTIVE:
        raise SystemExit(f"none of the say voices {list(SAY_VOICES.values())} is installed")


def voice_names() -> list[str]:
    return list(SAY_ACTIVE)


def health() -> dict:
    return {"status": "ok", "say": dict(SAY_ACTIVE), "voices": voice_names()}


# whitespace after . ! ? or …, optionally followed by one closing quote or bracket
SENTENCE_END = re.compile(r"(?:(?<=[.!?…])|(?<=[.!?…][\"'”’)\]]))\s+")


def split_sentences(text: str) -> list[str]:
    return [s.strip() for s in SENTENCE_END.split(text) if s.strip()]


def say_render(mac_voice: str, text: str, speed: float | None) -> bytes:
    """One `say` call rendered silently to a temp WAV (24 kHz int16 mono); returns its frames."""
    with tempfile.TemporaryDirectory(prefix="say-tts-") as tmp:
        out = Path(tmp) / "out.wav"
        cmd = [SAY, "-v", mac_voice, "-o", str(out), "--file-format=WAVE",
               f"--data-format=LEI16@{OUT_RATE}", "-f", "-"]
        if speed and speed != 1.0:
            cmd[3:3] = ["-r", str(round(SAY_WPM * speed))]
        subprocess.run(cmd, input=text.encode("utf-8"), check=True, capture_output=True, timeout=60)
        with wave.open(str(out), "rb") as w:
            if (w.getnchannels(), w.getsampwidth(), w.getframerate()) != (1, 2, OUT_RATE):
                raise RuntimeError(f"say wrote {w.getnchannels()}ch {w.getsampwidth() * 8}-bit "
                                   f"{w.getframerate()} Hz, expected mono 16-bit {OUT_RATE} Hz")
            return w.readframes(w.getnframes())


def synth_chunks(voice_name: str, text: str, speed: float | None):
    """Yield 24 kHz int16 PCM bytes per sentence; one worker renders ahead, in order."""
    gap = b"\x00\x00" * int(OUT_RATE * SENTENCE_GAP_S)
    mac_voice = SAY_ACTIVE[voice_name]
    with ThreadPoolExecutor(max_workers=1) as ex:
        futures = [ex.submit(say_render, mac_voice, s, speed) for s in split_sentences(text)]
        try:
            for i, fut in enumerate(futures):
                pcm = fut.result()
                yield (gap + pcm) if i else pcm
        finally:
            for fut in futures:
                fut.cancel()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):  # route http.server's access log through logging
        log.debug("%s " + fmt, self.address_string(), *args)

    def _json(self, status: int, body: dict) -> None:
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _error(self, status: int, message: str) -> None:
        log.warning("%d %s", status, message)
        self._json(status, {"error": {"message": message, "type": "invalid_request_error"}})

    def do_GET(self):
        if self.path in ("/health", "/v1/health"):
            self._json(200, health())
        elif self.path in ("/v1/models", "/models"):
            self._json(200, {"object": "list",
                             "data": [{"id": "say", "object": "model"}, {"id": "tts-1", "object": "model"}]})
        elif self.path in ("/v1/audio/voices", "/v1/voices"):
            self._json(200, {"voices": voice_names()})
        else:
            self._error(404, f"no route {self.path}")

    def do_POST(self):
        if self.path not in ("/v1/audio/speech", "/audio/speech"):
            return self._error(404, f"no route {self.path}")
        try:
            req = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        except json.JSONDecodeError as e:
            return self._error(400, f"invalid JSON: {e}")
        text = (req.get("input") or "").strip()
        voice = req.get("voice") or ""
        fmt = (req.get("response_format") or "pcm").lower()
        speed = req.get("speed")
        if voice not in SAY_ACTIVE:
            return self._error(400, f"unknown voice '{voice}'; available: {', '.join(SAY_ACTIVE)}")
        if fmt not in ("pcm", "wav"):
            return self._error(400, f"unsupported response_format '{fmt}'; use pcm or wav")
        if not text:
            return self._error(400, "empty input")

        t0 = time.perf_counter()
        first = None
        total = 0
        if fmt == "wav":
            pcm = b"".join(synth_chunks(voice, text, speed))
            buf = io.BytesIO()
            with wave.open(buf, "wb") as w:
                w.setnchannels(1)
                w.setsampwidth(2)
                w.setframerate(OUT_RATE)
                w.writeframes(pcm)
            data = buf.getvalue()
            first = time.perf_counter() - t0
            total = len(data)
            self.send_response(200)
            self.send_header("Content-Type", "audio/wav")
            self.send_header("Content-Length", str(total))
            self.end_headers()
            self.wfile.write(data)
        else:
            self.send_response(200)
            self.send_header("Content-Type", "audio/pcm")
            self.send_header("Transfer-Encoding", "chunked")
            self.end_headers()
            try:
                for piece in synth_chunks(voice, text, speed):
                    if first is None:
                        first = time.perf_counter() - t0
                    self.wfile.write(f"{len(piece):X}\r\n".encode() + piece + b"\r\n")
                    self.wfile.flush()
                    total += len(piece)
                self.wfile.write(b"0\r\n\r\n")
            except (BrokenPipeError, ConnectionResetError):
                log.info("client closed the stream early (%s)", voice)
                self.close_connection = True
                return
        log.info("%s %s %d chars -> %d bytes, first audio %.3fs, total %.3fs",
                 voice, fmt, len(text), total, first or 0.0, time.perf_counter() - t0)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8893)
    ap.add_argument("--debug", action="store_true")
    args = ap.parse_args()
    logging.basicConfig(level=logging.DEBUG if args.debug else logging.INFO,
                        format="%(asctime)s %(levelname)s %(message)s")
    load_say_voices()
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    log.info("listening on http://%s:%d/v1 with %s", args.host, args.port, ", ".join(SAY_ACTIVE))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()

"""piper-tts server: Dutch (and other) Piper voices, plus macOS `say` voices, behind an
OpenAI-compatible /v1/audio/speech endpoint, so VoiceMode can use them as a second
TTS_BASE_URLS entry after Kokoro.

Why it works with VoiceMode: VoiceMode tries each VOICEMODE_TTS_BASE_URLS entry
in order. Kokoro (8880) answers HTTP 400 for a voice it doesn't know (such as
"nl_NL-pim-medium"), so VoiceMode falls through to this server. English Kokoro
voices never reach here.

Wire format (matches what VoiceMode 8.12 sends and decodes):
  - response_format "pcm" (VoiceMode's default): raw 16-bit little-endian mono at
    24000 Hz, streamed one sentence per HTTP chunk. Piper's voices are 22050 Hz,
    so audio is resampled to 24000; without that it would play ~9% fast and high.
  - response_format "wav": the same audio as one WAV file (24000 Hz).
  - "model" and the Authorization header are ignored; "speed" maps to Piper's
    length_scale (1/speed).
  - Unknown voice or unsupported format: HTTP 400 with an OpenAI-shaped error.

Multi-speaker models (such as nl_NL-mls-medium, 52 speakers): request one speaker as
"<model>-<index>", e.g. "nl_NL-mls-medium-12", where <index> is Piper's speaker id
(0..num_speakers-1, the values of speaker_id_map in the .onnx.json, not the MLS
dataset ids that are its keys). The bare model name means the model's
default_speaker_id (0 for mls). The name keeps its "nl_NL-" prefix, so Kokoro
still rejects it (it checks the part before the first "-") and VoiceMode still
falls through to this server.

macOS `say` voices (SAY_VOICES): "nl_NL-claire-enhanced" is the installed system voice
"Claire (Enhanced)" (Francis's pick over the Piper voices, 2026-10-14). Each sentence is
rendered silently to a temp WAV file (`say -o <tmp> --data-format=LEI16@24000 -f -`, text on
stdin, never on the command line, never played through the speakers) and streamed as soon as
it is ready; one worker renders the next sentence meanwhile. A `say` call costs ~0.6 s
whatever the sentence length (process start plus voice load), so sentence 1 renders alone.
A say voice is only offered if `say -v '?'` lists it at start. "speed" maps to `say -r`.
The nl-respell.tsv table is applied to Piper voices only: Claire says Coolblue, Slack and
Jira right as written (Whisper round trip, 2026-10-14).

Stdlib HTTP server plus piper-tts and numpy; run it with the venv python via the
`piper-tts` launcher next to this file. Every voice in --voices-dir is loaded at
start, so the first request is not a cold load.
"""

import argparse
import io
import json
import logging
import re
import subprocess
import tempfile
import threading
import time
import wave
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import numpy as np
from piper import PiperVoice, SynthesisConfig

OUT_RATE = 24000  # VoiceMode decodes pcm as 16-bit mono at 24 kHz (config.SAMPLE_RATE)
SENTENCE_GAP_S = 0.12  # silence between sentences

log = logging.getLogger("piper-tts")
VOICES: dict[str, PiperVoice] = {}  # model name -> loaded model
LOCKS: dict[str, threading.Lock] = {}  # per model; a model's speakers share it
NAMES: dict[str, tuple[str, int | None]] = {}  # requestable voice name -> (model, speaker id)

SAY = "/usr/bin/say"
SAY_WPM = 175  # approximate default rate of the system voices; speed s -> say -r SAY_WPM*s
# requestable name -> macOS voice name. The name keeps an "nl_NL-" prefix so Kokoro rejects it.
SAY_VOICES = {"nl_NL-claire-enhanced": "Claire (Enhanced)"}
SAY_ACTIVE: dict[str, str] = {}  # the SAY_VOICES installed on this Mac


def load_voices(voices_dir: Path) -> None:
    for onnx in sorted(voices_dir.glob("*.onnx")):
        name = onnx.name[: -len(".onnx")]
        t0 = time.perf_counter()
        VOICES[name] = PiperVoice.load(onnx)
        LOCKS[name] = threading.Lock()
        n_speakers = VOICES[name].config.num_speakers
        NAMES[name] = (name, None)
        if n_speakers > 1:
            NAMES[name] = (name, VOICES[name].config.default_speaker_id or 0)
            for sid in range(n_speakers):
                NAMES[f"{name}-{sid}"] = (name, sid)
        log.info("loaded %s (%d Hz, %d speaker%s) in %.2fs", name, VOICES[name].config.sample_rate,
                 n_speakers, "" if n_speakers == 1 else "s", time.perf_counter() - t0)
    if not VOICES:
        raise SystemExit(f"no *.onnx voices in {voices_dir}")


def load_say_voices() -> None:
    """Offer each SAY_VOICES entry that `say -v '?'` lists, and warm it up once."""
    try:
        listing = subprocess.run([SAY, "-v", "?"], capture_output=True, text=True, timeout=20).stdout
    except (OSError, subprocess.SubprocessError) as e:
        log.warning("no macOS say voices: %s", e)
        return
    installed = {re.split(r"\s{2,}", line.strip())[0] for line in listing.splitlines() if line.strip()}
    for name, mac_voice in SAY_VOICES.items():
        if mac_voice not in installed:
            log.warning("say voice '%s' is not installed; %s is not offered", mac_voice, name)
            continue
        SAY_ACTIVE[name] = mac_voice
        t0 = time.perf_counter()
        say_render(mac_voice, "Hallo.", None)  # warm-up: the first call loads the voice from disk
        log.info("say voice %s -> '%s' (warm-up %.2fs)", name, mac_voice, time.perf_counter() - t0)


def voice_names() -> list[str]:
    """Every requestable voice name, multi-speaker entries in speaker order."""
    def key(n: str):
        model, sid = NAMES[n]
        return (model, -1 if sid is None else sid)
    return sorted(SAY_ACTIVE) + sorted(NAMES, key=key)


def health() -> dict:
    multi = {m: v.config.num_speakers for m, v in VOICES.items() if v.config.num_speakers > 1}
    return {"status": "ok", "models": sorted(VOICES),
            "speakers": {m: f"{m}-0 .. {m}-{n - 1}" for m, n in sorted(multi.items())},
            "say": dict(sorted(SAY_ACTIVE.items())),
            "voices": voice_names()}


RESPELL: list[tuple[re.Pattern, str]] = []


def load_respell(path: Path) -> None:
    """Loanword respellings for nl_* voices (see nl-respell.tsv)."""
    if not path.is_file():
        return
    for line in path.read_text().splitlines():
        if not line.strip() or line.startswith("#") or "\t" not in line:
            continue
        word, spoken = line.split("\t", 1)
        RESPELL.append((re.compile(rf"\b{re.escape(word.strip())}\b", re.IGNORECASE), spoken.strip()))
    log.info("loaded %d Dutch respellings from %s", len(RESPELL), path)


def respell(voice_name: str, text: str) -> str:
    """Piper nl_* voices only; say voices (Claire) pronounce the loanwords right as written."""
    if voice_name.startswith("nl_") and voice_name in NAMES:
        for pattern, spoken in RESPELL:
            text = pattern.sub(spoken, text)
    return text


def to_pcm24k(audio: np.ndarray, in_rate: int) -> bytes:
    """Float [-1, 1] at in_rate -> int16 little-endian bytes at OUT_RATE."""
    if in_rate != OUT_RATE and len(audio):
        n_out = int(round(len(audio) * OUT_RATE / in_rate))
        x_in = np.arange(len(audio)) / in_rate
        x_out = np.arange(n_out) / OUT_RATE
        audio = np.interp(x_out, x_in, audio)
    return (np.clip(audio, -1.0, 1.0) * 32767).astype("<i2").tobytes()


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


def say_chunks(voice_name: str, text: str, speed: float | None):
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


def synth_chunks(voice_name: str, text: str, speed: float | None):
    """Yield 24 kHz int16 PCM bytes, one piece per sentence."""
    if voice_name in SAY_ACTIVE:
        yield from say_chunks(voice_name, text, speed)
        return
    model, speaker_id = NAMES[voice_name]
    voice = VOICES[model]
    cfg = SynthesisConfig(speaker_id=speaker_id, length_scale=(1.0 / speed) if speed else None)
    gap = b"\x00\x00" * int(OUT_RATE * SENTENCE_GAP_S)
    text = respell(voice_name, text)
    with LOCKS[model]:
        for i, chunk in enumerate(voice.synthesize(text, syn_config=cfg)):
            pcm = to_pcm24k(chunk.audio_float_array, chunk.sample_rate)
            yield (gap + pcm) if i else pcm


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
                             "data": [{"id": "piper", "object": "model"}, {"id": "tts-1", "object": "model"}]})
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
        if voice not in NAMES and voice not in SAY_ACTIVE:
            return self._error(400, f"unknown voice '{voice}'; available: "
                                    f"{', '.join(sorted(SAY_ACTIVE) + sorted(VOICES))}"
                                    " (multi-speaker: <model>-<speaker index>, see /health)")
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
    ap.add_argument("--voices-dir", type=Path,
                    default=Path.home() / ".local/share/piper-tts/voices")
    ap.add_argument("--respell", type=Path, default=Path(__file__).with_name("nl-respell.tsv"))
    ap.add_argument("--debug", action="store_true")
    args = ap.parse_args()
    logging.basicConfig(level=logging.DEBUG if args.debug else logging.INFO,
                        format="%(asctime)s %(levelname)s %(message)s")
    load_voices(args.voices_dir)
    load_respell(args.respell)
    load_say_voices()
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    log.info("listening on http://%s:%d/v1 with %s (%d voice names)", args.host, args.port,
             ", ".join(sorted(SAY_ACTIVE) + sorted(VOICES)), len(NAMES) + len(SAY_ACTIVE))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()

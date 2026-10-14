"""piper-tts server: Dutch (and other) Piper voices behind an OpenAI-compatible
/v1/audio/speech endpoint, so VoiceMode can use them as a second TTS_BASE_URLS
entry after Kokoro.

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

Stdlib HTTP server plus piper-tts and numpy; run it with the venv python via the
`piper-tts` launcher next to this file. Every voice in --voices-dir is loaded at
start, so the first request is not a cold load.
"""

import argparse
import io
import json
import logging
import re
import threading
import time
import wave
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


def voice_names() -> list[str]:
    """Every requestable voice name, multi-speaker entries in speaker order."""
    def key(n: str):
        model, sid = NAMES[n]
        return (model, -1 if sid is None else sid)
    return sorted(NAMES, key=key)


def health() -> dict:
    multi = {m: v.config.num_speakers for m, v in VOICES.items() if v.config.num_speakers > 1}
    return {"status": "ok", "models": sorted(VOICES),
            "speakers": {m: f"{m}-0 .. {m}-{n - 1}" for m, n in sorted(multi.items())},
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
    if voice_name.startswith("nl_"):
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


def synth_chunks(voice_name: str, text: str, speed: float | None):
    """Yield 24 kHz int16 PCM bytes, one piece per sentence."""
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
        if voice not in NAMES:
            return self._error(400, f"unknown voice '{voice}'; available: {', '.join(sorted(VOICES))}"
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
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    log.info("listening on http://%s:%d/v1 with %s (%d voice names)", args.host, args.port,
             ", ".join(sorted(VOICES)), len(NAMES))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()

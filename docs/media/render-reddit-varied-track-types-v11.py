#!/usr/bin/env python3
"""Render the v11 Reddit demo from the real Logic UI capture.

The video source is the actual screen recording. Captions are explanatory QA
annotations generated from the real transcript; they do not replace or simulate
Logic UI. Audio is a guide reconstruction from the same MIDI pattern because
system audio capture is not available on this machine.
"""

from __future__ import annotations

import json
import math
import struct
import subprocess
import wave
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
RAW_VIDEO = Path("/tmp/logic-v11-varied-track-types-raw.mp4")
TRANSCRIPT = ROOT / "docs/media/reddit-dudddee-varied-track-types-v11-transcript.json"
ASS = ROOT / "docs/media/reddit-dudddee-varied-track-types-v11.ass"
AUDIO = Path("/tmp/logic-v11-guide-audio.wav")
OUTPUT = ROOT / "docs/media/reddit-dudddee-varied-track-types-v11.mp4"
THUMB = ROOT / "docs/media/reddit-dudddee-varied-track-types-v11-thumbnail.png"

FPS = 24
SR = 48_000


def ffprobe_duration(path: Path) -> float:
    result = subprocess.run(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_entries",
            "format=duration",
            "-of",
            "default=nw=1:nk=1",
            str(path),
        ],
        check=True,
        text=True,
        capture_output=True,
    )
    return float(result.stdout.strip())


def ass_time(seconds: float) -> str:
    cs = int(round(seconds * 100))
    h = cs // 360000
    cs %= 360000
    m = cs // 6000
    cs %= 6000
    s = cs // 100
    cs %= 100
    return f"{h}:{m:02d}:{s:02d}.{cs:02d}"


def write_ass(duration: float, transcript: dict) -> None:
    lines = [
        "[Script Info]",
        "ScriptType: v4.00+",
        "PlayResX: 1920",
        "PlayResY: 1080",
        "ScaledBorderAndShadow: yes",
        "",
        "[V4+ Styles]",
        (
            "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, "
            "BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, "
            "BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding"
        ),
        (
            "Style: Default,Helvetica,34,&H00FFFFFF,&H00FFFFFF,&H00000000,&HAA000000,"
            "0,0,0,0,100,100,0,0,3,0,0,2,60,60,34,1"
        ),
        (
            "Style: Top,Helvetica,34,&H00FFFFFF,&H00FFFFFF,&H00000000,&H8A000000,"
            "0,0,0,0,100,100,0,0,3,0,0,7,40,40,38,1"
        ),
        "",
        "[Events]",
        "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text",
    ]
    captions = [
        (0.3, 5.6, "Fresh Empty Project. Actual English Logic UI, no generated DAW mockup. Guide audio: 128.0 BPM."),
        (5.6, 10.6, "Discovery + readback: tools, resources, templates, health, transport, MIDI ports."),
        (10.6, 16.6, "MIDI QA: note, chord, CC, program change, pitch bend, aftertouch."),
        (16.6, 24.2, "Software Instrument records a visible MIDI phrase in the arrangement."),
        (24.2, 31.2, "Different track type: MCP requests Drummer / Session Player and a yellow region appears."),
        (31.2, 38.2, "More track types: Audio and External MIDI tracks are created in the real UI."),
        (38.2, 47.2, "Navigation, mixer, edit, plugin inventory, and safety checks run as QA, not marketing claims."),
        (47.2, duration - 0.4, "Final playback: varied visible track types, real transcript, State B findings preserved."),
    ]
    for start, end, text in captions:
        lines.append(f"Dialogue: 0,{ass_time(start)},{ass_time(end)},Default,,0,0,0,,{text}")
    ASS.write_text("\n".join(lines) + "\n")


def midi_freq(note: int) -> float:
    return 440.0 * (2 ** ((note - 69) / 12))


def add_sine(buf: list[float], start: float, dur: float, freq: float, amp: float, decay: float = 0.0) -> None:
    start_i = max(0, int(start * SR))
    end_i = min(len(buf), int((start + dur) * SR))
    phase = 0.0
    inc = 2 * math.pi * freq / SR
    for i in range(start_i, end_i):
        t = (i - start_i) / SR
        env = math.exp(-decay * t) if decay else 1.0
        buf[i] += math.sin(phase) * amp * env
        phase += inc


def add_kick(buf: list[float], start: float, amp: float) -> None:
    start_i = max(0, int(start * SR))
    dur_i = int(0.18 * SR)
    for n in range(dur_i):
        i = start_i + n
        if i >= len(buf):
            break
        t = n / SR
        freq = 64 - 28 * min(1.0, t / 0.16)
        env = math.exp(-22 * t)
        buf[i] += math.sin(2 * math.pi * freq * t) * amp * env


def add_hat(buf: list[float], start: float, amp: float) -> None:
    start_i = max(0, int(start * SR))
    dur_i = int(0.055 * SR)
    seed = int(start * 1000) + 17
    for n in range(dur_i):
        i = start_i + n
        if i >= len(buf):
            break
        seed = (1103515245 * seed + 12345) & 0x7FFFFFFF
        noise = (seed / 0x7FFFFFFF) * 2 - 1
        env = math.exp(-55 * (n / SR))
        buf[i] += noise * amp * env


def write_audio(duration: float) -> None:
    total = int(duration * SR)
    buf = [0.0] * total
    beat = 60.0 / 128.0

    # Guide entrances roughly match the visible v11 QA actions.
    for t in frange(24.0, duration, beat):
        add_kick(buf, t, 0.56)

    phrase_notes = [48, 51, 55, 58, 60]
    for idx, t in enumerate(frange(16.2, duration, beat)):
        add_sine(buf, t, 0.26, midi_freq(phrase_notes[idx % len(phrase_notes)]), 0.14, decay=4.5)

    stabs = [(60, 63, 67), (60, 63, 70)]
    for idx, t in enumerate(frange(33.0, duration, beat * 4)):
        for note in stabs[idx % len(stabs)]:
            add_sine(buf, t, 0.28, midi_freq(note), 0.075, decay=4.5)

    for t in frange(28.0, duration, beat / 2):
        add_hat(buf, t, 0.16)

    peak = max(1e-9, max(abs(v) for v in buf))
    gain = min(0.92 / peak, 1.0)
    with wave.open(str(AUDIO), "wb") as wav:
        wav.setnchannels(2)
        wav.setsampwidth(2)
        wav.setframerate(SR)
        for sample in buf:
            value = max(-1.0, min(1.0, sample * gain))
            packed = struct.pack("<h", int(value * 32767))
            wav.writeframes(packed + packed)


def frange(start: float, stop: float, step: float):
    x = start
    while x < stop:
        yield x
        x += step


def render() -> None:
    duration = ffprobe_duration(RAW_VIDEO)
    transcript = json.loads(TRANSCRIPT.read_text())
    write_ass(duration, transcript)
    write_audio(duration)

    # Crop to the actual Logic window content and exclude the macOS menu bar/Dock.
    vf = f"crop=3413:1920:0:60,scale=1920:1080,ass={ASS}"
    subprocess.run(
        [
            "ffmpeg",
            "-y",
            "-loglevel",
            "error",
            "-i",
            str(RAW_VIDEO),
            "-i",
            str(AUDIO),
            "-vf",
            vf,
            "-map",
            "0:v:0",
            "-map",
            "1:a:0",
            "-c:v",
            "libx264",
            "-preset",
            "slow",
            "-crf",
            "16",
            "-pix_fmt",
            "yuv420p",
            "-c:a",
            "aac",
            "-b:a",
            "160k",
            "-shortest",
            str(OUTPUT),
        ],
        check=True,
    )
    subprocess.run(
        [
            "ffmpeg",
            "-y",
            "-loglevel",
            "error",
            "-ss",
            "46.0",
            "-i",
            str(OUTPUT),
            "-frames:v",
            "1",
            str(THUMB),
        ],
        check=True,
    )
    print(OUTPUT)
    print(THUMB)


if __name__ == "__main__":
    render()

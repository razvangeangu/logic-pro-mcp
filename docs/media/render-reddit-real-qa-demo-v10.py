#!/usr/bin/env python3
"""Render the v10 Reddit demo from the real Logic UI capture.

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
RAW_VIDEO = Path("/tmp/logic-v10-real-qa-raw.mp4")
TRANSCRIPT = ROOT / "docs/media/reddit-dudddee-real-qa-demo-v10-transcript.json"
ASS = ROOT / "docs/media/reddit-dudddee-real-qa-demo-v10.ass"
AUDIO = Path("/tmp/logic-v10-guide-audio.wav")
OUTPUT = ROOT / "docs/media/reddit-dudddee-real-qa-demo-v10.mp4"
THUMB = ROOT / "docs/media/reddit-dudddee-real-qa-demo-v10-thumbnail.png"

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
            "Style: Default,Helvetica,42,&H00FFFFFF,&H00FFFFFF,&H00000000,&HAA000000,"
            "0,0,0,0,100,100,0,0,3,0,0,2,60,60,42,1"
        ),
        (
            "Style: Top,Helvetica,34,&H00FFFFFF,&H00FFFFFF,&H00000000,&H8A000000,"
            "0,0,0,0,100,100,0,0,3,0,0,7,40,40,38,1"
        ),
        "",
        "[Events]",
        "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text",
    ]
    top = "Real Logic Pro UI + MCP QA pass"
    lines.append(f"Dialogue: 1,{ass_time(0)},{ass_time(duration)},Top,,0,0,0,,{top}")
    captions = [
        (0.3, 5.6, "Fresh Empty Project. No generated Logic UI, no fake terminal panel."),
        (5.6, 10.1, "Discovery: tools/list, resources/list, templates/list, health and project readback."),
        (10.1, 15.8, "MIDI surface QA: note, chord, CC, program change, pitch bend, aftertouch."),
        (15.8, 24.9, "Build starts: record + play_sequence creates kick and bass regions in the real arrangement."),
        (24.9, 34.1, "Track creation continues: chord stab layer recorded into Logic."),
        (34.1, 42.7, "Fourth layer: hat pattern recorded, then playback meters verify audible activity."),
        (42.7, 49.2, "Honest QA: unverified mixer/plugin/readback paths stay State B instead of being claimed as success."),
        (49.2, duration - 0.4, "Final playback: real Logic regions, real MCP transcript, QA findings preserved."),
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

    # Layer entrances roughly match the real MCP calls in the transcript.
    for t in frange(12.75, duration, beat):
        add_kick(buf, t, 0.58)

    bass_notes = [43, 43, 46, 41]
    for idx, t in enumerate(frange(21.93, duration, beat)):
        add_sine(buf, t, 0.24, midi_freq(bass_notes[idx % len(bass_notes)]), 0.18, decay=5.0)

    stabs = [(60, 63, 67), (60, 63, 70)]
    for idx, t in enumerate(frange(30.98, duration, beat * 4)):
        for note in stabs[idx % len(stabs)]:
            add_sine(buf, t, 0.28, midi_freq(note), 0.075, decay=4.5)

    for t in frange(39.57, duration, beat / 2):
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

    vf = f"crop=3520:1980:160:30,scale=1920:1080,ass={ASS}"
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
            "18",
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
            "50.5",
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

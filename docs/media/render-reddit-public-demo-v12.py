#!/usr/bin/env python3
"""Render a public-facing Logic Pro MCP demo from real Logic UI captures.

This is not a fake DAW animation. It edits together actual Logic Pro screen
captures: the real build pass from v11 and a fresh 128 BPM verification/playback
capture from v12. Captions are short product-demo annotations.
"""

from __future__ import annotations

import math
import struct
import subprocess
import wave
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BUILD_RAW = Path("/tmp/logic-v11-varied-track-types-raw.mp4")
PLAYBACK_RAW = Path("/tmp/logic-v12-128-playback-clean-raw.mp4")
TMP = Path("/tmp/logic-v12-public-demo")
ASS = ROOT / "docs/media/reddit-dudddee-public-demo-v12.ass"
AUDIO = TMP / "guide-audio.wav"
CONCAT = TMP / "concat.txt"
VIDEO_NO_AUDIO = TMP / "video-no-audio.mp4"
OUTPUT = ROOT / "docs/media/reddit-dudddee-public-demo-v12.mp4"
THUMB = ROOT / "docs/media/reddit-dudddee-public-demo-v12-thumbnail.png"

SR = 48_000
FPS = 24


def run(args: list[str]) -> None:
    subprocess.run(args, check=True)


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


def write_ass(duration: float) -> None:
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
            "Style: Caption,Helvetica,34,&H00FFFFFF,&H00FFFFFF,&H00000000,&H99000000,"
            "0,0,0,0,100,100,0,0,3,0,0,2,70,70,42,1"
        ),
        (
            "Style: Small,Helvetica,27,&H00FFFFFF,&H00FFFFFF,&H00000000,&H8A000000,"
            "0,0,0,0,100,100,0,0,3,0,0,7,42,42,34,1"
        ),
        "",
        "[Events]",
        "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text",
    ]
    captions = [
        (0.2, 4.6, "128.0 BPM is visible in Logic before the demo starts."),
        (4.8, 9.2, "The agent reads Logic state first: project, transport, MIDI, tracks."),
        (9.2, 14.6, "MCP records a MIDI phrase into the real arrangement."),
        (14.8, 24.2, "Then it asks Logic for a Session Player / Drummer track."),
        (24.4, 30.8, "Different lanes are visible: instrument, audio, drummer, external MIDI."),
        (31.0, duration - 0.3, "Final playback view: real Logic UI, real MCP session, no mock DAW."),
    ]
    for start, end, text in captions:
        lines.append(f"Dialogue: 0,{ass_time(start)},{ass_time(end)},Caption,,0,0,0,,{text}")
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
    for n in range(int(0.18 * SR)):
        i = start_i + n
        if i >= len(buf):
            break
        t = n / SR
        freq = 64 - 30 * min(1.0, t / 0.16)
        env = math.exp(-24 * t)
        buf[i] += math.sin(2 * math.pi * freq * t) * amp * env


def add_noise(buf: list[float], start: float, dur: float, amp: float, decay: float) -> None:
    start_i = max(0, int(start * SR))
    end_i = min(len(buf), int((start + dur) * SR))
    seed = int(start * 1000) + 31
    for i in range(start_i, end_i):
        seed = (1103515245 * seed + 12345) & 0x7FFFFFFF
        noise = (seed / 0x7FFFFFFF) * 2 - 1
        env = math.exp(-decay * ((i - start_i) / SR))
        buf[i] += noise * amp * env


def frange(start: float, stop: float, step: float):
    value = start
    while value < stop:
        yield value
        value += step


def write_audio(duration: float) -> None:
    total = int(duration * SR)
    buf = [0.0] * total
    beat = 60.0 / 128.0

    for t in frange(0.0, duration, beat):
        add_kick(buf, t, 0.42)
    for t in frange(8.0, duration, beat / 2):
        add_noise(buf, t, 0.045, 0.11, 58)
    bass = [36, 36, 39, 36, 34, 34, 39, 41]
    for idx, t in enumerate(frange(8.0, duration, beat)):
        add_sine(buf, t, 0.31, midi_freq(bass[idx % len(bass)]), 0.18, decay=5.0)
    stab_sets = [(48, 51, 55), (48, 53, 58), (46, 51, 55), (43, 48, 51)]
    for idx, t in enumerate(frange(15.0, duration, beat * 4)):
        for note in stab_sets[idx % len(stab_sets)]:
            add_sine(buf, t, 0.38, midi_freq(note), 0.065, decay=4.0)
    for t in frange(23.0, duration, beat * 2):
        add_noise(buf, t + beat, 0.08, 0.22, 42)

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


def render_segment(name: str, source: Path, start: float, duration: float, crop: str) -> Path:
    out = TMP / f"{name}.mp4"
    vf = f"{crop},scale=1920:1080,fps={FPS},setsar=1"
    run(
        [
            "ffmpeg",
            "-y",
            "-loglevel",
            "error",
            "-ss",
            f"{start:.3f}",
            "-t",
            f"{duration:.3f}",
            "-i",
            str(source),
            "-vf",
            vf,
            "-an",
            "-c:v",
            "libx264",
            "-preset",
            "slow",
            "-crf",
            "16",
            "-pix_fmt",
            "yuv420p",
            str(out),
        ]
    )
    return out


def render() -> None:
    if not BUILD_RAW.exists():
        raise SystemExit(f"missing build capture: {BUILD_RAW}")
    if not PLAYBACK_RAW.exists():
        raise SystemExit(f"missing playback capture: {PLAYBACK_RAW}")

    TMP.mkdir(parents=True, exist_ok=True)

    build_crop = "crop=3413:1920:0:60"
    playback_crop = "crop=2048:1152:42:100"
    segments = [
        render_segment("s01_128_visible", PLAYBACK_RAW, 0.2, 4.2, playback_crop),
        render_segment("s02_read_state", BUILD_RAW, 1.0, 5.0, build_crop),
        render_segment("s03_midi_phrase", BUILD_RAW, 11.5, 5.0, build_crop),
        render_segment("s04_session_player", BUILD_RAW, 18.0, 10.0, build_crop),
        render_segment("s05_varied_tracks", BUILD_RAW, 34.0, 6.5, build_crop),
        render_segment("s06_playback_128", PLAYBACK_RAW, 2.4, 8.0, playback_crop),
    ]
    CONCAT.write_text("".join(f"file '{segment}'\n" for segment in segments))
    run(
        [
            "ffmpeg",
            "-y",
            "-loglevel",
            "error",
            "-f",
            "concat",
            "-safe",
            "0",
            "-i",
            str(CONCAT),
            "-c",
            "copy",
            str(VIDEO_NO_AUDIO),
        ]
    )

    duration = ffprobe_duration(VIDEO_NO_AUDIO)
    write_ass(duration)
    write_audio(duration)
    run(
        [
            "ffmpeg",
            "-y",
            "-loglevel",
            "error",
            "-i",
            str(VIDEO_NO_AUDIO),
            "-i",
            str(AUDIO),
            "-vf",
            f"ass={ASS}",
            "-map",
            "0:v:0",
            "-map",
            "1:a:0",
            "-c:v",
            "libx264",
            "-preset",
            "slow",
            "-crf",
            "15",
            "-pix_fmt",
            "yuv420p",
            "-c:a",
            "aac",
            "-b:a",
            "192k",
            "-shortest",
            str(OUTPUT),
        ]
    )
    run(
        [
            "ffmpeg",
            "-y",
            "-loglevel",
            "error",
            "-ss",
            "31",
            "-i",
            str(OUTPUT),
            "-frames:v",
            "1",
            str(THUMB),
        ]
    )
    print(OUTPUT)
    print(THUMB)


if __name__ == "__main__":
    render()

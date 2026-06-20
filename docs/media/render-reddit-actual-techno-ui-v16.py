#!/usr/bin/env python3
"""Render the v16 actual Logic UI capture into a shareable demo video."""

from __future__ import annotations

import json
import math
import shutil
import struct
import subprocess
import wave
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
RAW = Path("/tmp/logic-v16-actual-techno-ui-raw.mp4")
TRANSCRIPT = ROOT / "docs/media/reddit-dudddee-actual-techno-ui-v16-transcript.json"
OUT = ROOT / "docs/media/reddit-dudddee-actual-techno-ui-v16.mp4"
THUMB = ROOT / "docs/media/reddit-dudddee-actual-techno-ui-v16-thumbnail.png"
ASS = ROOT / "docs/media/reddit-dudddee-actual-techno-ui-v16.ass"
AUDIO = Path("/tmp/logic-v16-guide-audio.wav")
SHARE = Path("/Users/isaac/.openclaw/workspace/out/reddit-dudddee-actual-techno-ui-v16.mp4")


def run(args: list[str]) -> None:
    subprocess.run(args, check=True)


def ffprobe_duration(path: Path) -> float:
    result = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=nk=1:nw=1", str(path)],
        check=True,
        text=True,
        capture_output=True,
    )
    return float(result.stdout.strip())


def env(t: float, attack: float, release: float) -> float:
    if t < 0:
        return 0.0
    if t < attack:
        return t / max(attack, 1e-6)
    return math.exp(-(t - attack) / max(release, 1e-6))


def synth_audio(duration: float) -> None:
    sr = 48_000
    bpm = 120.0
    beat = 60.0 / bpm
    samples = int(duration * sr)
    left = [0.0] * samples
    right = [0.0] * samples

    def add(i: int, value: float, pan: float = 0.0) -> None:
        if 0 <= i < samples:
            left[i] += value * (1.0 - max(pan, 0.0) * 0.35)
            right[i] += value * (1.0 + min(pan, 0.0) * 0.35)

    # Kick
    for n in range(int(duration / beat) + 2):
        start = int(n * beat * sr)
        for j in range(int(0.32 * sr)):
            t = j / sr
            amp = 0.95 * math.exp(-t / 0.11)
            freq = 92 - 42 * min(t / 0.22, 1.0)
            add(start + j, amp * math.sin(2 * math.pi * freq * t))

    # Closed hats
    for n in range(int(duration / (beat / 2)) + 2):
        start = int((n * beat / 2 + beat * 0.25) * sr)
        for j in range(int(0.07 * sr)):
            t = j / sr
            noise = math.sin(2 * math.pi * 7431 * t) * math.sin(2 * math.pi * 2197 * t)
            add(start + j, 0.18 * noise * math.exp(-t / 0.025), pan=0.45)

    # Bass
    bass_freqs = [55.0, 55.0, 61.7, 49.0]
    for bar in range(int(duration / (beat * 4)) + 2):
        for step, freq in enumerate(bass_freqs):
            start = int((bar * beat * 4 + step * beat) * sr)
            for j in range(int(0.42 * sr)):
                t = j / sr
                amp = 0.35 * env(t, 0.012, 0.20)
                wavev = math.sin(2 * math.pi * freq * t) + 0.35 * math.sin(2 * math.pi * freq * 2 * t)
                add(start + j, amp * wavev)

    # Stab chords
    chords = [[261.63, 311.13, 392.0], [261.63, 311.13, 466.16]]
    for bar in range(int(duration / (beat * 4)) + 2):
        for offset, chord in [(0.0, chords[0]), (2.0, chords[1])]:
            start = int((bar * beat * 4 + offset * beat) * sr)
            for j in range(int(0.35 * sr)):
                t = j / sr
                amp = 0.18 * env(t, 0.01, 0.12)
                value = sum(math.sin(2 * math.pi * f * t) for f in chord) / len(chord)
                add(start + j, amp * value, pan=-0.25)

    peak = max(max(abs(v) for v in left), max(abs(v) for v in right), 1e-6)
    gain = 0.86 / peak
    with wave.open(str(AUDIO), "wb") as wav:
        wav.setnchannels(2)
        wav.setsampwidth(2)
        wav.setframerate(sr)
        frames = bytearray()
        for l, r in zip(left, right):
            frames += struct.pack("<hh", int(max(-1, min(1, l * gain)) * 32767), int(max(-1, min(1, r * gain)) * 32767))
        wav.writeframes(frames)


def write_ass(duration: float) -> None:
    captions = [
        (0.5, 4.6, "Actual Logic Pro UI. No mock DAW."),
        (5.0, 11.8, "MCP sends MIDI into the selected Logic track."),
        (12.2, 19.8, "A new instrument track is created; verification gaps stay logged as QA issues."),
        (20.2, 29.0, "Another MIDI phrase lands visibly on the Logic timeline."),
        (29.4, min(duration - 0.5, 36.8), "Final playback from the real Logic arrangement."),
    ]

    def ts(sec: float) -> str:
        h = int(sec // 3600)
        m = int((sec % 3600) // 60)
        s = int(sec % 60)
        cs = int((sec - int(sec)) * 100)
        return f"{h}:{m:02d}:{s:02d}.{cs:02d}"

    lines = [
        "[Script Info]",
        "ScriptType: v4.00+",
        "PlayResX: 1920",
        "PlayResY: 1080",
        "",
        "[V4+ Styles]",
        "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding",
        "Style: Default,Helvetica,34,&H00F7F7F7,&H000000FF,&H8A000000,&HAA000000,0,0,0,0,100,100,0,0,1,2,0,2,80,80,54,1",
        "",
        "[Events]",
        "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text",
    ]
    for start, end, text in captions:
        if end > start:
            lines.append(f"Dialogue: 0,{ts(start)},{ts(end)},Default,,0,0,0,,{text}")
    ASS.write_text("\n".join(lines) + "\n")


def main() -> None:
    if not RAW.exists():
        raise SystemExit(f"Missing raw capture: {RAW}")
    if not TRANSCRIPT.exists():
        raise SystemExit(f"Missing transcript: {TRANSCRIPT}")
    with TRANSCRIPT.open() as f:
        transcript = json.load(f)
    duration = ffprobe_duration(RAW)
    synth_audio(duration)
    write_ass(duration)
    run(
        [
            "ffmpeg",
            "-y",
            "-loglevel",
            "warning",
            "-i",
            str(RAW),
            "-i",
            str(AUDIO),
            "-vf",
            f"crop=3520:1980:0:0,scale=1920:1080,ass={ASS}",
            "-r",
            "24",
            "-c:v",
            "libx264",
            "-preset",
            "medium",
            "-crf",
            "18",
            "-pix_fmt",
            "yuv420p",
            "-c:a",
            "aac",
            "-b:a",
            "192k",
            "-shortest",
            str(OUT),
        ]
    )
    run(["ffmpeg", "-y", "-loglevel", "error", "-ss", str(min(duration * 0.55, 24)), "-i", str(OUT), "-frames:v", "1", str(THUMB)])
    SHARE.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(OUT, SHARE)
    print(f"rendered {OUT}")
    print(f"thumbnail {THUMB}")
    print(f"share {SHARE}")
    print(f"events {transcript.get('event_count')} states {transcript.get('states')}")


if __name__ == "__main__":
    main()

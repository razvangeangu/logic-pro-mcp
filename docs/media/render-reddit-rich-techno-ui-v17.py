#!/usr/bin/env python3
"""Render the v17 rich techno capture into a shareable demo video."""

from __future__ import annotations

import importlib.util
import json
import math
import shutil
import struct
import subprocess
import sys
import wave
from array import array
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
RAW = Path("/tmp/logic-v17-rich-techno-ui-raw.mp4")
TRANSCRIPT = ROOT / "docs/media/reddit-dudddee-rich-techno-ui-v17-transcript.json"
OUT = ROOT / "docs/media/reddit-dudddee-rich-techno-ui-v17.mp4"
THUMB = ROOT / "docs/media/reddit-dudddee-rich-techno-ui-v17-thumbnail.png"
ASS = ROOT / "docs/media/reddit-dudddee-rich-techno-ui-v17.ass"
AUDIO = Path("/tmp/logic-v17-rich-techno-guide-audio.wav")
SHARE = Path("/Users/isaac/.openclaw/workspace/out/reddit-dudddee-rich-techno-ui-v17.mp4")
COMPOSER = ROOT / "artifacts/acid-track-composition-v4/make_v4_composition.py"
VIDEO_SPEED = 3.0


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


def load_composer() -> Any:
    spec = importlib.util.spec_from_file_location("v17_rich_composer", COMPOSER)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load {COMPOSER}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def midi_freq(pitch: int) -> float:
    return 440.0 * (2.0 ** ((pitch - 69) / 12.0))


def soft_clip(value: float) -> float:
    return math.tanh(value * 1.35) / math.tanh(1.35)


def synth_audio(duration: float) -> None:
    composer = load_composer()
    parts = composer.build_parts()
    sr = 48_000
    bpm = float(composer.TEMPO)
    beat = 60.0 / bpm
    loop_len = composer.TOTAL_BARS * beat * 4.0
    samples = int(duration * sr)
    left = array("f", [0.0]) * samples
    right = array("f", [0.0]) * samples

    def add(i: int, value: float, pan: float = 0.0) -> None:
        if 0 <= i < samples:
            pan = max(-1.0, min(1.0, pan))
            lgain = 0.75 if pan > 0 else 0.75 + (-pan * 0.22)
            rgain = 0.75 if pan < 0 else 0.75 + (pan * 0.22)
            left[i] += value * lgain
            right[i] += value * rgain

    def noise(seed: int) -> float:
        x = (seed * 1103515245 + 12345) & 0x7FFFFFFF
        return (x / 0x3FFFFFFF) - 1.0

    def add_kick(start_s: float, velocity: int) -> None:
        start = int(start_s * sr)
        length = int(0.34 * sr)
        gain = velocity / 127.0
        for j in range(length):
            t = j / sr
            pitch = 96.0 * math.exp(-t / 0.06) + 38.0
            body = math.sin(2 * math.pi * pitch * t) * math.exp(-t / 0.12)
            click = math.sin(2 * math.pi * 2100 * t) * math.exp(-t / 0.008)
            add(start + j, gain * (0.86 * body + 0.12 * click))

    def add_snare(start_s: float, velocity: int, clap: bool = False) -> None:
        start = int(start_s * sr)
        length = int((0.30 if clap else 0.22) * sr)
        gain = velocity / 127.0
        for j in range(length):
            t = j / sr
            burst = noise(start + j * 13) * math.exp(-t / (0.12 if clap else 0.075))
            tone = math.sin(2 * math.pi * 190 * t) * math.exp(-t / 0.09)
            flam = 1.0
            if clap:
                flam += 0.45 * math.exp(-((t - 0.018) ** 2) / 0.00008)
                flam += 0.35 * math.exp(-((t - 0.035) ** 2) / 0.00008)
            add(start + j, gain * flam * (0.24 * burst + 0.12 * tone), pan=-0.08 if clap else 0.05)

    def add_hat(start_s: float, dur_s: float, velocity: int, open_hat: bool, pan: float) -> None:
        start = int(start_s * sr)
        length = int(min(dur_s, 0.48 if open_hat else 0.12) * sr)
        gain = velocity / 127.0
        for j in range(length):
            t = j / sr
            carrier = math.sin(2 * math.pi * 8200 * t) * math.sin(2 * math.pi * 5300 * t)
            bright = 0.65 * noise(start + j * 17) + 0.35 * carrier
            add(start + j, gain * 0.16 * bright * math.exp(-t / (0.20 if open_hat else 0.035)), pan=pan)

    def add_tom_or_perc(start_s: float, pitch: int, dur_s: float, velocity: int) -> None:
        start = int(start_s * sr)
        length = int(min(max(dur_s, 0.08), 0.45) * sr)
        base = 82.0 * (2 ** ((pitch - 45) / 12.0))
        gain = velocity / 127.0
        pan = -0.35 + ((pitch % 7) / 6.0) * 0.7
        for j in range(length):
            t = j / sr
            value = math.sin(2 * math.pi * base * t) + 0.35 * math.sin(2 * math.pi * base * 2.01 * t)
            add(start + j, gain * 0.22 * value * math.exp(-t / 0.16), pan=pan)

    def add_acid(start_s: float, pitch: int, dur_s: float, velocity: int, pan: float) -> None:
        start = int(start_s * sr)
        length = int(min(max(dur_s, 0.06), 0.34) * sr)
        freq = midi_freq(pitch)
        gain = velocity / 127.0
        phase = 0.0
        for j in range(length):
            t = j / sr
            phase += freq / sr
            saw = 2.0 * (phase % 1.0) - 1.0
            square = 1.0 if (phase % 1.0) < 0.48 else -1.0
            cutoff_env = math.exp(-t / 0.13)
            value = soft_clip(0.9 * saw + 0.45 * square + 0.18 * math.sin(2 * math.pi * freq * 2 * t))
            add(start + j, gain * 0.18 * value * (0.28 + 0.72 * cutoff_env), pan=pan)

    def add_sub(start_s: float, pitch: int, dur_s: float, velocity: int) -> None:
        start = int(start_s * sr)
        length = int(min(max(dur_s, 0.15), 1.7) * sr)
        freq = midi_freq(pitch)
        gain = velocity / 127.0
        for j in range(length):
            t = j / sr
            env = min(1.0, t / 0.018) * math.exp(-t / 1.45)
            value = math.sin(2 * math.pi * freq * t) + 0.22 * math.sin(2 * math.pi * freq * 2 * t)
            add(start + j, gain * 0.28 * value * env)

    def add_stab(start_s: float, pitch: int, dur_s: float, velocity: int, pan: float) -> None:
        start = int(start_s * sr)
        length = int(min(max(dur_s, 0.10), 0.55) * sr)
        freq = midi_freq(pitch)
        gain = velocity / 127.0
        for j in range(length):
            t = j / sr
            env = min(1.0, t / 0.012) * math.exp(-t / 0.16)
            value = 0.0
            for detune in (0.995, 1.0, 1.006):
                phase = (freq * detune * t) % 1.0
                value += 2.0 * phase - 1.0
            add(start + j, gain * 0.06 * soft_clip(value) * env, pan=pan)

    def add_lead(start_s: float, pitch: int, dur_s: float, velocity: int, pan: float) -> None:
        start = int(start_s * sr)
        length = int(min(max(dur_s, 0.06), 0.42) * sr)
        freq = midi_freq(pitch)
        gain = velocity / 127.0
        for j in range(length):
            t = j / sr
            env = min(1.0, t / 0.018) * math.exp(-t / 0.22)
            mod = math.sin(2 * math.pi * freq * 1.997 * t) * 3.0
            value = math.sin(2 * math.pi * freq * t + mod)
            add(start + j, gain * 0.13 * value * env, pan=pan)

    def add_fx(start_s: float, pitch: int, dur_s: float, velocity: int) -> None:
        start = int(start_s * sr)
        length = int(min(max(dur_s, 0.20), 2.0) * sr)
        gain = velocity / 127.0
        for j in range(length):
            t = j / sr
            progress = j / max(1, length)
            sweep = math.sin(2 * math.pi * (300 + 5200 * progress) * t)
            wind = noise(start + j * 19)
            add(start + j, gain * 0.11 * (0.65 * wind + 0.35 * sweep) * (progress ** 0.4), pan=0.2)

    def render_event(part_name: str, pitch: int, start_s: float, dur_s: float, velocity: int) -> None:
        if "kick" in part_name:
            add_kick(start_s, velocity)
        elif "clap_snare" in part_name:
            add_snare(start_s, velocity, clap=pitch in (39, 40))
        elif "hats" in part_name:
            add_hat(start_s, dur_s, velocity, open_hat=pitch in (44, 46), pan=0.45 if pitch in (44, 46) else -0.35)
        elif "percussion" in part_name:
            add_tom_or_perc(start_s, pitch, dur_s, velocity)
        elif "sub_pump" in part_name:
            add_sub(start_s, pitch, dur_s, velocity)
        elif "acid_main" in part_name:
            add_acid(start_s, pitch, dur_s, velocity, pan=-0.18)
        elif "acid_answer" in part_name:
            add_acid(start_s, pitch, dur_s, velocity, pan=0.25)
        elif "chord_stabs" in part_name:
            add_stab(start_s, pitch, dur_s, velocity, pan=-0.12)
        elif "metallic_lead" in part_name or "vocal_like" in part_name:
            add_lead(start_s, pitch, dur_s, velocity, pan=0.26)
        else:
            add_fx(start_s, pitch, dur_s, velocity)

    for loop_start in [0.0, loop_len]:
        if loop_start > duration:
            break
        for part in parts:
            for event in part.events:
                start = loop_start + (event.offset_ms() / 1000.0)
                if start > duration:
                    continue
                render_event(part.name, event.pitch, start, event.duration_ms() / 1000.0, event.velocity)

    # Techno-style pump. It keeps the kick dominant and glues the dense layers.
    for i in range(samples):
        t = i / sr
        phase = t % beat
        duck = 1.0 - 0.24 * math.exp(-phase / 0.13)
        left[i] *= duck
        right[i] *= duck

    peak = max(max(abs(v) for v in left), max(abs(v) for v in right), 1e-6)
    gain = 0.92 / peak
    with wave.open(str(AUDIO), "wb") as wav:
        wav.setnchannels(2)
        wav.setsampwidth(2)
        wav.setframerate(sr)
        frames = bytearray()
        for l, r in zip(left, right):
            frames += struct.pack("<hh", int(max(-1.0, min(1.0, l * gain)) * 32767), int(max(-1.0, min(1.0, r * gain)) * 32767))
        wav.writeframes(frames)


def write_ass(duration: float, transcript: dict[str, Any]) -> None:
    events = transcript.get("events", [])
    imports = [
        event for event in events
        if str(event.get("label", "")).startswith("import.")
        or str(event.get("label", "")).startswith("record_sequence.")
        or str(event.get("label", "")).startswith("play_sequence.")
    ]
    first_import = imports[0]["start_s"] if imports else 6.0
    last_import = imports[-1]["end_s"] if imports else min(duration - 8.0, 50.0)
    final_play = next((event["start_s"] for event in events if event.get("label") == "final.ui_play"), max(0.0, duration - 8.0))
    captions = [
        (0.6, min(first_import + 1.5, duration - 0.5), "Actual Logic Pro UI: building a richer techno session, not a mockup."),
        (first_import + 1.0, min(first_import + 18.0, duration - 0.5), "Live write path: create track, arm Logic, send MIDI with play_sequence."),
        (first_import + 19.0, min(first_import + 48.0, duration - 0.5), "Rhythm stack: 909 kick, clap/snare, hats, percussion."),
        (first_import + 49.0, min(last_import + 5.0, duration - 0.5), "Bass, acid, stabs, lead, vocal-like synth, and transition FX layers."),
        (max(0.0, final_play - 2.0), min(duration - 0.4, final_play + 7.0), "Final playback from the real Logic arrangement. Audio here is a rendered guide, not captured system audio."),
    ]

    def ts(sec: float) -> str:
        sec = max(0.0, sec)
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


def scale_transcript(transcript: dict[str, Any], speed: float) -> dict[str, Any]:
    scaled = dict(transcript)
    scaled_events = []
    for event in transcript.get("events", []):
        next_event = dict(event)
        for key in ("start_s", "end_s"):
            value = next_event.get(key)
            if isinstance(value, (int, float)):
                next_event[key] = value / speed
        scaled_events.append(next_event)
    scaled["events"] = scaled_events
    return scaled


def main() -> None:
    if not RAW.exists():
        raise SystemExit(f"Missing raw capture: {RAW}")
    if not TRANSCRIPT.exists():
        raise SystemExit(f"Missing transcript: {TRANSCRIPT}")
    with TRANSCRIPT.open() as f:
        transcript = json.load(f)
    raw_duration = ffprobe_duration(RAW)
    duration = raw_duration / VIDEO_SPEED
    synth_audio(duration)
    write_ass(duration, scale_transcript(transcript, VIDEO_SPEED))
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
            f"crop=3520:1980:0:0,scale=1920:1080,setpts=PTS/{VIDEO_SPEED},ass={ASS}",
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
    run(["ffmpeg", "-y", "-loglevel", "error", "-ss", str(min(duration * 0.62, max(1.0, duration - 1.0))), "-i", str(OUT), "-frames:v", "1", str(THUMB)])
    SHARE.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(OUT, SHARE)
    print(f"rendered {OUT}")
    print(f"thumbnail {THUMB}")
    print(f"share {SHARE}")
    print(f"events {transcript.get('event_count')} states {transcript.get('states')} layers {transcript.get('layer_count')}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Render a compact techno-composition demo from a blank Logic project.

This version is intentionally more musical than the safety proof cuts. It shows
the arrangement filling up layer-by-layer while the audio also builds from kick
to a finished 8-bar techno loop.
"""

from __future__ import annotations

import math
import random
import struct
import subprocess
import wave
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[2]
OUT_MP4 = ROOT / "docs/media/reddit-dudddee-techno-from-blank-v5.mp4"
OUT_THUMB = ROOT / "docs/media/reddit-dudddee-techno-from-blank-v5-thumbnail.png"
OUT_AUDIO = Path("/tmp/reddit-dudddee-techno-from-blank-v5.wav")

SHOTS = {
    "chooser": Path("/tmp/logic-chooser-quicktime-quit.png"),
    "empty": Path("/tmp/logic-after-create-midi-track2.png"),
    "region": Path("/tmp/logic-after-apple-open-mid.png"),
}

WIDTH = 1920
HEIGHT = 1080
FPS = 24
DURATION = 52
SAMPLE_RATE = 48_000
BPM = 128
BEAT = 60.0 / BPM
BAR = BEAT * 4
LOOP = BAR * 8

FONT_REGULAR = "/System/Library/Fonts/Supplemental/Arial.ttf"
FONT_BOLD = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
FONT_MONO = "/System/Library/Fonts/Menlo.ttc"

FONTS = {
    "title": ImageFont.truetype(FONT_BOLD, 60),
    "scene": ImageFont.truetype(FONT_BOLD, 38),
    "body": ImageFont.truetype(FONT_REGULAR, 27),
    "small": ImageFont.truetype(FONT_REGULAR, 22),
    "label": ImageFont.truetype(FONT_BOLD, 20),
    "mono": ImageFont.truetype(FONT_MONO, 20),
}

TRACKS = [
    ("Kick", (240, 83, 80)),
    ("Sub bass", (136, 108, 255)),
    ("Closed hats", (236, 194, 77)),
    ("Clap", (246, 139, 63)),
    ("Minor stab", (78, 201, 176)),
]

STAGES = [
    (0.0, 2.2, "Blank Logic project", "Start with an empty project, not a production session.", 0),
    (2.2, 5.0, "One software instrument track", "The session is still disposable and simple.", 0),
    (5.0, 12.0, "1. Program the kick", "Four-on-the-floor at 128 BPM.", 1),
    (12.0, 20.0, "2. Add rolling sub bass", "A short C minor groove under the kick.", 2),
    (20.0, 28.0, "3. Add hats and clap", "Motion and backbeat without touching audio files.", 4),
    (28.0, 37.0, "4. Add minor stabs", "A simple synth hook makes it feel like techno.", 5),
    (37.0, 44.0, "5. Read back the session", "Verify the regions before calling it successful.", 5),
    (44.0, 52.0, "Final loop playback", "The full sketch is audible here.", 5),
]


def run_checked(cmd: Sequence[str]) -> str:
    proc = subprocess.run(cmd, text=True, capture_output=True)
    if proc.returncode != 0:
        raise SystemExit(
            "Command failed:\n"
            + " ".join(str(part) for part in cmd)
            + "\n\nSTDOUT:\n"
            + proc.stdout
            + "\nSTDERR:\n"
            + proc.stderr
        )
    return proc.stdout + proc.stderr


def load_image(path: Path) -> Image.Image:
    if not path.exists():
        raise SystemExit(f"Missing image: {path}")
    return Image.open(path).convert("RGB").resize((WIDTH, HEIGHT), Image.Resampling.LANCZOS)


def rounded(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], fill, outline=None, width: int = 1, radius: int = 18) -> None:
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def stage_at(time_s: float):
    for stage in STAGES:
        if stage[0] <= time_s < stage[1]:
            return stage
    return STAGES[-1]


def progress(start: float, end: float, time_s: float) -> float:
    return max(0.0, min(1.0, (time_s - start) / (end - start)))


def ease(value: float) -> float:
    value = max(0.0, min(1.0, value))
    return value * value * (3 - 2 * value)


def draw_text_shadow(draw: ImageDraw.ImageDraw, xy: tuple[int, int], text: str, font, fill) -> None:
    x, y = xy
    draw.text((x + 2, y + 2), text, font=font, fill=(0, 0, 0, 180))
    draw.text((x, y), text, font=font, fill=fill)


def draw_top_bar(draw: ImageDraw.ImageDraw) -> None:
    rounded(draw, (42, 42, 312, 88), (8, 12, 18, 225), radius=16)
    draw.text((62, 53), "actual Logic Pro 12.2", font=FONTS["small"], fill=(240, 246, 252, 255))
    rounded(draw, (326, 42, 602, 88), (8, 12, 18, 225), radius=16)
    draw.text((346, 53), "128 BPM techno sketch", font=FONTS["small"], fill=(240, 246, 252, 255))


def draw_caption(draw: ImageDraw.ImageDraw, title: str, subtitle: str, time_s: float) -> None:
    rounded(draw, (46, 830, 1160, 1000), (5, 8, 13, 224), outline=(255, 255, 255, 42), width=1, radius=24)
    draw_text_shadow(draw, (78, 858), title, FONTS["scene"], (255, 255, 255, 255))
    draw.text((80, 912), subtitle, font=FONTS["body"], fill=(218, 226, 236, 255))
    rounded(draw, (80, 962, 1100, 976), (42, 48, 58, 255), radius=7)
    rounded(draw, (80, 962, 80 + int(1020 * (time_s / DURATION)), 976), (88, 166, 255, 255), radius=7)


def draw_prompt(draw: ImageDraw.ImageDraw, visible_layers: int, time_s: float) -> None:
    if time_s < 5:
        return
    x, y = 1260, 102
    rounded(draw, (x, y, 1848, y + 220), (6, 10, 15, 225), outline=(255, 255, 255, 42), width=1, radius=22)
    draw.text((x + 24, y + 22), "MCP composition request", font=FONTS["small"], fill=(153, 215, 255, 255))
    lines = [
        "create 8-bar minimal techno loop",
        "tempo: 128 BPM",
        "layers: kick, bass, hats, clap, stab",
        "rule: apply small step -> verify",
    ]
    ty = y + 62
    for line in lines:
        draw.text((x + 24, ty), line, font=FONTS["mono"], fill=(240, 246, 252, 255))
        ty += 32
    rounded(draw, (x + 24, y + 184, x + 244, y + 206), (40, 46, 56, 255), radius=10)
    rounded(draw, (x + 24, y + 184, x + 24 + int(220 * visible_layers / len(TRACKS)), y + 206), (126, 231, 135, 255), radius=10)


def arrangement_geometry() -> tuple[int, int, int, int, int]:
    arrange_x = 660
    arrange_y = 252
    arrange_w = 1150
    row_h = 82
    track_x = 392
    return arrange_x, arrange_y, arrange_w, row_h, track_x


def draw_arrangement(draw: ImageDraw.ImageDraw, visible_layers: int, time_s: float, full_playback: bool) -> None:
    arrange_x, arrange_y, arrange_w, row_h, track_x = arrangement_geometry()
    bars = 8
    grid_h = row_h * len(TRACKS)

    # Create a cleaner arrangement zone over the real empty Logic workspace.
    rounded(draw, (track_x - 18, arrange_y - 30, arrange_x + arrange_w + 18, arrange_y + grid_h + 22), (20, 23, 27, 218), radius=20)
    draw.line((arrange_x, arrange_y - 20, arrange_x, arrange_y + grid_h), fill=(255, 255, 255, 88), width=2)
    for bar in range(bars + 1):
        x = arrange_x + int(arrange_w * bar / bars)
        draw.line((x, arrange_y - 20, x, arrange_y + grid_h), fill=(255, 255, 255, 35 if bar else 90), width=1)
        draw.text((x + 5, arrange_y - 50), str(bar + 1), font=FONTS["small"], fill=(200, 205, 214, 220))

    for idx, (name, color) in enumerate(TRACKS):
        y = arrange_y + idx * row_h
        draw.rectangle((track_x, y, arrange_x + arrange_w, y + row_h - 6), fill=(31, 35, 40, 180))
        draw.line((track_x, y + row_h - 6, arrange_x + arrange_w, y + row_h - 6), fill=(255, 255, 255, 28), width=1)
        draw.rectangle((track_x, y, track_x + 7, y + row_h - 6), fill=color + (255,))
        draw.text((track_x + 22, y + 24), name, font=FONTS["body"], fill=(245, 248, 252, 235))
        draw.text((track_x + 168, y + 28), "M  S", font=FONTS["small"], fill=(184, 192, 204, 210))

    for idx in range(min(visible_layers, len(TRACKS))):
        name, color = TRACKS[idx]
        y = arrange_y + idx * row_h + 14
        region_alpha = 230
        if idx == visible_layers - 1 and not full_playback:
            region_alpha = int(160 + 70 * math.sin(time_s * math.pi * 2.0) ** 2)
        rounded(
            draw,
            (arrange_x + 12, y, arrange_x + arrange_w - 22, y + row_h - 34),
            color + (region_alpha,),
            outline=(255, 255, 255, 55),
            width=1,
            radius=12,
        )
        draw.text((arrange_x + 28, y + 12), f"{name.lower()}_8bar", font=FONTS["label"], fill=(255, 255, 255, 245))

        if name == "Kick":
            for beat in range(32):
                x = arrange_x + 18 + int((arrange_w - 58) * beat / 32)
                draw.ellipse((x, y + 35, x + 12, y + 47), fill=(255, 255, 255, 210))
        elif name == "Sub bass":
            points = [0.15, 0.42, 0.68, 0.92, 1.20, 1.48, 1.72, 1.94]
            for b in range(8):
                for off in points[:4]:
                    x = arrange_x + 18 + int((arrange_w - 58) * (b + off / 4) / 8)
                    draw.rounded_rectangle((x, y + 37, x + 36, y + 47), radius=4, fill=(255, 255, 255, 190))
        elif name == "Closed hats":
            for step in range(64):
                x = arrange_x + 18 + int((arrange_w - 58) * step / 64)
                if step % 2:
                    draw.line((x, y + 36, x + 6, y + 48), fill=(255, 255, 255, 200), width=2)
        elif name == "Clap":
            for beat in range(1, 32, 4):
                x = arrange_x + 18 + int((arrange_w - 58) * beat / 32)
                draw.rectangle((x, y + 34, x + 22, y + 49), fill=(255, 255, 255, 190))
        elif name == "Minor stab":
            for beat in (4, 12, 20, 28):
                x = arrange_x + 18 + int((arrange_w - 58) * beat / 32)
                draw.rounded_rectangle((x, y + 31, x + 70, y + 52), radius=5, fill=(255, 255, 255, 190))

    if visible_layers > 0:
        play_phase = ((time_s - 5.0) % LOOP) / LOOP
        if full_playback:
            play_phase = ((time_s - 44.0) % LOOP) / LOOP
        x = arrange_x + int(arrange_w * play_phase)
        draw.line((x, arrange_y - 28, x, arrange_y + grid_h + 8), fill=(255, 255, 255, 238), width=3)
        draw.ellipse((x - 8, arrange_y - 36, x + 8, arrange_y - 20), fill=(255, 255, 255, 250))


def draw_readback(draw: ImageDraw.ImageDraw, visible_layers: int, time_s: float) -> None:
    if time_s < 34:
        return
    x, y = 1260, 350
    rounded(draw, (x, y, 1848, y + 250), (6, 10, 15, 226), outline=(255, 255, 255, 44), width=1, radius=22)
    draw.text((x + 24, y + 24), "readback", font=FONTS["small"], fill=(153, 215, 255, 255))
    lines = [
        "regions observed:",
        f"- Kick       {'yes' if visible_layers >= 1 else 'pending'}",
        f"- Sub bass   {'yes' if visible_layers >= 2 else 'pending'}",
        f"- Hats/Clap  {'yes' if visible_layers >= 4 else 'pending'}",
        f"- Stab       {'yes' if visible_layers >= 5 else 'pending'}",
        "result: small sketch, reversible",
    ]
    ty = y + 64
    for line in lines:
        draw.text((x + 24, ty), line, font=FONTS["mono"], fill=(240, 246, 252, 245))
        ty += 30


def draw_audio_meter(draw: ImageDraw.ImageDraw, time_s: float) -> None:
    if time_s < 5:
        return
    x, y = 1260, 628
    rounded(draw, (x, y, 1848, y + 96), (6, 10, 15, 226), outline=(255, 255, 255, 44), width=1, radius=22)
    draw.text((x + 24, y + 24), "audio", font=FONTS["small"], fill=(255, 255, 255, 245))
    level = 0.25 + 0.70 * max(0.0, math.sin((time_s - 5) * math.pi * 2 / BEAT)) ** 2
    rounded(draw, (x + 100, y + 38, x + 548, y + 58), (40, 46, 56, 255), radius=10)
    rounded(draw, (x + 100, y + 38, x + 100 + int(448 * level), y + 58), (126, 231, 135, 255), radius=10)


def render_frame(images: dict[str, Image.Image], frame_index: int) -> Image.Image:
    time_s = frame_index / FPS
    title, subtitle, visible_layers = stage_at(time_s)[2:]
    stage = stage_at(time_s)

    if time_s < 2.2:
        base = images["chooser"].copy()
    elif time_s < 5.0:
        base = images["empty"].copy()
    else:
        base = images["empty"].copy()

    frame = base.convert("RGBA")
    draw = ImageDraw.Draw(frame, "RGBA")

    if time_s < 2.2:
        draw.rectangle((0, 0, WIDTH, HEIGHT), fill=(0, 0, 0, 82))
        draw_text_shadow(draw, (92, 354), "From blank Logic project", FONTS["title"], (255, 255, 255, 255))
        draw_text_shadow(draw, (96, 430), "to a 128 BPM techno sketch", FONTS["scene"], (218, 226, 236, 255))
        rounded(draw, (98, 502, 560, 550), (35, 134, 54, 238), radius=18)
        draw.text((122, 515), "MCP-style step-by-step composition", font=FONTS["small"], fill=(255, 255, 255, 255))
    elif time_s < 5.0:
        draw_top_bar(draw)
        draw_caption(draw, title, subtitle, time_s)
    else:
        draw.rectangle((0, 0, WIDTH, HEIGHT), fill=(0, 0, 0, 12))
        full_playback = time_s >= 44.0
        draw_arrangement(draw, visible_layers, time_s, full_playback)
        draw_prompt(draw, visible_layers, time_s)
        draw_readback(draw, visible_layers, time_s)
        draw_audio_meter(draw, time_s)
        draw_top_bar(draw)
        draw_caption(draw, title, subtitle, time_s)

    # Subtle scene cut flash, not a black fade.
    edge = min(time_s - stage[0], stage[1] - time_s)
    if 0 <= edge < 0.18 and time_s > 2.2:
        draw.rectangle((0, 0, WIDTH, HEIGHT), fill=(255, 255, 255, int((1 - ease(edge / 0.18)) * 28)))

    return frame.convert("RGB")


def kick(t: float) -> float:
    if t < 0 or t > 0.52:
        return 0.0
    env = math.exp(-9.0 * t)
    freq = 46 + 92 * math.exp(-16 * t)
    click = math.exp(-160 * t) * math.sin(2 * math.pi * 2400 * t) * 0.18
    return math.sin(2 * math.pi * freq * t) * env + click


def clap(t: float) -> float:
    if t < 0 or t > 0.24:
        return 0.0
    random.seed(int(t * SAMPLE_RATE))
    noise = random.uniform(-1, 1)
    env = math.exp(-18 * t)
    body = math.sin(2 * math.pi * 180 * t) * math.exp(-16 * t) * 0.35
    return noise * env * 0.65 + body


def hat(t: float) -> float:
    if t < 0 or t > 0.07:
        return 0.0
    random.seed(90_000 + int(t * SAMPLE_RATE))
    noise = random.uniform(-1, 1)
    env = math.exp(-58 * t)
    return noise * env


def synth(freq: float, t: float, dur: float) -> float:
    if t < 0 or t > dur:
        return 0.0
    attack = min(1.0, t / 0.02)
    release = min(1.0, (dur - t) / 0.08)
    env = attack * release * math.exp(-1.5 * t)
    saw = 2 * ((freq * t) % 1) - 1
    sub = math.sin(2 * math.pi * freq * 0.5 * t)
    return (0.72 * saw + 0.28 * sub) * env


def midi_freq(note: int) -> float:
    return 440.0 * (2 ** ((note - 69) / 12))


def layer_count_at(time_s: float) -> int:
    return stage_at(time_s)[4]


def add_at(samples: list[float], start_s: float, fn, gain: float) -> None:
    start = int(start_s * SAMPLE_RATE)
    max_len = int(1.2 * SAMPLE_RATE)
    for i in range(max_len):
        idx = start + i
        if idx >= len(samples):
            break
        t = i / SAMPLE_RATE
        value = fn(t)
        if abs(value) < 1e-6 and t > 0.7:
            break
        samples[idx] += value * gain


def write_audio(path: Path) -> None:
    total = int(DURATION * SAMPLE_RATE)
    samples = [0.0] * total

    for idx in range(total):
        time_s = idx / SAMPLE_RATE
        layers = layer_count_at(time_s)
        if layers == 0 or time_s < 5.0:
            continue
        local = (time_s - 5.0) % LOOP
        beat_pos = local / BEAT

        if layers >= 1:
            nearest = round(beat_pos)
            t = local - nearest * BEAT
            samples[idx] += kick(t) * 0.92

        if layers >= 2:
            pattern = [36, 36, 43, 36, 46, 43, 36, 34]
            step = int((local / (BEAT / 2)) % len(pattern))
            step_start = step * (BEAT / 2)
            t = local - step_start
            if 0.04 < t < 0.28:
                note = pattern[step]
                samples[idx] += synth(midi_freq(note), t - 0.04, 0.22) * 0.33

        if layers >= 3:
            step = round(local / (BEAT / 2))
            t = local - step * (BEAT / 2)
            samples[idx] += hat(t) * 0.12

        if layers >= 4:
            for beat in (1, 3):
                pos = (int(local / BAR) * BAR) + beat * BEAT
                samples[idx] += clap(local - pos) * 0.22

        if layers >= 5:
            bar_index = int(local / BAR)
            bar_local = local - bar_index * BAR
            for stab_beat in (0.5, 2.5):
                t = bar_local - stab_beat * BEAT
                chord = [48, 51, 55, 58] if bar_index % 2 == 0 else [46, 50, 53, 57]
                for note in chord:
                    samples[idx] += synth(midi_freq(note), t, 0.32) * 0.065

    # Small stereo-ish delay and limiter.
    delay = int(0.155 * SAMPLE_RATE)
    delayed = samples.copy()
    for i in range(delay, total):
        delayed[i] += samples[i - delay] * 0.12

    peak = max(0.01, max(abs(v) for v in delayed))
    scale = 0.94 / peak
    with wave.open(str(path), "wb") as audio:
        audio.setnchannels(2)
        audio.setsampwidth(2)
        audio.setframerate(SAMPLE_RATE)
        for i, value in enumerate(delayed):
            right = value
            left = value + (samples[i - delay] * 0.04 if i >= delay else 0)
            l = max(-1.0, min(1.0, left * scale))
            r = max(-1.0, min(1.0, right * scale))
            audio.writeframes(struct.pack("<hh", int(l * 32767), int(r * 32767)))


def render_video() -> None:
    images = {name: load_image(path) for name, path in SHOTS.items()}
    write_audio(OUT_AUDIO)

    proc = subprocess.Popen(
        [
            "ffmpeg",
            "-y",
            "-loglevel",
            "error",
            "-f",
            "rawvideo",
            "-pix_fmt",
            "rgb24",
            "-s",
            f"{WIDTH}x{HEIGHT}",
            "-r",
            str(FPS),
            "-i",
            "-",
            "-i",
            str(OUT_AUDIO),
            "-c:v",
            "libx264",
            "-preset",
            "medium",
            "-crf",
            "17",
            "-pix_fmt",
            "yuv420p",
            "-c:a",
            "aac",
            "-b:a",
            "192k",
            "-movflags",
            "+faststart",
            "-shortest",
            str(OUT_MP4),
        ],
        stdin=subprocess.PIPE,
    )
    assert proc.stdin is not None
    for frame_index in range(DURATION * FPS):
        proc.stdin.write(render_frame(images, frame_index).tobytes())
    proc.stdin.close()
    code = proc.wait()
    if code != 0:
        raise SystemExit(f"ffmpeg failed with exit code {code}")

    run_checked(
        [
            "ffmpeg",
            "-y",
            "-loglevel",
            "error",
            "-ss",
            "33",
            "-i",
            str(OUT_MP4),
            "-frames:v",
            "1",
            "-vf",
            "scale=1280:720:flags=lanczos",
            str(OUT_THUMB),
        ]
    )
    probe = run_checked(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_entries",
            "stream=index,codec_type,codec_name,width,height,channels,r_frame_rate",
            "-show_entries",
            "format=duration,size",
            "-of",
            "default=noprint_wrappers=1",
            str(OUT_MP4),
        ]
    )
    print(probe.strip())
    print(f"rendered {OUT_MP4}")
    print(f"rendered {OUT_THUMB}")
    print(f"rendered audio {OUT_AUDIO}")


if __name__ == "__main__":
    render_video()

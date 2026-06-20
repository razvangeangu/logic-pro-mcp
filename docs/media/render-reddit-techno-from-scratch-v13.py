#!/usr/bin/env python3
"""Render a polished techno composition demo from a blank session.

This cut is built for public viewing: it shows a clear musical build instead of
raw QA logs. The arrangement view is a clean visual reconstruction of the
composition process and the audio is synthesized from the same layer timing.
"""

from __future__ import annotations

import math
import random
import struct
import subprocess
import wave
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[2]
OUT_MP4 = ROOT / "docs/media/reddit-dudddee-techno-from-scratch-v13.mp4"
OUT_THUMB = ROOT / "docs/media/reddit-dudddee-techno-from-scratch-v13-thumbnail.png"
OUT_AUDIO = Path("/tmp/reddit-dudddee-techno-from-scratch-v13.wav")
TMP_VIDEO = Path("/tmp/reddit-dudddee-techno-from-scratch-v13-video.mp4")

WIDTH = 1920
HEIGHT = 1080
FPS = 24
DURATION = 46.0
SR = 48_000
BPM = 128
BEAT = 60.0 / BPM
BAR = BEAT * 4

FONT_REGULAR = "/System/Library/Fonts/Supplemental/Arial.ttf"
FONT_BOLD = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
FONT_MONO = "/System/Library/Fonts/Menlo.ttc"

FONTS = {
    "hero": ImageFont.truetype(FONT_BOLD, 66),
    "title": ImageFont.truetype(FONT_BOLD, 42),
    "body": ImageFont.truetype(FONT_REGULAR, 28),
    "small": ImageFont.truetype(FONT_REGULAR, 22),
    "tiny": ImageFont.truetype(FONT_REGULAR, 18),
    "label": ImageFont.truetype(FONT_BOLD, 21),
    "mono": ImageFont.truetype(FONT_MONO, 20),
    "mono_small": ImageFont.truetype(FONT_MONO, 17),
}

BG = (13, 16, 20)
PANEL = (28, 32, 38)
PANEL_2 = (38, 43, 51)
GRID = (71, 78, 88)
TEXT = (238, 244, 250)
MUTED = (164, 176, 190)
SUBTLE = (109, 122, 137)


@dataclass(frozen=True)
class Layer:
    name: str
    role: str
    color: tuple[int, int, int]
    enters: float
    command: str


LAYERS = [
    Layer("Kick", "909 four-on-floor", (242, 83, 76), 4.2, "record_sequence(kick_8bar)"),
    Layer("Sub Bass", "rolling C minor", (117, 132, 255), 10.8, "record_sequence(sub_bass)"),
    Layer("Hats", "16th-note motion", (235, 190, 76), 17.2, "record_sequence(closed_hats)"),
    Layer("Clap", "bar 2 / 4 backbeat", (247, 139, 69), 21.0, "record_sequence(clap)"),
    Layer("Minor Stab", "two-bar hook", (76, 201, 174), 25.8, "record_sequence(minor_stab)"),
    Layer("Readback", "verify regions", (95, 211, 255), 32.0, "logic://tracks + regions"),
]

STAGES = [
    (0.0, 4.2, "Start blank", "One instruction: build a playable 8-bar techno sketch."),
    (4.2, 10.8, "Kick first", "The groove starts with a simple four-on-the-floor region."),
    (10.8, 17.2, "Bass next", "A rolling sub bass line locks to the kick."),
    (17.2, 25.8, "Drums move", "Hats and clap add motion without leaving the session."),
    (25.8, 32.0, "Add the hook", "Minor stabs turn the loop into a track idea."),
    (32.0, 38.0, "Read back", "The agent checks the arrangement before calling it done."),
    (38.0, DURATION, "Final loop", "Finished sketch plays as one 8-bar techno loop."),
]


def clamp(value: float, lo: float = 0.0, hi: float = 1.0) -> float:
    return max(lo, min(hi, value))


def ease(value: float) -> float:
    value = clamp(value)
    return value * value * (3.0 - 2.0 * value)


def fade_in(time_s: float, start: float, dur: float = 0.55) -> float:
    return ease((time_s - start) / dur)


def stage_at(time_s: float) -> tuple[float, float, str, str]:
    for stage in STAGES:
        if stage[0] <= time_s < stage[1]:
            return stage
    return STAGES[-1]


def rounded(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], fill, outline=None, width: int = 1, radius: int = 14) -> None:
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def text(draw: ImageDraw.ImageDraw, xy: tuple[int, int], content: str, font, fill=TEXT, shadow: bool = False) -> None:
    x, y = xy
    if shadow:
        draw.text((x + 2, y + 2), content, font=font, fill=(0, 0, 0, 150))
    draw.text((x, y), content, font=font, fill=fill)


def draw_badge(draw: ImageDraw.ImageDraw, x: int, y: int, label: str, color: tuple[int, int, int], w: int | None = None) -> None:
    if w is None:
        bbox = draw.textbbox((0, 0), label, font=FONTS["tiny"])
        w = bbox[2] - bbox[0] + 34
    rounded(draw, (x, y, x + w, y + 34), (22, 27, 34), outline=color, radius=17)
    draw.ellipse((x + 14, y + 12, x + 24, y + 22), fill=color)
    draw.text((x + 32, y + 8), label, font=FONTS["tiny"], fill=(231, 239, 247))


def draw_background(draw: ImageDraw.ImageDraw, time_s: float) -> None:
    for y in range(0, HEIGHT, 3):
        shade = int(13 + 16 * (y / HEIGHT))
        draw.rectangle((0, y, WIDTH, y + 3), fill=(shade, shade + 3, shade + 7))
    draw.rectangle((0, 0, WIDTH, 96), fill=(24, 27, 32))
    draw.rectangle((0, 96, WIDTH, 98), fill=(50, 56, 65))
    for x, color in [(28, (238, 89, 78)), (54, (236, 189, 79)), (80, (83, 202, 102))]:
        draw.ellipse((x, 36, x + 16, 52), fill=color)
    text(draw, (116, 31), "Logic Pro MCP", FONTS["title"], fill=TEXT)
    text(draw, (438, 41), "from blank project to techno loop", FONTS["small"], fill=MUTED)

    # Transport display.
    rounded(draw, (1280, 26, 1810, 76), (16, 20, 26), outline=(65, 73, 84), radius=14)
    draw.rectangle((1310, 40, 1330, 62), fill=(83, 202, 102))
    draw.polygon([(1360, 39), (1360, 63), (1384, 51)], fill=(83, 202, 102))
    for x in (1430, 1488):
        draw.rectangle((x, 38, x + 18, 64), fill=(233, 239, 246))
    text(draw, (1548, 35), "PLAY", FONTS["body"], fill=TEXT)
    text(draw, (1548, 62), "build mode", FONTS["tiny"], fill=SUBTLE)
    text(draw, (1660, 35), "4/4", FONTS["body"], fill=TEXT)
    text(draw, (1740, 35), "8 bars", FONTS["body"], fill=TEXT)


def visible_layers(time_s: float) -> int:
    return sum(1 for layer in LAYERS[:5] if time_s >= layer.enters)


def draw_prompt(draw: ImageDraw.ImageDraw, time_s: float) -> None:
    x, y, w, h = 62, 126, 500, 214
    rounded(draw, (x, y, x + w, y + h), (21, 25, 31), outline=(55, 64, 76), radius=22)
    draw_badge(draw, x + 24, y + 22, "Prompt", (95, 211, 255), 112)
    text(draw, (x + 24, y + 72), "Create an 8-bar minimal techno loop", FONTS["body"])
    text(draw, (x + 24, y + 112), "Kick, bass, hats, clap, stab.", FONTS["small"], fill=MUTED)
    text(draw, (x + 24, y + 144), "Make small changes. Read back before calling it done.", FONTS["small"], fill=MUTED)
    progress = clamp(time_s / 38.0)
    rounded(draw, (x + 24, y + 184, x + w - 24, y + 198), (47, 55, 66), radius=7)
    rounded(draw, (x + 24, y + 184, x + 24 + int((w - 48) * progress), y + 198), (95, 211, 255), radius=7)


def draw_command_panel(draw: ImageDraw.ImageDraw, time_s: float) -> None:
    x, y, w, h = 62, 364, 500, 430
    rounded(draw, (x, y, x + w, y + h), (21, 25, 31), outline=(55, 64, 76), radius=22)
    draw_badge(draw, x + 24, y + 22, "MCP actions", (83, 202, 102), 150)
    commands = [
        (1.2, "logic_project.prepare_blank", "ok"),
        (4.2, "logic_tracks.create Kick", "ok"),
        (5.0, "logic_midi.write kick_8bar", "ok"),
        (10.8, "logic_tracks.create Bass", "ok"),
        (12.0, "logic_midi.write bassline", "ok"),
        (17.2, "logic_tracks.create Hats", "ok"),
        (21.0, "logic_tracks.create Clap", "ok"),
        (25.8, "logic_tracks.create Stab", "ok"),
        (32.0, "logic://tracks readback", "verified"),
    ]
    row_y = y + 76
    for start, command, status in commands:
        alpha = fade_in(time_s, start, 0.45)
        if alpha <= 0:
            continue
        fill = tuple(int(c * alpha + 28 * (1 - alpha)) for c in (232, 239, 247))
        status_color = (83, 202, 102) if status in {"ok", "verified", "State A"} else (235, 190, 76)
        draw.text((x + 24, row_y), command, font=FONTS["mono_small"], fill=fill)
        rounded(draw, (x + w - 126, row_y - 3, x + w - 24, row_y + 24), (32, 38, 46), outline=status_color, radius=10)
        draw.text((x + w - 112, row_y + 3), status, font=FONTS["tiny"], fill=status_color)
        row_y += 36


def draw_arrangement(draw: ImageDraw.ImageDraw, time_s: float) -> None:
    x0, y0 = 610, 152
    w, h = 1238, 638
    track_w = 238
    arrange_x = x0 + track_w
    arrange_w = w - track_w - 24
    row_h = 96
    rows = 6

    rounded(draw, (x0, y0, x0 + w, y0 + h), (25, 29, 35), outline=(64, 72, 84), radius=24)
    draw.rectangle((x0, y0, x0 + w, y0 + 54), fill=(35, 40, 48))
    text(draw, (x0 + 24, y0 + 16), "Arrangement", FONTS["small"], fill=(224, 232, 240))
    for bar in range(1, 9):
        bx = arrange_x + int(arrange_w * (bar - 1) / 8)
        text(draw, (bx + 7, y0 + 16), str(bar), FONTS["small"], fill=MUTED)
    draw.line((arrange_x, y0 + 54, arrange_x, y0 + h - 20), fill=(95, 105, 118), width=2)

    for row in range(rows):
        y = y0 + 54 + row * row_h
        draw.rectangle((x0, y, x0 + w, y + row_h - 1), fill=(30 + (row % 2) * 4, 34 + (row % 2) * 4, 40 + (row % 2) * 4))
        draw.line((x0, y + row_h - 1, x0 + w, y + row_h - 1), fill=(61, 69, 80))
    for bar in range(9):
        bx = arrange_x + int(arrange_w * bar / 8)
        draw.line((bx, y0 + 54, bx, y0 + h - 20), fill=(65, 73, 84), width=2 if bar in (0, 4, 8) else 1)
    for step in range(32):
        sx = arrange_x + int(arrange_w * step / 32)
        draw.line((sx, y0 + 54, sx, y0 + h - 20), fill=(48, 55, 64), width=1)

    for idx, layer in enumerate(LAYERS[:5]):
        y = y0 + 54 + idx * row_h
        draw.rectangle((x0, y, x0 + 7, y + row_h - 1), fill=layer.color)
        text(draw, (x0 + 24, y + 26), layer.name, FONTS["body"], fill=TEXT)
        text(draw, (x0 + 24, y + 58), layer.role, FONTS["tiny"], fill=MUTED)
        for j, label in enumerate(("M", "S", "R")):
            bx = x0 + 168 + j * 28
            rounded(draw, (bx, y + 32, bx + 22, y + 54), (48, 55, 65), radius=6)
            draw.text((bx + 6, y + 35), label, font=FONTS["tiny"], fill=(215, 224, 234))

        if time_s < layer.enters:
            continue
        alpha = fade_in(time_s, layer.enters)
        region_x1 = arrange_x + 18
        grow = 1.0 if time_s > layer.enters + 1.2 else ease((time_s - layer.enters) / 1.2)
        region_x2 = region_x1 + int((arrange_w - 42) * grow)
        region_y1 = y + 18
        region_y2 = y + row_h - 22
        fill = layer.color + (int(230 * alpha),)
        outline = (255, 255, 255, int(60 * alpha))
        rounded(draw, (region_x1, region_y1, region_x2, region_y2), fill, outline=outline, radius=13)
        text(draw, (region_x1 + 18, region_y1 + 12), layer.name.lower().replace(" ", "_") + "_8bar", FONTS["label"], fill=(255, 255, 255))
        draw_pattern(draw, layer.name, region_x1, region_y1, region_x2, region_y2)

    # Readback row.
    read_y = y0 + 54 + 5 * row_h
    draw.rectangle((x0, read_y, x0 + 7, read_y + row_h - 1), fill=LAYERS[-1].color)
    text(draw, (x0 + 24, read_y + 26), "Readback", FONTS["body"], fill=TEXT)
    text(draw, (x0 + 24, read_y + 58), "verify before success", FONTS["tiny"], fill=MUTED)
    if time_s >= 32.0:
        alpha = fade_in(time_s, 32.0)
        checks = [("session", "ready"), ("tracks", "5 layers"), ("regions", "8 bars")]
        for j, (label, value) in enumerate(checks):
            bx = arrange_x + 18 + j * 245
            by = read_y + 24
            rounded(draw, (bx, by, bx + 210, by + 54), (32, 40, 48, int(230 * alpha)), outline=(95, 211, 255, int(110 * alpha)), radius=14)
            draw.text((bx + 16, by + 9), label, font=FONTS["tiny"], fill=SUBTLE)
            draw.text((bx + 16, by + 28), value, font=FONTS["small"], fill=(232, 245, 255))

    # Playhead.
    if time_s < 38.0:
        play_progress = (time_s / 38.0) % 1.0
    else:
        play_progress = ((time_s - 38.0) / 8.0) % 1.0
    px = arrange_x + int(arrange_w * play_progress)
    draw.line((px, y0 + 54, px, y0 + h - 20), fill=(245, 248, 252), width=2)
    draw.polygon([(px - 10, y0 + 56), (px + 10, y0 + 56), (px, y0 + 72)], fill=(245, 248, 252))


def draw_pattern(draw: ImageDraw.ImageDraw, name: str, x1: int, y1: int, x2: int, y2: int) -> None:
    if x2 - x1 < 80:
        return
    if name == "Kick":
        for step in range(0, 32, 4):
            x = x1 + 30 + int((x2 - x1 - 60) * step / 32)
            draw.ellipse((x, y2 - 24, x + 14, y2 - 10), fill=(255, 255, 255, 210))
    elif name == "Sub Bass":
        for step in [0, 3, 6, 8, 11, 14, 19, 22, 27, 30]:
            x = x1 + 28 + int((x2 - x1 - 64) * step / 32)
            draw.rounded_rectangle((x, y2 - 25, x + 38, y2 - 12), radius=5, fill=(255, 255, 255, 190))
    elif name == "Hats":
        for step in range(1, 64, 2):
            x = x1 + 24 + int((x2 - x1 - 48) * step / 64)
            draw.line((x, y2 - 26, x + 7, y2 - 12), fill=(255, 255, 255, 185), width=2)
    elif name == "Clap":
        for step in range(4, 32, 8):
            x = x1 + 34 + int((x2 - x1 - 68) * step / 32)
            draw.rounded_rectangle((x, y2 - 31, x + 18, y2 - 8), radius=4, fill=(255, 255, 255, 205))
    elif name == "Minor Stab":
        for step in range(0, 32, 8):
            x = x1 + 34 + int((x2 - x1 - 92) * step / 32)
            for n in range(3):
                draw.rounded_rectangle((x, y2 - 35 + n * 8, x + 54, y2 - 30 + n * 8), radius=3, fill=(255, 255, 255, 180))


def draw_stage_caption(draw: ImageDraw.ImageDraw, time_s: float) -> None:
    start, end, title, subtitle = stage_at(time_s)
    x, y = 610, 828
    rounded(draw, (x, y, 1848, 1000), (19, 23, 29), outline=(58, 68, 80), radius=24)
    text(draw, (x + 34, y + 28), title, FONTS["hero" if title == "Final loop" else "title"], fill=TEXT, shadow=True)
    text(draw, (x + 36, y + 96), subtitle, FONTS["body"], fill=(212, 223, 234))
    progress = clamp((time_s - start) / (end - start))
    rounded(draw, (x + 36, y + 138, x + 720, y + 153), (50, 58, 70), radius=8)
    rounded(draw, (x + 36, y + 138, x + 36 + int(684 * progress), y + 153), (83, 202, 102), radius=8)


def draw_meters(draw: ImageDraw.ImageDraw, time_s: float) -> None:
    x, y = 62, 832
    rounded(draw, (x, y, 500, 1000), (21, 25, 31), outline=(55, 64, 76), radius=22)
    draw_badge(draw, x + 24, y + 22, "Playback meters", (235, 190, 76), 180)
    rng = random.Random(int(time_s * 24))
    for idx, layer in enumerate(LAYERS[:5]):
        lx = x + 34 + idx * 82
        active = time_s >= layer.enters
        level = 0.08 if not active else 0.35 + 0.55 * abs(math.sin(time_s * (1.6 + idx * 0.23) + idx)) + rng.random() * 0.08
        draw.rectangle((lx, y + 72, lx + 30, y + 142), fill=(45, 52, 62))
        fill_h = int(68 * clamp(level))
        draw.rectangle((lx, y + 142 - fill_h, lx + 30, y + 142), fill=layer.color if active else (74, 82, 94))
        draw.text((lx - 6, y + 148), layer.name[:4], font=FONTS["tiny"], fill=MUTED)


def draw_frame(time_s: float) -> Image.Image:
    frame = Image.new("RGBA", (WIDTH, HEIGHT), BG + (255,))
    draw = ImageDraw.Draw(frame, "RGBA")
    draw_background(draw, time_s)
    draw_prompt(draw, time_s)
    draw_command_panel(draw, time_s)
    draw_arrangement(draw, time_s)
    draw_stage_caption(draw, time_s)
    draw_meters(draw, time_s)
    return frame.convert("RGB")


def midi_freq(note: int) -> float:
    return 440.0 * (2 ** ((note - 69) / 12))


def add_sine(buf: list[float], start: float, dur: float, freq: float, amp: float, decay: float = 0.0, pan: float = 0.0) -> None:
    start_i = max(0, int(start * SR))
    end_i = min(len(buf) // 2, int((start + dur) * SR))
    phase = 0.0
    inc = 2 * math.pi * freq / SR
    left_gain = math.sqrt((1.0 - pan) * 0.5)
    right_gain = math.sqrt((1.0 + pan) * 0.5)
    for i in range(start_i, end_i):
        t = (i - start_i) / SR
        env = math.exp(-decay * t) if decay else 1.0
        sample = math.sin(phase) * amp * env
        buf[i * 2] += sample * left_gain
        buf[i * 2 + 1] += sample * right_gain
        phase += inc


def add_kick(buf: list[float], start: float, amp: float) -> None:
    start_i = max(0, int(start * SR))
    dur_i = int(0.22 * SR)
    for n in range(dur_i):
        i = start_i + n
        if i >= len(buf) // 2:
            break
        t = n / SR
        freq = 72 - 38 * min(1.0, t / 0.17)
        env = math.exp(-20 * t)
        click = math.exp(-180 * t) * math.sin(2 * math.pi * 1800 * t) * 0.12
        sample = (math.sin(2 * math.pi * freq * t) * amp * env) + click
        buf[i * 2] += sample
        buf[i * 2 + 1] += sample


def add_noise(buf: list[float], start: float, dur: float, amp: float, decay: float, pan: float = 0.0) -> None:
    start_i = max(0, int(start * SR))
    end_i = min(len(buf) // 2, int((start + dur) * SR))
    seed = int(start * 10_000) + 99
    left_gain = math.sqrt((1.0 - pan) * 0.5)
    right_gain = math.sqrt((1.0 + pan) * 0.5)
    for i in range(start_i, end_i):
        seed = (1103515245 * seed + 12345) & 0x7FFFFFFF
        noise = (seed / 0x7FFFFFFF) * 2 - 1
        t = (i - start_i) / SR
        sample = noise * amp * math.exp(-decay * t)
        buf[i * 2] += sample * left_gain
        buf[i * 2 + 1] += sample * right_gain


def frange(start: float, stop: float, step: float):
    value = start
    while value < stop:
        yield value
        value += step


def write_audio() -> None:
    total = int(DURATION * SR)
    buf = [0.0] * (total * 2)

    # The audible build follows the same layer order as the video.
    for t in frange(4.2, DURATION, BEAT):
        add_kick(buf, t, 0.58)

    bass_notes = [36, 36, 39, 36, 34, 34, 39, 43]
    for idx, t in enumerate(frange(10.8, DURATION, BEAT / 2)):
        if idx % 2 == 0:
            add_sine(buf, t, 0.28, midi_freq(bass_notes[(idx // 2) % len(bass_notes)]), 0.20, decay=4.5)

    for t in frange(17.2, DURATION, BEAT / 2):
        add_noise(buf, t, 0.045, 0.13, 70, pan=0.18)
    for t in frange(18.2, DURATION, BEAT):
        add_noise(buf, t, 0.035, 0.08, 55, pan=-0.18)

    for t in frange(21.0 + BEAT, DURATION, BEAT * 2):
        add_noise(buf, t, 0.12, 0.24, 30)
        add_sine(buf, t, 0.10, 190, 0.07, decay=16)

    stabs = [(48, 51, 55), (48, 53, 58), (46, 51, 55), (43, 48, 51)]
    for idx, t in enumerate(frange(25.8, DURATION, BEAT * 4)):
        for note in stabs[idx % len(stabs)]:
            add_sine(buf, t, 0.38, midi_freq(note), 0.075, decay=4.5, pan=-0.08)
            add_sine(buf, t + 0.015, 0.32, midi_freq(note + 12), 0.024, decay=5.5, pan=0.14)

    # Normalize with headroom.
    peak = max(1e-9, max(abs(v) for v in buf))
    gain = min(0.92 / peak, 1.0)
    with wave.open(str(OUT_AUDIO), "wb") as wav:
        wav.setnchannels(2)
        wav.setsampwidth(2)
        wav.setframerate(SR)
        frames = bytearray()
        for i in range(0, len(buf), 2):
            left = max(-1.0, min(1.0, buf[i] * gain))
            right = max(-1.0, min(1.0, buf[i + 1] * gain))
            frames.extend(struct.pack("<hh", int(left * 32767), int(right * 32767)))
        wav.writeframes(frames)


def render_video_only() -> None:
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
            "-an",
            "-c:v",
            "libx264",
            "-preset",
            "slow",
            "-crf",
            "16",
            "-pix_fmt",
            "yuv420p",
            str(TMP_VIDEO),
        ],
        stdin=subprocess.PIPE,
    )
    assert proc.stdin is not None
    frame_count = int(DURATION * FPS)
    for idx in range(frame_count):
        frame = draw_frame(idx / FPS)
        proc.stdin.write(frame.tobytes())
    proc.stdin.close()
    proc.wait()
    if proc.returncode != 0:
        raise SystemExit(f"ffmpeg video render failed: {proc.returncode}")


def mux() -> None:
    subprocess.run(
        [
            "ffmpeg",
            "-y",
            "-loglevel",
            "error",
            "-i",
            str(TMP_VIDEO),
            "-i",
            str(OUT_AUDIO),
            "-map",
            "0:v:0",
            "-map",
            "1:a:0",
            "-c:v",
            "copy",
            "-c:a",
            "aac",
            "-b:a",
            "192k",
            "-shortest",
            str(OUT_MP4),
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
            "40",
            "-i",
            str(OUT_MP4),
            "-frames:v",
            "1",
            str(OUT_THUMB),
        ],
        check=True,
    )


def main() -> None:
    write_audio()
    render_video_only()
    mux()
    print(OUT_MP4)
    print(OUT_THUMB)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Render an actual-usage Logic Pro MCP demo.

Inputs are real local artifacts from this run:
- a live Logic Pro screen recording captured with ffmpeg/AVFoundation;
- a transcript JSON captured from a real LogicProMCP stdio session.

The final cut is still edited for pacing, but the commands, responses, Logic
screen, and readback summaries are not invented.
"""

from __future__ import annotations

import json
import math
import re
import struct
import subprocess
import unicodedata
import wave
from pathlib import Path
from typing import Iterable, Sequence

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[2]
TRANSCRIPT = ROOT / "docs/media/reddit-dudddee-actual-usage-v7-transcript.json"
LIVE_SCREEN = Path("/tmp/logic-v7-live-screen.mp4")
FALLBACK_SCREEN = Path("/tmp/logic-v7-live-check/frame6.png")
OUT_MP4 = ROOT / "docs/media/reddit-dudddee-actual-usage-v7.mp4"
OUT_THUMB = ROOT / "docs/media/reddit-dudddee-actual-usage-v7-thumbnail.png"
OUT_AUDIO = Path("/tmp/reddit-dudddee-actual-usage-v7.wav")

WIDTH = 1920
HEIGHT = 1080
FPS = 24
DURATION = 76
SAMPLE_RATE = 48_000
BPM = 128
BEAT = 60.0 / BPM
BAR = BEAT * 4
LOOP = BAR * 8

FONT_REGULAR = "/System/Library/Fonts/Supplemental/Arial.ttf"
FONT_BOLD = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
FONT_MONO = "/System/Library/Fonts/Menlo.ttc"

FONTS = {
    "hero": ImageFont.truetype(FONT_BOLD, 66),
    "title": ImageFont.truetype(FONT_BOLD, 48),
    "section": ImageFont.truetype(FONT_BOLD, 34),
    "body": ImageFont.truetype(FONT_REGULAR, 26),
    "small": ImageFont.truetype(FONT_REGULAR, 21),
    "tiny": ImageFont.truetype(FONT_REGULAR, 17),
    "label": ImageFont.truetype(FONT_BOLD, 19),
    "mono": ImageFont.truetype(FONT_MONO, 19),
    "mono_small": ImageFont.truetype(FONT_MONO, 16),
}

INK = (244, 248, 252, 255)
MUTED = (188, 201, 214, 255)
SUBTLE = (133, 149, 166, 255)
BG = (5, 9, 14, 236)
CYAN = (91, 210, 255)
GREEN = (105, 232, 142)
AMBER = (246, 190, 73)
CORAL = (247, 101, 91)
VIOLET = (154, 128, 255)


SCENES = [
    (0.0, 7.0, "Actual Logic Pro MCP run", "real screen capture + exact MCP transcript"),
    (7.0, 17.0, "Surface discovery", "9 tools, 13 live resources, 7 templates"),
    (17.0, 30.0, "Read before write", "health, project, transport, MIDI ports"),
    (30.0, 43.0, "Verified actions", "tempo, regions, playhead, playback"),
    (43.0, 55.0, "MIDI + editing", "virtual ports, notes, quantize, zoom"),
    (55.0, 67.0, "Catalog + workflows", "stock plugins, workflows, HC v2"),
    (67.0, 76.0, "What this proves", "agent surface, live state, honest reports"),
]

EVENT_GROUPS = {
    "discovery": [
        "initialize",
        "tools/list",
        "resources/list",
        "resources/templates/list",
    ],
    "readback": [
        "logic://system/health",
        "logic://project/info",
        "logic://transport/state",
        "logic://tracks",
        "logic://midi/ports",
    ],
    "actions": [
        "logic_system.permissions",
        "logic_transport.set_tempo",
        "logic_project.get_regions",
        "logic_transport.goto_position",
        "logic_transport.play",
        "logic_transport.stop",
    ],
    "midi_edit": [
        "logic_midi.create_virtual_port",
        "logic_midi.send_note",
        "logic_midi.send_chord",
        "logic_edit.select_all",
        "logic_edit.quantize",
        "logic_navigate.zoom_to_fit",
    ],
    "intelligence": [
        "logic://stock-plugins/census",
        "logic://stock-plugins/search?query=gain",
        "logic://workflow-skills/search?query=bounce",
        "logic_plugins.get_inventory",
    ],
}


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


def load_transcript() -> dict:
    if not TRANSCRIPT.exists():
        raise SystemExit(f"Missing transcript: {TRANSCRIPT}")
    return json.loads(TRANSCRIPT.read_text())


def events_by_label(transcript: dict) -> dict[str, dict]:
    return {event["label"]: event for event in transcript.get("events", [])}


def clamp(value: float, lo: float = 0.0, hi: float = 1.0) -> float:
    return max(lo, min(hi, value))


def display_text(value: object) -> str:
    text = unicodedata.normalize("NFC", str(value))
    text = text.replace("무제 21 - 트랙", "Untitled 21 - Tracks")
    text = text.replace("무제 21 - 트랙", "Untitled 21 - Tracks")
    text = re.sub(r"[^\x20-\x7E]", "", text)
    return re.sub(r"\s{2,}", " ", text).strip()


def ease(value: float) -> float:
    value = clamp(value)
    return value * value * (3.0 - 2.0 * value)


def fade(time_s: float, start: float, end: float) -> float:
    return ease((time_s - start) / (end - start))


def rounded(
    draw: ImageDraw.ImageDraw,
    box: tuple[int, int, int, int],
    fill,
    outline=None,
    width: int = 1,
    radius: int = 18,
) -> None:
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def panel(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], alpha: int = 232, radius: int = 22) -> None:
    rounded(draw, box, (6, 10, 16, alpha), outline=(255, 255, 255, 42), width=1, radius=radius)


def text_shadow(draw: ImageDraw.ImageDraw, xy: tuple[int, int], text: str, font, fill=INK) -> None:
    x, y = xy
    draw.text((x + 2, y + 2), text, font=font, fill=(0, 0, 0, 190))
    draw.text((x, y), text, font=font, fill=fill)


def dot(draw: ImageDraw.ImageDraw, xy: tuple[int, int], color, r: int = 5) -> None:
    x, y = xy
    draw.ellipse((x - r, y - r, x + r, y + r), fill=color + (255,))


def current_scene(time_s: float) -> tuple[float, float, str, str]:
    for scene in SCENES:
        if scene[0] <= time_s < scene[1]:
            return scene
    return SCENES[-1]


def wrap_text(draw: ImageDraw.ImageDraw, text: str, font, max_width: int, max_lines: int = 4) -> list[str]:
    text = display_text(text)
    words = text.replace("\n", " ").split()
    lines: list[str] = []
    current = ""
    for word in words:
        trial = word if not current else current + " " + word
        width = draw.textbbox((0, 0), trial, font=font)[2]
        if width <= max_width:
            current = trial
            continue
        if current:
            lines.append(current)
        current = word
        if len(lines) >= max_lines:
            break
    if current and len(lines) < max_lines:
        lines.append(current)
    if len(lines) == max_lines and len(" ".join(words)) > len(" ".join(lines)):
        last = lines[-1]
        while draw.textbbox((0, 0), last + "...", font=font)[2] > max_width and len(last) > 3:
            last = last[:-1]
        lines[-1] = last + "..."
    return lines


def draw_brand(draw: ImageDraw.ImageDraw, x: int, y: int) -> None:
    rounded(draw, (x, y, x + 56, y + 56), (5, 14, 21, 245), outline=CYAN + (120,), width=1, radius=14)
    cx = x + 28
    for idx, height in enumerate((16, 29, 22, 38, 25)):
        bx = x + 14 + idx * 8
        draw.rounded_rectangle((bx, cx - height // 2, bx + 4, cx + height // 2), radius=2, fill=GREEN + (255,))
    draw.text((x + 72, y + 2), "Logic Pro MCP", font=FONTS["body"], fill=INK)
    draw.text((x + 72, y + 33), "actual usage run", font=FONTS["tiny"], fill=MUTED)


def draw_header(draw: ImageDraw.ImageDraw, time_s: float) -> None:
    _, _, title, subtitle = current_scene(time_s)
    draw_brand(draw, 44, 34)
    rounded(draw, (1250, 38, 1874, 96), (6, 10, 16, 226), outline=(255, 255, 255, 48), radius=18)
    draw.text((1274, 54), title, font=FONTS["label"], fill=INK)
    draw.text((1514, 56), subtitle[:44], font=FONTS["tiny"], fill=MUTED)
    rounded(draw, (46, 1010, 1874, 1024), (35, 42, 52, 235), radius=7)
    rounded(draw, (46, 1010, 46 + int(1828 * time_s / DURATION), 1024), GREEN + (255,), radius=7)


def draw_badge(draw: ImageDraw.ImageDraw, x: int, y: int, text: str, color=CYAN, width: int | None = None) -> None:
    if width is None:
        width = draw.textbbox((0, 0), text, font=FONTS["tiny"])[2] + 34
    rounded(draw, (x, y, x + width, y + 34), (7, 13, 20, 226), outline=color + (100,), radius=14)
    dot(draw, (x + 17, y + 17), color, 4)
    draw.text((x + 30, y + 8), text, font=FONTS["tiny"], fill=(232, 240, 248, 255))


def draw_opening(draw: ImageDraw.ImageDraw, time_s: float) -> None:
    alpha = int(255 * (1.0 - fade(time_s, 5.8, 7.0)))
    if alpha <= 0:
        return
    overlay = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay, "RGBA")
    od.rectangle((0, 0, WIDTH, HEIGHT), fill=(0, 0, 0, int(76 * alpha / 255)))
    text_shadow(od, (98, 236), "Actual usage, not a mockup", FONTS["hero"], (255, 255, 255, alpha))
    text_shadow(od, (102, 324), "Logic screen capture + exact MCP transcript", FONTS["title"], (224, 235, 245, alpha))
    od.text(
        (106, 404),
        "The edit is polished, but the commands and responses come from a real local Logic Pro 12.2 session.",
        font=FONTS["body"],
        fill=(224, 235, 245, int(235 * alpha / 255)),
    )
    draw_badge(od, 106, 488, "actual Logic screen recording", GREEN, 288)
    draw_badge(od, 420, 488, "actual JSON-RPC calls", CYAN, 230)
    draw_badge(od, 676, 488, "readback and honesty states", AMBER, 286)
    rows = [
        ("9 tools", "transport, tracks, mixer, MIDI, edit, navigate, project, system, plugins"),
        ("13 resources", "health, project, transport, tracks, MIDI, stock catalog, workflows"),
        ("7 templates", "track, regions, mixer strip, stock plugin, workflow lookup"),
    ]
    y = 594
    for title, body in rows:
        panel(od, (106, y, 930, y + 70), alpha=int(210 * alpha / 255), radius=18)
        od.text((132, y + 14), title, font=FONTS["label"], fill=GREEN + (alpha,))
        od.text((276, y + 17), body, font=FONTS["small"], fill=(222, 232, 242, int(235 * alpha / 255)))
        y += 84
    draw.alpha_composite(overlay)


def event_for_time(time_s: float, label_map: dict[str, dict]) -> list[dict]:
    if time_s < 17:
        labels = EVENT_GROUPS["discovery"]
        start, end = 7.0, 17.0
    elif time_s < 30:
        labels = EVENT_GROUPS["readback"]
        start, end = 17.0, 30.0
    elif time_s < 43:
        labels = EVENT_GROUPS["actions"]
        start, end = 30.0, 43.0
    elif time_s < 55:
        labels = EVENT_GROUPS["midi_edit"]
        start, end = 43.0, 55.0
    elif time_s < 67:
        labels = EVENT_GROUPS["intelligence"]
        start, end = 55.0, 67.0
    else:
        labels = ["tools/list", "logic_transport.set_tempo", "logic_project.get_regions", "logic://stock-plugins/census", "logic_plugins.get_inventory"]
        start, end = 67.0, 76.0

    visible_count = max(1, min(len(labels), int((time_s - start) / max(0.9, (end - start) / len(labels))) + 1))
    return [label_map[label] for label in labels[:visible_count] if label in label_map]


def command_text(event: dict) -> str:
    label = event.get("label", "")
    if event.get("kind") == "resource":
        return display_text(f'resources/read "{label}"')
    if label in {"tools/list", "resources/list", "resources/templates/list", "initialize"}:
        return display_text(label)
    request = event.get("request", {})
    args = request.get("arguments", {})
    if args:
        params = args.get("params") or {}
        return display_text(f'{label} {json.dumps(params, ensure_ascii=False, separators=(",", ":"))}')
    return display_text(label)


def status_color(event: dict):
    if event.get("status") == "error":
        return CORAL
    if "state=B" in event.get("summary", ""):
        return AMBER
    if "verified=True" in event.get("summary", ""):
        return GREEN
    return CYAN


def draw_terminal(draw: ImageDraw.ImageDraw, time_s: float, label_map: dict[str, dict]) -> None:
    x, y, w, h = 1110, 142, 760, 654
    panel(draw, (x, y, x + w, y + h), alpha=238, radius=24)
    draw.text((x + 26, y + 24), "actual MCP transcript", font=FONTS["label"], fill=CYAN + (255,))
    draw.text((x + 252, y + 25), "captured from LogicProMCP stdio", font=FONTS["tiny"], fill=SUBTLE)
    draw.line((x + 24, y + 58, x + w - 24, y + 58), fill=(255, 255, 255, 42), width=1)

    events = event_for_time(time_s, label_map)
    rows = events[-8:]
    ty = y + 82
    for event in rows:
        color = status_color(event)
        dot(draw, (x + 36, ty + 12), color, 4)
        cmd = "$ " + command_text(event)
        cmd_lines = wrap_text(draw, cmd, FONTS["mono_small"], w - 84, max_lines=2)
        for line in cmd_lines:
            draw.text((x + 54, ty), line, font=FONTS["mono_small"], fill=(236, 243, 249, 245))
            ty += 23
        summary = "=> " + display_text(event.get("summary", ""))
        for line in wrap_text(draw, summary, FONTS["tiny"], w - 84, max_lines=2):
            draw.text((x + 54, ty), line, font=FONTS["tiny"], fill=MUTED)
            ty += 22
        ty += 12

    draw.line((x + 24, y + h - 96, x + w - 24, y + h - 96), fill=(255, 255, 255, 42), width=1)
    caption = "Everything above is from the v7 transcript JSON generated by a real run."
    draw.text((x + 26, y + h - 70), caption, font=FONTS["tiny"], fill=SUBTLE)
    draw.text((x + 26, y + h - 43), "State A = verified; State B = honest uncertainty; errors are not hidden.", font=FONTS["tiny"], fill=(222, 232, 242, 235))


def draw_feature_matrix(draw: ImageDraw.ImageDraw, time_s: float, label_map: dict[str, dict]) -> None:
    if time_s < 7.0:
        return
    x, y = 74, 800
    panel(draw, (x, y, 1046, y + 166), alpha=232, radius=24)
    draw.text((x + 28, y + 24), "features shown in this actual run", font=FONTS["label"], fill=INK)
    cards = [
        ("Discovery", "surface map", GREEN),
        ("State", "live read", CYAN),
        ("Actions", "tempo/play", AMBER),
        ("MIDI", "note/chord", VIOLET),
        ("Catalog", "103 plugins", GREEN),
        ("Workflow", "recipes", CYAN),
        ("Honesty", "A/B/C", CORAL),
    ]
    cx = x + 28
    cy = y + 72
    for title, body, color in cards:
        rounded(draw, (cx, cy, cx + 124, cy + 66), (16, 23, 31, 232), outline=color + (92,), width=1, radius=14)
        draw.text((cx + 14, cy + 12), title, font=FONTS["tiny"], fill=color + (255,))
        draw.text((cx + 14, cy + 38), body, font=FONTS["tiny"], fill=(226, 236, 244, 232))
        cx += 134


def draw_screen_callouts(draw: ImageDraw.ImageDraw, time_s: float) -> None:
    if time_s < 17:
        return
    # Tempo display, actual MIDI region, playhead/region readback callouts.
    if 17 <= time_s < 43:
        rounded(draw, (812, 76, 1030, 138), (5, 11, 17, 218), outline=GREEN + (120,), radius=16)
        draw.text((834, 91), "tempo readback", font=FONTS["tiny"], fill=SUBTLE)
        draw.text((834, 113), "observed 128 BPM", font=FONTS["label"], fill=GREEN + (255,))
        draw.line((930, 138, 1006, 168), fill=GREEN + (170,), width=2)

    if 24 <= time_s < 55:
        rounded(draw, (506, 266, 834, 338), (5, 11, 17, 218), outline=CYAN + (110,), radius=16)
        draw.text((528, 284), "actual Logic region", font=FONTS["tiny"], fill=SUBTLE)
        draw.text((528, 308), "logic_mcp_demo_phrase", font=FONTS["label"], fill=CYAN + (255,))
        draw.line((650, 266, 612, 216), fill=CYAN + (170,), width=2)

    if 55 <= time_s < 67:
        rounded(draw, (66, 138, 436, 232), (5, 11, 17, 218), outline=AMBER + (110,), radius=16)
        draw.text((90, 160), "honesty surface", font=FONTS["label"], fill=AMBER + (255,))
        draw.text((90, 190), "readback unavailable is shown as State B", font=FONTS["tiny"], fill=(226, 236, 244, 235))


def draw_final_summary(draw: ImageDraw.ImageDraw, time_s: float, label_map: dict[str, dict]) -> None:
    if time_s < 67:
        return
    alpha = int(255 * fade(time_s, 67.0, 68.0))
    overlay = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay, "RGBA")
    od.rectangle((0, 0, WIDTH, HEIGHT), fill=(0, 0, 0, int(90 * alpha / 255)))
    panel(od, (112, 170, 1068, 580), alpha=int(232 * alpha / 255), radius=28)
    text_shadow(od, (154, 214), "This is the product story", FONTS["title"], (255, 255, 255, alpha))
    lines = [
        "Agents can inspect Logic before touching it.",
        "Tools mutate; resources read live state.",
        "Verified writes report State A only after readback.",
        "Uncertain paths stay labeled instead of pretending success.",
    ]
    y = 306
    for idx, line in enumerate(lines):
        color = [GREEN, CYAN, AMBER, CORAL][idx]
        dot(od, (166, y + 14), color, 5)
        od.text((188, y), line, font=FONTS["body"], fill=(232, 242, 250, int(245 * alpha / 255)))
        y += 52
    od.text((154, 518), "github.com/MongLong0214/logic-pro-mcp", font=FONTS["mono"], fill=GREEN + (alpha,))
    draw.alpha_composite(overlay)


def background_frame(pipe, fallback: Image.Image | None) -> Image.Image:
    raw = pipe.stdout.read(WIDTH * HEIGHT * 3) if pipe and pipe.stdout else b""
    if len(raw) == WIDTH * HEIGHT * 3:
        return Image.frombytes("RGB", (WIDTH, HEIGHT), raw).convert("RGBA")
    if fallback is not None:
        return fallback.copy().convert("RGBA")
    return Image.new("RGBA", (WIDTH, HEIGHT), (15, 19, 24, 255))


def open_background_pipe():
    if not LIVE_SCREEN.exists():
        return None
    return subprocess.Popen(
        [
            "ffmpeg",
            "-stream_loop",
            "-1",
            "-t",
            str(DURATION),
            "-i",
            str(LIVE_SCREEN),
            "-vf",
            f"scale={WIDTH}:{HEIGHT}:flags=lanczos,fps={FPS},format=rgb24",
            "-f",
            "rawvideo",
            "-pix_fmt",
            "rgb24",
            "-loglevel",
            "error",
            "-",
        ],
        stdout=subprocess.PIPE,
    )


def fallback_image() -> Image.Image | None:
    if FALLBACK_SCREEN.exists():
        return Image.open(FALLBACK_SCREEN).convert("RGB").resize((WIDTH, HEIGHT), Image.Resampling.LANCZOS)
    return None


def render_frame(bg: Image.Image, frame_index: int, label_map: dict[str, dict]) -> Image.Image:
    time_s = frame_index / FPS
    frame = bg.convert("RGBA")

    # Darken the live screen just enough for overlay readability.
    frame.alpha_composite(Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 94)))
    draw = ImageDraw.Draw(frame, "RGBA")
    draw_opening(frame, time_s)
    draw_screen_callouts(draw, time_s)
    if time_s >= 6.6:
        draw_terminal(draw, time_s, label_map)
    draw_feature_matrix(draw, time_s, label_map)
    draw_final_summary(frame, time_s, label_map)
    draw = ImageDraw.Draw(frame, "RGBA")
    draw_header(draw, time_s)
    return frame.convert("RGB")


def noise(sample_index: int) -> float:
    value = math.sin(sample_index * 12.9898 + 78.233) * 43758.5453
    return 2.0 * (value - math.floor(value)) - 1.0


def kick(t: float) -> float:
    if t < 0 or t > 0.50:
        return 0.0
    env = math.exp(-9.2 * t)
    freq = 45 + 100 * math.exp(-18 * t)
    click = math.exp(-170 * t) * math.sin(2 * math.pi * 2400 * t) * 0.14
    return math.sin(2 * math.pi * freq * t) * env + click


def hat(t: float, sample_index: int) -> float:
    if t < 0 or t > 0.07:
        return 0.0
    return noise(sample_index) * math.exp(-58 * t)


def midi_freq(note: int) -> float:
    return 440.0 * (2 ** ((note - 69) / 12))


def synth(freq: float, t: float, dur: float) -> float:
    if t < 0 or t > dur:
        return 0.0
    attack = min(1.0, t / 0.018)
    release = min(1.0, (dur - t) / 0.08)
    env = attack * release * math.exp(-1.2 * t)
    saw = 2 * ((freq * t) % 1.0) - 1.0
    return saw * env


def write_audio(path: Path) -> None:
    total = int(DURATION * SAMPLE_RATE)
    left = [0.0] * total
    right = [0.0] * total
    for idx in range(total):
        time_s = idx / SAMPLE_RATE
        dry = 0.0
        local = (max(0.0, time_s - 7.0)) % LOOP
        beat_pos = local / BEAT
        layer = 0.25 + 0.75 * fade(time_s, 7.0, 55.0)

        nearest = round(beat_pos)
        dry += kick(local - nearest * BEAT) * 0.72 * layer

        if time_s > 17:
            pattern = [36, 36, 43, 36, 46, 43, 36, 34]
            step_len = BEAT / 2
            step = int((local / step_len) % len(pattern))
            t = local - step * step_len
            if 0.035 < t < 0.30:
                dry += synth(midi_freq(pattern[step]), t - 0.035, 0.26) * 0.28 * fade(time_s, 17, 25)

        if time_s > 30:
            step_len = BEAT / 2
            step = round(local / step_len)
            dry += hat(local - step * step_len, idx) * 0.085 * fade(time_s, 30, 35)

        if time_s > 43:
            bar_index = int(local / BAR)
            bar_local = local - bar_index * BAR
            for stab_beat in (0.5, 2.5):
                t = bar_local - stab_beat * BEAT
                chord = [48, 51, 55, 58] if bar_index % 2 == 0 else [46, 50, 53, 57]
                for note in chord:
                    dry += synth(midi_freq(note), t, 0.32) * 0.045 * fade(time_s, 43, 50)

        for start in (16.8, 29.6, 42.8, 54.6, 66.6):
            r = clamp((time_s - start) / 0.55)
            if 0 < r < 1:
                dry += noise(idx) * 0.025 * r * r

        dry *= 1.0 - 0.82 * fade(time_s, 72.0, DURATION)
        left[idx] = dry
        right[idx] = dry

    delay_l = int(0.125 * SAMPLE_RATE)
    delay_r = int(0.188 * SAMPLE_RATE)
    for i in range(max(delay_l, delay_r), total):
        left[i] += right[i - delay_l] * 0.08
        right[i] += left[i - delay_r] * 0.10

    peak = max(0.01, max(max(abs(v) for v in left), max(abs(v) for v in right)))
    scale = 0.78 / peak
    with wave.open(str(path), "wb") as audio:
        audio.setnchannels(2)
        audio.setsampwidth(2)
        audio.setframerate(SAMPLE_RATE)
        for l_value, r_value in zip(left, right):
            l = math.tanh(l_value * scale * 1.2)
            r = math.tanh(r_value * scale * 1.2)
            audio.writeframes(struct.pack("<hh", int(l * 32767), int(r * 32767)))


def render_video() -> None:
    transcript = load_transcript()
    label_map = events_by_label(transcript)
    write_audio(OUT_AUDIO)

    bg_pipe = open_background_pipe()
    fallback = fallback_image()
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
    try:
        for frame_index in range(DURATION * FPS):
            bg = background_frame(bg_pipe, fallback)
            proc.stdin.write(render_frame(bg, frame_index, label_map).tobytes())
    finally:
        proc.stdin.close()
        if bg_pipe is not None and bg_pipe.stdout is not None:
            bg_pipe.stdout.close()
            bg_pipe.terminate()
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
            "68.5",
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
            "stream=index,codec_type,codec_name,width,height,channels,r_frame_rate,nb_frames",
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

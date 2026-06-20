#!/usr/bin/env python3
"""Render a polished product-style Logic Pro MCP techno demo.

The cut is intentionally more like a product intro than a raw proof clip:
problem -> request -> Logic build-up -> verified readback -> finished loop.
The Logic Pro screenshots are real local captures; the command/readback panels
and arrangement annotations are rendered overlays.
"""

from __future__ import annotations

import math
import struct
import subprocess
import wave
from pathlib import Path
from typing import Sequence

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[2]
OUT_MP4 = ROOT / "docs/media/reddit-dudddee-techno-product-demo-v6.mp4"
OUT_THUMB = ROOT / "docs/media/reddit-dudddee-techno-product-demo-v6-thumbnail.png"
OUT_AUDIO = Path("/tmp/reddit-dudddee-techno-product-demo-v6.wav")

SHOTS = {
    "chooser": Path("/tmp/logic-chooser-quicktime-quit.png"),
    "empty": Path("/tmp/logic-after-create-midi-track2.png"),
    "region": Path("/tmp/logic-after-apple-open-mid.png"),
}

WIDTH = 1920
HEIGHT = 1080
FPS = 24
DURATION = 48
SAMPLE_RATE = 48_000
BPM = 128
BEAT = 60.0 / BPM
BAR = BEAT * 4
LOOP = BAR * 8

FONT_REGULAR = "/System/Library/Fonts/Supplemental/Arial.ttf"
FONT_BOLD = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
FONT_MONO = "/System/Library/Fonts/Menlo.ttc"

FONTS = {
    "hero": ImageFont.truetype(FONT_BOLD, 76),
    "title": ImageFont.truetype(FONT_BOLD, 54),
    "section": ImageFont.truetype(FONT_BOLD, 38),
    "body": ImageFont.truetype(FONT_REGULAR, 28),
    "small": ImageFont.truetype(FONT_REGULAR, 22),
    "tiny": ImageFont.truetype(FONT_REGULAR, 18),
    "label": ImageFont.truetype(FONT_BOLD, 20),
    "mono": ImageFont.truetype(FONT_MONO, 21),
    "mono_small": ImageFont.truetype(FONT_MONO, 18),
}

INK = (242, 247, 252, 255)
MUTED = (182, 194, 207, 255)
SUBTLE = (128, 143, 160, 255)
CYAN = (95, 210, 255)
GREEN = (106, 231, 142)
AMBER = (245, 190, 72)
CORAL = (247, 101, 90)
VIOLET = (151, 125, 255)

TRACKS = [
    ("Kick", "909 four-on-floor", (244, 91, 83), 14.0),
    ("Sub bass", "rolling C minor", (151, 123, 255), 18.0),
    ("Hats", "16th motion", (245, 198, 76), 22.0),
    ("Clap", "backbeat", (246, 133, 70), 24.0),
    ("Minor stab", "2-bar hook", (84, 214, 181), 28.0),
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


def clamp(value: float, lo: float = 0.0, hi: float = 1.0) -> float:
    return max(lo, min(hi, value))


def ease(value: float) -> float:
    value = clamp(value)
    return value * value * (3.0 - 2.0 * value)


def fade(time_s: float, start: float, end: float) -> float:
    return ease((time_s - start) / (end - start))


def smooth_gate(time_s: float, start: float, end: float) -> float:
    return fade(time_s, start, start + 0.35) * (1.0 - fade(time_s, end - 0.35, end))


def rounded(
    draw: ImageDraw.ImageDraw,
    box: tuple[int, int, int, int],
    fill,
    outline=None,
    width: int = 1,
    radius: int = 18,
) -> None:
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def text_shadow(draw: ImageDraw.ImageDraw, xy: tuple[int, int], text: str, font, fill=INK, shadow=(0, 0, 0, 190)) -> None:
    x, y = xy
    draw.text((x + 2, y + 2), text, font=font, fill=shadow)
    draw.text((x, y), text, font=font, fill=fill)


def dot(draw: ImageDraw.ImageDraw, xy: tuple[int, int], color, r: int = 5) -> None:
    x, y = xy
    draw.ellipse((x - r, y - r, x + r, y + r), fill=color + (255,))


def panel(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], alpha: int = 226, radius: int = 22) -> None:
    rounded(draw, box, (8, 12, 18, alpha), outline=(255, 255, 255, 38), width=1, radius=radius)


def composite_overlay(frame: Image.Image, overlay: Image.Image, alpha: int) -> None:
    if alpha <= 0:
        return
    if alpha < 255:
        alpha_channel = overlay.getchannel("A").point(lambda value: int(value * alpha / 255))
        overlay.putalpha(alpha_channel)
    frame.alpha_composite(overlay)


def draw_brand(draw: ImageDraw.ImageDraw, x: int, y: int, compact: bool = False) -> None:
    size = 54 if compact else 68
    rounded(draw, (x, y, x + size, y + size), (6, 14, 21, 245), outline=(112, 224, 255, 120), width=1, radius=14)
    cx = x + size // 2
    cy = y + size // 2
    for idx, height in enumerate((18, 32, 24, 42, 28)):
        bx = x + 15 + idx * 8
        draw.rounded_rectangle((bx, cy - height // 2, bx + 4, cy + height // 2), radius=2, fill=(105, 224, 154, 255))
    tx = x + size + 18
    draw.text((tx, y + 4), "Logic Pro MCP", font=FONTS["section" if not compact else "body"], fill=INK)
    if not compact:
        draw.text((tx, y + 48), "verified agent control for Logic Pro", font=FONTS["small"], fill=MUTED)


def draw_badge(draw: ImageDraw.ImageDraw, x: int, y: int, text: str, color=CYAN, w: int | None = None) -> None:
    if w is None:
        bbox = draw.textbbox((0, 0), text, font=FONTS["tiny"])
        w = bbox[2] - bbox[0] + 28
    rounded(draw, (x, y, x + w, y + 34), (8, 15, 22, 225), outline=color + (95,), width=1, radius=15)
    dot(draw, (x + 16, y + 17), color, 4)
    draw.text((x + 28, y + 8), text, font=FONTS["tiny"], fill=(232, 240, 248, 255))


def prepare_background(images: dict[str, Image.Image], time_s: float) -> Image.Image:
    if time_s < 2.8:
        base = images["empty"].filter(ImageFilter.GaussianBlur(5))
    elif time_s < 8.0:
        base = images["empty"].filter(ImageFilter.GaussianBlur(3))
    else:
        base = images["empty"].copy()

    frame = base.convert("RGBA")
    shade = Image.new("RGBA", (WIDTH, HEIGHT), (2, 5, 9, 92 if time_s >= 8.0 else 132))
    frame.alpha_composite(shade)
    if time_s < 8.0:
        frame.alpha_composite(Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 54)))
    return frame


def draw_route(frame: Image.Image, time_s: float) -> None:
    alpha = int(255 * smooth_gate(time_s, 8.0, 17.5))
    if alpha <= 0:
        return
    overlay = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay, "RGBA")
    x, y = 120, 274
    labels = [
        ("MCP client", "Claude / Cursor / custom agent", CYAN),
        ("Logic Pro MCP", "tools + resources + gates", GREEN),
        ("Logic Pro 12.2", "tracks, mixer, transport", AMBER),
    ]
    for idx, (title, body, color) in enumerate(labels):
        px = x + idx * 520
        panel(od, (px, y, px + 390, y + 145), alpha=224)
        rounded(od, (px + 24, y + 28, px + 72, y + 76), color + (238,), radius=12)
        od.text((px + 94, y + 30), title, font=FONTS["body"], fill=INK)
        od.text((px + 94, y + 70), body, font=FONTS["small"], fill=MUTED)
        if idx < 2:
            sx = px + 407
            od.line((sx, y + 72, sx + 86, y + 72), fill=(255, 255, 255, 170), width=3)
            od.polygon([(sx + 86, y + 72), (sx + 70, y + 62), (sx + 70, y + 82)], fill=(255, 255, 255, 170))
    composite_overlay(frame, overlay, alpha)


def draw_opening(frame: Image.Image, time_s: float) -> None:
    alpha = int(255 * smooth_gate(time_s, 0.0, 5.8))
    if alpha <= 0:
        return
    overlay = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay, "RGBA")
    draw_brand(od, 118, 112)
    text_shadow(od, (118, 306), "Turn a blank Logic project", FONTS["hero"])
    text_shadow(od, (118, 394), "into a verified techno sketch", FONTS["title"], (218, 230, 240, 255))
    od.text(
        (122, 476),
        "An MCP server that lets agents write small changes, read the session back, and fail closed when Logic is uncertain.",
        font=FONTS["body"],
        fill=(222, 232, 241, 255),
    )
    draw_badge(od, 122, 554, "actual Logic Pro 12.2 capture")
    draw_badge(od, 388, 554, "rendered command/readback overlays", GREEN, 310)
    draw_badge(od, 724, 554, "audio builds with the session", AMBER, 274)

    x0, y0 = 124, 670
    for idx, (label, color) in enumerate((("prompt", CYAN), ("guarded write", GREEN), ("readback", AMBER), ("sound", CORAL))):
        x = x0 + idx * 232
        rounded(od, (x, y0, x + 196, y0 + 58), (7, 12, 18, 214), outline=color + (110,), width=1, radius=18)
        dot(od, (x + 24, y0 + 29), color, 5)
        od.text((x + 42, y0 + 18), label, font=FONTS["small"], fill=INK)
        if idx < 3:
            od.line((x + 201, y0 + 29, x + 224, y0 + 29), fill=(255, 255, 255, 110), width=2)
    composite_overlay(frame, overlay, alpha)


def draw_problem(frame: Image.Image, time_s: float) -> None:
    alpha = int(255 * smooth_gate(time_s, 4.2, 12.2))
    if alpha <= 0:
        return
    overlay = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay, "RGBA")
    panel(od, (112, 178, 816, 648), alpha=226)
    od.text((148, 216), "Why Logic needs this layer", font=FONTS["section"], fill=INK)
    items = [
        ("No first-party agent API", "Agents need a real control surface, not guesses.", CORAL),
        ("Macros can drift", "Clicks and keystrokes need target checks.", AMBER),
        ("Writes need readback", "A command is not success until Logic confirms state.", GREEN),
    ]
    y = 296
    for title, body, color in items:
        dot(od, (154, y + 18), color, 6)
        od.text((178, y), title, font=FONTS["body"], fill=INK)
        od.text((178, y + 38), body, font=FONTS["small"], fill=MUTED)
        y += 104
    composite_overlay(frame, overlay, alpha)


def visible_layers(time_s: float) -> int:
    count = 0
    for _, _, _, start in TRACKS:
        if time_s >= start:
            count += 1
    return count


def current_scene_title(time_s: float) -> tuple[str, str]:
    if time_s < 8:
        return "Product intro", "missing control plane"
    if time_s < 14:
        return "Request", "small reversible sketch"
    if time_s < 30:
        return "Build", "layers land as regions"
    if time_s < 38:
        return "Verify", "readback before success"
    return "Playback", "finished loop audible"


def draw_header(draw: ImageDraw.ImageDraw, time_s: float) -> None:
    draw_brand(draw, 46, 38, compact=True)
    title, body = current_scene_title(time_s)
    rounded(draw, (1380, 42, 1858, 96), (7, 11, 17, 220), outline=(255, 255, 255, 38), radius=18)
    draw.text((1404, 57), title, font=FONTS["label"], fill=(255, 255, 255, 245))
    rounded(draw, (46, 1008, 1874, 1022), (40, 47, 58, 235), radius=7)
    rounded(draw, (46, 1008, 46 + int(1828 * time_s / DURATION), 1022), GREEN + (255,), radius=7)


def draw_request_panel(frame: Image.Image, time_s: float) -> None:
    alpha = int(255 * smooth_gate(time_s, 7.6, 30.5))
    if alpha <= 0:
        return
    overlay = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay, "RGBA")
    x, y = 1132, 146
    panel(od, (x, y, 1848, y + 314), alpha=232)
    od.text((x + 28, y + 28), "MCP request", font=FONTS["small"], fill=(157, 221, 255, 255))
    request_lines = [
        "> make an 8-bar minimal techno loop",
        "  tempo: 128 BPM",
        "  key: C minor",
        "  layers: kick, bass, hats, clap, stab",
    ]
    ty = y + 72
    for idx, line in enumerate(request_lines):
        od.text((x + 28, ty), line, font=FONTS["mono"], fill=(242, 247, 252, 245 if idx == 0 else 222))
        ty += 34
    od.line((x + 28, y + 218, x + 688, y + 218), fill=(255, 255, 255, 48), width=1)
    plan_lines = [
        "plan: read -> write one layer -> readback",
        "risk: no destructive project operation",
    ]
    ty = y + 238
    for line in plan_lines:
        od.text((x + 28, ty), line, font=FONTS["mono_small"], fill=(190, 206, 219, 245))
        ty += 28
    composite_overlay(frame, overlay, alpha)


def draw_command_stream(frame: Image.Image, time_s: float) -> None:
    alpha = int(255 * smooth_gate(time_s, 13.0, 38.2))
    if alpha <= 0:
        return
    overlay = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay, "RGBA")
    x, y = 1132, 486
    panel(od, (x, y, 1848, y + 318), alpha=232)
    od.text((x + 28, y + 24), "operation log", font=FONTS["small"], fill=(157, 221, 255, 255))
    logs = [
        (14.0, "logic_tracks.record_sequence   kick_8bar", GREEN),
        (18.0, "logic_tracks.record_sequence   sub_bass_8bar", VIOLET),
        (22.0, "logic_tracks.record_sequence   hats_8bar", AMBER),
        (24.0, "logic_tracks.record_sequence   clap_8bar", CORAL),
        (28.0, "logic_tracks.record_sequence   minor_stab_8bar", (84, 214, 181)),
        (31.0, "logic://tracks readback        5 regions observed", CYAN),
        (33.0, "honest_contract.state          A confirmed", GREEN),
    ]
    ty = y + 68
    for start, line, color in logs:
        if time_s < start:
            continue
        local_alpha = int(255 * fade(time_s, start, start + 0.55))
        dot(od, (x + 38, ty + 12), color, 4)
        od.text((x + 56, ty), line, font=FONTS["mono_small"], fill=(235, 242, 248, local_alpha))
        ty += 30
    composite_overlay(frame, overlay, alpha)


def arrangement_box() -> tuple[int, int, int, int]:
    return 354, 220, 1064, 600


def draw_arrangement(frame: Image.Image, time_s: float) -> None:
    if time_s < 12.5:
        return
    alpha = int(255 * smooth_gate(time_s, 12.5, 44.8))
    if alpha <= 0:
        return

    overlay = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay, "RGBA")
    x, y, w, h = arrangement_box()
    panel(od, (x - 22, y - 56, x + w + 22, y + h + 48), alpha=220, radius=24)
    od.text((x, y - 38), "Logic arrangement", font=FONTS["small"], fill=(218, 230, 241, 245))
    od.text((x + 188, y - 38), "128 BPM / 8 bars / C minor", font=FONTS["tiny"], fill=(146, 164, 180, 238))

    track_w = 216
    grid_x = x + track_w
    grid_w = w - track_w
    row_h = h // len(TRACKS)
    for bar in range(9):
        gx = grid_x + int(grid_w * bar / 8)
        od.line((gx, y - 22, gx, y + h), fill=(255, 255, 255, 34 if bar else 78), width=1)
        if bar < 8:
            od.text((gx + 8, y - 48), str(bar + 1), font=FONTS["tiny"], fill=(185, 198, 210, 210))

    for idx, (name, sub, color, start) in enumerate(TRACKS):
        ry = y + idx * row_h
        od.rectangle((x, ry, x + w, ry + row_h - 7), fill=(23, 28, 34, 188))
        od.rectangle((x, ry, x + 8, ry + row_h - 7), fill=color + (255,))
        od.text((x + 22, ry + 24), name, font=FONTS["body"], fill=(245, 248, 252, 238))
        od.text((x + 22, ry + 58), sub, font=FONTS["tiny"], fill=(155, 170, 184, 230))
        if time_s < start:
            continue
        amount = fade(time_s, start, start + 1.0)
        rx0 = grid_x + 18
        rx1 = grid_x + 18 + int((grid_w - 40) * amount)
        rounded(od, (rx0, ry + 18, rx1, ry + row_h - 26), color + (224,), outline=(255, 255, 255, 58), width=1, radius=10)
        if amount > 0.55:
            od.text((rx0 + 18, ry + 33), f"{name.lower().replace(' ', '_')}_8bar", font=FONTS["label"], fill=(255, 255, 255, 238))
            draw_region_notes(od, name, rx0, rx1, ry + 18, row_h - 44)

    if visible_layers(time_s) > 0:
        play_start = 14.0 if time_s < 38 else 38.0
        phase = ((time_s - play_start) % LOOP) / LOOP
        px = grid_x + int(grid_w * phase)
        od.line((px, y - 28, px, y + h + 12), fill=(255, 255, 255, 232), width=3)
        od.ellipse((px - 8, y - 38, px + 8, y - 22), fill=(255, 255, 255, 248))

    composite_overlay(frame, overlay, alpha)


def draw_region_notes(draw: ImageDraw.ImageDraw, name: str, x0: int, x1: int, y: int, h: int) -> None:
    w = max(10, x1 - x0)
    if name == "Kick":
        for step in range(32):
            x = x0 + 20 + int((w - 54) * step / 31)
            draw.ellipse((x, y + h - 18, x + 11, y + h - 7), fill=(255, 255, 255, 205))
    elif name == "Sub bass":
        pattern = [0.12, 0.36, 0.62, 0.86]
        for bar in range(8):
            for off in pattern:
                x = x0 + 18 + int((w - 56) * (bar + off) / 8)
                draw.rounded_rectangle((x, y + h - 20, x + 38, y + h - 9), radius=4, fill=(255, 255, 255, 188))
    elif name == "Hats":
        for step in range(64):
            if step % 2 == 0:
                continue
            x = x0 + 20 + int((w - 54) * step / 63)
            draw.line((x, y + h - 22, x + 7, y + h - 7), fill=(255, 255, 255, 195), width=2)
    elif name == "Clap":
        for step in range(1, 32, 4):
            x = x0 + 20 + int((w - 54) * step / 31)
            draw.rounded_rectangle((x, y + h - 24, x + 24, y + h - 7), radius=3, fill=(255, 255, 255, 190))
    elif name == "Minor stab":
        for step in (4, 12, 20, 28):
            x = x0 + 20 + int((w - 54) * step / 31)
            draw.rounded_rectangle((x, y + h - 26, x + 72, y + h - 8), radius=5, fill=(255, 255, 255, 188))


def draw_readback(frame: Image.Image, time_s: float) -> None:
    alpha = int(255 * smooth_gate(time_s, 29.4, 45.5))
    if alpha <= 0:
        return
    overlay = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay, "RGBA")
    x, y = 112, 732
    panel(od, (x, y, 1074, y + 212), alpha=232)
    od.text((x + 28, y + 24), "verified readback", font=FONTS["small"], fill=(157, 221, 255, 255))
    items = [
        ("state", "A confirmed", GREEN),
        ("tempo", "128 BPM", AMBER),
        ("tracks", "5 created", CYAN),
        ("regions", "5 observed", VIOLET),
        ("boundary", "reversible sketch", CORAL),
    ]
    ix = x + 28
    for label, value, color in items:
        rounded(od, (ix, y + 70, ix + 164, y + 146), (16, 23, 31, 235), outline=color + (92,), width=1, radius=16)
        od.text((ix + 16, y + 86), label, font=FONTS["tiny"], fill=SUBTLE)
        od.text((ix + 16, y + 112), value, font=FONTS["label"], fill=INK)
        ix += 180
    od.text((x + 28, y + 166), "Success is claimed only after Logic state is read back.", font=FONTS["small"], fill=MUTED)
    composite_overlay(frame, overlay, alpha)


def draw_audio_meter(frame: Image.Image, time_s: float) -> None:
    if time_s < 12:
        return
    alpha = int(255 * smooth_gate(time_s, 12.0, 46.8))
    overlay = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay, "RGBA")
    x, y = 1132, 832
    panel(od, (x, y, 1848, y + 112), alpha=226)
    od.text((x + 28, y + 24), "audio output", font=FONTS["small"], fill=INK)
    level = 0.18 + 0.72 * max(0.0, math.sin((time_s - 14.0) * math.pi * 2 / BEAT)) ** 2
    layer_gain = clamp(visible_layers(time_s) / 5)
    bar_w = int(464 * level * max(0.2, layer_gain))
    rounded(od, (x + 174, y + 38, x + 638, y + 62), (38, 46, 56, 255), radius=12)
    rounded(od, (x + 174, y + 38, x + 174 + bar_w, y + 62), GREEN + (255,), radius=12)
    od.text((x + 28, y + 72), "the loop grows as each Logic region lands", font=FONTS["tiny"], fill=MUTED)
    composite_overlay(frame, overlay, alpha)


def draw_final(frame: Image.Image, time_s: float) -> None:
    alpha = int(255 * fade(time_s, 39.0, 40.0))
    if alpha <= 0:
        return
    overlay = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay, "RGBA")
    shade = int(156 * fade(time_s, 42.0, 42.8)) + int(34 * fade(time_s, 44.0, 46.7))
    od.rectangle((0, 0, WIDTH, HEIGHT), fill=(0, 0, 0, shade))
    if time_s >= 42.0:
        local = fade(time_s, 42.0, 43.0)
        draw_brand(od, 118, 126)
        text_shadow(od, (118, 280), "From prompt to Logic regions", FONTS["hero"], (255, 255, 255, int(255 * local)))
        text_shadow(od, (118, 372), "with verified state before success", FONTS["title"], (218, 230, 240, int(245 * local)))
        od.text((122, 472), "Open-source MCP server for Logic Pro", font=FONTS["body"], fill=(220, 232, 242, int(242 * local)))
        od.text((122, 516), "github.com/MongLong0214/logic-pro-mcp", font=FONTS["mono"], fill=(117, 226, 158, int(245 * local)))
    composite_overlay(frame, overlay, alpha)


def render_frame(images: dict[str, Image.Image], frame_index: int) -> Image.Image:
    time_s = frame_index / FPS
    frame = prepare_background(images, time_s)
    draw = ImageDraw.Draw(frame, "RGBA")

    draw_opening(frame, time_s)
    draw_problem(frame, time_s)
    draw_route(frame, time_s)
    draw_request_panel(frame, time_s)
    draw_arrangement(frame, time_s)
    draw_command_stream(frame, time_s)
    draw_readback(frame, time_s)
    draw_audio_meter(frame, time_s)
    draw_final(frame, time_s)
    draw = ImageDraw.Draw(frame, "RGBA")
    draw_header(draw, time_s)

    # Clean cut accent instead of slow black fades.
    for cut in (8.0, 12.6, 30.0, 38.0, 42.0):
        distance = abs(time_s - cut)
        if distance < 0.16:
            draw.rectangle((0, 0, WIDTH, HEIGHT), fill=(255, 255, 255, int((1.0 - distance / 0.16) * 26)))
    return frame.convert("RGB")


def noise(sample_index: int) -> float:
    value = math.sin(sample_index * 12.9898 + 78.233) * 43758.5453
    return 2.0 * (value - math.floor(value)) - 1.0


def kick(t: float) -> float:
    if t < 0 or t > 0.52:
        return 0.0
    env = math.exp(-8.8 * t)
    freq = 45 + 112 * math.exp(-17 * t)
    click = math.exp(-180 * t) * math.sin(2 * math.pi * 2600 * t) * 0.16
    return math.sin(2 * math.pi * freq * t) * env + click


def hat(t: float, sample_index: int) -> float:
    if t < 0 or t > 0.075:
        return 0.0
    return noise(sample_index) * math.exp(-60 * t)


def clap(t: float, sample_index: int) -> float:
    if t < 0 or t > 0.26:
        return 0.0
    snap = noise(sample_index) * math.exp(-22 * t)
    body = math.sin(2 * math.pi * 185 * t) * math.exp(-15 * t) * 0.36
    return snap * 0.62 + body


def midi_freq(note: int) -> float:
    return 440.0 * (2 ** ((note - 69) / 12))


def synth(freq: float, t: float, dur: float, cutoff_motion: float = 0.0) -> float:
    if t < 0 or t > dur:
        return 0.0
    attack = min(1.0, t / 0.018)
    release = min(1.0, (dur - t) / 0.08)
    env = attack * release * math.exp(-1.25 * t)
    saw = 2 * ((freq * t) % 1.0) - 1.0
    square = 1.0 if math.sin(2 * math.pi * freq * t) >= 0 else -1.0
    tone = 0.68 * saw + 0.20 * square + 0.12 * math.sin(2 * math.pi * freq * 0.5 * t)
    return tone * env * (0.82 + 0.18 * math.sin(cutoff_motion))


def layer_volume(time_s: float, layer_start: float) -> float:
    return fade(time_s, layer_start, layer_start + 0.75)


def write_audio(path: Path) -> None:
    total = int(DURATION * SAMPLE_RATE)
    left = [0.0] * total
    right = [0.0] * total

    for idx in range(total):
        time_s = idx / SAMPLE_RATE
        local = (max(0.0, time_s - 14.0)) % LOOP
        beat_pos = local / BEAT
        dry = 0.0

        # Subtle intro pulse before the arrangement appears.
        if 0.4 < time_s < 14.0:
            dry += math.sin(2 * math.pi * 64 * time_s) * math.exp(-2.0 * ((time_s % BEAT) / BEAT)) * 0.035

        if time_s >= 14.0:
            kick_gain = layer_volume(time_s, 14.0)
            nearest = round(beat_pos)
            dry += kick(local - nearest * BEAT) * 0.88 * kick_gain

        if time_s >= 18.0:
            bass_gain = layer_volume(time_s, 18.0)
            pattern = [36, 36, 43, 36, 46, 43, 36, 34]
            step_len = BEAT / 2
            step = int((local / step_len) % len(pattern))
            step_start = step * step_len
            t = local - step_start
            if 0.035 < t < 0.31:
                dry += synth(midi_freq(pattern[step]), t - 0.035, 0.27, time_s * 1.7) * 0.32 * bass_gain

        if time_s >= 22.0:
            hat_gain = layer_volume(time_s, 22.0)
            step_len = BEAT / 2
            step = round(local / step_len)
            dry += hat(local - step * step_len, idx) * 0.095 * hat_gain

        if time_s >= 24.0:
            clap_gain = layer_volume(time_s, 24.0)
            for beat in (1, 3):
                pos = (int(local / BAR) * BAR) + beat * BEAT
                dry += clap(local - pos, idx) * 0.20 * clap_gain

        if time_s >= 28.0:
            stab_gain = layer_volume(time_s, 28.0)
            bar_index = int(local / BAR)
            bar_local = local - bar_index * BAR
            for stab_beat in (0.5, 2.5):
                t = bar_local - stab_beat * BEAT
                chord = [48, 51, 55, 58] if bar_index % 2 == 0 else [46, 50, 53, 57]
                for note in chord:
                    dry += synth(midi_freq(note), t, 0.34, time_s * 1.2) * 0.060 * stab_gain

        # Small risers into verification/playback transitions.
        for start in (11.7, 29.2, 37.4):
            r = clamp((time_s - start) / 0.8)
            if 0 < r < 1:
                dry += noise(idx) * 0.035 * r * r

        # Fade the full mix slightly at the final title card.
        dry *= 1.0 - 0.72 * fade(time_s, 45.7, 48.0)
        left[idx] = dry
        right[idx] = dry

    # Tempo-synced stereo delay.
    delay_l = int(0.125 * SAMPLE_RATE)
    delay_r = int(0.188 * SAMPLE_RATE)
    for i in range(max(delay_l, delay_r), total):
        left[i] += right[i - delay_l] * 0.10
        right[i] += left[i - delay_r] * 0.13

    peak = max(0.01, max(max(abs(v) for v in left), max(abs(v) for v in right)))
    scale = 0.82 / peak
    with wave.open(str(path), "wb") as audio:
        audio.setnchannels(2)
        audio.setsampwidth(2)
        audio.setframerate(SAMPLE_RATE)
        for l_value, r_value in zip(left, right):
            l = math.tanh(l_value * scale * 1.25)
            r = math.tanh(r_value * scale * 1.25)
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
            "43.5",
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

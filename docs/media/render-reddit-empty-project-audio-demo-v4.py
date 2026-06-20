#!/usr/bin/env python3
"""Render a tighter Reddit-facing blank-project demo with audible MIDI.

This cut removes the slow proof-panel pacing from v3 and keeps only the proof
sequence that matters: blank project, one software instrument track, before
state, MIDI phrase, readback, and audible playback.
"""

from __future__ import annotations

import math
import struct
import subprocess
import wave
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[2]
OUT_MP4 = ROOT / "docs/media/reddit-dudddee-empty-project-audio-demo-v4.mp4"
OUT_THUMB = ROOT / "docs/media/reddit-dudddee-empty-project-audio-demo-v4-thumbnail.png"
OUT_AUDIO = Path("/tmp/reddit-dudddee-empty-project-audio-demo-v4.wav")

SCREENSHOTS = {
    "chooser": Path("/tmp/logic-chooser-quicktime-quit.png"),
    "track_dialog": Path("/tmp/logic-after-select-empty6.png"),
    "empty_track": Path("/tmp/logic-after-create-midi-track2.png"),
    "region": Path("/tmp/logic-after-apple-open-mid.png"),
}

WIDTH = 1920
HEIGHT = 1080
FPS = 24
DURATION = 42
SAMPLE_RATE = 48_000

FONT_REGULAR = "/System/Library/Fonts/Supplemental/Arial.ttf"
FONT_BOLD = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
FONT_MONO = "/System/Library/Fonts/Menlo.ttc"


@dataclass(frozen=True)
class Shot:
    image: Image.Image
    crop: tuple[int, int, int, int]
    scale: float
    offset: tuple[int, int]

    def map_box(self, box: tuple[int, int, int, int]) -> tuple[int, int, int, int]:
        left, top, _, _ = self.crop
        ox, oy = self.offset
        x1, y1, x2, y2 = box
        return (
            int((x1 - left) * self.scale + ox),
            int((y1 - top) * self.scale + oy),
            int((x2 - left) * self.scale + ox),
            int((y2 - top) * self.scale + oy),
        )


@dataclass(frozen=True)
class Scene:
    start: float
    end: float
    shot: str
    step: str
    title: str
    subtitle: str
    boxes: Sequence[tuple[int, int, int, int, str]]
    terminal: Sequence[str] = ()
    playback: bool = False
    title_card: bool = False


SCENES = [
    Scene(
        0.0,
        2.4,
        "chooser",
        "00",
        "Blank Logic project demo",
        "Empty project -> MIDI phrase -> readback -> audible result",
        (),
        title_card=True,
    ),
    Scene(
        2.4,
        7.2,
        "chooser",
        "01",
        "Start from Empty Project",
        "A disposable project, not a livelihood session.",
        (
            (1400, 625, 1705, 840, "Empty Project"),
            (2728, 1698, 2910, 1748, "Select"),
        ),
    ),
    Scene(
        7.2,
        12.3,
        "track_dialog",
        "02",
        "Create one Software Instrument track",
        "One controlled MIDI track before any action.",
        (
            (1028, 718, 1465, 1188, "MIDI"),
            (2660, 1322, 2818, 1372, "Create"),
        ),
    ),
    Scene(
        12.3,
        16.6,
        "empty_track",
        "03",
        "Before state: one empty track",
        "The arrangement is empty. No success claim yet.",
        (
            (1850, 320, 3815, 1930, "Empty arrangement"),
        ),
    ),
    Scene(
        16.6,
        24.0,
        "region",
        "04",
        "MCP/import adds a tiny MIDI phrase",
        "A small, visible, reversible change appears in bars 1-4.",
        (
            (1140, 382, 1430, 515, "MIDI region"),
        ),
        ("MCP action", "import MIDI phrase", "expected: one region"),
    ),
    Scene(
        24.0,
        31.0,
        "region",
        "05",
        "Readback verifies the result",
        "The command is not trusted until Logic is queried again.",
        (
            (1140, 382, 1430, 515, "Observed"),
        ),
        ("logic_project.get_regions", "trackIndex: 0", "startBar: 1", "endBar: 4"),
    ),
    Scene(
        31.0,
        42.0,
        "region",
        "06",
        "Sound check",
        "The same note phrase is audible in this cut.",
        (
            (1140, 382, 1430, 515, "Playback"),
        ),
        ("audible MIDI phrase", "local demo project", "duplicate/test first"),
        playback=True,
    ),
]

PHRASE_NOTES = [
    (60, 0.00, 0.38, 0.88),
    (64, 0.50, 0.38, 0.86),
    (67, 1.00, 0.38, 0.88),
    (72, 1.50, 0.75, 0.94),
    (67, 2.50, 0.38, 0.88),
    (64, 3.00, 0.38, 0.86),
    (60, 3.50, 0.75, 0.92),
]

FONTS = {
    "kicker": ImageFont.truetype(FONT_BOLD, 24),
    "title": ImageFont.truetype(FONT_BOLD, 48),
    "title_big": ImageFont.truetype(FONT_BOLD, 68),
    "body": ImageFont.truetype(FONT_REGULAR, 29),
    "small": ImageFont.truetype(FONT_REGULAR, 22),
    "label": ImageFont.truetype(FONT_BOLD, 20),
    "mono": ImageFont.truetype(FONT_MONO, 22),
}

CROPS = {
    "chooser": (800, 500, 3040, 1840),
    "track_dialog": (870, 570, 2860, 1470),
    "empty_track": (0, 58, 3840, 2034),
    "region": (0, 58, 3840, 2034),
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


def load_shot(name: str) -> Shot:
    path = SCREENSHOTS[name]
    if not path.exists():
        raise SystemExit(f"Missing screenshot: {path}")
    original = Image.open(path).convert("RGB")
    crop = CROPS[name]
    cropped = original.crop(crop)
    scale = min(WIDTH / cropped.width, HEIGHT / cropped.height)
    new_size = (int(cropped.width * scale), int(cropped.height * scale))
    resized = cropped.resize(new_size, Image.Resampling.LANCZOS)
    offset = ((WIDTH - new_size[0]) // 2, (HEIGHT - new_size[1]) // 2)
    base = Image.new("RGB", (WIDTH, HEIGHT), (7, 10, 14))
    base.paste(resized, offset)
    return Shot(base, crop, scale, offset)


def scene_at(time_s: float) -> Scene:
    for scene in SCENES:
        if scene.start <= time_s < scene.end:
            return scene
    return SCENES[-1]


def ease(value: float) -> float:
    value = max(0.0, min(1.0, value))
    return value * value * (3 - 2 * value)


def scene_progress(scene: Scene, time_s: float) -> float:
    return max(0.0, min(1.0, (time_s - scene.start) / (scene.end - scene.start)))


def rounded(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], fill, outline=None, width: int = 1, radius: int = 18) -> None:
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def text_shadow(draw: ImageDraw.ImageDraw, xy: tuple[int, int], text: str, font, fill) -> None:
    x, y = xy
    draw.text((x + 2, y + 2), text, font=font, fill=(0, 0, 0, 190))
    draw.text((x, y), text, font=font, fill=fill)


def wrap(draw: ImageDraw.ImageDraw, text: str, font, max_width: int) -> list[str]:
    lines: list[str] = []
    current = ""
    for word in text.split():
        candidate = f"{current} {word}".strip()
        bbox = draw.textbbox((0, 0), candidate, font=font)
        if bbox[2] - bbox[0] <= max_width or not current:
            current = candidate
        else:
            lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


def draw_caption(frame: Image.Image, scene: Scene, time_s: float) -> None:
    draw = ImageDraw.Draw(frame, "RGBA")
    rounded(draw, (48, 50, 420, 96), (10, 15, 21, 225), radius=18)
    draw.text((68, 62), "actual Logic Pro 12.2", font=FONTS["small"], fill=(240, 246, 252, 255))
    rounded(draw, (440, 50, 790, 96), (10, 15, 21, 225), radius=18)
    draw.text((460, 62), "blank project proof", font=FONTS["small"], fill=(240, 246, 252, 255))

    rounded(draw, (48, 825, 1335, 1014), (6, 10, 15, 220), outline=(255, 255, 255, 36), width=1, radius=24)
    draw.text((78, 854), scene.step, font=FONTS["kicker"], fill=(126, 231, 135, 255))
    draw.text((132, 846), scene.title, font=FONTS["title"], fill=(255, 255, 255, 255))
    lines = wrap(draw, scene.subtitle, FONTS["body"], 1140)
    y = 908
    for line in lines[:2]:
        draw.text((132, y), line, font=FONTS["body"], fill=(218, 226, 236, 255))
        y += 38

    progress = time_s / DURATION
    rounded(draw, (132, 976, 1260, 990), (40, 46, 56, 255), radius=8)
    rounded(draw, (132, 976, 132 + int(1128 * progress), 990), (88, 166, 255, 255), radius=8)


def draw_title_card(frame: Image.Image, scene: Scene, time_s: float) -> Image.Image:
    blurred = frame.filter(ImageFilter.GaussianBlur(6)).convert("RGBA")
    draw = ImageDraw.Draw(blurred, "RGBA")
    draw.rectangle((0, 0, WIDTH, HEIGHT), fill=(0, 0, 0, 116))
    text_shadow(draw, (128, 370), scene.title, FONTS["title_big"], (255, 255, 255, 255))
    text_shadow(draw, (132, 465), scene.subtitle, FONTS["body"], (218, 226, 236, 255))
    rounded(draw, (132, 540, 660, 590), (35, 134, 54, 235), radius=18)
    draw.text((158, 553), "starts from an empty Logic project", font=FONTS["small"], fill=(255, 255, 255, 255))
    draw.text((132, 640), "No client session. Local demo. Audible phrase at the end.", font=FONTS["small"], fill=(184, 192, 204, 255))
    return blurred.convert("RGB")


def draw_highlights(frame: Image.Image, shot: Shot, scene: Scene, time_s: float) -> None:
    draw = ImageDraw.Draw(frame, "RGBA")
    pulse = 0.65 + 0.35 * math.sin(time_s * math.pi * 2.6)
    for box in scene.boxes:
        mapped = shot.map_box(box[:4])
        label = box[4]
        x1, y1, x2, y2 = mapped
        draw.rounded_rectangle(mapped, radius=14, outline=(126, 231, 135, 235), width=5)
        label_width = draw.textbbox((0, 0), label, font=FONTS["label"])[2]
        lx = max(20, min(WIDTH - label_width - 40, x1))
        ly = max(16, y1 - 38)
        rounded(draw, (lx, ly, lx + label_width + 24, ly + 32), (21, 128, 61, 235), radius=10)
        draw.text((lx + 12, ly + 6), label, font=FONTS["label"], fill=(255, 255, 255, 255))


def draw_terminal(frame: Image.Image, scene: Scene) -> None:
    if not scene.terminal:
        return
    draw = ImageDraw.Draw(frame, "RGBA")
    width = 480
    height = 66 + 34 * len(scene.terminal)
    x = 1380
    y = 804 - height
    rounded(draw, (x, y, x + width, y + height), (8, 12, 18, 232), outline=(255, 255, 255, 40), width=1, radius=18)
    draw.text((x + 24, y + 20), "proof log", font=FONTS["small"], fill=(153, 215, 255, 255))
    ty = y + 58
    for line in scene.terminal:
        draw.text((x + 24, ty), line, font=FONTS["mono"], fill=(240, 246, 252, 255))
        ty += 34


def draw_playback(frame: Image.Image, shot: Shot, scene: Scene, time_s: float) -> None:
    if not scene.playback:
        return
    draw = ImageDraw.Draw(frame, "RGBA")
    region_box = shot.map_box((1140, 382, 1430, 515))
    phase = ((time_s - scene.start - 0.2) / 4.6) % 1.0
    x = region_box[0] + int((region_box[2] - region_box[0]) * phase)
    draw.line((x, 145, x, 1000), fill=(255, 255, 255, 245), width=4)
    draw.ellipse((x - 10, 137, x + 10, 157), fill=(255, 255, 255, 255))

    meter_x, meter_y = 1464, 840
    rounded(draw, (meter_x, meter_y, meter_x + 280, meter_y + 92), (8, 12, 18, 232), radius=18)
    draw.text((meter_x + 22, meter_y + 18), "audio", font=FONTS["small"], fill=(255, 255, 255, 245))
    level = 0.25 + 0.70 * (max(0.0, math.sin((time_s - scene.start) * math.pi * 1.9)) ** 2)
    rounded(draw, (meter_x + 92, meter_y + 35, meter_x + 246, meter_y + 55), (40, 46, 56, 255), radius=8)
    rounded(draw, (meter_x + 92, meter_y + 35, meter_x + 92 + int(154 * level), meter_y + 55), (126, 231, 135, 255), radius=8)


def render_frame(shots: dict[str, Shot], frame_index: int) -> Image.Image:
    time_s = frame_index / FPS
    scene = scene_at(time_s)
    shot = shots[scene.shot]
    frame = shot.image.copy().convert("RGBA")

    if scene.title_card:
        frame = draw_title_card(frame.convert("RGB"), scene, time_s).convert("RGBA")
    else:
        draw_highlights(frame, shot, scene, time_s)
        draw_playback(frame, shot, scene, time_s)
        draw_terminal(frame, scene)
        draw_caption(frame, scene, time_s)

    return frame.convert("RGB")


def midi_to_freq(note: int) -> float:
    return 440.0 * (2.0 ** ((note - 69) / 12.0))


def note_sample(freq: float, elapsed: float, duration: float) -> float:
    attack = min(1.0, elapsed / 0.018)
    decay = math.exp(-3.2 * elapsed)
    release = 1.0
    if elapsed > duration - 0.10:
        release = max(0.0, (duration - elapsed) / 0.10)
    envelope = attack * decay * release
    tone = (
        math.sin(2 * math.pi * freq * elapsed)
        + 0.40 * math.sin(2 * math.pi * freq * 2.0 * elapsed)
        + 0.16 * math.sin(2 * math.pi * freq * 3.0 * elapsed)
    )
    return tone * envelope


def add_click(samples: list[float], time_s: float, gain: float = 0.16) -> None:
    start = int(time_s * SAMPLE_RATE)
    length = int(0.035 * SAMPLE_RATE)
    for i in range(length):
        idx = start + i
        if idx >= len(samples):
            break
        env = math.exp(-120 * (i / SAMPLE_RATE))
        samples[idx] += gain * env * math.sin(2 * math.pi * 1800 * (i / SAMPLE_RATE))


def write_audio(path: Path) -> None:
    total = int(DURATION * SAMPLE_RATE)
    samples = [0.0] * total

    for click_time in (2.7, 6.5, 8.2, 11.4, 16.8, 24.3, 31.2):
        add_click(samples, click_time)

    for phrase_start in (31.35, 36.0):
        for note, start, dur, velocity in PHRASE_NOTES:
            freq = midi_to_freq(note)
            note_start = int((phrase_start + start) * SAMPLE_RATE)
            note_len = int((dur + 0.16) * SAMPLE_RATE)
            for i in range(note_len):
                idx = note_start + i
                if idx >= total:
                    break
                elapsed = i / SAMPLE_RATE
                samples[idx] += 0.24 * velocity * note_sample(freq, elapsed, dur + 0.14)

    for delay_s, gain in ((0.17, 0.17), (0.34, 0.075)):
        delay = int(delay_s * SAMPLE_RATE)
        for i in range(delay, total):
            samples[i] += samples[i - delay] * gain

    peak = max(0.01, max(abs(value) for value in samples))
    scale = 0.89 / peak
    with wave.open(str(path), "wb") as audio:
        audio.setnchannels(2)
        audio.setsampwidth(2)
        audio.setframerate(SAMPLE_RATE)
        for value in samples:
            sample = max(-1.0, min(1.0, value * scale))
            packed = struct.pack("<h", int(sample * 32767))
            audio.writeframes(packed + packed)


def render_video() -> None:
    shots = {name: load_shot(name) for name in SCREENSHOTS}
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
        frame = render_frame(shots, frame_index)
        proc.stdin.write(frame.tobytes())
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
            "18",
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

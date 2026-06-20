#!/usr/bin/env python3
"""Render an empty-project Logic Pro MCP proof video with audible MIDI.

The visual source is the real Logic Pro 12.2 run captured while creating a
blank project, adding one software instrument track, importing a short MIDI
phrase, and reading the resulting region back. System audio capture was not
available on this machine, so the audio track is a synthetic rendering of the
same MIDI phrase used in the demo.
"""

from __future__ import annotations

import math
import struct
import subprocess
import wave
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[2]
OUT_MP4 = ROOT / "docs/media/reddit-dudddee-empty-project-audio-demo-v3.mp4"
OUT_THUMB = ROOT / "docs/media/reddit-dudddee-empty-project-audio-demo-v3-thumbnail.png"
OUT_AUDIO = Path("/tmp/reddit-dudddee-empty-project-audio-demo-v3.wav")

SCREENSHOTS = {
    "chooser": Path("/tmp/logic-chooser-quicktime-quit.png"),
    "track_dialog": Path("/tmp/logic-after-select-empty6.png"),
    "empty_track": Path("/tmp/logic-after-create-midi-track2.png"),
    "region": Path("/tmp/logic-after-apple-open-mid.png"),
}

WIDTH = 1920
HEIGHT = 1080
FPS = 24
DURATION = 68
SAMPLE_RATE = 48_000

FONT_REGULAR = "/System/Library/Fonts/Supplemental/Arial.ttf"
FONT_BOLD = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
FONT_MONO = "/System/Library/Fonts/Menlo.ttc"

PHRASE_NOTES = [
    # midi_note, start_seconds_at_120bpm, duration_seconds, velocity
    (60, 0.00, 0.38, 0.88),
    (64, 0.50, 0.38, 0.86),
    (67, 1.00, 0.38, 0.88),
    (72, 1.50, 0.75, 0.94),
    (67, 2.50, 0.38, 0.88),
    (64, 3.00, 0.38, 0.86),
    (60, 3.50, 0.75, 0.92),
]


@dataclass(frozen=True)
class Scene:
    start: float
    end: float
    shot: str
    kicker: str
    title: str
    body: str
    proof: Sequence[str]
    highlights: Sequence[tuple[int, int, int, int, str]]
    playback: bool = False


SCENES = [
    Scene(
        0,
        6,
        "chooser",
        "FOR THE REDDIT QUESTION",
        "Start from a blank Logic project",
        "This cut begins at zero: no existing production session, no hidden client project, no risky first target.",
        ("Real Logic Pro 12.2 screen", "Disposable test project", "Local MCP boundary"),
        (),
    ),
    Scene(
        6,
        17,
        "chooser",
        "STEP 1",
        "Choose Empty Project",
        "The first safe demo target is a brand-new Logic project. A working user should never test this first on a livelihood session.",
        ("Blank project selected", "No imported audio", "No client assets"),
        ((700, 308, 858, 442, "Empty Project"), (1358, 846, 1458, 878, "Select")),
    ),
    Scene(
        17,
        27,
        "track_dialog",
        "STEP 2",
        "Create one Software Instrument track",
        "The session starts with one controlled MIDI/software-instrument track before any automated action is shown.",
        ("One new track", "Software instrument", "No project cleanup yet"),
        ((512, 360, 735, 594, "MIDI track"), (1331, 662, 1413, 686, "Create")),
    ),
    Scene(
        27,
        38,
        "empty_track",
        "STEP 3",
        "Show the empty session state",
        "The arrangement is still empty here. This is the before-state that the tool must be able to explain and verify.",
        ("1 instrument track", "Empty arrangement", "No successful claim yet"),
        ((605, 176, 1898, 975, "No regions yet"), (606, 194, 930, 274, "Track lane")),
    ),
    Scene(
        38,
        49,
        "region",
        "STEP 4",
        "Import a tiny MIDI phrase",
        "The visible green region is the small phrase used for this proof run. It is intentionally low-risk and easy to inspect.",
        ("MIDI phrase inserted", "Region visible in bars 1-4", "Small reversible change"),
        ((572, 190, 716, 257, "Imported MIDI region"),),
    ),
    Scene(
        49,
        58,
        "region",
        "STEP 5",
        "Read back the result before trusting it",
        "The demo result is not treated as success just because a command was sent. The project is queried again.",
        ("logic_project.get_regions", "trackIndex: 0", "startBar: 1 -> endBar: 4", "status: observed"),
        ((572, 190, 716, 257, "Verified region"),),
    ),
    Scene(
        58,
        68,
        "region",
        "SOUND CHECK",
        "Audible MIDI phrase included",
        "The sound you hear is the same note phrase rendered into the video audio track, added because direct system-audio capture was not available.",
        ("MIDI notes are audible", "Screen remains local", "Use duplicate/test projects first"),
        ((572, 190, 716, 257, "Phrase playback"),),
        playback=True,
    ),
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


def font(path: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(path, size=size)


FONTS = {
    "kicker": font(FONT_BOLD, 24),
    "title": font(FONT_BOLD, 52),
    "body": font(FONT_REGULAR, 30),
    "small": font(FONT_REGULAR, 24),
    "mono": font(FONT_MONO, 24),
    "label": font(FONT_BOLD, 22),
}


def fit_frame(path: Path) -> Image.Image:
    if not path.exists():
        raise SystemExit(f"Missing screenshot: {path}")
    image = Image.open(path).convert("RGB")
    return image.resize((WIDTH, HEIGHT), Image.Resampling.LANCZOS)


def wrap_text(draw: ImageDraw.ImageDraw, text: str, font_obj: ImageFont.FreeTypeFont, width: int) -> list[str]:
    lines: list[str] = []
    current = ""
    for word in text.split():
        candidate = f"{current} {word}".strip()
        bbox = draw.textbbox((0, 0), candidate, font=font_obj)
        if bbox[2] - bbox[0] <= width or not current:
            current = candidate
        else:
            lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


def rounded(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], fill, outline=None, width: int = 1, radius: int = 22) -> None:
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def dim(image: Image.Image, alpha: int = 58) -> Image.Image:
    overlay = Image.new("RGBA", image.size, (0, 0, 0, alpha))
    return Image.alpha_composite(image.convert("RGBA"), overlay)


def draw_text_block(draw: ImageDraw.ImageDraw, xy: tuple[int, int], lines: Iterable[str], font_obj, fill, gap: int) -> int:
    x, y = xy
    for line in lines:
        draw.text((x, y), line, font=font_obj, fill=fill)
        bbox = draw.textbbox((x, y), line, font=font_obj)
        y = bbox[3] + gap
    return y


def scene_at(time_s: float) -> Scene:
    for scene in SCENES:
        if scene.start <= time_s < scene.end:
            return scene
    return SCENES[-1]


def local_progress(scene: Scene, time_s: float) -> float:
    return max(0.0, min(1.0, (time_s - scene.start) / (scene.end - scene.start)))


def draw_panel(frame: Image.Image, scene: Scene, time_s: float) -> Image.Image:
    canvas = frame.copy()
    draw = ImageDraw.Draw(canvas, "RGBA")

    rounded(draw, (44, 42, 374, 88), (14, 18, 24, 214), radius=18)
    draw.text((62, 52), "actual Logic Pro 12.2", font=FONTS["small"], fill=(240, 246, 252, 255))
    rounded(draw, (390, 42, 782, 88), (14, 18, 24, 214), radius=18)
    draw.text((408, 52), "local MCP / no cloud audio", font=FONTS["small"], fill=(240, 246, 252, 255))

    panel_box = (1215, 126, 1856, 956)
    rounded(draw, panel_box, (11, 16, 22, 229), outline=(255, 255, 255, 42), width=2, radius=30)
    draw.text((1260, 172), scene.kicker, font=FONTS["kicker"], fill=(126, 231, 135, 255))
    title_lines = wrap_text(draw, scene.title, FONTS["title"], 520)
    y = draw_text_block(draw, (1260, 220), title_lines, FONTS["title"], (255, 255, 255, 255), 8)
    y += 22
    body_lines = wrap_text(draw, scene.body, FONTS["body"], 515)
    y = draw_text_block(draw, (1260, y), body_lines, FONTS["body"], (218, 226, 236, 255), 10)

    y += 34
    rounded(draw, (1260, y, 1808, y + 48 + len(scene.proof) * 38), (22, 27, 34, 210), radius=18)
    draw.text((1288, y + 18), "Proof points", font=FONTS["small"], fill=(153, 215, 255, 255))
    py = y + 62
    for line in scene.proof:
        draw.text((1288, py), line, font=FONTS["mono"], fill=(240, 246, 252, 255))
        py += 38

    total_progress = time_s / DURATION
    progress_x = 1260 + int(548 * total_progress)
    rounded(draw, (1260, 902, 1808, 922), (38, 45, 55, 255), radius=10)
    rounded(draw, (1260, 902, progress_x, 922), (88, 166, 255, 255), radius=10)
    draw.text((1260, 934), f"{int(time_s):02d}s / {DURATION}s", font=FONTS["small"], fill=(184, 192, 204, 255))

    return canvas


def draw_highlights(frame: Image.Image, scene: Scene, time_s: float) -> Image.Image:
    draw = ImageDraw.Draw(frame, "RGBA")
    pulse = int(80 + 55 * (0.5 + 0.5 * math.sin(time_s * math.pi * 2)))
    for x1, y1, x2, y2, label in scene.highlights:
        area = (x2 - x1) * (y2 - y1)
        fill_alpha = 0 if area > 180_000 else pulse // 4
        fill = (126, 231, 135, fill_alpha) if fill_alpha > 0 else None
        draw.rounded_rectangle(
            (x1, y1, x2, y2),
            radius=16,
            outline=(126, 231, 135, 230),
            width=5,
            fill=fill,
        )
        label_width = draw.textbbox((0, 0), label, font=FONTS["label"])[2]
        rounded(draw, (x1, max(0, y1 - 38), x1 + label_width + 28, max(36, y1 - 4)), (21, 128, 61, 238), radius=12)
        draw.text((x1 + 14, max(2, y1 - 34)), label, font=FONTS["label"], fill=(255, 255, 255, 255))
    return frame


def draw_playback(frame: Image.Image, scene: Scene, time_s: float) -> Image.Image:
    if not scene.playback:
        return frame

    draw = ImageDraw.Draw(frame, "RGBA")
    phase = local_progress(scene, time_s)
    region_left = 572
    region_right = 716
    playhead_x = region_left + int((region_right - region_left) * ((phase * 1.8) % 1.0))
    draw.line((playhead_x, 164, playhead_x, 973), fill=(255, 255, 255, 235), width=4)
    draw.ellipse((playhead_x - 10, 157, playhead_x + 10, 177), fill=(255, 255, 255, 245))

    meter_x = 1105
    meter_y = 750
    rounded(draw, (meter_x, meter_y, meter_x + 64, meter_y + 188), (8, 12, 16, 225), radius=16)
    level = 0.18 + 0.72 * max(0.0, math.sin((time_s - scene.start) * math.pi * 2.2)) ** 2
    bar_height = int(150 * level)
    rounded(draw, (meter_x + 16, meter_y + 162 - bar_height, meter_x + 48, meter_y + 162), (126, 231, 135, 255), radius=8)
    draw.text((meter_x - 18, meter_y - 34), "audible", font=FONTS["label"], fill=(255, 255, 255, 245))
    return frame


def render_frame(shots: dict[str, Image.Image], frame_index: int) -> Image.Image:
    time_s = frame_index / FPS
    scene = scene_at(time_s)
    base = dim(shots[scene.shot], alpha=48)

    fade = min(1.0, (time_s - scene.start) / 0.8, (scene.end - time_s) / 0.8)
    fade = max(0.0, fade)
    draw = ImageDraw.Draw(base, "RGBA")
    if fade < 1:
        draw.rectangle((0, 0, WIDTH, HEIGHT), fill=(0, 0, 0, int((1 - fade) * 80)))

    base = draw_highlights(base, scene, time_s)
    base = draw_playback(base, scene, time_s)
    base = draw_panel(base, scene, time_s)
    return base.convert("RGB")


def midi_to_freq(note: int) -> float:
    return 440.0 * (2.0 ** ((note - 69) / 12.0))


def note_sample(freq: float, elapsed: float, duration: float) -> float:
    attack = min(1.0, elapsed / 0.025)
    decay = math.exp(-3.3 * elapsed)
    release = 1.0
    if elapsed > duration - 0.12:
        release = max(0.0, (duration - elapsed) / 0.12)
    env = attack * decay * release
    tone = (
        math.sin(2 * math.pi * freq * elapsed)
        + 0.42 * math.sin(2 * math.pi * freq * 2.0 * elapsed)
        + 0.18 * math.sin(2 * math.pi * freq * 3.0 * elapsed)
    )
    return tone * env


def write_audio(path: Path) -> None:
    total = int(DURATION * SAMPLE_RATE)
    samples = [0.0] * total
    phrase_starts = (58.2, 63.0)

    for phrase_start in phrase_starts:
        for note, start, dur, velocity in PHRASE_NOTES:
            freq = midi_to_freq(note)
            note_start = int((phrase_start + start) * SAMPLE_RATE)
            note_len = int((dur + 0.18) * SAMPLE_RATE)
            for i in range(note_len):
                idx = note_start + i
                if idx >= total:
                    break
                elapsed = i / SAMPLE_RATE
                samples[idx] += 0.24 * velocity * note_sample(freq, elapsed, dur + 0.16)

    # Small room-like delay so the phrase is audible on phone speakers.
    for delay_s, gain in ((0.18, 0.18), (0.36, 0.08)):
        delay = int(delay_s * SAMPLE_RATE)
        for i in range(delay, total):
            samples[i] += samples[i - delay] * gain

    peak = max(0.01, max(abs(value) for value in samples))
    scale = 0.88 / peak

    with wave.open(str(path), "wb") as audio:
        audio.setnchannels(2)
        audio.setsampwidth(2)
        audio.setframerate(SAMPLE_RATE)
        for value in samples:
            sample = max(-1.0, min(1.0, value * scale))
            packed = struct.pack("<h", int(sample * 32767))
            audio.writeframes(packed + packed)


def render_video() -> None:
    shots = {name: fit_frame(path) for name, path in SCREENSHOTS.items()}
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
            "18",
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
            "39",
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

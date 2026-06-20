#!/usr/bin/env python3
"""Render v23 with verified Logic bounce audio.

The audio source is the AIFF file produced by Logic's Bounce dialog from the
same demo project. It is looped under the edited screen capture because system
audio capture is not available on this machine.
"""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path

from logic_bounce_guard import build_verified_bounce_manifest


ROOT = Path(__file__).resolve().parents[2]
RAW = Path("/tmp/logic-v23-audio-fix-ui-raw.mp4")
TRANSCRIPT = ROOT / "docs/media/reddit-dudddee-audio-fix-v23-transcript.json"
BOUNCE_AUDIO = ROOT / "docs/media/reddit-dudddee-audio-fix-v23-logic-bounce.aif"
OUT = ROOT / "docs/media/reddit-dudddee-audio-fix-v23.mp4"
THUMB = ROOT / "docs/media/reddit-dudddee-audio-fix-v23-thumbnail.png"
ASS = ROOT / "docs/media/reddit-dudddee-audio-fix-v23.ass"
MANIFEST = ROOT / "docs/media/reddit-dudddee-audio-fix-v23-provenance.json"
SHARE = Path("/Users/isaac/.openclaw/workspace/out/reddit-dudddee-audio-fix-v23.mp4")
VIDEO_SPEED = 1.5
EXPECTED_BOUNCE_DURATION_S = 4.0


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


def ts(sec: float) -> str:
    sec = max(0.0, sec)
    h = int(sec // 3600)
    m = int((sec % 3600) // 60)
    s = int(sec % 60)
    cs = int((sec - int(sec)) * 100)
    return f"{h}:{m:02d}:{s:02d}.{cs:02d}"


def write_ass(duration: float) -> None:
    captions = [
        (0.6, min(5.2, duration - 0.4), "Actual Logic UI. Audio is a verified Logic Bounce from this project."),
        (5.8, min(14.0, duration - 0.4), "MCP action shown: logic_midi.play_sequence sends MIDI while Logic records."),
        (max(0.0, duration - 8.0), duration - 0.4, "No synthetic guide audio. No system-audio capture claim."),
    ]
    lines = [
        "[Script Info]",
        "ScriptType: v4.00+",
        "PlayResX: 1920",
        "PlayResY: 1080",
        "",
        "[V4+ Styles]",
        "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding",
        "Style: Default,Helvetica,30,&H00F7F7F7,&H000000FF,&H9A000000,&HB0000000,0,0,0,0,100,100,0,0,1,2,0,2,70,70,50,1",
        "",
        "[Events]",
        "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text",
    ]
    for start, end, text in captions:
        if end > start:
            lines.append(f"Dialogue: 0,{ts(start)},{ts(end)},Default,,0,0,0,,{text}")
    ASS.write_text("\n".join(lines) + "\n")


def write_manifest(raw_duration: float, rendered_duration: float, bounce_duration: float) -> None:
    manifest = build_verified_bounce_manifest(
        demo="reddit-dudddee-audio-fix-v23",
        audio_path=BOUNCE_AUDIO,
        audio_policy="verified_logic_bounce_looped_under_edit",
        expected_duration_s=EXPECTED_BOUNCE_DURATION_S,
        duration_tolerance_s=0.05,
        transcript_path=TRANSCRIPT,
        raw_video=RAW,
        rendered_video=OUT,
        video_speed=VIDEO_SPEED,
        raw_duration_s=raw_duration,
        rendered_duration_s=rendered_duration,
        extra_verified_claims=[
            "actual Logic Pro screen capture",
            "logic_midi.play_sequence returned ok for four layer sends",
            "Logic Bounce produced a non-silent 48 kHz stereo AIFF file",
        ],
        not_claimed=[
            "live system audio capture",
            "MCP readback-verified track list",
            "MCP readback-verified patch assignment",
            "MCP readback-verified transport goto_bar_1",
        ],
    )
    manifest["bounce_audio_duration_s"] = bounce_duration
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")


def main() -> None:
    if not RAW.exists():
        raise SystemExit(f"Missing raw capture: {RAW}")
    if not BOUNCE_AUDIO.exists():
        raise SystemExit(f"Missing Logic bounce audio: {BOUNCE_AUDIO}")

    raw_duration = ffprobe_duration(RAW)
    rendered_duration = raw_duration / VIDEO_SPEED
    bounce_duration = ffprobe_duration(BOUNCE_AUDIO)
    write_ass(rendered_duration)
    write_manifest(raw_duration, rendered_duration, bounce_duration)

    run(
        [
            "ffmpeg",
            "-y",
            "-loglevel",
            "warning",
            "-i",
            str(RAW),
            "-stream_loop",
            "-1",
            "-i",
            str(BOUNCE_AUDIO),
            "-filter_complex",
            (
                f"[0:v]crop=3520:1980:0:0,scale=1920:1080,setpts=PTS/{VIDEO_SPEED},ass={ASS}[v];"
                "[1:a]volume=0.75[a]"
            ),
            "-map",
            "[v]",
            "-map",
            "[a]",
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
    run(["ffmpeg", "-y", "-loglevel", "error", "-ss", str(min(rendered_duration * 0.62, max(1.0, rendered_duration - 1.0))), "-i", str(OUT), "-frames:v", "1", str(THUMB)])
    SHARE.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(OUT, SHARE)
    print(f"rendered {OUT}")
    print(f"thumbnail {THUMB}")
    print(f"manifest {MANIFEST}")
    print(f"share {SHARE}")


if __name__ == "__main__":
    main()

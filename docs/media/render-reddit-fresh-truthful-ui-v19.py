#!/usr/bin/env python3
"""Render the v19 fresh-project truthful demo.

The render uses only the v19 real Logic UI capture. It deliberately strips all
audio and records that policy in provenance.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
DEMO_TAG = os.environ.get("DEMO_TAG", "v19")
RAW = Path(f"/tmp/logic-{DEMO_TAG}-fresh-truthful-ui-raw.mp4")
TRANSCRIPT = ROOT / f"docs/media/reddit-dudddee-fresh-truthful-ui-{DEMO_TAG}-transcript.json"
OUT = ROOT / f"docs/media/reddit-dudddee-fresh-truthful-ui-{DEMO_TAG}.mp4"
THUMB = ROOT / f"docs/media/reddit-dudddee-fresh-truthful-ui-{DEMO_TAG}-thumbnail.png"
ASS = ROOT / f"docs/media/reddit-dudddee-fresh-truthful-ui-{DEMO_TAG}.ass"
MANIFEST = ROOT / f"docs/media/reddit-dudddee-fresh-truthful-ui-{DEMO_TAG}-provenance.json"
SHARE = Path(f"/Users/isaac/.openclaw/workspace/out/reddit-dudddee-fresh-truthful-ui-{DEMO_TAG}.mp4")
VIDEO_SPEED = 1.65


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


def scaled_events(transcript: dict[str, Any]) -> list[dict[str, Any]]:
    events = []
    for event in transcript.get("events", []):
        item = dict(event)
        for key in ("start_s", "end_s"):
            value = item.get(key)
            if isinstance(value, (int, float)):
                item[key] = value / VIDEO_SPEED
        events.append(item)
    return events


def first_start(events: list[dict[str, Any]], prefix: str, fallback: float) -> float:
    for event in events:
        if str(event.get("label", "")).startswith(prefix):
            value = event.get("start_s")
            if isinstance(value, (int, float)):
                return float(value)
    return fallback


def write_ass(duration: float, transcript: dict[str, Any]) -> None:
    events = scaled_events(transcript)
    first_patch = first_start(events, "ui.patch.", 4.0)
    first_midi = first_start(events, "track1_drums.play_sequence", 7.0)
    final_play = first_start(events, "final.ui_play", max(0.0, duration - 7.0))

    captions = [
        (0.6, min(first_patch + 2.0, duration - 0.4), "Fresh Logic project: the first visible track starts at 1."),
        (first_patch + 0.4, min(first_midi + 6.0, duration - 0.4), "Visible Logic Library choices are shown on screen. No hidden audio replacement."),
        (first_midi + 1.0, min(final_play - 1.0, duration - 0.4), "Verified product action here: logic_midi.play_sequence sends MIDI while Logic Record is armed."),
        (max(0.0, final_play - 3.0), min(duration - 0.4, final_play + 7.0), "Audio is intentionally absent: no verified Logic system audio or bounce was available."),
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


def write_manifest(raw_duration: float, duration: float, transcript: dict[str, Any]) -> None:
    manifest = {
        "demo": f"reddit-dudddee-fresh-truthful-ui-{DEMO_TAG}",
        "raw_video": str(RAW),
        "source_transcript": str(TRANSCRIPT),
        "rendered_video": str(OUT),
        "share_video": str(SHARE),
        "video_speed": VIDEO_SPEED,
        "raw_duration_s": raw_duration,
        "rendered_duration_s": duration,
        "fresh_baseline_screenshot": transcript.get("fresh_baseline_screenshot"),
        "final_screenshot": transcript.get("final_screenshot"),
        "audio_policy": "no_audio",
        "audio_sources_used": [],
        "forbidden_sources_not_used": [
            "Python synth_audio guide audio",
            "reference stems",
            "system audio not captured by ffmpeg avfoundation",
            "unverified Logic bounce/export",
        ],
        "discarded_inputs_not_used": [
            "/tmp/logic-v17-rich-techno-ui-raw.mp4",
            "docs/media/reddit-dudddee-rich-techno-ui-v18-truthful.mp4",
        ],
        "verified_claims": [
            "fresh Logic project baseline screenshot shows visible track number 1",
            "new v19 actual Logic Pro screen capture",
            "visible Logic Library patch choices performed during capture",
            "logic_midi.play_sequence responses are recorded in transcript",
        ],
        "not_claimed": [
            "actual Logic system audio",
            "verified Logic bounce/export",
            "MCP readback-verified patch assignment",
            "MCP readback-verified track creation",
        ],
        "source_states": transcript.get("states", {}),
        "source_event_count": transcript.get("event_count"),
    }
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")


def main() -> None:
    if not RAW.exists():
        raise SystemExit(f"Missing raw capture: {RAW}")
    if not TRANSCRIPT.exists():
        raise SystemExit(f"Missing transcript: {TRANSCRIPT}")

    transcript = json.loads(TRANSCRIPT.read_text(encoding="utf-8"))
    raw_duration = ffprobe_duration(RAW)
    duration = raw_duration / VIDEO_SPEED
    write_ass(duration, transcript)
    write_manifest(raw_duration, duration, transcript)

    run(
        [
            "ffmpeg",
            "-y",
            "-loglevel",
            "warning",
            "-i",
            str(RAW),
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
            "-an",
            str(OUT),
        ]
    )
    run(
        [
            "ffmpeg",
            "-y",
            "-loglevel",
            "error",
            "-ss",
            str(min(duration * 0.58, max(1.0, duration - 1.0))),
            "-i",
            str(OUT),
            "-frames:v",
            "1",
            str(THUMB),
        ]
    )
    SHARE.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(OUT, SHARE)
    print(f"rendered {OUT}")
    print(f"thumbnail {THUMB}")
    print(f"manifest {MANIFEST}")
    print(f"share {SHARE}")


if __name__ == "__main__":
    main()

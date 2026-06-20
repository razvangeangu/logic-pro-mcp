#!/usr/bin/env python3
"""Render a truthful v18 demo from the actual v17 Logic UI capture.

This version deliberately removes all post-produced/guide audio. The only
source media is the real Logic Pro screen recording plus captions that state
which parts are verified and which parts are not.
"""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
RAW = Path("/tmp/logic-v17-rich-techno-ui-raw.mp4")
TRANSCRIPT = ROOT / "docs/media/reddit-dudddee-rich-techno-ui-v17-transcript.json"
OUT = ROOT / "docs/media/reddit-dudddee-rich-techno-ui-v18-truthful.mp4"
THUMB = ROOT / "docs/media/reddit-dudddee-rich-techno-ui-v18-truthful-thumbnail.png"
ASS = ROOT / "docs/media/reddit-dudddee-rich-techno-ui-v18-truthful.ass"
MANIFEST = ROOT / "docs/media/reddit-dudddee-rich-techno-ui-v18-truthful-provenance.json"
SHARE = Path("/Users/isaac/.openclaw/workspace/out/reddit-dudddee-rich-techno-ui-v18-truthful.mp4")
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


def scale_transcript_events(transcript: dict[str, Any]) -> list[dict[str, Any]]:
    scaled = []
    for event in transcript.get("events", []):
        item = dict(event)
        for key in ("start_s", "end_s"):
            value = item.get(key)
            if isinstance(value, (int, float)):
                item[key] = value / VIDEO_SPEED
        scaled.append(item)
    return scaled


def ts(sec: float) -> str:
    sec = max(0.0, sec)
    h = int(sec // 3600)
    m = int((sec % 3600) // 60)
    s = int(sec % 60)
    cs = int((sec - int(sec)) * 100)
    return f"{h}:{m:02d}:{s:02d}.{cs:02d}"


def write_ass(duration: float, transcript: dict[str, Any]) -> None:
    events = scale_transcript_events(transcript)
    play_events = [e for e in events if str(e.get("label", "")).startswith("play_sequence.")]
    first_play = play_events[0]["start_s"] if play_events else 6.0
    last_play = play_events[-1]["end_s"] if play_events else min(duration - 8.0, 50.0)
    final_play = next((e["start_s"] for e in events if e.get("label") == "final.ui_play"), max(0.0, duration - 8.0))

    captions = [
        (0.6, min(first_play + 1.0, duration - 0.5), "Actual Logic Pro UI capture. No mock DAW. No synthetic audio."),
        (first_play + 0.7, min(first_play + 17.0, duration - 0.5), "Verified product action: logic_midi.play_sequence sends MIDI into Logic while Record is armed."),
        (first_play + 17.5, min(first_play + 45.0, duration - 0.5), "Not claimed as verified: track creation / patch assignment remain State B readback gaps."),
        (first_play + 45.5, min(last_play + 4.0, duration - 0.5), "11 MIDI layer writes are visible in the real Logic arrangement."),
        (max(0.0, final_play - 3.0), min(duration - 0.4, final_play + 8.0), "Audio intentionally muted: no verified Logic system audio or bounce was available."),
    ]

    lines = [
        "[Script Info]",
        "ScriptType: v4.00+",
        "PlayResX: 1920",
        "PlayResY: 1080",
        "",
        "[V4+ Styles]",
        "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding",
        "Style: Default,Helvetica,32,&H00F7F7F7,&H000000FF,&H9A000000,&HB0000000,0,0,0,0,100,100,0,0,1,2,0,2,80,80,54,1",
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
        "demo": "reddit-dudddee-rich-techno-ui-v18-truthful",
        "raw_video": str(RAW),
        "source_transcript": str(TRANSCRIPT),
        "rendered_video": str(OUT),
        "video_speed": VIDEO_SPEED,
        "raw_duration_s": raw_duration,
        "rendered_duration_s": duration,
        "audio_policy": "no_audio",
        "audio_sources_used": [],
        "forbidden_sources_not_used": [
            "/tmp/logic-v17-rich-techno-guide-audio.wav",
            "Python synth_audio guide audio",
            "reference stems",
        ],
        "verified_claims": [
            "actual Logic Pro screen capture",
            "actual Logic UI record/play/stop button interactions",
            "logic_midi.play_sequence returned ok for 11 layer writes",
        ],
        "not_claimed": [
            "actual Logic system audio",
            "verified Logic bounce/export",
            "verified distinct instrument or patch assignment",
            "verified track creation readback",
        ],
        "source_states": transcript.get("states", {}),
        "source_event_count": transcript.get("event_count"),
        "source_layer_count": transcript.get("layer_count"),
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
    run(["ffmpeg", "-y", "-loglevel", "error", "-ss", str(min(duration * 0.62, max(1.0, duration - 1.0))), "-i", str(OUT), "-frames:v", "1", str(THUMB)])
    SHARE.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(OUT, SHARE)
    print(f"rendered {OUT}")
    print(f"thumbnail {THUMB}")
    print(f"manifest {MANIFEST}")
    print(f"share {SHARE}")


if __name__ == "__main__":
    main()

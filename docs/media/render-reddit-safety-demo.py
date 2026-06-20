#!/usr/bin/env python3
"""Render a Reddit-facing safety-first Logic Pro MCP demo cut.

This video is intentionally based on the existing real Logic Pro 12.2 capture
instead of a synthetic DAW mockup. It loops that live capture and overlays a
short proof-oriented narrative for a working Logic user who wants to see the
tool in action without risking a production session.
"""

from __future__ import annotations

import subprocess
from pathlib import Path
from typing import Sequence

ROOT = Path(__file__).resolve().parents[2]
SOURCE_MP4 = ROOT / "docs/media/logic-pro-mcp-demo.mp4"
OUT_ASS = ROOT / "docs/media/reddit-dudddee-safety-demo.ass"
OUT_MP4 = ROOT / "docs/media/reddit-dudddee-safety-demo.mp4"
OUT_THUMB = ROOT / "docs/media/reddit-dudddee-safety-demo-thumbnail.png"

WIDTH = 1920
HEIGHT = 1080
DURATION_SECONDS = 62


EVENTS = [
    (
        "0:00:00.00",
        "0:00:05.00",
        "Title",
        "{\\pos(960,148)}Logic Pro MCP\\Nsafe first-look demo for a working Logic user",
    ),
    (
        "0:00:05.00",
        "0:00:11.00",
        "Caption",
        "{\\pos(960,870)}Real Logic Pro 12.2 screen capture. Not a DAW mockup.\\NThe MCP server runs locally; core control does not require\\Nuploading the project or audio.",
    ),
    (
        "0:00:11.00",
        "0:00:18.00",
        "Caption",
        "{\\pos(960,880)}I would not ask you to try this on a livelihood session first.\\NStart on a duplicate project or a disposable test session.",
    ),
    (
        "0:00:18.00",
        "0:00:26.00",
        "Caption",
        "{\\pos(960,862)}Use case 1: inspect before acting.\\NRead-only resources expose transport, tracks, mixer, project metadata,\\NMIDI ports, stock plugins, and workflow skills.",
    ),
    (
        "0:00:26.00",
        "0:00:34.00",
        "Caption",
        "{\\pos(960,862)}Before any risky write: fail-closed targets.\\NTrack, mixer, plugin, MIDI import, marker, and project operations\\Nrequire explicit targets and validation.",
    ),
    (
        "0:00:34.00",
        "0:00:42.00",
        "Caption",
        "{\\pos(960,862)}After a write: readback and provenance.\\NA command is not treated as success just because it was sent;\\Nit must be observed or reported as uncertain or failed.",
    ),
    (
        "0:00:42.00",
        "0:00:50.00",
        "Caption",
        "{\\pos(960,862)}Good first high-trust task: exact stock plugin insertion.\\NRequire an empty slot, insert only an allowlisted plugin,\\Nread the slot back, and rollback on mismatch.",
    ),
    (
        "0:00:50.00",
        "0:00:57.00",
        "Caption",
        "{\\pos(960,862)}What I would show in a longer Loom:\\Nduplicate project -> read state -> guarded action -> readback\\N-> cleanup or undo -> test evidence.",
    ),
    (
        "0:00:57.00",
        "0:01:02.00",
        "Footer",
        "{\\pos(960,905)}Not claiming production safety for every session yet.\\NThe goal is to earn trust by proving what happened, not by hiding uncertainty.",
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


def write_ass() -> None:
    lines = [
        "[Script Info]",
        "ScriptType: v4.00+",
        "Collisions: Normal",
        f"PlayResX: {WIDTH}",
        f"PlayResY: {HEIGHT}",
        "WrapStyle: 2",
        "ScaledBorderAndShadow: yes",
        "",
        "[V4+ Styles]",
        "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding",
        "Style: Title,Helvetica,58,&H00FFFFFF,&H000000FF,&HAA111111,&H80202020,1,0,0,0,100,100,0,0,3,16,0,8,120,120,38,1",
        "Style: Caption,Helvetica,38,&H00FFFFFF,&H000000FF,&HAA111111,&H70202020,0,0,0,0,100,100,0,0,3,14,0,2,150,150,78,1",
        "Style: Footer,Helvetica,38,&H00FFFFFF,&H000000FF,&HAA111111,&H70202020,0,0,0,0,100,100,0,0,3,14,0,2,170,170,78,1",
        "Style: Badge,Helvetica,26,&H00F2F2F2,&H000000FF,&HAA111111,&H80202020,0,0,0,0,100,100,0,0,3,10,0,7,34,34,34,1",
        "",
        "[Events]",
        "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text",
        "Dialogue: 2,0:00:00.00,0:01:02.00,Badge,,0,0,0,,{\\pos(44,42)}actual Logic Pro 12.2 capture",
        "Dialogue: 2,0:00:00.00,0:01:02.00,Badge,,0,0,0,,{\\pos(44,86)}local MCP server / no cloud audio upload",
    ]
    for start, end, style, text in EVENTS:
        lines.append(f"Dialogue: 3,{start},{end},{style},,0,0,0,,{text}")
    OUT_ASS.write_text("\n".join(lines) + "\n", encoding="utf-8")


def render_video() -> None:
    if not SOURCE_MP4.exists():
        raise SystemExit(f"Missing source capture: {SOURCE_MP4}")

    write_ass()
    run_checked(
        [
            "ffmpeg",
            "-y",
            "-loglevel",
            "error",
            "-stream_loop",
            "11",
            "-i",
            str(SOURCE_MP4),
            "-t",
            str(DURATION_SECONDS),
            "-vf",
            f"scale={WIDTH}:{HEIGHT}:flags=lanczos,eq=brightness=-0.055:saturation=0.96,ass={OUT_ASS}",
            "-an",
            "-pix_fmt",
            "yuv420p",
            "-movflags",
            "+faststart",
            str(OUT_MP4),
        ]
    )
    run_checked(
        [
            "ffmpeg",
            "-y",
            "-loglevel",
            "error",
            "-ss",
            "5",
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
            "stream=width,height,r_frame_rate",
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
    print(f"subtitle source {OUT_ASS}")


if __name__ == "__main__":
    render_video()

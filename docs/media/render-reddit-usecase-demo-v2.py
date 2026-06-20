#!/usr/bin/env python3
"""Render a polished Reddit/Loom-style use-case demo video.

This is a second pass for a working Logic user who asked for a video and said
they cannot risk a livelihood session. The cut uses the existing real Logic Pro
12.2 capture as the product surface and adds a separate proof panel rather than
covering the DAW with large captions.
"""

from __future__ import annotations

import subprocess
from pathlib import Path
from typing import Sequence

ROOT = Path(__file__).resolve().parents[2]
SOURCE_MP4 = ROOT / "docs/media/logic-pro-mcp-demo.mp4"
OUT_ASS = ROOT / "docs/media/reddit-dudddee-usecase-demo-v2.ass"
OUT_MP4 = ROOT / "docs/media/reddit-dudddee-usecase-demo-v2.mp4"
OUT_THUMB = ROOT / "docs/media/reddit-dudddee-usecase-demo-v2-thumbnail.png"

WIDTH = 1920
HEIGHT = 1080
DURATION_SECONDS = 96


def ts(seconds: int) -> str:
    minutes = seconds // 60
    rest = seconds % 60
    return f"0:{minutes:02d}:{rest:02d}.00"


SCENES = [
    (
        0,
        8,
        "TITLE",
        "For a working Logic user",
        "You asked for a video. I agree:\\Na DAW tool needs visible evidence,\\Nnot trust-me claims.",
        "This is a safety-first use-case cut,\\Nnot a promise to run on a live\\Nclient session today.",
    ),
    (
        8,
        18,
        "START SAFELY",
        "Duplicate/test project first",
        "I would not point this at\\Na livelihood session as\\Nthe first test.",
        "Good first target: a copied project,\\Nan old session, or a disposable\\NLogic file.",
    ),
    (
        18,
        31,
        "STEP 1",
        "Read before acting",
        "Read-only MCP resources expose\\Nhealth, project info, transport,\\Ntracks, mixer, MIDI ports,\\Nstock plugins, and workflow skills.",
        "First useful operation:\\Nwhat is in this session,\\Nand what looks risky?",
    ),
    (
        31,
        44,
        "STEP 2",
        "Plan before mutation",
        "A useful assistant should produce\\Na cleanup/export/routing plan\\Nbefore changing anything.",
        "If the plan is vague,\\Nthe tool should stay in planning mode\\Ninstead of touching Logic.",
    ),
    (
        44,
        58,
        "STEP 3",
        "Guarded action example",
        "Example: insert a stock Gain plugin\\Ninto an exact empty slot.",
        "The request must name the project path,\\Ntrack, insert slot, plugin identity,\\Nmode, and confirmation.",
    ),
    (
        58,
        72,
        "STEP 4",
        "Readback or no success",
        "The command is not considered\\Nsuccessful just because it was sent.",
        "It must read the slot back,\\Nconfirm the expected plugin, or report\\Nuncertainty/failure. Rollback on mismatch.",
    ),
    (
        72,
        84,
        "BOUNDARIES",
        "What this is not claiming",
        "Not production-safe for every\\NLogic version, locale, project shape,\\Nor plugin window yet.",
        "The point is to make the boundary\\Nvisible instead of hiding uncertainty\\Nbehind an AI demo.",
    ),
    (
        84,
        96,
        "NEXT LOOM",
        "The longer demo should show",
        "duplicate project -> read state\\N-> guarded action -> readback\\N-> cleanup/undo -> test evidence",
        "That is the bar: boring trust,\\Nlocal operation, and proof of\\Nwhat actually happened.",
    ),
]


STATIC_LINES = [
    ("Badge", 0, DURATION_SECONDS, "{\\pos(82,58)}actual Logic Pro 12.2 capture"),
    ("Badge", 0, DURATION_SECONDS, "{\\pos(82,96)}local MCP server / no cloud audio upload"),
    ("HeroTitle", 0, DURATION_SECONDS, "{\\pos(72,164)}Logic Pro MCP: safety-first use-case demo"),
    ("HeroSub", 0, DURATION_SECONDS, "{\\pos(72,206)}Built for the concern: \"Logic is my livelihood; I cannot have it crash or fail.\""),
    ("PanelKicker", 0, DURATION_SECONDS, "{\\pos(1392,260)}MCP safety flow"),
    ("Small", 0, DURATION_SECONDS, "{\\pos(92,982)}Real DAW footage is shown on the left. The proof panel explains the safe operating sequence."),
]


SCENE_DETAIL_LINES = {
    "START SAFELY": [
        "Suggested first test:",
        "- duplicate project",
        "- disposable session",
        "- no client deadline",
    ],
    "STEP 1": [
        "Read-only resources:",
        "logic://system/health",
        "logic://project/info",
        "logic://tracks",
        "logic://mixer",
    ],
    "STEP 2": [
        "Planning mode:",
        "- inspect state",
        "- list risks",
        "- propose small steps",
        "- ask before mutation",
    ],
    "STEP 3": [
        "Guarded write shape:",
        "project_expected_path",
        "track + exact insert",
        "allowlisted plugin",
        "confirmed mode",
    ],
    "STEP 4": [
        "Honest result:",
        "State A = confirmed",
        "State B = uncertain",
        "State C = failed",
        "no fake success",
    ],
    "BOUNDARIES": [
        "Current trust scope:",
        "- Logic Pro 12.2 evidence",
        "- local host testing",
        "- stock-plugin guardrails",
        "- more Loom proof needed",
    ],
    "NEXT LOOM": [
        "One clean proof run:",
        "1. duplicate",
        "2. read",
        "3. act",
        "4. verify",
        "5. cleanup",
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


def ass_dialog(style: str, start: int, end: int, text: str, layer: int = 3) -> str:
    return f"Dialogue: {layer},{ts(start)},{ts(end)},{style},,0,0,0,,{text}"


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
        "Style: Badge,Helvetica,25,&H00F2F2F2,&H000000FF,&H77101010,&H80101010,0,0,0,0,100,100,0,0,3,8,0,7,0,0,0,1",
        "Style: HeroTitle,Helvetica,44,&H00FFFFFF,&H000000FF,&H00101010,&H00000000,1,0,0,0,100,100,0,0,1,2,0,7,0,0,0,1",
        "Style: HeroSub,Helvetica,27,&H00DADDE2,&H000000FF,&H00101010,&H00000000,0,0,0,0,100,100,0,0,1,1,0,7,0,0,0,1",
        "Style: PanelKicker,Helvetica,25,&H0099D7FF,&H000000FF,&H00101010,&H00000000,1,0,0,0,100,100,0,0,1,1,0,7,0,0,0,1",
        "Style: SceneTag,Helvetica,24,&H007EE787,&H000000FF,&H00101010,&H00000000,1,0,0,0,100,100,0,0,1,1,0,7,0,0,0,1",
        "Style: SceneTitle,Helvetica,42,&H00FFFFFF,&H000000FF,&H00101010,&H00000000,1,0,0,0,100,100,0,0,1,1,0,7,0,0,0,1",
        "Style: SceneBody,Helvetica,29,&H00DADDE2,&H000000FF,&H00101010,&H00000000,0,0,0,0,100,100,0,0,1,1,0,7,0,0,0,1",
        "Style: SceneDetail,Menlo,24,&H00F0F6FC,&H000000FF,&H00101010,&H00000000,0,0,0,0,100,100,0,0,1,1,0,7,0,0,0,1",
        "Style: Small,Helvetica,23,&H00B8C0CC,&H000000FF,&H00101010,&H00000000,0,0,0,0,100,100,0,0,1,1,0,7,0,0,0,1",
        "Style: Progress,Helvetica,22,&H00FFFFFF,&H000000FF,&H00101010,&H00000000,1,0,0,0,100,100,0,0,1,1,0,7,0,0,0,1",
        "",
        "[Events]",
        "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text",
    ]

    for style, start, end, text in STATIC_LINES:
        lines.append(ass_dialog(style, start, end, text))

    for index, (start, end, tag, title, body, body2) in enumerate(SCENES, start=1):
        lines.append(ass_dialog("SceneTag", start, end, f"{{\\pos(1392,314)}}{tag}"))
        lines.append(ass_dialog("SceneTitle", start, end, f"{{\\pos(1392,368)}}{title}"))
        lines.append(ass_dialog("SceneBody", start, end, f"{{\\pos(1392,452)}}{body}\\N{body2}"))
        details = SCENE_DETAIL_LINES.get(tag)
        if details:
            escaped = "\\N".join(details)
            lines.append(ass_dialog("SceneDetail", start, end, f"{{\\pos(1392,672)}}{escaped}"))
        progress = f"scene {index} / {len(SCENES)}"
        lines.append(ass_dialog("Progress", start, end, f"{{\\pos(1392,910)}}{progress}"))

    OUT_ASS.write_text("\n".join(lines) + "\n", encoding="utf-8")


def render_video() -> None:
    if not SOURCE_MP4.exists():
        raise SystemExit(f"Missing source capture: {SOURCE_MP4}")

    write_ass()

    filter_complex = (
        f"[0:v]scale=1240:698:flags=lanczos,eq=brightness=-0.015:saturation=0.96[ui];"
        f"[1:v][ui]overlay=72:236:shortest=1[base];"
        f"[base]"
        f"drawbox=x=58:y=222:w=1268:h=726:color=white@0.18:t=2,"
        f"drawbox=x=1360:y=236:w=500:h=712:color=0x151a21@0.92:t=fill,"
        f"drawbox=x=1360:y=236:w=500:h=712:color=white@0.13:t=2,"
        f"drawbox=x=58:y=124:w=1802:h=88:color=0x151a21@0.94:t=fill,"
        f"drawbox=x=72:y=962:w=1240:h=48:color=0x151a21@0.74:t=fill,"
        f"ass={OUT_ASS}[out]"
    )

    run_checked(
        [
            "ffmpeg",
            "-y",
            "-loglevel",
            "error",
            "-stream_loop",
            "20",
            "-i",
            str(SOURCE_MP4),
            "-f",
            "lavfi",
            "-i",
            f"color=c=0x0d1117:s={WIDTH}x{HEIGHT}:r=24:d={DURATION_SECONDS}",
            "-filter_complex",
            filter_complex,
            "-map",
            "[out]",
            "-t",
            str(DURATION_SECONDS),
            "-r",
            "24",
            "-an",
            "-pix_fmt",
            "yuv420p",
            "-movflags",
            "+faststart",
            "-preset",
            "medium",
            "-crf",
            "21",
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
            "6",
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
            "stream=width,height,r_frame_rate,nb_frames",
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

#!/usr/bin/env python3
"""Maintain the README live Logic Pro demo media.

The README hero video is a real Logic Pro 12.2 screen recording, not a
synthetic DAW surface. This script validates the captured MP4 and regenerates
the GIF/thumbnail derivatives plus evidence artifacts from that MP4 so the
README stays tied to the actual Logic interface artifact.
"""

from __future__ import annotations

import json
from pathlib import Path

from demo_asset_guard import (
    ensure_no_extreme_frames,
    first_video_stream,
    probe_dimensions,
    probe_duration_s,
    probe_frame_rate,
    probe_media,
    read_signal_stats,
    render_contact_sheet,
    run_checked,
    select_valid_thumbnail,
    summarize_extreme_frames,
    validate_real_ui_only,
    write_evidence_manifest,
)

ROOT = Path(__file__).resolve().parents[2]
OUT_MP4 = ROOT / "docs/media/logic-pro-mcp-demo.mp4"
OUT_GIF = ROOT / "docs/media/logic-pro-mcp-demo.gif"
OUT_THUMB = ROOT / "docs/media/logic-pro-mcp-thumbnail.png"
OUT_CONTACT = ROOT / "docs/media/logic-pro-mcp-demo-contact-sheet.jpg"
OUT_EVIDENCE = ROOT / "docs/media/logic-pro-mcp-demo-evidence.json"
TRANSCRIPT = ROOT / "docs/media/logic-pro-mcp-demo-transcript.json"
BRIEF = ROOT / "docs/media/demo-brief.md"

GIF_FPS = 12
THUMBNAIL_CANDIDATES = [2.0, 2.5, 1.5, 3.0, 3.5]


def render_derivatives_from_live_capture() -> None:
    if not OUT_MP4.exists():
        raise SystemExit(
            f"{OUT_MP4} is missing. Recapture a live Logic Pro screen recording first."
        )
    if not TRANSCRIPT.exists():
        raise SystemExit(f"{TRANSCRIPT} is missing. Add the README demo transcript first.")

    transcript = json.loads(TRANSCRIPT.read_text(encoding="utf-8"))
    real_ui_attestation = validate_real_ui_only(transcript)

    probe = probe_media(OUT_MP4)
    stream = first_video_stream(probe)
    duration_s = probe_duration_s(probe)
    frame_rate = probe_frame_rate(probe)
    expected = {
        "width": 1920,
        "height": 1080,
        "r_frame_rate": "24/1",
        "duration": "6.000000",
    }
    observed = {
        "width": stream.get("width"),
        "height": stream.get("height"),
        "r_frame_rate": stream.get("r_frame_rate"),
        "duration": f"{duration_s:.6f}",
    }
    mismatches = {key: {"expected": expected[key], "observed": observed[key]} for key in expected if observed[key] != expected[key]}
    if mismatches:
        raise SystemExit(f"{OUT_MP4} does not match the live-capture spec: {mismatches}")

    frames = read_signal_stats(OUT_MP4)
    frame_duration_s = 1.0 / frame_rate
    black_scan = summarize_extreme_frames(frames, frame_duration_s=frame_duration_s, mode="black")
    white_scan = summarize_extreme_frames(frames, frame_duration_s=frame_duration_s, mode="white")
    ensure_no_extreme_frames(black_scan)
    ensure_no_extreme_frames(white_scan)

    palette = OUT_MP4.with_suffix(".palette.png")
    run_checked(
        [
            "ffmpeg",
            "-y",
            "-loglevel",
            "error",
            "-i",
            str(OUT_MP4),
            "-vf",
            f"fps={GIF_FPS},scale=920:-1:flags=lanczos,palettegen=stats_mode=diff",
            str(palette),
        ]
    )
    run_checked(
        [
            "ffmpeg",
            "-y",
            "-loglevel",
            "error",
            "-i",
            str(OUT_MP4),
            "-i",
            str(palette),
            "-lavfi",
            f"fps={GIF_FPS},scale=920:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle",
            "-loop",
            "0",
            str(OUT_GIF),
        ]
    )
    thumbnail = select_valid_thumbnail(
        OUT_MP4,
        OUT_THUMB,
        candidates_s=THUMBNAIL_CANDIDATES,
    )
    contact_sheet = render_contact_sheet(OUT_MP4, OUT_CONTACT, duration_s=duration_s)
    manifest = write_evidence_manifest(
        OUT_EVIDENCE,
        repo_root=ROOT,
        source_capture=OUT_MP4,
        brief_path=BRIEF,
        transcript_path=TRANSCRIPT,
        gif_path=OUT_GIF,
        thumbnail_path=OUT_THUMB,
        transcript=transcript,
        real_ui_attestation=real_ui_attestation,
        probe=probe,
        black_scan=black_scan,
        white_scan=white_scan,
        thumbnail=thumbnail,
        contact_sheet=contact_sheet,
    )
    palette.unlink(missing_ok=True)

    print(json.dumps({"probe_summary": observed}, ensure_ascii=False))
    print("black/white frame scans passed")
    print(f"thumbnail {thumbnail['selected']['timestamp_s']}s validated")
    print(f"rendered {OUT_GIF} from live Logic capture")
    print(f"rendered {OUT_THUMB} from live Logic capture")
    print(f"contact sheet {OUT_CONTACT}")
    print(f"evidence {OUT_EVIDENCE}")
    print(json.dumps({"thumbnail_dimensions": probe_dimensions(OUT_THUMB), "contact_sheet_dimensions": probe_dimensions(OUT_CONTACT), "audio_provenance": manifest["audio_provenance"]}, ensure_ascii=False))


if __name__ == "__main__":
    render_derivatives_from_live_capture()

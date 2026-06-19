#!/usr/bin/env python3
"""Fail-closed verification for Logic Bounce / export audio used in public demos."""

from __future__ import annotations

import argparse
import json
import math
import re
import subprocess
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
PUBLIC_READY_POLICIES = {
    "verified_logic_bounce_looped_under_edit",
    "verified_logic_export_looped_under_edit",
    "verified_logic_bounce_direct",
    "verified_logic_export_direct",
}
DEFAULT_FORBIDDEN_SOURCES = [
    "/tmp/logic-v17-rich-techno-guide-audio.wav",
    "Python synth_audio guide audio",
    "reference stems",
    "system output capture",
]
LOUDNESS_FLOOR_LUFS = -60.0
VOLUME_FLOOR_DB = -60.0
LOUDNORM_JSON = re.compile(r"\{\s*\"input_i\".*?\}", re.S)
FFPROBE_CMD = [
    "ffprobe",
    "-v",
    "error",
    "-show_entries",
    "stream=codec_name,codec_type,sample_rate,channels",
    "-show_entries",
    "format=duration",
    "-of",
    "json",
]


def repo_relative(path: Path) -> str:
    resolved = path.resolve()
    try:
        return str(resolved.relative_to(ROOT))
    except ValueError:
        return str(path)


def run_checked(cmd: list[str]) -> str:
    proc = subprocess.run(cmd, text=True, capture_output=True)
    if proc.returncode != 0:
        raise RuntimeError(
            f"command failed ({proc.returncode}): {' '.join(cmd)}\n{proc.stdout}{proc.stderr}"
        )
    return proc.stdout + proc.stderr


def parse_float(value: Any) -> float:
    text = str(value).strip()
    if text in {"-inf", "inf", "nan"}:
        return math.nan
    return float(text)


def probe_audio(path: Path) -> dict[str, Any]:
    payload = json.loads(run_checked([*FFPROBE_CMD, str(path)]))
    streams = payload.get("streams", [])
    audio_stream = next(
        (stream for stream in streams if stream.get("codec_type") == "audio"),
        None,
    )
    if audio_stream is None:
        raise ValueError(f"{path} does not contain an audio stream")
    duration = parse_float(payload["format"]["duration"])
    return {
        "codec_name": audio_stream.get("codec_name", "unknown"),
        "sample_rate_hz": int(audio_stream.get("sample_rate", 0)),
        "channels": int(audio_stream.get("channels", 0)),
        "duration_s": duration,
    }


def measure_loudness(path: Path) -> dict[str, float]:
    output = run_checked(
        [
            "ffmpeg",
            "-hide_banner",
            "-nostats",
            "-i",
            str(path),
            "-af",
            "loudnorm=I=-16:TP=-1.5:LRA=11:print_format=json",
            "-f",
            "null",
            "-",
        ]
    )
    match = LOUDNORM_JSON.search(output)
    if match is None:
        raise ValueError(f"Could not parse loudnorm output for {path}")
    payload = json.loads(match.group(0))
    return {
        "integrated_lufs": parse_float(payload["input_i"]),
        "true_peak_dbtp": parse_float(payload["input_tp"]),
        "loudness_range_lu": parse_float(payload["input_lra"]),
        "threshold_lufs": parse_float(payload["input_thresh"]),
    }


def measure_volume(path: Path) -> dict[str, float]:
    output = run_checked(
        [
            "ffmpeg",
            "-hide_banner",
            "-nostats",
            "-i",
            str(path),
            "-af",
            "volumedetect",
            "-f",
            "null",
            "-",
        ]
    )
    mean_match = re.search(r"mean_volume:\s*([-\d.]+)\s*dB", output)
    max_match = re.search(r"max_volume:\s*([-\d.]+)\s*dB", output)
    if mean_match is None or max_match is None:
        raise ValueError(f"Could not parse volumedetect output for {path}")
    return {
        "mean_volume_db": float(mean_match.group(1)),
        "max_volume_db": float(max_match.group(1)),
    }


def verify_logic_bounce_audio(
    audio_path: Path,
    *,
    expected_duration_s: float | None,
    duration_tolerance_s: float = 0.25,
) -> dict[str, Any]:
    probe = probe_audio(audio_path)
    loudness = measure_loudness(audio_path)
    volume = measure_volume(audio_path)

    duration_s = probe["duration_s"]
    duration_delta_s = (
        abs(duration_s - expected_duration_s) if expected_duration_s is not None else None
    )
    duration_within_tolerance = (
        duration_delta_s is None or duration_delta_s <= duration_tolerance_s
    )
    non_silent = (
        math.isfinite(loudness["integrated_lufs"])
        and loudness["integrated_lufs"] > LOUDNESS_FLOOR_LUFS
        and math.isfinite(volume["max_volume_db"])
        and volume["max_volume_db"] > VOLUME_FLOOR_DB
    )

    errors: list[str] = []
    if probe["sample_rate_hz"] <= 0:
        errors.append("sample_rate_unreadable")
    if probe["channels"] <= 0:
        errors.append("channel_count_unreadable")
    if not duration_within_tolerance:
        errors.append(
            f"duration_mismatch expected={expected_duration_s:.3f}s observed={duration_s:.3f}s"
        )
    if not non_silent:
        errors.append(
            "audio_is_silent_or_too_quiet "
            f"(integrated={loudness['integrated_lufs']:.2f} LUFS, max={volume['max_volume_db']:.2f} dB)"
        )

    verification = {
        "verification_passed": not errors,
        "checked_by": "docs/media/logic_bounce_guard.py",
        "codec_name": probe["codec_name"],
        "sample_rate_hz": probe["sample_rate_hz"],
        "channels": probe["channels"],
        "duration_s": duration_s,
        "expected_duration_s": expected_duration_s,
        "duration_tolerance_s": duration_tolerance_s,
        "duration_delta_s": duration_delta_s,
        "duration_within_tolerance": duration_within_tolerance,
        "integrated_lufs": loudness["integrated_lufs"],
        "true_peak_dbtp": loudness["true_peak_dbtp"],
        "loudness_range_lu": loudness["loudness_range_lu"],
        "threshold_lufs": loudness["threshold_lufs"],
        "mean_volume_db": volume["mean_volume_db"],
        "max_volume_db": volume["max_volume_db"],
        "non_silent": non_silent,
        "errors": errors,
    }
    if errors:
        raise ValueError("; ".join(errors))
    return verification


def build_verified_bounce_manifest(
    *,
    demo: str,
    audio_path: Path,
    audio_policy: str,
    expected_duration_s: float | None,
    duration_tolerance_s: float = 0.25,
    transcript_path: Path | None = None,
    raw_video: Path | None = None,
    rendered_video: Path | None = None,
    video_speed: float | None = None,
    raw_duration_s: float | None = None,
    rendered_duration_s: float | None = None,
    extra_verified_claims: list[str] | None = None,
    not_claimed: list[str] | None = None,
    forbidden_sources_not_used: list[str] | None = None,
    require_public_demo_ready: bool = True,
) -> dict[str, Any]:
    verification = verify_logic_bounce_audio(
        audio_path,
        expected_duration_s=expected_duration_s,
        duration_tolerance_s=duration_tolerance_s,
    )
    transcript = {}
    if transcript_path and transcript_path.exists():
        transcript = json.loads(transcript_path.read_text(encoding="utf-8"))

    public_demo_audio_ready = audio_policy in PUBLIC_READY_POLICIES
    if require_public_demo_ready and not public_demo_audio_ready:
        raise ValueError(f"Audio policy {audio_policy!r} is not public-demo ready")

    manifest: dict[str, Any] = {
        "demo": demo,
        "logic_bounce_audio": repo_relative(audio_path),
        "audio_policy": audio_policy,
        "audio_sources_used": [repo_relative(audio_path)],
        "forbidden_sources_not_used": forbidden_sources_not_used or DEFAULT_FORBIDDEN_SOURCES,
        "public_demo_audio_ready": public_demo_audio_ready,
        "audio_verification": verification,
        "verified_claims": extra_verified_claims or [],
        "not_claimed": not_claimed or [],
        "source_states": transcript.get("states", {}),
        "source_event_count": transcript.get("event_count"),
    }
    if transcript_path is not None:
        manifest["source_transcript"] = repo_relative(transcript_path)
    if raw_video is not None:
        manifest["raw_video"] = repo_relative(raw_video)
    if rendered_video is not None:
        manifest["rendered_video"] = repo_relative(rendered_video)
    if video_speed is not None:
        manifest["video_speed"] = video_speed
    if raw_duration_s is not None:
        manifest["raw_duration_s"] = raw_duration_s
    if rendered_duration_s is not None:
        manifest["rendered_duration_s"] = rendered_duration_s
    return manifest


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Verify a Logic Bounce/export audio file and optionally write a provenance manifest."
    )
    parser.add_argument("--demo", required=True)
    parser.add_argument("--audio", required=True, type=Path)
    parser.add_argument("--audio-policy", required=True)
    parser.add_argument("--expected-duration", required=True, type=float)
    parser.add_argument("--duration-tolerance", type=float, default=0.25)
    parser.add_argument("--transcript", type=Path)
    parser.add_argument("--raw-video", type=Path)
    parser.add_argument("--rendered-video", type=Path)
    parser.add_argument("--video-speed", type=float)
    parser.add_argument("--raw-duration", type=float)
    parser.add_argument("--rendered-duration", type=float)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--verified-claim", action="append", default=[])
    parser.add_argument("--not-claimed", action="append", default=[])
    parser.add_argument("--forbidden-source", action="append", default=[])
    parser.add_argument(
        "--allow-non-public-policy",
        action="store_true",
        help="Do not fail when the supplied audio policy is not public-demo ready.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    manifest = build_verified_bounce_manifest(
        demo=args.demo,
        audio_path=args.audio,
        audio_policy=args.audio_policy,
        expected_duration_s=args.expected_duration,
        duration_tolerance_s=args.duration_tolerance,
        transcript_path=args.transcript,
        raw_video=args.raw_video,
        rendered_video=args.rendered_video,
        video_speed=args.video_speed,
        raw_duration_s=args.raw_duration,
        rendered_duration_s=args.rendered_duration,
        extra_verified_claims=args.verified_claim,
        not_claimed=args.not_claimed,
        forbidden_sources_not_used=args.forbidden_source or None,
        require_public_demo_ready=not args.allow_non_public_policy,
    )
    payload = json.dumps(manifest, ensure_ascii=False, indent=2) + "\n"
    if args.manifest is not None:
        args.manifest.write_text(payload, encoding="utf-8")
    sys.stdout.write(payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

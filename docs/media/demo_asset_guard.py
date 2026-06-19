#!/usr/bin/env python3
"""Shared validation helpers for public Logic Pro demo assets."""

from __future__ import annotations

import json
import math
import subprocess
import tempfile
from copy import deepcopy
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Sequence

BLACK_FRAME_MAX_YHIGH = 24.0
BLACK_FRAME_MAX_YAVG = 8.0
WHITE_FRAME_MIN_YLOW = 235.0
WHITE_FRAME_MIN_YAVG = 245.0
CONTACT_SHEET_COLUMNS = 3


def run_checked(cmd: Sequence[str]) -> str:
    proc = subprocess.run(cmd, text=True, capture_output=True)
    if proc.returncode != 0:
        raise RuntimeError(
            f"command failed ({proc.returncode}): {' '.join(cmd)}\n{proc.stdout}\n{proc.stderr}"
        )
    return proc.stdout + proc.stderr


def load_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise RuntimeError(f"{path} must contain a top-level JSON object")
    return value


def probe_media(path: Path) -> dict[str, Any]:
    return load_probe_json(
        run_checked(
            [
                "ffprobe",
                "-v",
                "error",
                "-show_streams",
                "-show_format",
                "-print_format",
                "json",
                str(path),
            ]
        )
    )


def load_probe_json(payload: str) -> dict[str, Any]:
    value = json.loads(payload)
    if not isinstance(value, dict):
        raise RuntimeError("ffprobe payload was not a JSON object")
    return value


def first_video_stream(probe: dict[str, Any]) -> dict[str, Any]:
    streams = probe.get("streams")
    if not isinstance(streams, list):
        raise RuntimeError("ffprobe stream list missing")
    for stream in streams:
        if isinstance(stream, dict) and stream.get("codec_type") == "video":
            return stream
    raise RuntimeError("video stream missing from ffprobe output")


def first_audio_stream(probe: dict[str, Any]) -> dict[str, Any] | None:
    streams = probe.get("streams")
    if not isinstance(streams, list):
        return None
    for stream in streams:
        if isinstance(stream, dict) and stream.get("codec_type") == "audio":
            return stream
    return None


def parse_ratio(value: str) -> float:
    numerator, denominator = value.split("/", 1)
    num = float(numerator)
    den = float(denominator)
    if den == 0:
        raise RuntimeError(f"invalid ratio with zero denominator: {value}")
    return num / den


def probe_duration_s(probe: dict[str, Any]) -> float:
    fmt = probe.get("format")
    if not isinstance(fmt, dict):
        raise RuntimeError("ffprobe format section missing")
    duration = fmt.get("duration")
    if duration is None:
        raise RuntimeError("ffprobe format.duration missing")
    return float(duration)


def probe_frame_rate(probe: dict[str, Any]) -> float:
    stream = first_video_stream(probe)
    raw = stream.get("r_frame_rate") or stream.get("avg_frame_rate")
    if not isinstance(raw, str):
        raise RuntimeError("video frame rate missing from ffprobe output")
    return parse_ratio(raw)


def probe_dimensions(path: Path) -> dict[str, int]:
    raw = run_checked(["sips", "-g", "pixelWidth", "-g", "pixelHeight", str(path)])
    values: dict[str, int] = {}
    for line in raw.splitlines():
        line = line.strip()
        if line.startswith("pixelWidth:"):
            values["pixelWidth"] = int(line.split(":", 1)[1].strip())
        elif line.startswith("pixelHeight:"):
            values["pixelHeight"] = int(line.split(":", 1)[1].strip())
    if "pixelWidth" not in values or "pixelHeight" not in values:
        raise RuntimeError(f"unable to read image dimensions for {path}")
    return values


def read_signal_stats(path: Path, *, limit_frames: int | None = None) -> list[dict[str, Any]]:
    cmd = [
        "ffmpeg",
        "-v",
        "error",
        "-i",
        str(path),
        "-vf",
        "signalstats,metadata=mode=print:file=-",
    ]
    if limit_frames is not None:
        cmd.extend(["-frames:v", str(limit_frames)])
    cmd.extend(["-an", "-f", "null", "-"])
    raw = run_checked(cmd)

    frames: list[dict[str, Any]] = []
    current: dict[str, Any] | None = None
    for line in raw.splitlines():
        line = line.strip()
        if not line:
            continue
        if line.startswith("frame:"):
            if current is not None:
                frames.append(current)
            parts = line.split()
            current = {"index": int(parts[0].split(":", 1)[1])}
            for part in parts[1:]:
                if ":" not in part:
                    continue
                key, value = part.split(":", 1)
                if key == "pts_time":
                    current["pts_time"] = float(value)
        elif line.startswith("lavfi.signalstats.") and current is not None:
            key, value = line.split("=", 1)
            stat_name = key.split(".", 2)[-1]
            current[stat_name] = float(value)
    if current is not None:
        frames.append(current)
    if not frames:
        raise RuntimeError(f"ffmpeg signalstats returned no frames for {path}")
    return frames


def _extreme_kind(frame: dict[str, Any]) -> str | None:
    yavg = float(frame.get("YAVG", 0.0))
    yhigh = float(frame.get("YHIGH", 0.0))
    ylow = float(frame.get("YLOW", 0.0))
    if yhigh <= BLACK_FRAME_MAX_YHIGH or yavg <= BLACK_FRAME_MAX_YAVG:
        return "black"
    if ylow >= WHITE_FRAME_MIN_YLOW or yavg >= WHITE_FRAME_MIN_YAVG:
        return "white"
    return None


def summarize_extreme_frames(
    frames: list[dict[str, Any]],
    *,
    frame_duration_s: float,
    mode: str,
) -> dict[str, Any]:
    events: list[dict[str, Any]] = []
    current: dict[str, Any] | None = None

    for frame in frames:
        detected = _extreme_kind(frame)
        if detected != mode:
            if current is not None:
                current["end_s"] = round(current["last_pts_time"] + frame_duration_s, 6)
                current["duration_s"] = round(current["end_s"] - current["start_s"], 6)
                current.pop("last_pts_time", None)
                events.append(current)
                current = None
            continue

        pts_time = float(frame.get("pts_time", 0.0))
        if current is None:
            current = {
                "start_s": round(pts_time, 6),
                "last_pts_time": pts_time,
                "frames": 1,
                "peak_yavg": float(frame.get("YAVG", 0.0)),
            }
            continue

        current["last_pts_time"] = pts_time
        current["frames"] += 1
        current["peak_yavg"] = max(current["peak_yavg"], float(frame.get("YAVG", 0.0)))

    if current is not None:
        current["end_s"] = round(current["last_pts_time"] + frame_duration_s, 6)
        current["duration_s"] = round(current["end_s"] - current["start_s"], 6)
        current.pop("last_pts_time", None)
        events.append(current)

    return {
        "mode": mode,
        "thresholds": {
            "black_frame_max_yhigh": BLACK_FRAME_MAX_YHIGH,
            "black_frame_max_yavg": BLACK_FRAME_MAX_YAVG,
            "white_frame_min_ylow": WHITE_FRAME_MIN_YLOW,
            "white_frame_min_yavg": WHITE_FRAME_MIN_YAVG,
        },
        "event_count": len(events),
        "events": events,
    }


def ensure_no_extreme_frames(scan: dict[str, Any]) -> None:
    if scan.get("event_count", 0):
        raise RuntimeError(
            f"{scan['mode']} frame scan detected {scan['event_count']} event(s): {scan['events']}"
        )


def validate_real_ui_only(transcript: dict[str, Any]) -> dict[str, Any]:
    surface_mode = transcript.get("surface_mode")
    source_capture_kind = transcript.get("source_capture_kind")
    if surface_mode != "real-ui-only":
        raise RuntimeError(
            f"transcript surface_mode must be 'real-ui-only' (got {surface_mode!r})"
        )
    if source_capture_kind != "actual_logic_capture":
        raise RuntimeError(
            "transcript source_capture_kind must be 'actual_logic_capture' "
            f"(got {source_capture_kind!r})"
        )
    truth_boundaries = transcript.get("truth_boundaries")
    if not isinstance(truth_boundaries, dict):
        raise RuntimeError("transcript truth_boundaries missing")
    return {
        "surface_mode": surface_mode,
        "source_capture_kind": source_capture_kind,
        "audio_policy": transcript.get("audio_policy"),
        "truth_boundaries": truth_boundaries,
    }


def select_valid_thumbnail(
    video_path: Path,
    output_path: Path,
    *,
    candidates_s: Sequence[float],
) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="logic-demo-thumb.") as tmpdir:
        evaluations: list[dict[str, Any]] = []
        tmpdir_path = Path(tmpdir)
        for index, candidate_s in enumerate(candidates_s):
            frame_path = tmpdir_path / f"candidate-{index}.png"
            run_checked(
                [
                    "ffmpeg",
                    "-y",
                    "-loglevel",
                    "error",
                    "-ss",
                    f"{candidate_s:.3f}",
                    "-i",
                    str(video_path),
                    "-frames:v",
                    "1",
                    "-vf",
                    "scale=1280:720:flags=lanczos",
                    str(frame_path),
                ]
            )
            stats = read_signal_stats(frame_path, limit_frames=1)[0]
            evaluation = {
                "timestamp_s": round(candidate_s, 3),
                "stats": {
                    key: round(float(stats.get(key, 0.0)), 3)
                    for key in ("YLOW", "YAVG", "YHIGH", "SATAVG")
                },
                "extreme": _extreme_kind(stats),
            }
            evaluations.append(evaluation)
            if evaluation["extreme"] is None:
                output_path.parent.mkdir(parents=True, exist_ok=True)
                frame_path.replace(output_path)
                evaluation["selected"] = True
                evaluation["dimensions"] = probe_dimensions(output_path)
                return {"selected": evaluation, "evaluations": evaluations}

    raise RuntimeError(f"no safe thumbnail candidate found: {evaluations}")


def render_contact_sheet(
    video_path: Path,
    output_path: Path,
    *,
    duration_s: float,
    sample_count: int = 6,
) -> dict[str, Any]:
    fps = sample_count / max(duration_s, 0.1)
    rows = math.ceil(sample_count / CONTACT_SHEET_COLUMNS)
    run_checked(
        [
            "ffmpeg",
            "-y",
            "-loglevel",
            "error",
            "-i",
            str(video_path),
            "-vf",
            (
                f"fps={fps:.6f},"
                "scale=640:-1:flags=lanczos,"
                f"tile={CONTACT_SHEET_COLUMNS}x{rows}"
            ),
            "-frames:v",
            "1",
            str(output_path),
        ]
    )
    return {
        "path": str(output_path),
        "sample_count": sample_count,
        "columns": CONTACT_SHEET_COLUMNS,
        "dimensions": probe_dimensions(output_path),
    }


def repo_relative_path(path: Path, repo_root: Path) -> str:
    try:
        return str(path.resolve().relative_to(repo_root.resolve()))
    except ValueError:
        return str(path)


def write_evidence_manifest(
    evidence_path: Path,
    *,
    repo_root: Path,
    source_capture: Path,
    brief_path: Path,
    transcript_path: Path,
    gif_path: Path,
    thumbnail_path: Path,
    transcript: dict[str, Any],
    real_ui_attestation: dict[str, Any],
    probe: dict[str, Any],
    black_scan: dict[str, Any],
    white_scan: dict[str, Any],
    thumbnail: dict[str, Any],
    contact_sheet: dict[str, Any],
) -> dict[str, Any]:
    audio_stream = first_audio_stream(probe)
    sanitized_probe = deepcopy(probe)
    fmt = sanitized_probe.get("format")
    if isinstance(fmt, dict) and fmt.get("filename") == str(source_capture):
        fmt["filename"] = repo_relative_path(source_capture, repo_root)
    relative_contact_sheet = dict(contact_sheet)
    relative_contact_sheet["path"] = repo_relative_path(Path(contact_sheet["path"]), repo_root)
    manifest = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "source_capture": repo_relative_path(source_capture, repo_root),
        "brief": repo_relative_path(brief_path, repo_root),
        "transcript": repo_relative_path(transcript_path, repo_root),
        "derivatives": {
            "gif": repo_relative_path(gif_path, repo_root),
            "thumbnail": repo_relative_path(thumbnail_path, repo_root),
            "contact_sheet": repo_relative_path(Path(contact_sheet["path"]), repo_root),
        },
        "surface_mode": real_ui_attestation["surface_mode"],
        "source_capture_kind": real_ui_attestation["source_capture_kind"],
        "audio_provenance": transcript.get("audio_provenance"),
        "ffprobe_audio_stream": audio_stream,
        "ffprobe": sanitized_probe,
        "black_frame_scan": black_scan,
        "white_frame_scan": white_scan,
        "thumbnail_validation": thumbnail,
        "contact_sheet": relative_contact_sheet,
    }
    evidence_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return manifest

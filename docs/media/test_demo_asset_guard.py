#!/usr/bin/env python3
"""Smoke tests for demo asset validation helpers."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from demo_asset_guard import (
    ensure_no_extreme_frames,
    load_json,
    probe_media,
    probe_duration_s,
    probe_frame_rate,
    read_signal_stats,
    render_contact_sheet,
    select_valid_thumbnail,
    summarize_extreme_frames,
    validate_real_ui_only,
)


ROOT = Path(__file__).resolve().parent
README_MP4 = ROOT / "logic-pro-mcp-demo.mp4"
README_TRANSCRIPT = ROOT / "logic-pro-mcp-demo-transcript.json"


class DemoAssetGuardTests(unittest.TestCase):
    def make_color_clip(self, directory: Path, color: str, name: str) -> Path:
        out = directory / name
        import subprocess

        subprocess.run(
            [
                "ffmpeg",
                "-y",
                "-loglevel",
                "error",
                "-f",
                "lavfi",
                "-i",
                f"color=c={color}:s=64x64:d=1",
                "-r",
                "24",
                str(out),
            ],
            check=True,
        )
        return out

    def test_black_clip_scan_detects_black_frames(self) -> None:
        with tempfile.TemporaryDirectory(prefix="logic-demo-test.") as tmpdir:
            clip = self.make_color_clip(Path(tmpdir), "black", "black.mp4")
            probe = probe_media(clip)
            frames = read_signal_stats(clip)
            scan = summarize_extreme_frames(
                frames,
                frame_duration_s=1.0 / probe_frame_rate(probe),
                mode="black",
            )
            self.assertGreater(scan["event_count"], 0)
            with self.assertRaises(RuntimeError):
                ensure_no_extreme_frames(scan)

    def test_white_clip_scan_detects_white_frames(self) -> None:
        with tempfile.TemporaryDirectory(prefix="logic-demo-test.") as tmpdir:
            clip = self.make_color_clip(Path(tmpdir), "white", "white.mp4")
            probe = probe_media(clip)
            frames = read_signal_stats(clip)
            scan = summarize_extreme_frames(
                frames,
                frame_duration_s=1.0 / probe_frame_rate(probe),
                mode="white",
            )
            self.assertGreater(scan["event_count"], 0)
            with self.assertRaises(RuntimeError):
                ensure_no_extreme_frames(scan)

    def test_real_readme_asset_stays_clean(self) -> None:
        transcript = load_json(README_TRANSCRIPT)
        attestation = validate_real_ui_only(transcript)
        self.assertEqual(attestation["surface_mode"], "real-ui-only")

        probe = probe_media(README_MP4)
        duration_s = probe_duration_s(probe)
        frame_duration_s = 1.0 / probe_frame_rate(probe)
        frames = read_signal_stats(README_MP4)

        black_scan = summarize_extreme_frames(frames, frame_duration_s=frame_duration_s, mode="black")
        white_scan = summarize_extreme_frames(frames, frame_duration_s=frame_duration_s, mode="white")
        ensure_no_extreme_frames(black_scan)
        ensure_no_extreme_frames(white_scan)

        with tempfile.TemporaryDirectory(prefix="logic-demo-test.") as tmpdir:
            tmpdir_path = Path(tmpdir)
            thumb = select_valid_thumbnail(
                README_MP4,
                tmpdir_path / "thumb.png",
                candidates_s=[2.0, 2.5, 1.5, 3.0],
            )
            self.assertEqual(thumb["selected"]["extreme"], None)
            contact = render_contact_sheet(
                README_MP4,
                tmpdir_path / "contact.jpg",
                duration_s=duration_s,
            )
            self.assertEqual(contact["sample_count"], 6)


if __name__ == "__main__":
    unittest.main()

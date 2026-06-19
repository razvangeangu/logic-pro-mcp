#!/usr/bin/env python3
"""Smoke coverage for Logic bounce verification."""

from __future__ import annotations

import tempfile
import subprocess
import unittest
from pathlib import Path

from logic_bounce_guard import build_verified_bounce_manifest, verify_logic_bounce_audio


def run_checked(cmd: list[str]) -> None:
    subprocess.run(cmd, check=True, capture_output=True, text=True)


def synth_tone(path: Path, duration_s: float) -> None:
    run_checked(
        [
            "ffmpeg",
            "-y",
            "-loglevel",
            "error",
            "-f",
            "lavfi",
            "-i",
            f"sine=frequency=220:sample_rate=48000:duration={duration_s}",
            "-ac",
            "2",
            "-c:a",
            "pcm_s24be",
            str(path),
        ]
    )


def synth_silence(path: Path, duration_s: float) -> None:
    run_checked(
        [
            "ffmpeg",
            "-y",
            "-loglevel",
            "error",
            "-f",
            "lavfi",
            "-i",
            "anullsrc=r=48000:cl=stereo",
            "-t",
            str(duration_s),
            "-c:a",
            "pcm_s24be",
            str(path),
        ]
    )


class LogicBounceGuardTests(unittest.TestCase):
    def test_tone_passes_duration_and_loudness_checks(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            audio = Path(tmpdir) / "tone.aif"
            synth_tone(audio, 2.0)

            verification = verify_logic_bounce_audio(
                audio,
                expected_duration_s=2.0,
                duration_tolerance_s=0.05,
            )

            self.assertTrue(verification["verification_passed"])
            self.assertTrue(verification["non_silent"])
            self.assertEqual(verification["channels"], 2)
            self.assertEqual(verification["sample_rate_hz"], 48000)

    def test_silence_fails_non_silence_guard(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            audio = Path(tmpdir) / "silence.aif"
            synth_silence(audio, 2.0)

            with self.assertRaisesRegex(ValueError, "audio_is_silent_or_too_quiet"):
                verify_logic_bounce_audio(
                    audio,
                    expected_duration_s=2.0,
                    duration_tolerance_s=0.05,
                )

    def test_duration_mismatch_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            audio = Path(tmpdir) / "tone.aif"
            synth_tone(audio, 2.0)

            with self.assertRaisesRegex(ValueError, "duration_mismatch"):
                verify_logic_bounce_audio(
                    audio,
                    expected_duration_s=4.0,
                    duration_tolerance_s=0.05,
                )

    def test_non_public_policy_is_not_marked_ready(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            audio = Path(tmpdir) / "tone.aif"
            synth_tone(audio, 2.0)

            manifest = build_verified_bounce_manifest(
                demo="fixture-guide-audio",
                audio_path=audio,
                audio_policy="explicitly_labeled_guide_audio",
                expected_duration_s=2.0,
                duration_tolerance_s=0.05,
                require_public_demo_ready=False,
            )

            self.assertFalse(manifest["public_demo_audio_ready"])
            self.assertEqual(manifest["audio_policy"], "explicitly_labeled_guide_audio")


if __name__ == "__main__":
    unittest.main()

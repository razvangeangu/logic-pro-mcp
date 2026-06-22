#!/usr/bin/env python3
"""Tests for the demo render gate helpers (issues #129, #130, #137)."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from demo_render_gates import (
    DEFAULT_REQUIRED_GATES,
    DemoGatesRejected,
    compute_logic_crop,
    crop_is_within_logic_bounds,
    derive_run_issue_coverage,
    enforce_demo_reject_gates,
    evaluate_reject_gates,
    load_run_issue_numbers,
    quarantine_rejected_video,
)


class RejectGateTests(unittest.TestCase):
    """#129: required gates must be fatal."""

    def _all_pass(self) -> dict[str, bool]:
        return {key: True for key in DEFAULT_REQUIRED_GATES}

    def test_all_gates_pass_does_not_raise(self) -> None:
        self.assertEqual(enforce_demo_reject_gates(self._all_pass()), [])

    def test_failed_bounce_guard_is_fatal(self) -> None:
        gates = self._all_pass()
        gates["logic_bounce_guard_returncode_0"] = False
        with self.assertRaises(DemoGatesRejected) as ctx:
            enforce_demo_reject_gates(gates)
        self.assertIn("logic_bounce_guard_returncode_0", ctx.exception.rejected)
        self.assertNotEqual(ctx.exception.code, 0)

    def test_failed_audio_analyze_is_fatal(self) -> None:
        gates = self._all_pass()
        gates["logic_audio_analyze_status_not_fail"] = False
        rejected = evaluate_reject_gates(gates)
        self.assertEqual(rejected, ["logic_audio_analyze_status_not_fail"])

    def test_missing_required_gate_counts_as_rejected(self) -> None:
        # An unmeasured required gate is never an implicit pass.
        gates = self._all_pass()
        del gates["arrangement_gate_pass"]
        self.assertIn("arrangement_gate_pass", evaluate_reject_gates(gates))

    def test_extra_true_gate_does_not_break_enforcement(self) -> None:
        gates = self._all_pass()
        gates["screen_capture_logic_window_visible"] = True
        self.assertEqual(enforce_demo_reject_gates(gates), [])

    def test_quarantine_renames_rejected_video(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            video = Path(tmp) / "demo.mp4"
            video.write_bytes(b"not a real mp4")
            quarantined = quarantine_rejected_video(video)
            self.assertIsNotNone(quarantined)
            self.assertFalse(video.exists())
            self.assertTrue(quarantined.exists())
            self.assertEqual(quarantined.name, "demo-REJECTED.mp4")

    def test_quarantine_missing_video_returns_none(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            self.assertIsNone(quarantine_rejected_video(Path(tmp) / "missing.mp4"))


class IssueCoverageTests(unittest.TestCase):
    """#130: coverage derived from run issues, never a hard-coded range."""

    def test_covered_when_all_run_issues_open(self) -> None:
        result = derive_run_issue_coverage([123, 124, 125], [120, 123, 124, 125, 130])
        self.assertTrue(result["covered"])
        self.assertEqual(result["missing"], [])
        self.assertEqual(result["current_run_issues"], [123, 124, 125])

    def test_not_covered_lists_missing_run_issue(self) -> None:
        result = derive_run_issue_coverage([129, 130, 131], [129, 131])
        self.assertFalse(result["covered"])
        self.assertEqual(result["missing"], [130])

    def test_closed_legacy_range_cannot_gate_coverage(self) -> None:
        # The exact original bug: legacy #105-#112 are closed, so they are simply
        # not run issues. They can never produce covered=true nor false.
        result = derive_run_issue_coverage([123, 124], [123, 124])
        self.assertTrue(result["covered"])
        for legacy in range(105, 113):
            self.assertNotIn(legacy, result["current_run_issues"])

    def test_empty_run_issues_is_not_covered(self) -> None:
        # No run issues should not falsely report coverage.
        result = derive_run_issue_coverage([], [123, 124])
        self.assertFalse(result["covered"])

    def test_load_run_issue_numbers_from_issues_json(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            run_dir = Path(tmp)
            (run_dir / "issues.json").write_text(
                json.dumps([{"number": 129}, {"number": 130}, {"number": 130}]),
                encoding="utf-8",
            )
            self.assertEqual(load_run_issue_numbers(run_dir), [129, 130])

    def test_load_run_issue_numbers_from_issue_log_md(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            run_dir = Path(tmp)
            (run_dir / "issue-log-v41.md").write_text(
                "Run issues: #123, #124, #125 and follow-up #130", encoding="utf-8"
            )
            self.assertEqual(load_run_issue_numbers(run_dir), [123, 124, 125, 130])

    def test_load_run_issue_numbers_from_github_urls(self) -> None:
        # The real v41 issue-log uses GitHub issue URLs, not #NNN tokens.
        with tempfile.TemporaryDirectory() as tmp:
            run_dir = Path(tmp)
            (run_dir / "issue-log-v41.md").write_text(
                "1. https://github.com/MongLong0214/logic-pro-mcp/issues/129 - guard\n"
                "2. https://github.com/MongLong0214/logic-pro-mcp/issues/130 - stale\n",
                encoding="utf-8",
            )
            self.assertEqual(load_run_issue_numbers(run_dir), [129, 130])

    def test_load_run_issue_numbers_raises_without_source(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(FileNotFoundError):
                load_run_issue_numbers(Path(tmp))


class LogicCropTests(unittest.TestCase):
    """#137: crop derived from Logic window bounds, not a static rectangle."""

    def test_crop_matches_bounds_at_unit_scale(self) -> None:
        bounds = {"x": 120, "y": 30, "w": 1600, "h": 1000}
        crop = compute_logic_crop(bounds, capture_width=1920, capture_height=1080)
        self.assertEqual(crop, {"x": 120, "y": 30, "w": 1600, "h": 1000})

    def test_crop_scales_for_retina_capture(self) -> None:
        bounds = {"x": 100, "y": 40, "w": 800, "h": 500}
        crop = compute_logic_crop(
            bounds, capture_width=3840, capture_height=2160, capture_scale=2.0
        )
        self.assertEqual(crop, {"x": 200, "y": 80, "w": 1600, "h": 1000})

    def test_crop_dimensions_are_even(self) -> None:
        bounds = {"x": 11, "y": 13, "w": 1601, "h": 1003}
        crop = compute_logic_crop(bounds, capture_width=1920, capture_height=1080)
        self.assertEqual(crop["w"] % 2, 0)
        self.assertEqual(crop["h"] % 2, 0)

    def test_crop_clamped_inside_capture(self) -> None:
        bounds = {"x": 100, "y": 50, "w": 5000, "h": 4000}
        crop = compute_logic_crop(bounds, capture_width=1920, capture_height=1080)
        self.assertLessEqual(crop["x"] + crop["w"], 1920)
        self.assertLessEqual(crop["y"] + crop["h"], 1080)

    def test_inset_shrinks_crop(self) -> None:
        bounds = {"x": 100, "y": 100, "w": 1000, "h": 800}
        crop = compute_logic_crop(
            bounds, capture_width=1920, capture_height=1080, inset=10
        )
        self.assertEqual(crop["x"], 110)
        self.assertEqual(crop["y"], 110)
        self.assertEqual(crop["w"], 980)
        self.assertEqual(crop["h"], 780)

    def test_within_bounds_accepts_logic_crop(self) -> None:
        bounds = {"x": 120, "y": 30, "w": 1600, "h": 1000}
        crop = compute_logic_crop(bounds, capture_width=1920, capture_height=1080)
        self.assertTrue(crop_is_within_logic_bounds(crop, bounds))

    def test_within_bounds_rejects_legacy_x0_fullwidth_crop(self) -> None:
        # The exact v42 leak: x:0 full-width box wider than the Logic window.
        bounds = {"x": 390, "y": 90, "w": 1400, "h": 900}
        legacy_crop = {"x": 0, "y": 80, "w": 2300, "h": 1294}
        self.assertFalse(crop_is_within_logic_bounds(legacy_crop, bounds))


if __name__ == "__main__":
    unittest.main()

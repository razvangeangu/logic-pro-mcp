#!/usr/bin/env python3
"""Tests for the timeout-resilient press_any policy (issue #126)."""

from __future__ import annotations

import subprocess
import unittest

from demo_press_any import press_any


class PressAnyTests(unittest.TestCase):
    """#126: a per-candidate press timeout must never escape press_any."""

    def test_first_candidate_pressing_returns_its_title(self) -> None:
        pressed: list[str] = []

        def press_fn(title: str) -> None:
            pressed.append(title)

        self.assertEqual(press_any(["Play", "Bounce"], press_fn), "Play")
        # Short-circuits on the first success; later candidates are not tried.
        self.assertEqual(pressed, ["Play"])

    def test_first_candidate_timeout_falls_through_to_next(self) -> None:
        attempted: list[str] = []

        def press_fn(title: str) -> None:
            attempted.append(title)
            if title == "Play":
                raise TimeoutError("AX press timed out")

        self.assertEqual(press_any(["Play", "Bounce"], press_fn), "Bounce")
        self.assertEqual(attempted, ["Play", "Bounce"])

    def test_all_candidates_timeout_returns_none_no_escape(self) -> None:
        def press_fn(title: str) -> None:
            raise TimeoutError("AX press timed out")

        # The original bug: this would have escaped and aborted the run.
        self.assertIsNone(press_any(["Play", "Bounce", "Record"], press_fn))

    def test_subprocess_timeout_expired_is_caught(self) -> None:
        # subprocess.TimeoutExpired is NOT a TimeoutError subclass (it derives
        # from subprocess.SubprocessError); press_any must still catch it -- this
        # is the exact escape that aborted the run in #126.
        self.assertFalse(issubclass(subprocess.TimeoutExpired, TimeoutError))

        def press_fn(title: str) -> None:
            if title == "Play":
                raise subprocess.TimeoutExpired(cmd=["osascript"], timeout=5.0)

        self.assertEqual(press_any(["Play", "Bounce"], press_fn), "Bounce")

    def test_candidate_order_is_preserved(self) -> None:
        attempted: list[str] = []

        def press_fn(title: str) -> None:
            attempted.append(title)
            raise TimeoutError("AX press timed out")

        self.assertIsNone(press_any(["a", "b", "c", "d"], press_fn))
        self.assertEqual(attempted, ["a", "b", "c", "d"])

    def test_empty_candidates_returns_none(self) -> None:
        def press_fn(title: str) -> None:  # pragma: no cover - never called
            raise AssertionError("press_fn must not be called for no candidates")

        self.assertIsNone(press_any([], press_fn))


if __name__ == "__main__":
    unittest.main()

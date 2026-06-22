#!/usr/bin/env python3
"""Tests for the duration-aware play_sequence read-timeout (issue #134)."""

from __future__ import annotations

import unittest

from demo_play_timeout import play_sequence_timeout

# The exact bug: the demo harness used a fixed read-timeout of 22 seconds.
_OLD_HARDCODED_TIMEOUT = 22

# Real part durations observed in the demo composition.
_SEVEN_BAR_DURATION_S = 24.6
_NINE_BAR_DURATION_S = 27.7


class PlaySequenceTimeoutTests(unittest.TestCase):
    """#134: the read-timeout must outlast a part's real playback duration."""

    def test_seven_bar_part_timeout_strictly_exceeds_duration(self) -> None:
        # A 7-bar part (~24.6s) must get a timeout strictly greater than its
        # duration so the read deadline cannot expire mid-playback.
        timeout = play_sequence_timeout(_SEVEN_BAR_DURATION_S)
        self.assertGreater(timeout, _SEVEN_BAR_DURATION_S)
        self.assertEqual(timeout, _SEVEN_BAR_DURATION_S + 10)

    def test_nine_bar_part_timeout_strictly_exceeds_duration(self) -> None:
        # A 9-bar part (~27.7s) must likewise clear its own duration.
        timeout = play_sequence_timeout(_NINE_BAR_DURATION_S)
        self.assertGreater(timeout, _NINE_BAR_DURATION_S)
        self.assertEqual(timeout, _NINE_BAR_DURATION_S + 10)

    def test_tiny_part_still_gets_the_twenty_second_floor(self) -> None:
        # A trivially short part must not drop below the 20s floor.
        self.assertEqual(play_sequence_timeout(0.5), 20)
        self.assertEqual(play_sequence_timeout(0.0), 20)
        # The floor wins right up to where duration + headroom overtakes it.
        self.assertEqual(play_sequence_timeout(9.0), 20)
        self.assertEqual(play_sequence_timeout(10.0), 20)

    def test_old_hardcoded_22_would_have_undershot_the_long_part(self) -> None:
        # Documents the #134 bug as a comparison: the old fixed 22s deadline was
        # SHORTER than the 7-bar part's ~24.6s playback, so the client gave up
        # while the server was still playing -> false "timeout", response: null.
        self.assertLess(_OLD_HARDCODED_TIMEOUT, _SEVEN_BAR_DURATION_S)
        # The duration-aware timeout fixes exactly that: it now exceeds 22s and
        # the part's real duration.
        fixed = play_sequence_timeout(_SEVEN_BAR_DURATION_S)
        self.assertGreater(fixed, _OLD_HARDCODED_TIMEOUT)
        self.assertGreater(fixed, _SEVEN_BAR_DURATION_S)

    def test_custom_floor_and_headroom_are_honoured(self) -> None:
        # Floor wins when duration + headroom is below it.
        self.assertEqual(play_sequence_timeout(2.0, floor=30, headroom=5), 30)
        # Otherwise duration + headroom wins.
        self.assertEqual(play_sequence_timeout(40.0, floor=20, headroom=15), 55)


if __name__ == "__main__":
    unittest.main()

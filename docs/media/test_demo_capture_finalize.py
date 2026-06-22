#!/usr/bin/env python3
"""Tests for the demo capture-finalization policy (issue #124)."""

from __future__ import annotations

import signal
import unittest

from demo_capture_finalize import (
    STREAMABLE_MOVFLAG_TOKENS,
    finalize_capture_signal_numbers,
    finalize_capture_signal_sequence,
    is_streamable_mux,
    streamable_ffmpeg_movflags,
    streamable_movflags_value,
)


class MovflagsTests(unittest.TestCase):
    """#124: the mux flags must keep a killed capture playable."""

    def test_movflags_contain_faststart_frag_keyframe_empty_moov(self) -> None:
        value = streamable_movflags_value()
        self.assertIn("faststart", value)
        self.assertIn("frag_keyframe", value)
        self.assertIn("empty_moov", value)

    def test_movflags_include_default_base_moof(self) -> None:
        self.assertIn("default_base_moof", streamable_movflags_value())

    def test_movflags_value_matches_proven_v40_string(self) -> None:
        # The exact value proven in logic_commercial_blank_to_bounce_v40.py.
        self.assertEqual(
            streamable_movflags_value(),
            "+faststart+frag_keyframe+empty_moov+default_base_moof",
        )

    def test_ffmpeg_movflags_args_are_a_flag_value_pair(self) -> None:
        args = streamable_ffmpeg_movflags()
        self.assertEqual(len(args), 2)
        self.assertEqual(args[0], "-movflags")
        self.assertEqual(args[1], streamable_movflags_value())

    def test_ffmpeg_movflags_splice_into_a_capture_argv(self) -> None:
        argv = [
            "ffmpeg",
            "-f",
            "avfoundation",
            "-i",
            "0:none",
            "-c:v",
            "libx264",
            *streamable_ffmpeg_movflags(),
            "out.mp4",
        ]
        self.assertTrue(is_streamable_mux(argv))


class StreamableMuxGateTests(unittest.TestCase):
    """#124: the QA gate that would have caught the invalid-MP4 bug."""

    def test_rejects_plain_libx264_arglist(self) -> None:
        # The pre-fix capture command: no -movflags, default muxer leaves an
        # invalid MP4 on an abrupt kill.
        plain = ["ffmpeg", "-i", "0:none", "-c:v", "libx264", "-crf", "18", "out.mp4"]
        self.assertFalse(is_streamable_mux(plain))

    def test_accepts_finalize_args(self) -> None:
        argv = ["ffmpeg", "-c:v", "libx264", *streamable_ffmpeg_movflags(), "out.mp4"]
        self.assertTrue(is_streamable_mux(argv))

    def test_faststart_alone_is_not_streamable(self) -> None:
        # +faststart by itself does NOT survive a kill (moov still only at clean
        # shutdown); the gate must require the fragmented-write tokens too.
        argv = ["ffmpeg", "-c:v", "libx264", "-movflags", "+faststart", "out.mp4"]
        self.assertFalse(is_streamable_mux(argv))

    def test_token_order_does_not_matter(self) -> None:
        argv = [
            "ffmpeg",
            "-movflags",
            "empty_moov+frag_keyframe+faststart+default_base_moof",
            "out.mp4",
        ]
        self.assertTrue(is_streamable_mux(argv))

    def test_last_movflags_value_wins(self) -> None:
        # ffmpeg applies the last -movflags occurrence. A later non-fragmented
        # value must not be rescued by an earlier streamable value.
        argv = [
            "ffmpeg",
            *streamable_ffmpeg_movflags(),
            "-movflags",
            "+faststart",
            "out.mp4",
        ]
        self.assertFalse(is_streamable_mux(argv))

    def test_empty_arglist_is_not_streamable(self) -> None:
        self.assertFalse(is_streamable_mux([]))

    def test_dangling_movflags_flag_is_not_streamable(self) -> None:
        # A trailing -movflags with no value must not crash or pass.
        self.assertFalse(is_streamable_mux(["ffmpeg", "-c:v", "libx264", "-movflags"]))

    def test_dangling_final_movflags_invalidates_prior_streamable_value(self) -> None:
        argv = ["ffmpeg", *streamable_ffmpeg_movflags(), "-movflags"]
        self.assertFalse(is_streamable_mux(argv))

    def test_published_token_tuple_covers_required_tokens(self) -> None:
        for token in ("faststart", "frag_keyframe", "empty_moov"):
            self.assertIn(token, STREAMABLE_MOVFLAG_TOKENS)


class SignalSequenceTests(unittest.TestCase):
    """#124: graceful-first stop so the moov atom flushes before force-kill."""

    def test_sequence_is_sigint_sigterm_sigkill(self) -> None:
        names = [name for name, _ in finalize_capture_signal_sequence()]
        self.assertEqual(names, ["SIGINT", "SIGTERM", "SIGKILL"])

    def test_sigint_before_sigterm_before_sigkill(self) -> None:
        names = [name for name, _ in finalize_capture_signal_sequence()]
        self.assertLess(names.index("SIGINT"), names.index("SIGTERM"))
        self.assertLess(names.index("SIGTERM"), names.index("SIGKILL"))

    def test_waits_are_sigint_20_sigterm_8_sigkill_0(self) -> None:
        self.assertEqual(
            finalize_capture_signal_sequence(),
            [("SIGINT", 20.0), ("SIGTERM", 8.0), ("SIGKILL", 0.0)],
        )

    def test_graceful_signals_have_positive_wait(self) -> None:
        # SIGINT and SIGTERM must wait so ffmpeg can flush the trailer.
        sequence = finalize_capture_signal_sequence()
        sigint_wait = dict(sequence)["SIGINT"]
        sigterm_wait = dict(sequence)["SIGTERM"]
        self.assertGreater(sigint_wait, 0.0)
        self.assertGreater(sigterm_wait, 0.0)

    def test_sigkill_is_terminal_with_zero_wait(self) -> None:
        # SIGKILL cannot be caught: nothing left to flush, so it waits 0s.
        sequence = finalize_capture_signal_sequence()
        last_name, last_wait = sequence[-1]
        self.assertEqual(last_name, "SIGKILL")
        self.assertEqual(last_wait, 0.0)

    def test_sigint_wait_is_longest(self) -> None:
        # The first graceful attempt gets the most time to flush the moov atom.
        waits = {name: wait for name, wait in finalize_capture_signal_sequence()}
        self.assertEqual(max(waits.values()), waits["SIGINT"])

    def test_signal_numbers_match_platform_values(self) -> None:
        self.assertEqual(
            finalize_capture_signal_numbers(),
            [
                (int(signal.SIGINT), 20.0),
                (int(signal.SIGTERM), 8.0),
                (int(signal.SIGKILL), 0.0),
            ],
        )


if __name__ == "__main__":
    unittest.main()

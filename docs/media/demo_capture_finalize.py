#!/usr/bin/env python3
"""Tracked, tested capture-finalization policy for the demo capture pipeline.

This module owns the correctness behaviour that previously lived inline in the
untracked workspace capture scripts (``~/.openclaw/workspace/scripts``): when a
screen-capture run is killed mid-capture, the raw MP4 it leaves behind must
still be a valid, playable (``ffprobe``-openable) file (issue #124).

The bug: ffmpeg's default MP4 muxer writes the ``moov`` atom (the index that
makes a file seekable/playable) only on a clean shutdown. If the capture is
SIGKILLed before that trailer is written, the file has no ``moov`` and is an
invalid, unplayable raw MP4.

The fix, proven in ``logic_commercial_blank_to_bounce_v40.py`` and re-homed here
as pure, unit-tested logic:

* ``streamable_ffmpeg_movflags`` -- the exact ``-movflags`` value that writes the
  ``moov`` metadata incrementally (``empty_moov`` + ``frag_keyframe``) with
  ``+faststart`` finalization, so the file stays valid even on an abrupt kill.
* ``finalize_capture_signal_sequence`` -- the ordered (signal, wait_seconds)
  escalation (graceful SIGINT first, then SIGTERM, then a last-resort SIGKILL)
  so the capturer is given a real chance to flush the ``moov`` atom before it is
  force-killed.
* ``is_streamable_mux`` -- the QA gate that would have caught the invalid-MP4
  bug: it returns True only when the ffmpeg args carry the fragmented +
  faststart flags.

Keeping the logic here (a tracked, dependency-free, unit-tested module) lets CI
guard it; the workspace pipeline imports and calls these helpers.
"""

from __future__ import annotations

import signal

# --- #124: streamable / fragmented mux flags -------------------------------

# The individual ``-movflags`` tokens that keep a killed capture playable. Order
# matches the proven v40 value; ``is_streamable_mux`` compares membership, not
# order, so a caller may reorder these without tripping the gate.
#
# * ``faststart``         -- move the moov atom to the front so the file is
#                            immediately playable / streamable once finalized.
# * ``frag_keyframe``     -- start a new fragment at each keyframe so already
#                            written fragments form a self-describing file.
# * ``empty_moov``        -- write an initial empty moov up front instead of
#                            only at clean shutdown, so a killed file still has
#                            the structural index it needs to open.
# * ``default_base_moof`` -- use the moof box as the base data offset, which
#                            keeps the fragmented layout robust to truncation.
STREAMABLE_MOVFLAG_TOKENS: tuple[str, ...] = (
    "faststart",
    "frag_keyframe",
    "empty_moov",
    "default_base_moof",
)

# The subset of tokens whose presence proves the mux is crash-safe. faststart on
# its own does NOT make a killed file valid (the moov is still only written at
# clean shutdown), so the QA gate requires the fragmented-write tokens.
_REQUIRED_STREAMABLE_TOKENS: frozenset[str] = frozenset(
    {
        "faststart",
        "frag_keyframe",
        "empty_moov",
    }
)


def streamable_movflags_value() -> str:
    """Return the exact ``-movflags`` value (``+``-joined) for a crash-safe mux.

    This is the single string ffmpeg expects after the ``-movflags`` flag, e.g.
    ``"+faststart+frag_keyframe+empty_moov+default_base_moof"``.
    """
    return "+" + "+".join(STREAMABLE_MOVFLAG_TOKENS)


def streamable_ffmpeg_movflags() -> list[str]:
    """Return the exact ``-movflags`` args that keep a killed capture playable.

    The returned list is ready to splice into an ffmpeg argv, e.g.::

        ["ffmpeg", "-i", "0:none", "-c:v", "libx264",
         *streamable_ffmpeg_movflags(), out]

    so the moov atom is written incrementally and the raw file stays
    ffprobe-openable even if ffmpeg is SIGINT/SIGTERM/SIGKILLed mid-capture.
    """
    return ["-movflags", streamable_movflags_value()]


def _movflags_tokens(args: list[str]) -> set[str]:
    """Extract the set of ``-movflags`` tokens present in an ffmpeg argv.

    ffmpeg applies the last ``-movflags <value>`` pair, so the QA gate must do
    the same. Splits the ``+a+b`` / ``a+b`` value form into individual tokens.
    A dangling final ``-movflags`` is invalid and fails closed.
    """
    tokens: set[str] = set()
    for index, arg in enumerate(args):
        if arg == "-movflags" and index + 1 < len(args):
            value = args[index + 1]
            tokens = {token.strip() for token in value.split("+") if token.strip()}
        elif arg == "-movflags":
            return set()
    return tokens


def is_streamable_mux(args: list[str]) -> bool:
    """QA gate: True iff ffmpeg args carry the faststart + fragmented flags.

    Returns False for a plain ``-c:v libx264`` arg list (the pre-fix capture
    command, whose default muxer leaves an invalid MP4 on an abrupt kill) and
    True for an arg list that includes the streamable ``-movflags`` value.
    This is the gate that would have caught issue #124.
    """
    return _REQUIRED_STREAMABLE_TOKENS.issubset(_movflags_tokens(args))


# --- #124: graceful-first stop escalation ----------------------------------

# Ordered escalation a caller applies to the capture process: try the gentlest
# signal first and wait for ffmpeg to flush the moov atom and exit cleanly,
# escalating only after each wait elapses. SIGKILL is the terminal step and has
# a 0s wait because it cannot be caught -- the process is gone immediately and
# there is nothing left to flush (the fragmented mux is what keeps the
# already-written file valid in that case).
_FINALIZE_SIGNAL_SEQUENCE: tuple[tuple[int, float], ...] = (
    (signal.SIGINT, 20.0),
    (signal.SIGTERM, 8.0),
    (signal.SIGKILL, 0.0),
)


def finalize_capture_signal_sequence() -> list[tuple[str, float]]:
    """Return the ordered (signal_name, wait_seconds) stop escalation.

    The sequence is ``[("SIGINT", 20.0), ("SIGTERM", 8.0), ("SIGKILL", 0.0)]``:
    SIGINT is what ffmpeg handles cleanly for an avfoundation device capture, so
    it is the FIRST escalation and gets the longest wait to let the moov atom
    flush; SIGTERM is the next graceful attempt; SIGKILL is the last resort that
    cannot flush a trailer but leaves the fragmented file ffprobe-openable.

    Returned as signal *names* (strings) so the policy is serializable and
    testable without depending on a platform's numeric signal values; map back
    to numbers via ``finalize_capture_signal_numbers`` when sending.
    """
    return [(signal.Signals(sig).name, wait) for sig, wait in _FINALIZE_SIGNAL_SEQUENCE]


def finalize_capture_signal_numbers() -> list[tuple[int, float]]:
    """Return the stop escalation as (signal_number, wait_seconds) pairs.

    The numeric form a caller passes to ``os.killpg`` / ``Popen.send_signal``.
    """
    return [(int(sig), wait) for sig, wait in _FINALIZE_SIGNAL_SEQUENCE]


if __name__ == "__main__":
    print("movflags:", streamable_movflags_value())
    print("signal sequence:", finalize_capture_signal_sequence())

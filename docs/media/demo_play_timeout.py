#!/usr/bin/env python3
"""Duration-aware ``play_sequence`` read-timeout policy for the demo run.

This owns the correctness behaviour that previously lived inline in the
untracked workspace capture scripts (``~/.openclaw/workspace/scripts``). The
proven shape is ``compose_logic_lofi_mcp_live.py``:

    play_timeout = max(20, part_duration_seconds + 10)

The original bug (issue #134): the demo harness drove ``play_sequence`` with a
hardcoded client read-timeout of 22 seconds. Long parts -- a 7-bar part runs
~24.6s, a 9-bar part ~27.7s -- play *longer* than 22s, so the client's read
deadline expired while the Logic Pro server was still legitimately playing the
regions. The harness reported a false "timed out" (``response: null``) even
though playback succeeded; nothing was actually wrong with the server.

The fix is to size the read-timeout to the part: never wait less than a 20s
floor, and always allow ``headroom`` seconds beyond the part's real duration so
the server's response arrives before the client gives up. Keeping the logic
here (a tracked, unit-tested module) lets CI guard it; the workspace pipeline
imports and calls ``play_sequence_timeout`` with each part's duration.
"""

from __future__ import annotations


def play_sequence_timeout(
    part_duration_seconds: float,
    floor: int = 20,
    headroom: int = 10,
) -> float:
    """Return a read-timeout (seconds) that outlasts a part's real playback.

    ``part_duration_seconds`` is how long the part actually plays. The returned
    timeout is ``max(floor, part_duration_seconds + headroom)``: it never drops
    below the ``floor`` (so trivially short parts still get a sane minimum), and
    it always clears the part's duration by ``headroom`` seconds so the client
    read deadline cannot expire mid-playback. This is what stops the false
    "timeout" with ``response: null`` that #134 reported when a fixed 22s
    deadline under-shot long (~24-28s) parts.
    """
    return max(floor, part_duration_seconds + headroom)

#!/usr/bin/env python3
"""Timeout-resilient candidate-press policy for the public Logic Pro demo run.

This owns the correctness behaviour that previously lived inline in the
untracked workspace capture scripts (``~/.openclaw/workspace/scripts``):

* ``press_any`` -- try a list of candidate AX button titles in order, pressing
  each via an injected ``press_fn``. A press that times out is caught per
  candidate and the policy continues to the next candidate; only a successful
  press short-circuits and is returned. If every candidate fails or times out,
  ``None`` is returned -- the timeout is never allowed to escape (issue #126).

The original bug (issue #126): a single AX button press in ``press_any`` raised
``subprocess.TimeoutExpired``, which escaped the helper and aborted the entire
demo render run instead of falling through to the next candidate button. The
real workspace press is a ``subprocess.run(..., timeout=...)`` call that raises
``subprocess.TimeoutExpired`` on timeout. Note ``subprocess.TimeoutExpired`` is
NOT a subclass of the builtin ``TimeoutError`` (it derives from
``subprocess.SubprocessError``), so the policy catches BOTH explicitly: the
real subprocess path and a pure, subprocess-free ``TimeoutError`` test double.

Keeping the logic here (a tracked, unit-tested module) lets CI guard it; the
workspace pipeline imports and calls ``press_any`` with its real ``press_fn``.
"""

from __future__ import annotations

import subprocess
from typing import Callable, Sequence

# The timeout exceptions a candidate press may raise. ``subprocess.TimeoutExpired``
# is the real workspace path (subprocess.run timeout); ``TimeoutError`` is the
# builtin a pure test double / non-subprocess press_fn can raise. They are
# unrelated in the class hierarchy, so both must be named explicitly.
_TIMEOUT_EXCEPTIONS: tuple[type[BaseException], ...] = (
    subprocess.TimeoutExpired,
    TimeoutError,
)


def press_any(
    candidates: Sequence[str],
    press_fn: Callable[[str], object],
) -> str | None:
    """Press the first candidate that succeeds, surviving per-candidate timeouts.

    ``press_fn(title)`` is called for each candidate title in order. If it
    raises ``subprocess.TimeoutExpired`` (the real subprocess press path) or the
    builtin ``TimeoutError`` (a subprocess-free test double), the timeout is
    swallowed and the policy advances to the next candidate.

    Returns the title of the first candidate whose ``press_fn`` call returned
    without raising, or ``None`` when every candidate timed out. A timeout from
    any single candidate never escapes this function, so one slow AX button
    press can no longer abort the whole demo run (issue #126).
    """
    for title in candidates:
        try:
            press_fn(title)
        except _TIMEOUT_EXCEPTIONS:
            continue
        return title
    return None

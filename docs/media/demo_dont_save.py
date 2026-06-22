#!/usr/bin/env python3
"""Tracked, tested candidate-expansion policy for Logic's "Don't Save" modal (#132).

Issue #132: a blank-start run failed to dismiss Logic Pro's unsaved-changes
sheet because the candidate button-title list only contained the
straight-apostrophe ``"Don't Save"`` (U+0027 APOSTROPHE). Logic actually renders
the button with a curly typographic apostrophe -- ``"Don’t Save"`` (U+2019 RIGHT
SINGLE QUOTATION MARK) -- so the literal compare never matched and the sheet was
never clicked, stalling the harness.

The fix (already live in the ``~/.openclaw`` harness) is re-homed here as a pure,
unit-tested helper so CI can guard the byte-exact behaviour: whenever the
straight ``"Don't Save"`` (U+0027) is a candidate, also try the curly
``"Don’t Save"`` (U+2019) and ``"Delete"`` (Logic's alternate localized
discard-on-blank-start label), without ever dropping or reordering the originals.

Keeping the U+2019-vs-U+0027 distinction in a tracked module -- rather than inline
in the untracked workspace capture scripts -- lets a test assert the literal
codepoint, which is exactly the assumption that broke in #132.
"""

from __future__ import annotations

from typing import Iterable

# The straight-apostrophe spelling the candidate list historically contained
# (U+0027 APOSTROPHE). This is what failed to match Logic's rendered button.
STRAIGHT_DONT_SAVE = "Don't Save"

# The curly-apostrophe spelling Logic actually renders (U+2019 RIGHT SINGLE
# QUOTATION MARK). The character between "Don" and "t" below is U+2019, NOT a
# plain ASCII apostrophe -- this is the load-bearing distinction from #132.
CURLY_DONT_SAVE = "Don’t Save"

# Logic's alternate discard label on a blank-start / never-saved project.
DELETE_LABEL = "Delete"


def expand_dont_save_candidates(titles: Iterable[str]) -> list[str]:
    """Return ``titles`` with the curly ``"Don’t Save"`` + ``"Delete"`` ensured.

    Policy (issue #132): when the straight-apostrophe ``"Don't Save"`` (U+0027)
    is present in ``titles`` and the curly-apostrophe ``"Don’t Save"`` (U+2019)
    is *absent*, append the curly spelling so the dismiss step matches the button
    Logic actually renders. Likewise append ``"Delete"`` when it is absent.

    Originals are preserved verbatim and in order; only the genuinely missing
    fallbacks are appended (so the function is idempotent). Lists that do not
    contain the straight ``"Don't Save"`` are returned unchanged.
    """
    result = list(titles)
    if STRAIGHT_DONT_SAVE not in result:
        return result
    if CURLY_DONT_SAVE not in result:
        result.append(CURLY_DONT_SAVE)
    if DELETE_LABEL not in result:
        result.append(DELETE_LABEL)
    return result

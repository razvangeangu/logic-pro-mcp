#!/usr/bin/env python3
"""Tracked, tested gate helpers for the public Logic Pro demo render pipeline.

These helpers own three correctness behaviours that previously lived inline in
the untracked workspace capture scripts (``~/.openclaw/workspace/scripts``):

* ``enforce_demo_reject_gates`` -- fail-closed when a required reject gate is
  false, so a render whose own bounce/audio proof failed can never be reported
  as a finished deliverable (issue #129).
* ``derive_run_issue_coverage`` -- derive issue-registration coverage from the
  issues a run actually created, instead of a hard-coded, now-closed issue
  range like #105-#112 (issue #130).
* ``logic_front_window_bounds`` / ``compute_logic_crop`` -- crop the screen
  capture to the detected Logic Pro front-window bounds instead of a static,
  full-width-from-origin screen rectangle that leaks non-Logic background
  (issue #137).

Keeping the logic here (a tracked, unit-tested module) lets CI guard it; the
workspace pipeline imports and calls these helpers.
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path
from typing import Any, Iterable, Sequence

# --- #129: fail-closed required gate enforcement ---------------------------

# The minimum set of reject gates that must be true for a render to be treated
# as a publishable deliverable. A demo run may pass additional keys; only these
# are enforced unless the caller overrides ``required_keys``.
DEFAULT_REQUIRED_GATES: tuple[str, ...] = (
    "logic_bounce_guard_returncode_0",
    "logic_audio_analyze_status_not_fail",
    "arrangement_gate_pass",
    "blackdetect_no_black_start",
)


class DemoGatesRejected(SystemExit):
    """Raised (as a non-zero SystemExit) when a required reject gate is false."""

    def __init__(self, rejected: Sequence[str], *, code: int = 2) -> None:
        self.rejected = list(rejected)
        super().__init__(code)


def evaluate_reject_gates(
    reject_gate_results: dict[str, Any],
    required_keys: Iterable[str] = DEFAULT_REQUIRED_GATES,
) -> list[str]:
    """Return the list of required gates that are false or missing.

    A required key that is absent from ``reject_gate_results`` counts as
    rejected: an unmeasured required gate is never an implicit pass.
    """
    rejected: list[str] = []
    for key in required_keys:
        if not reject_gate_results.get(key, False):
            rejected.append(key)
    return rejected


def enforce_demo_reject_gates(
    reject_gate_results: dict[str, Any],
    required_keys: Iterable[str] = DEFAULT_REQUIRED_GATES,
) -> list[str]:
    """Raise ``DemoGatesRejected`` (non-zero exit) if any required gate is false.

    Returns the (empty) rejected list when every required gate passes so callers
    can keep a single code path.
    """
    rejected = evaluate_reject_gates(reject_gate_results, required_keys)
    if rejected:
        raise DemoGatesRejected(rejected)
    return rejected


def quarantine_rejected_video(final_video: Path) -> Path | None:
    """Move a render produced before rejection out of the deliverable slot.

    Renames ``<name>.mp4`` to ``<name>-REJECTED.mp4`` so it cannot be mistaken
    for a publishable artifact. Returns the new path, or ``None`` if the source
    does not exist.
    """
    final_video = Path(final_video)
    if not final_video.exists():
        return None
    quarantined = final_video.with_name(f"{final_video.stem}-REJECTED{final_video.suffix}")
    final_video.replace(quarantined)
    return quarantined


# --- #130: run-derived issue coverage (no hard-coded issue range) ----------


def _coerce_issue_number(value: Any) -> int | None:
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def load_run_issue_numbers(run_dir: Path) -> list[int]:
    """Read the run's own issue numbers from a run-local source of truth.

    Looks for, in order:
      1. ``issues.json`` -- a list of ``{"number": N, ...}`` objects (preferred
         structured artifact).
      2. ``issue-log-*.md`` -- markdown issue logs; ``#NNN`` tokens are parsed.

    Returns a sorted, de-duplicated list. Raises ``FileNotFoundError`` if no
    run-local issue source exists, so coverage is never silently derived from a
    stale literal.
    """
    run_dir = Path(run_dir)
    issues_json = run_dir / "issues.json"
    if issues_json.exists():
        data = json.loads(issues_json.read_text(encoding="utf-8"))
        numbers: set[int] = set()
        for item in data:
            number = _coerce_issue_number(item.get("number")) if isinstance(item, dict) else None
            if number is not None:
                numbers.add(number)
        return sorted(numbers)

    log_candidates = sorted(run_dir.glob("issue-log*.md"))
    if log_candidates:
        import re

        # Match both the GitHub URL form (.../issues/NNN) and the short #NNN form.
        pattern = re.compile(r"(?:issues/|#)(\d+)")
        numbers = set()
        for log_path in log_candidates:
            for token in pattern.findall(log_path.read_text(encoding="utf-8")):
                numbers.add(int(token))
        return sorted(numbers)

    raise FileNotFoundError(
        f"no run-local issue source (issues.json or issue-log*.md) found in {run_dir}"
    )


def derive_run_issue_coverage(
    run_issue_numbers: Sequence[int],
    open_issue_numbers: Sequence[int],
) -> dict[str, Any]:
    """Compute issue-registration coverage for THIS run's issues.

    ``covered`` is true only when every issue created/verified during the run is
    present in the open-issue set. ``missing`` lists the genuine registration
    gaps (run issues that are not open). A closed legacy range can never gate
    coverage because it is simply not in ``run_issue_numbers``.
    """
    run_set = sorted({int(n) for n in run_issue_numbers})
    open_set = {int(n) for n in open_issue_numbers}
    missing = [n for n in run_set if n not in open_set]
    return {
        "current_run_issues": run_set,
        "open_issue_numbers": sorted(open_set),
        "missing": missing,
        "covered": len(run_set) > 0 and not missing,
    }


# --- #137: crop to detected Logic front-window bounds ----------------------

_LOGIC_BOUNDS_SWIFT = r"""
import AppKit
import ApplicationServices
import Foundation

func bounds(_ window: AXUIElement) -> (CGPoint, CGSize)? {
    var posObj: CFTypeRef?
    var sizeObj: CFTypeRef?
    guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posObj) == .success,
          AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeObj) == .success
    else { return nil }
    var point = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(posObj as! AXValue, .cgPoint, &point),
          AXValueGetValue(sizeObj as! AXValue, .cgSize, &size)
    else { return nil }
    return (point, size)
}

let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.logic10")
guard let app = apps.first else { exit(2) }
let ax = AXUIElementCreateApplication(app.processIdentifier)
var target: AXUIElement?
var focusedObj: CFTypeRef?
if AXUIElementCopyAttributeValue(ax, kAXFocusedWindowAttribute as CFString, &focusedObj) == .success {
    target = (focusedObj as! AXUIElement)
}
if target == nil {
    var mainObj: CFTypeRef?
    if AXUIElementCopyAttributeValue(ax, kAXMainWindowAttribute as CFString, &mainObj) == .success {
        target = (mainObj as! AXUIElement)
    }
}
guard let window = target, let (point, size) = bounds(window) else { exit(3) }
let screen = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 0, height: 0)
print("{\"x\":\(Int(point.x)),\"y\":\(Int(point.y)),\"w\":\(Int(size.width)),\"h\":\(Int(size.height)),\"screen_w\":\(Int(screen.width)),\"screen_h\":\(Int(screen.height))}")
"""


def logic_front_window_bounds(*, timeout: float = 12.0) -> dict[str, int] | None:
    """Query Logic Pro's front-window position/size via AX (kAXPosition/kAXSize).

    Returns ``{"x", "y", "w", "h"}`` in screen points, or ``None`` if Logic is
    not running / no front window is available. Callers must treat ``None`` as
    "could not determine bounds" and fail closed rather than fall back to a
    static full-screen rectangle.
    """
    try:
        proc = subprocess.run(
            ["swift", "-"],
            input=_LOGIC_BOUNDS_SWIFT,
            text=True,
            capture_output=True,
            timeout=timeout,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if proc.returncode != 0:
        return None
    line = proc.stdout.strip().splitlines()[-1] if proc.stdout.strip() else ""
    if not line:
        return None
    try:
        data = json.loads(line)
    except json.JSONDecodeError:
        return None
    try:
        result = {k: int(data[k]) for k in ("x", "y", "w", "h")}
    except (KeyError, TypeError, ValueError):
        return None
    for optional in ("screen_w", "screen_h"):
        if optional in data:
            try:
                result[optional] = int(data[optional])
            except (TypeError, ValueError):
                pass
    return result


def _even(value: int) -> int:
    """Snap to an even integer (H.264 requires even crop width/height)."""
    return value - (value % 2)


def compute_logic_crop(
    bounds: dict[str, int],
    *,
    capture_width: int,
    capture_height: int,
    capture_scale: float = 1.0,
    inset: int = 0,
) -> dict[str, int]:
    """Derive an H.264-safe crop rectangle from Logic window bounds.

    ``bounds`` are in screen points; ``capture_scale`` maps points to captured
    pixels (e.g. 2.0 on a Retina display captured at native resolution). The
    result is clamped inside the captured frame and snapped to even dimensions.

    Raises ``ValueError`` if the derived crop would be empty, so a bad bounds
    read can never silently produce a degenerate full-frame crop.
    """
    x = int(round((bounds["x"] + inset) * capture_scale))
    y = int(round((bounds["y"] + inset) * capture_scale))
    w = int(round((bounds["w"] - 2 * inset) * capture_scale))
    h = int(round((bounds["h"] - 2 * inset) * capture_scale))

    x = max(0, min(x, max(0, capture_width - 2)))
    y = max(0, min(y, max(0, capture_height - 2)))
    w = _even(max(2, min(w, capture_width - x)))
    h = _even(max(2, min(h, capture_height - y)))
    if w < 2 or h < 2:
        raise ValueError(f"derived Logic crop is empty for bounds={bounds}")
    return {"x": x, "y": y, "w": w, "h": h}


def crop_from_bounds_and_capture(
    bounds: dict[str, int],
    *,
    capture_width: int,
    capture_height: int,
    inset: int = 0,
) -> dict[str, int]:
    """Derive a crop from window bounds + captured frame dimensions.

    The point->pixel scale is inferred from ``bounds['screen_w']`` (screen width
    in points) versus ``capture_width`` (pixels). Falls back to scale 1.0 when
    the screen width is unknown. This is the render-time entry point: the bounds
    are queried during capture and the captured frame size is read from the raw
    video.
    """
    screen_w = bounds.get("screen_w")
    capture_scale = (capture_width / screen_w) if screen_w else 1.0
    return compute_logic_crop(
        bounds,
        capture_width=capture_width,
        capture_height=capture_height,
        capture_scale=capture_scale,
        inset=inset,
    )


def crop_is_within_logic_bounds(
    crop: dict[str, int],
    bounds: dict[str, int],
    *,
    capture_scale: float = 1.0,
    margin: int = 2,
) -> bool:
    """QA check: confirm the crop is contained within the Logic window bounds.

    Used to reject the legacy ``x:0`` full-width crop pattern that captured the
    background to the right of Logic (issue #137). Returns False when the crop
    starts left of / above the window or extends past its right / bottom edge.
    """
    bx = bounds["x"] * capture_scale
    by = bounds["y"] * capture_scale
    bw = bounds["w"] * capture_scale
    bh = bounds["h"] * capture_scale
    return (
        crop["x"] >= bx - margin
        and crop["y"] >= by - margin
        and crop["x"] + crop["w"] <= bx + bw + margin
        and crop["y"] + crop["h"] <= by + bh + margin
    )

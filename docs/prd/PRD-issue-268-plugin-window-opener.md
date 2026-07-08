# PRD: Issue #268 - set_param_verified Plugin Window Opener

**Version**: 1.0
**Date**: 2026-07-08
**Status**: Implemented
**Issue**: https://github.com/MongLong0214/logic-pro-mcp/issues/268
**Size**: M

## 1. Problem

`logic_plugins.set_param_verified` can see the target Compressor insert through
`get_inventory`, but fails before writing when the Compressor editor window is not
already open:

```json
{
  "state": "C",
  "error": "window_open_failed",
  "write_attempted": false,
  "what_was_observed": "no open plugin window titled 'Chords' exposes the 'Threshold' control, and one could not be opened"
}
```

The current production path says it will try to open the plugin editor, but the
default opener is a no-op:

```swift
static let liveNoOpPluginWindowOpener: PluginWindowOpener = { _, _, _, _ in nil }
```

So the implementation only succeeds when the right plugin editor window is
already open. That makes `set_param_verified` brittle even when the inventory,
track selection, slot identity, and parameter metadata are all valid.

## 2. Goals

- G1: When the target insert is occupied and readable, `set_param_verified`
  opens/acquires the target plugin editor if no matching editor window is already
  open.
- G2: The write remains fail-closed. No parameter write may occur unless a plugin
  window with the requested control is positively identified.
- G3: Failure diagnostics include enough window/control evidence to distinguish
  "could not open" from "opened something but no matching control".
- G4: The local Logic Pro 12.3 repro for Compressor `threshold` reaches State A.
- G5: The fix is covered by red-first fixture tests plus live E2E evidence.

## 3. Non-Goals

- NG1: Guaranteeing every plugin/preset/layout in Logic Pro forever. Apple AX UI
  is not a stable public automation contract.
- NG2: Adding verified write support for new plugins or parameters.
- NG3: Reworking the insert-slot inventory enumerator.
- NG4: Changing the Honest Contract State A/B/C schema.

## 4. Design

### 4.1 Opener responsibility

Replace the no-op production opener with a real opener that:

1. Reuses the selected track and verified insert slot from the existing
   `performVerifiedParamWrite` path.
2. Presses/clicks the target occupied insert slot's editor/open control.
3. Polls Logic's AX windows for a newly available plugin editor.
4. Accepts the window only if it exposes the requested parameter slider.
5. Returns nil if no safe window/control match is found.

The opener should be driven by slot provenance, not by title text alone. A title
match remains useful evidence, but the safety gate is the requested AX control
inside a window opened from the target slot.

### 4.2 Diagnostics

When window acquisition fails, the State C payload should include a bounded
census:

- requested track name
- requested insert index
- requested slider description
- visible candidate window titles
- visible slider descriptions discovered in candidate windows
- whether an open-slot action was attempted

This evidence must not include local absolute paths, project names beyond the
already requested track name, or private machine metadata.

### 4.3 Safety invariant

The only acceptable write path is:

```
verified track selection
  -> verified occupied insert slot
  -> open/acquire plugin window
  -> verify requested AXSlider
  -> write AXValue
  -> read back AXValue
  -> State A only on tolerance match
```

If any step fails, the response stays State C and `write_attempted:false` until
the actual slider write step.

## 5. Acceptance Criteria

- AC-1: Fixture test fails on current `main`: closed plugin window plus no
  opener produces `window_open_failed`.
- AC-2: Fixture test passes after fix: the default production-style opener opens
  a target-slot-backed window and `set_param_verified` reaches State A.
- AC-3: Wrong window/wrong slider fixture remains State C with
  `write_attempted:false`.
- AC-4: Diagnostics expose candidate window/slider evidence on acquisition
  failure.
- AC-5: Live Logic Pro 12.3 E2E: reproduced Compressor `threshold` target that
  previously returned `window_open_failed` now returns State A.
- AC-6: Full relevant tests and build pass; final PR links this PRD and the
  ticket board.

## 6. Verification Summary

- Red-first fixture reproduced the pre-fix `window_open_failed` path when the
  plugin window starts closed.
- The production opener now presses/clicks the target insert slot, polls for the
  editor window, and accepts it only when the requested slider is present.
- Safety fixtures cover the opened-but-wrong-slider case and keep
  `write_attempted:false`.
- Local Logic Pro 12.3 E2E replay moved the reproduced Compressor `threshold`
  case from State C `window_open_failed` to State A with
  `write_source:"ax_plugin_window"` and `verify_source:"ax_plugin_window"`.
- Final verification commands and PR evidence are tracked in the ticket board.

## 7. Ticket Board

Execution tickets live under `docs/tickets/issue-268-plugin-window-opener/`.

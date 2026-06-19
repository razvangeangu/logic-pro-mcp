# Issue #40 Verification - 2026-06-19

## Root cause

- The affected dispatchers forwarded routed channel results with `toolTextResult(result)` and never reinterpreted Honest Contract State B.
- That meant key-command / fallback paths such as `logic_edit.select_all`, `logic_edit.quantize`, `logic_navigate.zoom_to_fit`, `logic_navigate.create_marker`, `logic_transport.toggle_metronome`, and `logic_transport.goto_position` surfaced outer MCP success even when the nested payload already said `verified:false`.
- The repo already had observable readback surfaces for transport state (`transport.get_state`, `logic://transport/state`) and markers (`nav.get_markers`, `logic://markers`), but the dispatchers never used them to upgrade or reject fallback writes.
- `create_marker` also accepted an optional `name`, while the live key-command path only fires the shortcut. Pre-fix, a marker-name mismatch still looked like a clean success.

## Fix

- Added shared dispatcher helpers for decoding Honest Contract envelopes and promoting nested State B to outer `isError:true`.
- `logic_edit.select_all`, `logic_edit.quantize`, `logic_navigate.zoom_to_fit`, and `logic_navigate.set_zoom` now surface unverified State B as outer error instead of false-green success.
- `logic_transport.goto_position` plus `logic_navigate.goto_bar` / `goto_marker` now post-verify unverified writes against live transport state and only return State A when the observed position matches.
- `logic_transport.toggle_metronome` now post-verifies fallback writes against live transport state.
- `logic_navigate.create_marker` now compares live marker snapshots before/after, updates the marker cache, returns State A only on proven marker creation, and returns outer-error State B on no delta or requested-name mismatch.
- Added dispatcher regression coverage for the new transport-state, marker-readback, and outer-error behaviors.

## Automated verification

- `swift test --filter DispatcherTests`
  - Passed: 94 tests

## Live verification

Environment:
- Logic Pro 12.2 running from `/Applications/Logic Pro.app`
- Release binary: `/private/tmp/logic-pro-mcp-issue40/.build/release/LogicProMCP`
- Marker probe pre-step: manually opened `Navigate > Open Marker List` so `logic://markers` had the Logic 12.2 marker surface available

Observed results:

- `logic_transport.goto_position { "bar": 1 }`
  - Returned State A:
    - `success:true`
    - `verified:true`
    - `requested:"1.1.1.1"`
    - `observed:"1.1.1.1"`
    - `via:"slider"`
  - `logic://transport/state` immediately reported `position:"1.1.1.1"`.

- `logic_edit.select_all`
  - Returned outer `isError:true` with nested State B `reason:"readback_unavailable"`.

- `logic_edit.quantize { "value": "1/16" }`
  - Returned outer `isError:true` with nested State B `reason:"readback_unavailable"`.

- `logic_navigate.zoom_to_fit`
  - Returned outer `isError:true` with nested State B `reason:"readback_unavailable"`.

- `logic_transport.toggle_metronome`
  - Returned outer `isError:true` with nested State B:
    - `reason:"readback_mismatch"`
    - `verification_source:"transport_state"`
    - `previous_enabled:false`
    - `requested_enabled:true`
    - `observed_enabled:false`
  - `logic://transport/state` confirmed the metronome flag never changed in this UI state.

- `logic_navigate.create_marker {}`
  - Returned outer `isError:true` with nested State B:
    - `reason:"readback_mismatch"`
    - `verification_source:"logic://markers"`
    - `marker_count_before:0`
    - `marker_count_after:0`
  - `logic://markers` remained empty before and after the shortcut.

## Conclusion

- Issue #40's contract bug is fixed: unverified key-command-backed commands no longer present as clean MCP success.
- Live verification also surfaced two remaining environment/setup truths that are now reported honestly instead of masked:
  - the current metronome toggle path did not change transport state in this Logic session
  - the current marker-create shortcut produced no observable marker delta in `logic://markers`

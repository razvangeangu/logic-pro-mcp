# Issue 35 Verification - 2026-06-19

## Root cause

- `logic_tracks.create_audio`, `create_instrument`, `create_drummer`, and `create_external_midi` forwarded the routed `ChannelResult` directly to the tool layer.
- When the router fell back to non-verifying channels, nested Honest Contract State B envelopes (`success:true`, `verified:false`) were surfaced as outer tool success.
- The AX create-track path already verified a count delta, but it did not expose the created track's observed index/name/type metadata.
- When Logic left a modal Create New Track dialog up, the channel returned a generic count-failure error instead of an explicit waiting-for-user/dialog state.

## Fix

- `TrackDispatcher` now marks all `create_*` commands as outer errors when the routed channel returns an unverified Honest Contract success envelope.
- `AccessibilityChannel.createTrackViaMenu(...)` now:
  - captures the post-create selected track index and name when the count delta is verified
  - tags the created type from the exact menu action with `observed_track_type` plus `track_type_verification_source:"menu_clicked"`
  - includes `verification_source:"track_count_delta"`
  - preserves the legacy AX type heuristic as diagnostics via `observed_track_type_inferred`
- If the track count still has not moved and a modal dialog is still present, the channel now returns State B `retry_exhausted` with `dialog_present:true` and `waiting_for_user:true` instead of a fabricated success or a vague failure.

## Deterministic test coverage

Executed in `/private/tmp/logic-pro-mcp-issue35` on 2026-06-19:

```bash
swift test --filter testAccessibilityChannelCreateInstrumentVerifiesTrackCountIncrease
swift test --filter testAccessibilityChannelCreateInstrumentFailsWhenTrackCountDoesNotIncrease
swift test --filter testAccessibilityChannelCreateInstrumentReportsDialogPendingWhenModalPersists
swift test --filter testTrackDispatcherCreateCommandsReturnErrorForUnverifiedEnvelope
swift test --skip-build --filter DispatcherTests
```

Observed results:

- All 4 targeted create-track regression tests passed.
- `swift test --skip-build --filter DispatcherTests` passed all 88 dispatcher tests.

Added/updated regression tests:

- `testAccessibilityChannelCreateInstrumentVerifiesTrackCountIncrease`
- `testAccessibilityChannelCreateInstrumentReportsDialogPendingWhenModalPersists`
- `testTrackDispatcherCreateCommandsReturnErrorForUnverifiedEnvelope`

## Live E2E verification

Environment:

- Logic Pro 12.2
- Release binary: `/private/tmp/logic-pro-mcp-issue35/.build/release/LogicProMCP`
- Open project during probe: `Untitled 3 - Tracks`

Probe note:

- The live project already carried 4 tracks because a prior create probe on this same Logic session could not clean itself up through `track.delete` (that separate menu-path failure is unrelated to this ticket). The verification run below uses the 4-track baseline it actually observed.

Health snapshot before the run:

```json
{
  "logic_pro_running": true,
  "logic_pro_has_document": true,
  "logic_pro_version": "12.2",
  "project": "Untitled 3 - Tracks",
  "track_count": 4
}
```

Track resource before `create_instrument`:

```json
[
  {"id": 0, "name": "Deluxe Classic", "type": "audio", "isSelected": false},
  {"id": 1, "name": "Deluxe Classic", "type": "audio", "isSelected": true},
  {"id": 2, "name": "Studio Grand", "type": "audio", "isSelected": false},
  {"id": 3, "name": "Studio Grand", "type": "audio", "isSelected": false}
]
```

Call `logic_tracks.create_instrument`:

```json
{
  "dialog_confirmation_attempted": false,
  "menu_clicked": "New Software Instrument Track",
  "observed_delta": 1,
  "observed_track_index": 2,
  "observed_track_name": "Deluxe Classic",
  "observed_track_type": "software_instrument",
  "observed_track_type_inferred": "audio",
  "requested_delta": 1,
  "success": true,
  "track_count_after": 5,
  "track_count_before": 4,
  "track_type_verification_source": "menu_clicked",
  "verification_source": "track_count_delta",
  "verified": true
}
```

Track resource after `create_instrument` plus `logic_system.refresh_cache`:

```json
[
  {"id": 0, "name": "Deluxe Classic", "type": "audio", "isSelected": false},
  {"id": 1, "name": "Deluxe Classic", "type": "audio", "isSelected": false},
  {"id": 2, "name": "Deluxe Classic", "type": "audio", "isSelected": true},
  {"id": 3, "name": "Studio Grand", "type": "audio", "isSelected": false},
  {"id": 4, "name": "Studio Grand", "type": "audio", "isSelected": false}
]
```

Conclusion:

- The public tool no longer flattens fallback State B create responses into outer success.
- Verified create success now includes the created track index/name plus an explicit type-verification source.
- On this Logic 12.2 project, the legacy AX track-type heuristic still inferred `audio`; the response now exposes that mismatch as diagnostics instead of silently pretending AX proved the type.

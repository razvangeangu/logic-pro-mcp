# Issue 55 Verification - 2026-06-19

## Root cause

- `TrackDispatcher.handle(command: "arm")` and `TrackDispatcher.handle(command: "arm_only")` only checked `ChannelResult.isSuccess`.
- Fallback channels can return Honest Contract State B envelopes for `track.set_arm`, for example `{"success":true,"verified":false,"reason":"readback_unavailable",...}` from the MCU strip-button path.
- The dispatcher flattened that nested `verified:false` envelope into an outer tool success, so demo QA and transcript classification overstated certainty.
- `arm_only` also hid the target/readback metadata inside a nested string instead of surfacing it at the outer response level.

## Fix

- `logic_tracks.arm` now returns an outer tool error when `track.set_arm` succeeds but the nested Honest Contract envelope is unverified.
- `logic_tracks.arm_only` now:
  - treats unverified target-arm and unverified disarm operations as outer errors
  - returns structured outer fields for `target_track`, `requested_enabled`, `observed_enabled`, `verification_source`, `disarmed`, `unverifiedDisarm`, `failedDisarm`, and `verified`
  - preserves the raw nested arm envelope in `detail`
- AX record-arm verification now tags successful readback with `verification_source: "ax_value"`.
- MCU strip-button fallbacks now tag unverified record-arm writes with `write_source: "mcu"` and `verification_source: "mcu_led_echo"`.

## Deterministic test coverage

Executed in `/private/tmp/logic-pro-mcp-issue55` on 2026-06-19:

```bash
swift test --skip-build --filter testArmReturnsErrorForUnverifiedEnvelope
swift test --skip-build --filter testArmOnlyTreatsUnverifiedTargetArmAsError
swift test --skip-build --filter testArmOnlyTreatsUnverifiedDisarmAsError
swift test --skip-build --filter testArmOnlySuccessPathReportsArmedSuccess
swift test --skip-build --filter DispatcherTests
```

Observed results:

- All 4 targeted arm verification tests passed.
- `swift test --skip-build --filter DispatcherTests` passed all 90 dispatcher tests.

Added/updated regression tests:

- `testArmReturnsErrorForUnverifiedEnvelope`
- `testArmOnlyTreatsUnverifiedTargetArmAsError`
- `testArmOnlyTreatsUnverifiedDisarmAsError`
- `testArmOnlySuccessPathReportsArmedSuccess`

## Live E2E verification

Environment:

- Logic Pro 12.2
- Release binary: `/private/tmp/logic-pro-mcp-issue55/.build/release/LogicProMCP`
- Open project during probe: `Untitled 3 - Tracks`

Probe note:

- Track-arm state is resource-backed, so the verification run called `logic_system.refresh_cache` between steps to eliminate poller lag from the probe itself.

Health snapshot before the run:

```json
{
  "logic_pro_running": true,
  "logic_pro_has_document": true,
  "logic_pro_version": "12.2",
  "project": "Untitled 3 - Tracks",
  "track_count": 3
}
```

Reset both tracks, then arm track 0:

```json
{
  "arm0": {
    "action": "mouse-click",
    "button": "Record",
    "observed": true,
    "requested": true,
    "success": true,
    "track": 0,
    "verification_source": "ax_value",
    "verified": true
  }
}
```

Track resource after `arm(0, true)` plus `refresh_cache`:

```json
[
  {"id": 0, "name": "Deluxe Classic", "isArmed": true},
  {"id": 1, "name": "Studio Grand", "isArmed": false},
  {"id": 2, "name": "Studio Grand", "isArmed": false}
]
```

Call `logic_tracks.arm_only {index: 1}`:

```json
{
  "action": "mouse-click",
  "armed": 1,
  "armedSuccess": true,
  "button": "Record",
  "detail": "{\"action\":\"mouse-click\",\"button\":\"Record\",\"observed\":true,\"requested\":true,\"success\":true,\"track\":1,\"verification_source\":\"ax_value\",\"verified\":true}",
  "disarmed": [0],
  "failedDisarm": [],
  "observed_enabled": true,
  "requested_enabled": true,
  "target_track": 1,
  "unverifiedDisarm": [],
  "verification_source": "ax_value",
  "verified": true
}
```

Track resource after `arm_only(1)` plus `refresh_cache`:

```json
[
  {"id": 0, "name": "Deluxe Classic", "isArmed": false},
  {"id": 1, "name": "Studio Grand", "isArmed": true},
  {"id": 2, "name": "Studio Grand", "isArmed": false}
]
```

Conclusion:

- The outer `arm_only` response now carries verification metadata instead of hiding it in a nested string.
- Verified AX success stays outer-success only when the target arm matches the observed state.
- The live run confirmed `arm_only` reported `disarmed: [0]` and the resource state showed track 0 disarmed while track 1 remained armed.

# Logic Pro MCP — Honest Contract

> Response contract that all mutating operations comply with starting from v3.1.0+.

## Why

GUI automation (AX, CoreMIDI, Scripter) is inherently asynchronous with limited verifiability. In v3.0.x the assumption was "AX write success = operation success", but in practice the write return code can succeed vacuously, or Logic can accept the write without the actual state changing.

The Honest Contract lets **clients (LLM agents) clearly distinguish between confirmed success, uncertain success, and failure**.

## 3-State Contract

### State A — Confirmed Success
```json
{"success": true, "verified": true, "requested": <X>, "observed": <X>}
```
- AX write succeeded and the actual state `<X>` was confirmed via read-back.
- The client can safely proceed to the next step.

### State B — Uncertain Success
```json
{"success": true, "verified": false, "reason": "<enum>", "requested": <X>, "observed": null | <Y>}
```
- The AX write returned `kAXErrorSuccess` or bytes were transmitted successfully.
- Read-back was unavailable, timed out, or returned a mismatch.
- `reason` values:
  - `echo_timeout_<ms>` — no MCU feedback echo within the window (± `2/16383` tolerance)
  - `readback_unavailable` — AX attribute not exposed (Logic version/state issue)
  - `readback_mismatch` — the read value (`observed`) differs from the requested value (`requested`). For `track.select`, a different index was selected.
  - `retry_exhausted` — read-back metadata did not surface after 6 retries (100 ms apart, 600 ms total). Distinct from `readback_mismatch`: the former means "value differs", the latter means "value never surfaced".
- The client must perform follow-up verification (e.g. query `logic://tracks`).

### State C — Hard Failure
```json
{"success": false, "error": "<enum>", "axCode": <int?>, "hint": "<str?>"}
```
- The AX write itself returned a `kAXError` or an explicit failure.
- Retrying will produce the same state — a different path is required.
- `error` values: `ax_write_failed`, `element_not_found`, `permission_denied`, `logic_not_running`, etc.

## Which operations return the 3-state contract

As of v3.1.0:
- `track.select`
- `track.set_instrument`
- `mixer.set_volume`, `mixer.set_pan`, `mixer.set_master_volume`
- `transport.set_cycle_range`

Planned for future releases:
- All remaining `track.*`, `mixer.*`, `transport.*` mutating operations.

## State resource (query)

Read-only resources such as `logic://tracks` and `logic://library/inventory` use a cache envelope instead of the 3-state contract:

```json
{"cache_age_sec": 12, "fetched_at": "2026-04-24T13:00:00Z", "data": [...]}
```

- `cache_age_sec`: Cache age in seconds. `0` means just refreshed.
- The client can request a refresh via the `refresh` flag if needed.

## Recommended client pattern

```pseudo
result = call("track.set_instrument", {...})

if not result.success:
    # State C: hard fail, try alternate path
    abort_or_fallback(result.error)

elif result.verified:
    # State A: confirmed, proceed
    next_step()

else:
    # State B: uncertain
    if result.reason == "echo_timeout_500ms":
        sleep(0.5)
        actual = query("logic://tracks")
        if actual.matches(result.requested):
            proceed()
        else:
            retry_or_abort()
    # ... handle other reasons
```

## Developer guide (server side)

When adding a new mutating operation:
1. AX write → check success (State C branch)
2. On write success, attempt read-back
3. Read-back success + value matches → State A
4. Read-back failure or mismatch → State B with explicit `reason`
5. All branches must return the `verified` field
6. Add 3-state test cases to `Tests/HonestContractTests.swift`

Violations:
- ❌ `return {"success": true}` — missing `verified`
- ❌ `return {"verified": false}` — missing `reason`
- ❌ `return {"success": false}` — missing `error`
- ❌ No read-back code at all + `verified:true`

## Related release notes

- **v3.1.0** — Initial Honest Contract introduced. T2–T8 tickets completed.
- **v3.1.0 Ralph-2 fix** — MCU `pollFaderEcho` stale-cache false-positive blocked (send-time freshness stamp introduced); `track.select` mismatch reclassified as `readback_mismatch` (previously `retry_exhausted`); `scan_library {mode:both}` also updates `lastPanelScan`; `track.set_instrument` / `transport.set_cycle_range` State C `.error(...)` wrapping unified; resource envelope (`{cache_age_sec, fetched_at, data}` / `{source, root}`) correctly declared as a breaking change in CHANGELOG.

# PRD — Logic Pro MCP v3.1.0 "Honest Contract"

> Historical record (2026-06-09 docs refresh): latest production-readiness and live E2E evidence is in `README.md`, `CHANGELOG.md`, and `docs/live-verify-v3.4.6.md`; this file remains preserved implementation context.

**Status**: Approved
**Size**: L
**Level**: 1.5 (no irreversible changes, external user contract impact → 3-party consensus required)
**Authored**: 2026-04-24
**Owner**: Isaac (weplay0628@gmail.com)

---

## 1. Problem Statement

v3.0.9 Guardian full audit result: **FAIL**. Core issue: multiple mutating operations return success without verifying the AX write result, causing clients (Claude/LLM agents) to interpret actually-failed calls as successful — a pervasive "dishonest contract."

### Specific defects
| # | Location | Symptom |
|---|----------|---------|
| P0-1 | `AccessibilityChannel.swift:1766-1773` | `set_instrument` wraps `selectPath` internal return as success without read-back. Client has no way to know if the wrong patch was loaded |
| P1-1 | `AXLogicProElements.swift` `selectTrackViaAX` | HTTP success returned even when `verified:false` after `AXSelectedChildren` write. Honest contract violation |
| P1-2 | `MCUChannel.swift:148/161/169` | `set_volume/pan/master_volume` sends MCU bytes only. Does not confirm Logic echo (fader position feedback) |
| P1-3 | `transport.set_cycle_range` AX path (line 637) | No `verified` field — schema mismatch with osascript fallback |
| P1-4 | `README.md:154` | "every patch addressable" is false. Disk-only entries succeed at `resolve_path` but fail at `selectPath` |
| P1-5 | `scan_library {mode:disk}` | lastScan cache contamination → disk entries bleed into panel-only queries |
| P2 | state resources | No `cache_age_sec` → client cannot judge staleness |

## 2. Goals / Non-Goals

### Goals
1. All mutating operations comply with the **Honest Contract** invariants
2. Clients can clearly distinguish confirmed success vs uncertain vs failure via the `verified` field
3. v3.0.9 users can upgrade **without breaking changes** (additive fields + existing success paths retained)
4. Release after 3+ cycles of live Logic Pro verification

### Non-Goals
- Adding new features
- Adding new communication channels beyond the AX API
- Backward compatibility with versions prior to v3.0.9

## 3. Honest Contract Specification (Invariants)

All mutating operations MUST return exactly one of the following 3 states:

### State A — `success: true, verified: true`
AX write succeeded + actual state confirmed via read-back.

```json
{"success": true, "verified": true, "requested": "Classic Suitcase Mk IV", "observed": "Classic Suitcase Mk IV"}
```

### State B — `success: true, verified: false`
AX write succeeded (kAXErrorSuccess or bytes reached Logic) but read-back was unavailable / timed out / mismatched. **Explicitly signals uncertainty to the client.**

```json
{"success": true, "verified": false, "reason": "echo_timeout_500ms", "requested": 100, "observed": null}
```

`reason` enum:
- `echo_timeout_<ms>` — MCU feedback timeout
- `readback_unavailable` — AX read-back attribute not exposed
- `readback_mismatch` — write succeeded but read value differs (SMF fresh track lag, etc.). For `track.select`, a different index was selected.
- `retry_exhausted` — after 6 retries (100ms interval, 600ms total), read-back metadata still not surfaced. Distinct from value mismatch (that is `readback_mismatch`).

### State C — `success: false, error: <...>`
AX write itself failed (kAXError returned, etc.). Retrying will not help.

```json
{"success": false, "error": "ax_write_failed", "axCode": -25212, "hint": "…"}
```

### Contract violation = bug
- `success:true` with no `verified` field → violation
- `verified:false` returned without `reason` → violation
- `success:true` with no read-back call in the code → violation (even if `verified` field is present)

## 4. Scope — Ticket Inventory

| ID | Title | Priority | Files |
|----|-------|----------|-------|
| T2 | set_instrument read-back | P0 | AccessibilityChannel.swift, LibraryAccessor.swift |
| T3 | track.select verified enforcement | P1 | AXLogicProElements.swift |
| T4 | MCU mixer echo polling | P1 | MCUChannel.swift, MCUEchoListener (new) |
| T5 | set_cycle_range verified | P1 | AccessibilityChannel.swift |
| T6 | scan_library cache separation | P1 | LibraryAccessor.swift, LibraryDiskScanner.swift |
| T7 | cache_age_sec in resources | P2 | Resources/*.swift |
| T8 | README + CHANGELOG honesty | P1 | README.md, CHANGELOG.md |

## 5. Key Risks

1. **MCU echo timing uncertainty** — fader feedback latency varies significantly with Logic version and project load state. A fixed 500ms may produce false negatives. **Mitigation**: A/B live measurement with 250/500/1000ms windows; default 500ms + env override.
2. **SMF-fresh track delay** — newly created tracks appear in the AX tree later than expected. Tightening track.select to a strict error could break existing scripts. **Mitigation**: 6 retries (100ms interval, 600ms total) — if metadata never surfaces: `verified:false + reason:retry_exhausted`; if metadata surfaces but wrong index is selected: `readback_mismatch`. Strict error only on AX write failure itself.
3. **Library Panel read-back method** — selected patch name is read via `Inventory.currentPreset` (`AXList`'s `AXSelectedChildren` → first selected child's `AXValue`). At Ralph-2 time, a secondary channel-strip plugin-name fallback via `PluginInspector.topInstrumentName` is not implemented (defer to a future release if needed).

## 6. Acceptance Criteria

- [ ] All mutating ops (`set_instrument`, `track.select`, `mixer.*`, `set_cycle_range`) return 3-state response
- [ ] `verified:false` MUST include a `reason` field
- [ ] `success:false` MUST include an `error` field (string enum)
- [ ] Each op verified for 3+ cycles against live Logic Pro and PASS
- [ ] `scan_library {mode:disk}` call does not contaminate panel-only queries
- [ ] `logic://tracks`, `logic://library/inventory` include `cache_age_sec` field
- [ ] README + CHANGELOG updated: "every patch" removed, verified field contract documented
- [ ] Build 3종 pass (swift build --configuration release / swift test / swift format lint)
- [ ] `docs/HONEST-CONTRACT.md` client guide added

## 7. Phase 1 Execution Order

1. **T2 (P0)** — set_instrument read-back: Library Panel AX dump → confirm attribute → implement + test
2. **T3 (P1)** — track.select enforcement: inject retry/3-state return into existing code
3. **T5 (P1)** — set_cycle_range verified field (single read-back, lowest risk → immediately after T3)
4. **T4 (P1)** — MCU echo polling: new MCUEchoListener (most complex, most time-consuming)
5. **T6 (P1)** — scan_library cache separation (independent)
6. **T7 (P2)** — cache_age field (bulk across all resources)
7. **T8** — documentation update (last)

## 8. Definition of Done

- Phase 2 Guardian + Boomer ALL PASS
- Live Logic Pro verification (10+ calls) passed
- v3.1.0 tag + Formula SHA256 sync + GitHub release published
- CHANGELOG v3.1.0 entry

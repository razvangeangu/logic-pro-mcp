# T2: MIDIDispatcher `validatePort` + `validateMidiChannel` helpers

> Historical record (2026-06-05 docs refresh): latest production-readiness and live E2E evidence is in `README.md`, `CHANGELOG.md`, and `docs/live-verify-v3.4.5-rc5.md`; this file remains preserved implementation context.

**PRD Ref**: PRD-issue1-keycmd-port-routing > §3 AC-1.3, AC-2.1-2.5, §4.3 helper sketches
**Priority**: P1 (High — foundational, blocks T5)
**Size**: M (2-4h)
**Status**: Todo
**Depends On**: None

---

## 1. Objective
Add two new helper functions inside `MIDIDispatcher`:
- `validatePort(_:) -> Result<String, String>` — port enum validation (`"midi"|"keycmd"`, default `"midi"`)
- `validateMidiChannel(_:) -> Result<UInt8, String>` — 1-based channel input → wire byte (0..15) + Value case-switch (int/double/string), rejects fractional (1.5 etc.)

## 2. Acceptance Criteria
- [ ] AC-0 (visibility, Phase 4 Loop 1 boomer P1): `validatePort` + `validateMidiChannel` declared as `internal static func` (for test access). `private` prevents white-box test compilation. Uses `@testable import`.
- [ ] AC-1: `validatePort(["port": .string("midi")])` → `.success("midi")`
- [ ] AC-2: `validatePort(["port": .string("keycmd")])` → `.success("keycmd")`
- [ ] AC-3: `validatePort([:])` (missing) → `.success("midi")` (default, backward compat)
- [ ] AC-4: `validatePort(["port": .string("scripter")])` → `.failure(...)` (NG5 — unsupported in v3.1.5)
- [ ] AC-5: `validatePort(["port": .string("foo")])` → `.failure("port must be one of: midi, keycmd")`. **`validatePort(["port": .string("")])` (empty string) also `.failure`** — explicit reject (Phase 4 Loop 1 tester P1 — sketch/test consistency).
- [ ] AC-6: `validateMidiChannel(["channel": .int(1)])` → `.success(0)` (wire byte 0)
- [ ] AC-7: `validateMidiChannel(["channel": .int(16)])` → `.success(15)` (wire byte 0xF)
- [ ] AC-8: `validateMidiChannel(["channel": .int(0)])` → `.failure("channel must be integer 1..16 (1-based)")`
- [ ] AC-9: `validateMidiChannel(["channel": .int(17)])` → `.failure(...)`
- [ ] AC-10: `validateMidiChannel(["channel": .double(1.0)])` → `.success(0)` (whole-number double accepted)
- [ ] AC-11: `validateMidiChannel(["channel": .double(1.5)])` → `.failure(...)` (fractional rejected)
- [ ] AC-12: `validateMidiChannel(["channel": .string("1")])` → `.success(0)` (string-encoded int OK)
- [ ] AC-13: `validateMidiChannel(["channel": .string("1.5")])` → `.failure(...)` (string with fractional)
- [ ] AC-14: `validateMidiChannel([:])` (missing) → `.success(0)` (default = 1-based ch1)

## 3. TDD Spec (Red Phase)

### 3.1 Test Cases

| # | Test Name | Type | Description | Expected |
|---|-----------|------|-------------|----------|
| 1 | `testValidatePortDefaultsToMidi` | Unit | port not specified | `.success("midi")` |
| 2 | `testValidatePortAcceptsKeycmd` | Unit | "keycmd" | `.success("keycmd")` |
| 3 | `testValidatePortRejectsScripter` | Unit | "scripter" (NG5) | `.failure` |
| 4 | `testValidatePortRejectsUnknown` | Unit | "foo" | `.failure(hint matches)` |
| 5 | `testValidatePortRejectsEmpty` | Unit | "" | `.failure` |
| 6 | `testValidateChannel1MapsToWire0` | Unit | channel:1 | `.success(0)` |
| 7 | `testValidateChannel16MapsToWire15` | Unit | channel:16 | `.success(15)` |
| 8 | `testValidateChannel0Rejected` | Unit | channel:0 | `.failure(hint)` |
| 9 | `testValidateChannel17Rejected` | Unit | channel:17 | `.failure` |
| 10 | `testValidateChannelMissingDefaultsToWire0` | Unit | channel not specified | `.success(0)` |
| 11 | `testValidateChannelWholeDoubleAccepted` | Unit | 1.0 | `.success(0)` |
| 12 | `testValidateChannelFractionalDoubleRejected` | Unit | 1.5 | `.failure` |
| 13 | `testValidateChannelStringIntAccepted` | Unit | "5" | `.success(4)` |
| 14 | `testValidateChannelStringFractionalRejected` | Unit | "1.5" | `.failure` |
| 15 | `testValidateChannelNegativeRejected` | Unit | -1 | `.failure` |
| 16 | `testValidateChannelBoolRejected` | Unit | `.bool(true)` (EC-1) | `.failure` |
| 17 | `testValidateChannelInfinityRejected` | Unit | `.double(Double.infinity)` (EC-4) | `.failure` |
| 18 | `testValidateChannelNaNRejected` | Unit | `.double(.nan)` (EC-4) | `.failure` |

### 3.2 Test File Location
- `Tests/LogicProMCPTests/MIDIDispatcherValidationHelpersTests.swift` (NEW)

### 3.3 Mock/Setup Required
- None (pure helper, params dictionary input only)

## 4. Implementation Guide

### 4.1 Files to Modify
| File | Change Type | Description |
|------|------------|-------------|
| `Sources/LogicProMCP/Dispatchers/MIDIDispatcher.swift` | Modify | Add 2 helpers (file-private static func) |
| `Tests/LogicProMCPTests/MIDIDispatcherValidationHelpersTests.swift` | Create | 15 unit tests |

### 4.2 Implementation Steps (Green Phase)
1. Add `validatePort(_ params: [String: Value]) -> Result<String, String>`:
   ```swift
   private static func validatePort(_ params: [String: Value]) -> Result<String, String> {
       // v0.4 consistency: `""` input is explicitly rejected, not treated as default (consistent with test #5)
       guard let raw = params["port"]?.stringValue else {
           return .success("midi") // not specified = default
       }
       let validPorts: Set<String> = ["midi", "keycmd"]
       guard validPorts.contains(raw) else {
           return .failure("port must be one of: midi, keycmd")
       }
       return .success(raw)
   }
   ```
2. Add `validateMidiChannel(_ params: [String: Value]) -> Result<UInt8, String>`:
   ```swift
   private static func validateMidiChannel(_ params: [String: Value]) -> Result<UInt8, String> {
       guard let raw = params["channel"] else {
           return .success(0) // default Ch 1 (wire 0)
       }
       let intCandidate: Int? = {
           switch raw {
           case .int(let n): return n
           case .double(let f): return Int(exactly: f)
           case .string(let s):
               // strict integer string only — reject "1.5"
               guard let i = Int(s) else { return nil }
               return i
           default: return nil
           }
       }()
       guard let v = intCandidate else {
           return .failure("channel must be integer 1..16 (1-based)")
       }
       guard (1...16).contains(v) else {
           return .failure("channel must be integer 1..16 (1-based)")
       }
       return .success(UInt8(v - 1))
   }
   ```
3. Run tests → all 15 PASS

### 4.3 Refactor Phase
- Consider moving to DispatcherSupport.swift as a shared helper (other dispatchers could reuse). However, for v3.1.5 scope, keep local in MIDIDispatcher (avoid over-engineering).

## 5. Edge Cases
- EC-1: `Value.bool` input (e.g., `{channel: true}`) — default case → `.failure` ✓
- EC-2: `Value.array` / `Value.object` — default case → `.failure` ✓
- EC-3: Very large integer (Int64.max) — rejected by `(1...16).contains` guard ✓
- EC-4: `Value.double(Double.infinity)` / `NaN` — `Int(exactly:)` returns nil → `.failure` ✓

## 6. Review Checklist
- [ ] Red: tests run → FAILED (helpers not implemented)
- [ ] Green: all 15 tests PASSED
- [ ] Refactor: PASSED maintained
- [ ] AC 14 items satisfied
- [ ] No conflict with DispatcherSupport.swift `intParam` and other existing helpers
- [ ] Existing MIDI tests: 0 regressions

# T1: HonestContract `.portUnavailable` FailureError + terminalErrorCodes

> Historical record. Current release-candidate evidence is in `README.md`, `CHANGELOG.md`, and `docs/live-verify-v3.6.0.md`; published stable evidence remains in `docs/live-verify-v3.5.0.md`; this file remains preserved implementation context.

**PRD Ref**: PRD-issue1-keycmd-port-routing > §4.1 step 7, §10.1 R7, OQ-7
**Priority**: P1 (High — foundational, blocks T4/T6)
**Size**: S (< 2h)
**Status**: Todo
**Depends On**: None

---

## 1. Objective
Add `.portUnavailable` case to `HonestContract.FailureError` enum and register it in the `terminalErrorCodes` set to block router fallback chain wrapping. Standardizes the envelope used by T4/T6.

## 2. Acceptance Criteria
- [ ] AC-1: `HonestContract.FailureError` gains `case portUnavailable = "port_unavailable"`
- [ ] AC-2: `terminalErrorCodes` set includes `"port_unavailable"` → `isTerminalStateC()` returns true
- [ ] AC-3: `encodeStateC(error: .portUnavailable, hint: ..., extras: [...])` produces a correct envelope (`{success:false, verified:false, error: "port_unavailable", hint: ..., ...extras}`)
- [ ] AC-4: Existing FailureError cases (invalidParams, elementNotFound, axWriteFailed, notImplemented) behavior unchanged

## 3. TDD Spec (Red Phase)

### 3.1 Test Cases

| # | Test Name | Type | Description | Expected |
|---|-----------|------|-------------|----------|
| 1 | `testPortUnavailableErrorRawValue` | Unit | `.portUnavailable.rawValue == "port_unavailable"` | rawValue matches |
| 2 | `testPortUnavailableInTerminalErrorCodes` | Unit | `HonestContract.terminalErrorCodes.contains("port_unavailable")` | true |
| 3 | `testIsTerminalStateCWithPortUnavailableEnvelope` | Unit | encodeStateC(.portUnavailable) result verified with isTerminalStateC() | true |
| 4 | `testEncodeStateCPortUnavailableEnvelopeShape` | Unit | envelope JSON contains `error:"port_unavailable"` + hint + extras | shape matches |
| 5 | `testExistingFailureErrorsUnaffected` | Unit | invalidParams/elementNotFound/axWriteFailed/notImplemented rawValues unchanged | regression |

### 3.2 Test File Location
- `Tests/LogicProMCPTests/HonestContractPortUnavailableTests.swift` (NEW)

### 3.3 Mock/Setup Required
- None (pure enum + static set + static encode function verification)

## 4. Implementation Guide

### 4.1 Files to Modify
| File | Change Type | Description |
|------|------------|-------------|
| `Sources/LogicProMCP/Utilities/HonestContract.swift` | Modify | Add case to `FailureError` enum, add to `terminalErrorCodes` set |
| `Tests/LogicProMCPTests/HonestContractPortUnavailableTests.swift` | Create | 5 unit tests |

### 4.2 Implementation Steps (Green Phase)
1. Add `case portUnavailable = "port_unavailable"` to `HonestContract.FailureError` enum (alphabetical or follow existing convention)
2. Add `"port_unavailable"` to the `terminalErrorCodes` static set definition
3. Run tests → all PASS

### 4.3 Refactor Phase
- Verify doc comment consistency with other cases
- Public API change (adding enum case is minor SemVer OK — PRD OQ-7 decision)

## 5. Edge Cases
- EC-1: External envelope parser encountering unknown reason gracefully handled (PRD R7) — no external impact verified

## 6. Review Checklist
- [ ] Red: tests run → FAILED (case missing)
- [ ] Green: tests run → PASSED
- [ ] Refactor: tests PASSED maintained
- [ ] AC 4 items satisfied
- [ ] Existing tests unbroken (especially ChannelRouter terminalState C tests)
- [ ] CHANGELOG-prep note: "FailureError +.portUnavailable" entry to be added (integrated in T8)

# T8: BackwardCompat regression + cleanup

> Historical record. Current stable evidence is in `README.md`, `CHANGELOG.md`, and `docs/live-verify-v3.7.0.md`; previous stable evidence remains in `docs/live-verify-v3.6.0.md`; this file remains preserved implementation context.

**PRD Ref**: PRD-issue7-logic12-read-paths > §9.3, AC-4.4
**Priority**: P2 (Medium)
**Size**: S (1h)
**Status**: Todo
**Depends On**: T4, T5

---

## 1. Objective
Verify Codable backward compatibility (v3.1.7 envelope decodes into v3.1.8 ProjectInfo) and clean up any leftover dead references after T6's AppleScript-primary deletion.

## 2. Acceptance Criteria
- [ ] AC-1: Decoding v3.1.7-shaped JSON (no `source` / `placeholder` / `last_saved_age_sec` fields) into v3.1.8 ProjectInfo / TrackState succeeds.
- [ ] AC-2: Encoding v3.1.8 ProjectInfo with `source: nil` produces the same JSON shape as v3.1.7 (no extraneous nulls if Swift Codable's default behavior emits them — accept as wire change).
- [ ] AC-3: All tests in the suite pass; total count ≥ 1019 + (T1:14) + (T2:4) + (T3:8) + (T4:7) + (T5:7) + (T6:+7-17) + (T7:5) - 17 deletes ≈ +35 net new tests.
- [ ] AC-4: `swift build -c release` clean.
- [ ] AC-5: `git grep -E 'markersViaAppleScript|projectInfoViaAppleScript|tracksViaAppleScript'` returns empty in `Sources/`.

## 3. TDD Spec (Red Phase)

### 3.1 Test Cases
File: `Tests/LogicProMCPTests/Issue7BackwardCompatTests.swift` (new)

| # | Test Name | Type | Expected |
|---|-----------|------|----------|
| 1 | `decodeV317ProjectInfo_succeeds` | Unit | hand-rolled v3.1.7 JSON → ProjectInfo with source=nil, lastSavedAgeSec=nil |
| 2 | `decodeV317TrackState_succeeds` | Unit | v3.1.7 TrackState JSON → placeholder=false (default) |
| 3 | `encodeV318ProjectInfo_NilSource_omitsKey` | Unit | encode with source=nil → JSON does NOT contain `"source":null` (use custom encode if Codable default is too noisy; otherwise accept) |
| 4 | `encodeV318TrackState_NilPlaceholder_omitsKey` | Unit | encode with placeholder=false → encoder behaviour stable |

### 3.2 Mock/Setup
- Pure JSON string fixtures from prior release output

## 4. Implementation Guide

### 4.1 Files to Modify
| File | Change | Description |
|------|--------|-------------|
| `Tests/LogicProMCPTests/Issue7BackwardCompatTests.swift` | Create | 4 tests |
| `Sources/LogicProMCP/State/StateModels.swift` | Modify (optional) | Custom `encode(to:)` if Codable default emits null fields and tests demand absence |

### 4.2 Implementation Steps (Green)
1. Add a v3.1.7 JSON snapshot string in test file.
2. Use `JSONDecoder()` with `iso8601` strategy to decode.
3. Verify new fields default correctly.
4. If Codable default behavior emits `"source":null`, decide: accept (additive shape change is harmless for JSON) OR add custom encode that skips nil. Prefer accept (saves churn). If existing tests break, then customise.

### 4.3 Refactor Phase
- Final `git grep` confirms no orphan references to deleted symbols.

## 5. Edge Cases
- Reverted v3.1.7 binary reading v3.1.8 JSON: covered by Codable default ignoring unknown keys (already tested).

## 6. Review Checklist
- [ ] Red: 4 tests fail
- [ ] Green: 4 tests pass; full build clean
- [ ] `grep` for deleted symbols returns empty
- [ ] Test count delta net positive (≥ +25)

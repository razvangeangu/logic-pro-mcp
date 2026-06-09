# T3: NoteSequenceParser API Change — `Result<[ParsedNote], NoteSequenceParseError>`

> Historical record (2026-06-09 docs refresh): latest production-readiness and live E2E evidence is in `README.md`, `CHANGELOG.md`, and `docs/live-verify-v3.4.6.md`; this file remains preserved implementation context.

**PRD Ref**: PRD-issue1-keycmd-port-routing > §4.3 NoteSequenceParser API, AC-2.1, AC-2.6 table #2
**Priority**: P1 (High — foundational, blocks T5/play_sequence/record_sequence)
**Size**: M (2-4h)
**Status**: Todo
**Depends On**: None (independent of T1)

---

## 1. Objective
Change `NoteSequenceParser.parse(_:)` return type from `[ParsedNote]` (silent fall-through) → `Result<[ParsedNote], NoteSequenceParseError>` (strict whole-parse-fail). Unify the `ch` field semantic to 1-based (input 1..16 → wire 0..15). Update 2 call sites (TrackDispatcher, CoreMIDIChannel).

## 2. Acceptance Criteria
- [ ] AC-1: `NoteSequenceParser.parse(_:)` return type = `Result<[ParsedNote], NoteSequenceParseError>`
- [ ] AC-2: `NoteSequenceParseError` enum defined: `.channelOutOfRange(segment: String, value: Int)` / `.invalidPitch(segment: String)` / `.invalidTiming(segment: String)` / `.malformed(segment: String)` — 4 cases
- [ ] AC-3: `"60,0,500,127,1"` (ch=1) → `.success([ParsedNote(channel: 0, ...)])` (wire 0)
- [ ] AC-4: `"60,0,500,127,16"` (ch=16) → `.success([ParsedNote(channel: 15, ...)])` (wire 0xF)
- [ ] AC-5: `"60,0,500,127,0"` (ch=0) → `.failure(.channelOutOfRange(segment: "60,0,500,127,0", value: 0))`
- [ ] AC-6: `"60,0,500,127,17"` (ch=17) → `.failure(.channelOutOfRange(...))`
- [ ] AC-7: `"60,0,500,127"` (ch omit) → `.success([ParsedNote(channel: 0, ...)])` (default Ch 1 wire 0)
- [ ] AC-8: Any invalid segment causes whole parse failure (`"60,0,500;invalid;70,1000,500"` → `.failure`)
- [ ] AC-9: `TrackDispatcher.handleRecordSequenceSMF` callsite updated — `.failure` returns toolTextResult error + hint
- [ ] AC-10: `CoreMIDIChannel.play_sequence` callsite (line ~286) updated — `.failure` returns `.error(...)`

## 3. TDD Spec (Red Phase)

### 3.1 Test Cases

| # | Test Name | Type | Description | Expected |
|---|-----------|------|-------------|----------|
| 1 | `testParseEmptyStringReturnsSuccessEmpty` | Unit | "" | `.success([])` |
| 2 | `testParseValidSegmentChannel1Maps` | Unit | "60,0,500,127,1" | `.success([{channel:0}])` |
| 3 | `testParseValidSegmentChannel16Maps` | Unit | "60,0,500,127,16" | `.success([{channel:15}])` |
| 4 | `testParseChannel0RejectedWhole` | Unit | "60,0,500,127,0" | `.failure(.channelOutOfRange)` |
| 5 | `testParseChannel17RejectedWhole` | Unit | "60,0,500,127,17" | `.failure` |
| 6 | `testParseChannelOmittedDefaultsCh1` | Unit | "60,0,500,127" | `.success([{channel:0}])` |
| 7 | `testParseInvalidPitchRejectedWhole` | Unit | "200,0,500,127,1" (pitch out 0..127) | `.failure(.invalidPitch)` |
| 8 | `testParseInvalidTimingRejectedWhole` | Unit | "60,-1,500,127,1" | `.failure(.invalidTiming)` |
| 9 | `testParseMalformedRejectedWhole` | Unit | "60" (insufficient fields) | `.failure(.malformed)` |
| 10 | `testParseMixedValidInvalidWholeFails` | Unit | "60,0,500;invalid;70,1000,500" | `.failure` (whole failure) |
| 11 | `testParseMultipleValidSegments` | Unit | "60,0,500,127,1;72,1000,500,100,2" | `.success([2 notes])` |
| 12 | `testRecordSequenceCallSiteHandlesFailure` | Integration | TrackDispatcher mock — invalid notes input | toolTextResult error + hint |
| 13 | `testPlaySequenceCallSiteHandlesFailure` | Integration | CoreMIDIChannel mock — invalid notes input | `.error(...)` returned |

### 3.2 Test File Location
- `Tests/LogicProMCPTests/NoteSequenceParserResultTests.swift` (NEW, 1-11)
- `Tests/LogicProMCPTests/TrackDispatcherRecordSequenceTests.swift` (extend 12)
- `Tests/LogicProMCPTests/CoreMIDIPlaySequenceTests.swift` (extend or NEW 13)

### 3.3 Mock/Setup Required
- TrackDispatcher / CoreMIDIChannel callsite tests reuse existing mock patterns

## 4. Implementation Guide

### 4.1 Files to Modify
| File | Change Type | Description |
|------|------------|-------------|
| `Sources/LogicProMCP/MIDI/NoteSequenceParser.swift` | Modify | API signature change + Error enum + 1-based ch conversion |
| `Sources/LogicProMCP/Dispatchers/TrackDispatcher.swift` | Modify | record_sequence callsite (line ~515) — Result handling |
| `Sources/LogicProMCP/Channels/CoreMIDIChannel.swift` | Modify | play_sequence callsite (line ~286) — Result handling |
| `Tests/LogicProMCPTests/NoteSequenceParserResultTests.swift` | Create | 11 unit tests |

### 4.2 Implementation Steps (Green Phase)
1. Add `enum NoteSequenceParseError: Error` to `NoteSequenceParser.swift`
2. Change `parse(_:)` signature: return type `Result<[ParsedNote], NoteSequenceParseError>`
3. Internal logic changes:
   - Retire `compactMap` (silent skip prohibited)
   - Early return `.failure(...)` on any segment parse failure
   - ch field: validate 1..16 input → wire byte `UInt8(ch - 1)`. Omitted = default 0 (Ch 1)
4. Update call sites:
   - `TrackDispatcher`: `.failure` → `toolTextResult("record_sequence: \(error)", isError: true)`
   - `CoreMIDIChannel`: `.failure` → `.error(HonestContract.encodeStateC(error: .invalidParams, hint: "\(error)"))`
5. Run tests → all PASS

### 4.3 Refactor Phase
- Optionally add `LocalizedError` conformance to `NoteSequenceParseError` for user-friendly messages
- Review hint message wording consistency at existing callsites

## 5. Edge Cases
- EC-1: `";"` (empty segments) — empty segment after split is skipped vs `.failure`? **Decision**: skip (empty results after split+trim are ignored)
- EC-2: 1024-note SMF import limit (v3.1.4 P1-4) — parser is unaware of limit. Caller (TrackDispatcher) maintains verification
- EC-3: Very long notes string (10K segments) — Result evaluates once, large memory OK (UInt8-based ParsedNote)

## 6. Review Checklist
- [ ] Red: all 13 tests FAILED confirmed
- [ ] Green: 13 PASSED
- [ ] Refactor: PASSED maintained
- [ ] AC 10 items satisfied
- [ ] Existing NoteSequenceParser tests (if any) migrated or BREAKING noted
- [ ] play_sequence / record_sequence existing tests: regression verified
- [ ] CHANGELOG-prep: BREAKING — NoteSequenceParser API signature change (internal module, no external impact)

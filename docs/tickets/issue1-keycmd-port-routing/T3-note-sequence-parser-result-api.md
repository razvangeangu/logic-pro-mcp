# T3: NoteSequenceParser API 변경 — `Result<[ParsedNote], NoteSequenceParseError>`

**PRD Ref**: PRD-issue1-keycmd-port-routing > §4.3 NoteSequenceParser API, AC-2.1, AC-2.6 표 #2
**Priority**: P1 (High — foundational, blocks T5/play_sequence/record_sequence)
**Size**: M (2-4h)
**Status**: Todo
**Depends On**: None (T1과 독립)

---

## 1. Objective
`NoteSequenceParser.parse(_:)` 반환 타입을 `[ParsedNote]` (silent fall-through) → `Result<[ParsedNote], NoteSequenceParseError>` (strict whole-parse-fail)로 변경. ch field semantic을 1-based로 통일 (입력 1..16 → wire 0..15). 호출부 2곳 (TrackDispatcher, CoreMIDIChannel) 갱신.

## 2. Acceptance Criteria
- [ ] AC-1: `NoteSequenceParser.parse(_:)` 반환 타입 = `Result<[ParsedNote], NoteSequenceParseError>`
- [ ] AC-2: `NoteSequenceParseError` enum 정의: `.channelOutOfRange(segment: String, value: Int)` / `.invalidPitch(segment: String)` / `.invalidTiming(segment: String)` / `.malformed(segment: String)` 4 cases
- [ ] AC-3: `"60,0,500,127,1"` (ch=1) → `.success([ParsedNote(channel: 0, ...)])` (wire 0)
- [ ] AC-4: `"60,0,500,127,16"` (ch=16) → `.success([ParsedNote(channel: 15, ...)])` (wire 0xF)
- [ ] AC-5: `"60,0,500,127,0"` (ch=0) → `.failure(.channelOutOfRange(segment: "60,0,500,127,0", value: 0))`
- [ ] AC-6: `"60,0,500,127,17"` (ch=17) → `.failure(.channelOutOfRange(...))`
- [ ] AC-7: `"60,0,500,127"` (ch omit) → `.success([ParsedNote(channel: 0, ...)])` (default Ch 1 wire 0)
- [ ] AC-8: 한 segment라도 invalid면 전체 parse 실패 (`"60,0,500;invalid;70,1000,500"` → `.failure`)
- [ ] AC-9: `TrackDispatcher.handleRecordSequenceSMF` callsite 갱신 — `.failure` 시 toolTextResult error 반환 + hint 포함
- [ ] AC-10: `CoreMIDIChannel.play_sequence` callsite (line ~286) 갱신 — `.failure` 시 `.error(...)` 반환

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
| 10 | `testParseMixedValidInvalidWholeFails` | Unit | "60,0,500;invalid;70,1000,500" | `.failure` (전체 실패) |
| 11 | `testParseMultipleValidSegments` | Unit | "60,0,500,127,1;72,1000,500,100,2" | `.success([2 notes])` |
| 12 | `testRecordSequenceCallSiteHandlesFailure` | Integration | TrackDispatcher mock — invalid notes 입력 | toolTextResult error + hint |
| 13 | `testPlaySequenceCallSiteHandlesFailure` | Integration | CoreMIDIChannel mock — invalid notes 입력 | `.error(...)` 반환 |

### 3.2 Test File Location
- `Tests/LogicProMCPTests/NoteSequenceParserResultTests.swift` (NEW, 1-11)
- `Tests/LogicProMCPTests/TrackDispatcherRecordSequenceTests.swift` (확장 12)
- `Tests/LogicProMCPTests/CoreMIDIPlaySequenceTests.swift` (확장 또는 NEW 13)

### 3.3 Mock/Setup Required
- TrackDispatcher / CoreMIDIChannel callsite 테스트는 기존 mock 패턴 재사용

## 4. Implementation Guide

### 4.1 Files to Modify
| File | Change Type | Description |
|------|------------|-------------|
| `Sources/LogicProMCP/MIDI/NoteSequenceParser.swift` | Modify | API 시그니처 변경 + Error enum 추가 + 1-based ch 변환 |
| `Sources/LogicProMCP/Dispatchers/TrackDispatcher.swift` | Modify | record_sequence callsite (line ~515 근처) — Result 핸들링 |
| `Sources/LogicProMCP/Channels/CoreMIDIChannel.swift` | Modify | play_sequence callsite (line ~286) — Result 핸들링 |
| `Tests/LogicProMCPTests/NoteSequenceParserResultTests.swift` | Create | 11 unit tests |

### 4.2 Implementation Steps (Green Phase)
1. `NoteSequenceParser.swift`에 `enum NoteSequenceParseError: Error` 추가
2. `parse(_:)` 시그니처 변경: 반환 타입 `Result<[ParsedNote], NoteSequenceParseError>`
3. 내부 로직 변경:
   - `compactMap` 폐기 (silent skip 금지)
   - 각 segment 파싱 실패 시 즉시 `.failure(...)` early return
   - ch field: 입력 1..16 검증 → wire byte `UInt8(ch - 1)`. omit 시 default 0 (Ch 1)
4. 호출부 갱신:
   - `TrackDispatcher`: `.failure` → `toolTextResult("record_sequence: \(error)", isError: true)`
   - `CoreMIDIChannel`: `.failure` → `.error(HonestContract.encodeStateC(error: .invalidParams, hint: "\(error)"))`
5. 테스트 실행 → all PASS

### 4.3 Refactor Phase
- `NoteSequenceParseError`에 `LocalizedError` conformance 추가하여 사용자 친화적 메시지 (선택)
- 기존 callsite의 hint message wording 일관성 검토

## 5. Edge Cases
- EC-1: `";"` (empty segments) — 빈 segment는 skip vs `.failure`? **결정**: skip (split 후 trim 빈 결과는 무시)
- EC-2: 1024-note SMF import 한도 (v3.1.4 P1-4) — parser는 한도 모름. caller (TrackDispatcher)에서 검증 유지
- EC-3: 매우 긴 notes 문자열 (10K segments) — Result는 한 번에 evaluate, large memory OK (UInt8 기반 ParsedNote)

## 6. Review Checklist
- [ ] Red: 모든 13 test FAILED 확인
- [ ] Green: 13 PASSED
- [ ] Refactor: PASSED 유지
- [ ] AC 10건 충족
- [ ] 기존 NoteSequenceParser 테스트 (있다면) 마이그레이션 또는 BREAKING note
- [ ] play_sequence / record_sequence 기존 테스트 regression 검증
- [ ] CHANGELOG-prep: BREAKING — NoteSequenceParser API 시그니처 변경 (internal module이므로 외부 영향 없음)

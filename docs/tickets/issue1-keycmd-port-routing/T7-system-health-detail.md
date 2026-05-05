# T7: SystemDispatcher health detail (audited matrix + orphan ops)

**PRD Ref**: PRD-issue1-keycmd-port-routing > §3 AC-5.1, AC-5.2, AC-5.4
**Priority**: P2 (Medium)
**Size**: S (< 2h)
**Status**: Todo
**Depends On**: None (independent — health detail is read-only string)

---

## 1. Objective
MIDIKeyCommands 채널 health `detail` 메시지를 정직하게 재작성: virtual port 상태 + Manual MIDI Learn 안내 + audited coverage matrix link + effectively keycmd-only ops + orphan ops 명시. 길이 < 1 KB 유지.

## 2. Acceptance Criteria
- [ ] AC-1: detail 문자열에 virtual MIDI port 상태 포함 (`"LogicProMCP-KeyCmd-Internal is ready"` 또는 unavailability 사유)
- [ ] AC-2: detail에 `"Manual MIDI Learn required — see docs/SETUP.md §<section>"` 포함
- [ ] AC-3: detail에 `"Most preset operations are covered by logic_edit / logic_project / logic_navigate / logic_tracks / logic_transport — see audited coverage matrix in SETUP.md"` 포함
- [ ] AC-4: detail에 `"Effectively keycmd-only (cgEvent fallback unmapped): transport.capture_recording. Manual MIDI Learn binding required for actual function activation."` 포함
- [ ] AC-5: detail에 orphan ops 명시 — `"Orphan ops in mappingTable (no MCP tool currently exposes call path): note.up_semitone, note.up_octave, note.down_semitone, note.down_octave, view.toggle_smart_controls, view.toggle_plugin_windows, view.toggle_automation (CC 57; distinct from automation.toggle_view CC 85). Manual binding possible but MCP has no caller path; tracked in NG6 follow-up."`
- [ ] AC-6: 전체 detail 길이 < 1024 bytes (UTF-8)
- [ ] AC-7: `verification_status` 필드는 `"manual_validation_required"` 그대로 유지 (변경 없음)
- [ ] AC-8: `available: true / ready: false` 상태 그대로 유지 (변경 없음)

## 3. TDD Spec (Red Phase)

### 3.1 Test Cases

| # | Test Name | Type | Description | Expected |
|---|-----------|------|-------------|----------|
| 1 | `testKeyCmdChannelDetailIncludesPortStatus` | Unit | health 응답 detail 검사 | "LogicProMCP-KeyCmd-Internal" substring |
| 2 | `testKeyCmdChannelDetailIncludesManualLearnHint` | Unit | "Manual MIDI Learn required" substring |
| 3 | `testKeyCmdChannelDetailMentionsCoverageMatrix` | Unit | "audited coverage matrix" substring |
| 4 | `testKeyCmdChannelDetailListsKeycmdOnlyOps` | Unit | "transport.capture_recording" substring |
| 5 | `testKeyCmdChannelDetailListsOrphanOps` | Unit | "note.up_semitone" + "view.toggle_smart_controls" substrings |
| 6 | `testKeyCmdChannelDetailUnderOneKB` | Unit | UTF-8 byte length | < 1024 |
| 7 | `testKeyCmdChannelVerificationStatusUnchanged` | Regression | verification_status | "manual_validation_required" |
| 8 | `testKeyCmdChannelAvailableReadyUnchanged` | Regression | available, ready | true, false |

### 3.2 Test File Location
- `Tests/LogicProMCPTests/HealthDispatcherKeyCmdDetailTests.swift` (NEW)

### 3.3 Mock/Setup Required
- mock LogicProServer health snapshot

## 4. Implementation Guide

### 4.1 Files to Modify
| File | Change Type | Description |
|------|------------|-------------|
| `Sources/LogicProMCP/Channels/MIDIKeyCommandsChannel.swift` (또는 healthCheck() 메소드 위치) | Modify | detail 메시지 재작성 |
| `Tests/LogicProMCPTests/HealthDispatcherKeyCmdDetailTests.swift` | Create | 8 tests |

### 4.2 Implementation Steps (Green Phase)
1. `MIDIKeyCommandsChannel.healthCheck()` 메소드의 detail 문자열 빌더 수정:
   ```swift
   let detail = """
       LogicProMCP-KeyCmd-Internal is ready. \
       Manual MIDI Learn required — see docs/SETUP.md §<section>. \
       Most preset operations are covered by logic_edit / logic_project / logic_navigate / logic_tracks / logic_transport — see audited coverage matrix in SETUP.md. \
       Effectively keycmd-only (cgEvent fallback unmapped): transport.capture_recording. Manual MIDI Learn binding required for actual function activation. \
       Orphan ops in mappingTable (no MCP tool currently exposes call path): note.up_semitone, note.up_octave, note.down_semitone, note.down_octave, view.toggle_smart_controls, view.toggle_plugin_windows, view.toggle_automation (CC 57; distinct from automation.toggle_view CC 85). Manual binding possible but MCP has no caller path; tracked in NG6 follow-up.
       """
   ```
2. 길이 검증 unit test (CI에서 실패 시 detail 트리밍)
3. 테스트 8 PASS

### 4.3 Refactor Phase
- detail을 const string template으로 추출 검토

## 5. Edge Cases
- EC-1: KeyCmd transport 미초기화 시 detail에서 "is ready" → 상황별 분기 ("not yet published")
- EC-2: 1024 byte 초과 시 string truncate vs warn-fail — 결정: Test에서 fail (개발 중 길이 컨트롤)

## 6. Review Checklist
- [ ] Red: 8 test FAILED
- [ ] Green: 8 PASSED
- [ ] AC 8건 충족
- [ ] 기존 health 응답 schema regression 0

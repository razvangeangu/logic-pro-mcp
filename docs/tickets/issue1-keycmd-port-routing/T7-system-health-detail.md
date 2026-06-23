# T7: SystemDispatcher health detail (audited matrix + orphan ops)

> Historical record. Current stable evidence is in `README.md`, `CHANGELOG.md`, and `docs/live-verify-v3.7.0.md`; previous stable evidence remains in `docs/live-verify-v3.6.0.md`; this file remains preserved implementation context.

**PRD Ref**: PRD-issue1-keycmd-port-routing > §3 AC-5.1, AC-5.2, AC-5.4
**Priority**: P2 (Medium)
**Size**: S (< 2h)
**Status**: Todo
**Depends On**: None (independent — health detail is a read-only string)

---

## 1. Objective
Honestly rewrite the MIDIKeyCommands channel health `detail` message: include virtual port status + Manual MIDI Learn guidance + audited coverage matrix link + effectively keycmd-only ops + explicit orphan ops. Keep length < 1 KB.

## 2. Acceptance Criteria
- [ ] AC-1: detail string includes virtual MIDI port status (`"LogicProMCP-KeyCmd-Internal is ready"` or unavailability reason)
- [ ] AC-2: detail includes `"Manual MIDI Learn required — see docs/SETUP.md §<section>"`
- [ ] AC-3: detail includes `"Most preset operations are covered by logic_edit / logic_project / logic_navigate / logic_tracks / logic_transport — see audited coverage matrix in SETUP.md"`
- [ ] AC-4: detail includes `"Effectively keycmd-only (cgEvent fallback unmapped): transport.capture_recording. Manual MIDI Learn binding required for actual function activation."`
- [ ] AC-5: detail lists orphan ops — `"Orphan ops in mappingTable (no MCP tool currently exposes call path): note.up_semitone, note.up_octave, note.down_semitone, note.down_octave, view.toggle_smart_controls, view.toggle_plugin_windows, view.toggle_automation (CC 57; distinct from automation.toggle_view CC 85). Manual binding possible but MCP has no caller path; tracked in NG6 follow-up."`
- [ ] AC-6: Total detail length < 1024 bytes (UTF-8)
- [ ] AC-7: `verification_status` field remains `"manual_validation_required"` (no change)
- [ ] AC-8: `available: true / ready: false` state unchanged

## 3. TDD Spec (Red Phase)

### 3.1 Test Cases

| # | Test Name | Type | Description | Expected |
|---|-----------|------|-------------|----------|
| 1 | `testKeyCmdChannelDetailIncludesPortStatus` | Unit | inspect health response detail | "LogicProMCP-KeyCmd-Internal" substring |
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
- Mock LogicProServer health snapshot

## 4. Implementation Guide

### 4.1 Files to Modify
| File | Change Type | Description |
|------|------------|-------------|
| `Sources/LogicProMCP/Channels/MIDIKeyCommandsChannel.swift` (or wherever `healthCheck()` is located) | Modify | Rewrite detail message |
| `Tests/LogicProMCPTests/HealthDispatcherKeyCmdDetailTests.swift` | Create | 8 tests |

### 4.2 Implementation Steps (Green Phase)
1. Modify the detail string builder in `MIDIKeyCommandsChannel.healthCheck()`:
   ```swift
   let detail = """
       LogicProMCP-KeyCmd-Internal is ready. \
       Manual MIDI Learn required — see docs/SETUP.md §<section>. \
       Most preset operations are covered by logic_edit / logic_project / logic_navigate / logic_tracks / logic_transport — see audited coverage matrix in SETUP.md. \
       Effectively keycmd-only (cgEvent fallback unmapped): transport.capture_recording. Manual MIDI Learn binding required for actual function activation. \
       Orphan ops in mappingTable (no MCP tool currently exposes call path): note.up_semitone, note.up_octave, note.down_semitone, note.down_octave, view.toggle_smart_controls, view.toggle_plugin_windows, view.toggle_automation (CC 57; distinct from automation.toggle_view CC 85). Manual binding possible but MCP has no caller path; tracked in NG6 follow-up.
       """
   ```
2. Add length verification unit test (CI fails if detail exceeds limit)
3. All 8 tests PASS

### 4.3 Refactor Phase
- Consider extracting detail as a constant string template

## 5. Edge Cases
- EC-1: KeyCmd transport not yet initialized — branch detail from "is ready" to "not yet published"
- EC-2: On > 1024 byte overflow — Decision: fail the test (enforce length during development, not via runtime truncation)

## 6. Review Checklist
- [ ] Red: 8 tests FAILED
- [ ] Green: 8 PASSED
- [ ] AC 8 items satisfied
- [ ] Existing health response schema: 0 regressions

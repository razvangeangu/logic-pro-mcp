# T5: MIDIDispatcher port routing integration + 7 ops × 2 ports + record_sequence/mmc_* reject

> Historical record (2026-06-05 docs refresh): latest production-readiness and live E2E evidence is in `README.md`, `CHANGELOG.md`, and `docs/live-verify-v3.4.5-rc5.md`; this file remains preserved implementation context.

**PRD Ref**: PRD-issue1-keycmd-port-routing > §3 AC-1.1, AC-1.2, AC-1.4, AC-1.6, AC-2.x, §4.3
**Priority**: P1 (High)
**Size**: L (4-8h — 7 ops integration + routingTable + reject logic)
**Status**: Todo
**Depends On**: T1 (HonestContract), T2 (validatePort/validateMidiChannel), T3 (NoteSequenceParser API)

---

## 1. Objective
Integrate port + 1-based channel validation across MIDIDispatcher 7 send ops. Branch directly via operationKey suffix routing (`.keycmd`). record_sequence + mmc_* + send_sysex + step_input + create_virtual_port return invalid_params when port is specified. Add 14 entries to ChannelRouter routingTable.

## 2. Acceptance Criteria
- [ ] AC-1: `send_cc` / `send_note` / `send_chord` / `send_program_change` / `send_pitch_bend` / `send_aftertouch` / `play_sequence` — 7 ops accept port parameter
- [ ] AC-2: `port` not specified → default `"midi"` → operation key `"midi.send_cc"` (existing backward compat)
- [ ] AC-3: `port: "keycmd"` → operation key `"midi.send_cc.keycmd"` dispatched
- [ ] AC-4: All 7 ops integrate 1-based channel validation (T2 validateMidiChannel)
- [ ] AC-5: `record_sequence` with explicit `port` parameter → invalid_params reject + hint `"port parameter not supported for record_sequence"`. (Pre-check at dispatcher-level before TrackDispatcher.routedTextResult call, or included in TrackDispatcher.swift)
- [ ] AC-6: `mmc_play` / `mmc_stop` / `mmc_record` / `mmc_locate` / `send_sysex` / `step_input` / `create_virtual_port` with explicit `port` → invalid_params reject (NG8)
- [ ] AC-7: `pitch_bend` / `aftertouch` channel validation integrated (existing raw UInt8 casting → validateMidiChannel)
- [ ] AC-8: `play_sequence` `notes` string delegated to T3 NoteSequenceParser API — entry-level port + entry-level channel validation separate (`notes` inner ch field is parser responsibility)
- [ ] AC-9: ChannelRouter `routingTable` gains 14 entries:
  ```
  "midi.send_cc": [.coreMIDI]
  "midi.send_cc.keycmd": [.midiKeyCommands]
  "midi.send_note": [.coreMIDI]
  "midi.send_note.keycmd": [.midiKeyCommands]
  "midi.send_chord": [.coreMIDI]
  "midi.send_chord.keycmd": [.midiKeyCommands]
  "midi.send_program_change": [.coreMIDI]
  "midi.send_program_change.keycmd": [.midiKeyCommands]
  "midi.send_pitch_bend": [.coreMIDI]
  "midi.send_pitch_bend.keycmd": [.midiKeyCommands]
  "midi.send_aftertouch": [.coreMIDI]
  "midi.send_aftertouch.keycmd": [.midiKeyCommands]
  "midi.play_sequence": [.coreMIDI]
  "midi.play_sequence.keycmd": [.midiKeyCommands]
  ```
- [ ] AC-10: Existing calls (`send_cc {controller, value, channel}`) backward compat — identical response message string-equality

## 3. TDD Spec (Red Phase)

### 3.1 Test Cases

| # | Test Name | Type | Description | Expected |
|---|-----------|------|-------------|----------|
| 1 | `testSendCCDefaultPortRoutesToMidiSendCC` | Unit | port not specified | router called with op="midi.send_cc" |
| 2 | `testSendCCKeycmdPortRoutesToMidiSendCCKeycmd` | Unit | `port:"keycmd"` | op="midi.send_cc.keycmd" |
| 3 | `testSendCCInvalidPortReturnsStateCInvalidParams` | Unit | `port:"foo"` | toolTextResult error + hint |
| 4 | `testSendCCScripterPortRejected` | Unit | `port:"scripter"` (NG5) | error |
| 5 | `testSendCCChannel16WireByteFifteen` | Unit | channel:16 | router params channel="15" |
| 6 | `testSendCCChannel0Rejected` | Unit | channel:0 | invalid_params |
| 7 | `testSendCCFloatChannelRejected` | Unit | channel:1.5 | invalid_params |
| 8 | `testAllSendOpsAcceptPortParam` | Parametrized | 7 ops × 2 ports = 14 cases | all pass correct op key to router |
| 9 | `testAllSendOpsValidateChannel1Based` | Parametrized | 7 ops × 1-based check | wire = ch-1 |
| 10 | `testRecordSequenceRejectsPortParam` | Unit | record_sequence + port="keycmd" | invalid_params reject, hint includes "record_sequence" |
| 11 | `testMmcPlayRejectsPortParam` | Unit | mmc_play + port | reject |
| 12 | `testMmcLocateRejectsPortParam` | Unit | mmc_locate + port | reject |
| 13 | `testSendSysexRejectsPortParam` | Unit | send_sysex + port | reject |
| 14 | `testStepInputRejectsPortParam` | Unit | step_input + port | reject |
| 15 | `testCreateVirtualPortRejectsPortParam` | Unit | create_virtual_port + port | reject |
| 16 | `testPitchBendChannelValidation` | Unit | pitch_bend + ch=17 | invalid_params (previous raw UInt8 silent corruption fix) |
| 17 | `testAftertouchChannelValidation` | Unit | aftertouch + ch=0 | invalid_params |
| 18 | `testRoutingTableHasFourteenMidiKeycmdEntries` | Unit | ChannelRouter.routingTable inspection | 14 entries match expected list |
| 19 | `testBackwardCompatSendCCWithoutPortMatchesPriorBehavior` | Regression | v3.1.4 call pattern | same router op + params **+ response message string-equality** (v3.1.4 fixture string captured + assertEqual to v3.1.5 output) — Phase 4 Loop 1 tester P1 |

### 3.2 Test File Location
- `Tests/LogicProMCPTests/MIDIDispatcherSendCCPortTests.swift` (NEW, tests 1-7)
- `Tests/LogicProMCPTests/MIDIDispatcherEntryPointConsistencyTests.swift` (NEW, tests 8-9, 18)
- `Tests/LogicProMCPTests/MIDIDispatcherRejectionTests.swift` (NEW, tests 10-15)
- `Tests/LogicProMCPTests/MIDIDispatcherChannelEncodingTests.swift` (NEW, tests 16-17)
- `Tests/LogicProMCPTests/BackwardCompatRegressionTests.swift` (NEW, test 19)

### 3.3 Mock/Setup Required
- `MockChannelRouter` capturing operation key + params (reuse existing pattern)

## 4. Implementation Guide

### 4.1 Files to Modify
| File | Change Type | Description |
|------|------------|-------------|
| `Sources/LogicProMCP/Dispatchers/MIDIDispatcher.swift` | Modify | Apply validatePort+validateMidiChannel to 7 send ops, operationKey suffix dispatch, port reject for mmc_*/sysex/step_input/create_virtual_port |
| `Sources/LogicProMCP/Dispatchers/TrackDispatcher.swift` | Modify | Add port reject to record_sequence case |
| `Sources/LogicProMCP/Channels/ChannelRouter.swift` | Modify | Add 14 entries to routingTable |
| Tests/LogicProMCPTests/`*5 NEW files` | Create | 19 tests across 5 files |

### 4.2 Implementation Steps (Green Phase)
1. Add 14 entries to ChannelRouter routingTable (simple dictionary append)
2. Modify MIDIDispatcher 7 send ops — shared helper:
   ```swift
   private static func dispatchSendOp(
       baseOp: String,
       params: [String: Value],
       additionalParams: [String: String],
       router: ChannelRouter
   ) async -> CallTool.Result {
       switch validatePort(params) {
       case .failure(let msg):
           return toolTextResult(HonestContract.encodeStateC(error: .invalidParams, hint: msg, extras: [:]), isError: true)
       case .success(let port):
           switch validateMidiChannel(params) {
           case .failure(let msg):
               return toolTextResult(HonestContract.encodeStateC(error: .invalidParams, hint: msg, extras: [:]), isError: true)
           case .success(let wireChannel):
               let opKey = port == "midi" ? baseOp : "\(baseOp).\(port)"
               var allParams = additionalParams
               allParams["channel"] = String(wireChannel)
               return await routedTextResult(router, operation: opKey, params: allParams)
           }
       }
   }
   ```
3. Apply `dispatchSendOp` to all 7 send cases
4. Add `params["port"] != nil` check to mmc_*/sysex/step_input/create_virtual_port cases → invalid_params reject
5. Add same reject to TrackDispatcher record_sequence case
6. Run 19 tests → PASS

### 4.3 Refactor Phase
- Consider extracting common reject helper (`rejectIfPortPresent`)
- Apply consistent channel validation to pitch_bend/aftertouch separate dispatcher functions

## 5. Edge Cases
- EC-1: `play_sequence` takes only `notes` string — no separate entry-level channel. Skip validateMidiChannel + apply port only
- EC-2: `send_chord` uses single `channel` (same channel for all notes in chord)
- EC-3: No routingTable entry → ChannelRouter default "operation not handled" error — invariant test detects omissions

## 6. Review Checklist
- [ ] Red: 19 tests FAILED
- [ ] Green: 19 PASSED
- [ ] AC 10 items satisfied
- [ ] T1/T2/T3 dependency integration verified
- [ ] Existing MIDIDispatcher tests (if any): 0 regressions
- [ ] BackwardCompatRegressionTests explicitly documents existing call pattern compatibility

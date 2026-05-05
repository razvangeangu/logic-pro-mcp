# T5: MIDIDispatcher port routing 통합 + 7 ops × 2 ports + record_sequence/mmc_* reject

**PRD Ref**: PRD-issue1-keycmd-port-routing > §3 AC-1.1, AC-1.2, AC-1.4, AC-1.6, AC-2.x, §4.3
**Priority**: P1 (High)
**Size**: L (4-8h — 7 ops 통합 + routingTable + reject 로직)
**Status**: Todo
**Depends On**: T1 (HonestContract), T2 (validatePort/validateMidiChannel), T3 (NoteSequenceParser API)

---

## 1. Objective
MIDIDispatcher 7 send ops에 port + 1-based channel validation 통합. operationKey suffix routing (`.keycmd`)으로 직접 분기. record_sequence + mmc_* + send_sysex + step_input + create_virtual_port은 port 입력 시 invalid_params reject. ChannelRouter routingTable에 14 entries 추가.

## 2. Acceptance Criteria
- [ ] AC-1: `send_cc` / `send_note` / `send_chord` / `send_program_change` / `send_pitch_bend` / `send_aftertouch` / `play_sequence` 7 ops에 port 파라미터 적용
- [ ] AC-2: `port` 미지정 시 default `"midi"` → operation key `"midi.send_cc"` (기존 backward compat)
- [ ] AC-3: `port: "keycmd"` → operation key `"midi.send_cc.keycmd"`로 dispatch
- [ ] AC-4: 모든 7 ops에 1-based channel validation 통합 (T2 validateMidiChannel)
- [ ] AC-5: `record_sequence` 호출에 `port` 파라미터 명시 시 invalid_params reject + hint `"port parameter not supported for record_sequence"`. (TrackDispatcher가 routedTextResult 호출 전 dispatcher-level pre-check 또는 TrackDispatcher.swift에 포함)
- [ ] AC-6: `mmc_play` / `mmc_stop` / `mmc_record` / `mmc_locate` / `send_sysex` / `step_input` / `create_virtual_port` 호출에 `port` 명시 시 invalid_params reject (NG8)
- [ ] AC-7: `pitch_bend` / `aftertouch` 채널 검증 통합 (기존 raw UInt8 캐스팅 → validateMidiChannel)
- [ ] AC-8: `play_sequence`의 `notes` 문자열은 T3 NoteSequenceParser API로 위임 — entry-level port + entry-level channel 검증은 별도 (`notes` 안 ch field는 parser 책임)
- [ ] AC-9: ChannelRouter `routingTable`에 14 entries 추가:
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
- [ ] AC-10: 기존 호출(`send_cc {controller, value, channel}`) backward compat — 동일 응답 메시지 string-equality

## 3. TDD Spec (Red Phase)

### 3.1 Test Cases

| # | Test Name | Type | Description | Expected |
|---|-----------|------|-------------|----------|
| 1 | `testSendCCDefaultPortRoutesToMidiSendCC` | Unit | port 미지정 | router 호출에 op="midi.send_cc" |
| 2 | `testSendCCKeycmdPortRoutesToMidiSendCCKeycmd` | Unit | `port:"keycmd"` | op="midi.send_cc.keycmd" |
| 3 | `testSendCCInvalidPortReturnsStateCInvalidParams` | Unit | `port:"foo"` | toolTextResult error + hint |
| 4 | `testSendCCScripterPortRejected` | Unit | `port:"scripter"` (NG5) | error |
| 5 | `testSendCCChannel16WireByteFifteen` | Unit | channel:16 | router params channel="15" |
| 6 | `testSendCCChannel0Rejected` | Unit | channel:0 | invalid_params |
| 7 | `testSendCCFloatChannelRejected` | Unit | channel:1.5 | invalid_params |
| 8 | `testAllSendOpsAcceptPortParam` | Parametrized | 7 ops × 2 ports = 14 cases | 모두 router로 정확한 op key 전달 |
| 9 | `testAllSendOpsValidateChannel1Based` | Parametrized | 7 ops × 1-based check | wire = ch-1 |
| 10 | `testRecordSequenceRejectsPortParam` | Unit | record_sequence + port="keycmd" | invalid_params reject, hint includes "record_sequence" |
| 11 | `testMmcPlayRejectsPortParam` | Unit | mmc_play + port | reject |
| 12 | `testMmcLocateRejectsPortParam` | Unit | mmc_locate + port | reject |
| 13 | `testSendSysexRejectsPortParam` | Unit | send_sysex + port | reject |
| 14 | `testStepInputRejectsPortParam` | Unit | step_input + port | reject |
| 15 | `testCreateVirtualPortRejectsPortParam` | Unit | create_virtual_port + port | reject |
| 16 | `testPitchBendChannelValidation` | Unit | pitch_bend + ch=17 | invalid_params (이전 raw UInt8 silent corruption fix) |
| 17 | `testAftertouchChannelValidation` | Unit | aftertouch + ch=0 | invalid_params |
| 18 | `testRoutingTableHasFourteenMidiKeycmdEntries` | Unit | ChannelRouter.routingTable inspection | 14 entries match expected list |
| 19 | `testBackwardCompatSendCCWithoutPortMatchesPriorBehavior` | Regression | 기존 v3.1.4 호출 패턴 | 동일 router op + params **+ 응답 메시지 string-equality** (v3.1.4 fixture string captured + assertEqual to v3.1.5 output) — Phase 4 Loop 1 tester P1 |

### 3.2 Test File Location
- `Tests/LogicProMCPTests/MIDIDispatcherSendCCPortTests.swift` (NEW, tests 1-7)
- `Tests/LogicProMCPTests/MIDIDispatcherEntryPointConsistencyTests.swift` (NEW, tests 8-9, 18)
- `Tests/LogicProMCPTests/MIDIDispatcherRejectionTests.swift` (NEW, tests 10-15)
- `Tests/LogicProMCPTests/MIDIDispatcherChannelEncodingTests.swift` (NEW, tests 16-17)
- `Tests/LogicProMCPTests/BackwardCompatRegressionTests.swift` (NEW, test 19)

### 3.3 Mock/Setup Required
- `MockChannelRouter` capturing operation key + params (기존 패턴 재사용)

## 4. Implementation Guide

### 4.1 Files to Modify
| File | Change Type | Description |
|------|------------|-------------|
| `Sources/LogicProMCP/Dispatchers/MIDIDispatcher.swift` | Modify | 7 send ops에 validatePort+validateMidiChannel 적용, operationKey suffix dispatch, mmc_*/sysex/step_input/create_virtual_port에 port reject |
| `Sources/LogicProMCP/Dispatchers/TrackDispatcher.swift` | Modify | record_sequence case에 port 입력 reject 추가 |
| `Sources/LogicProMCP/Channels/ChannelRouter.swift` | Modify | routingTable에 14 entries 추가 |
| Tests/LogicProMCPTests/`*5 NEW files` | Create | 19 tests across 5 files |

### 4.2 Implementation Steps (Green Phase)
1. ChannelRouter routingTable에 14 entries 추가 (단순 dictionary append)
2. MIDIDispatcher 7 send ops 수정 — 공통 helper:
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
3. 7 send case에 dispatchSendOp 호출 적용
4. mmc_*/sysex/step_input/create_virtual_port case에 `params["port"] != nil` 체크 → invalid_params reject
5. TrackDispatcher record_sequence case에 동일 reject
6. 테스트 19 PASS

### 4.3 Refactor Phase
- 공통 reject helper (`rejectIfPortPresent`) 추출 검토
- pitch_bend/aftertouch 별도 dispatcher 함수에서 channel validation 일관 적용

## 5. Edge Cases
- EC-1: `play_sequence`는 `notes` 문자열만 받음 — entry-level channel 별도 없음. validateMidiChannel skip + port만 적용
- EC-2: `send_chord`는 `channel` 단일 (chord 내 모든 note 동일 채널)
- EC-3: routingTable에 entry 없으면 ChannelRouter 기본 에러 (`operation not handled`) — invariant test가 누락 detect

## 6. Review Checklist
- [ ] Red: 19 test FAILED
- [ ] Green: 19 PASSED
- [ ] AC 10건 충족
- [ ] T1/T2/T3 의존성 통합 검증
- [ ] 기존 MIDIDispatcher 테스트 (있다면) regression 0
- [ ] BackwardCompatRegressionTests로 기존 호출 패턴 호환 명시

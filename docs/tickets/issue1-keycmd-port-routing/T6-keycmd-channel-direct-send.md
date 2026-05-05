# T6: MIDIKeyCommandsChannel `midi.send_*.keycmd` direct send path

**PRD Ref**: PRD-issue1-keycmd-port-routing > §4.3 MIDIKeyCommandsChannel 변경 명세, §3 AC-1.1
**Priority**: P1 (High)
**Size**: M (2-4h)
**Status**: Todo
**Depends On**: T1 (HonestContract `.portUnavailable`), T3 (NoteSequenceParser Result API — for play_sequence.keycmd), T4 (ChannelRouter bypassReadinessOps)

---

## 1. Objective
MIDIKeyCommandsChannel.execute에 7 신규 case (`midi.send_*.keycmd`)를 추가하여 KeyCmd virtual port로 직접 MIDI 송신. 기존 mappingTable lookup path는 그대로 유지. 응답은 HC State B `readback_unavailable` envelope (transport echo 없음).

## 2. Acceptance Criteria
- [ ] AC-1: MIDIKeyCommandsChannel.execute에 7 신규 case: `midi.send_cc.keycmd` / `midi.send_note.keycmd` / `midi.send_chord.keycmd` / `midi.send_program_change.keycmd` / `midi.send_pitch_bend.keycmd` / `midi.send_aftertouch.keycmd` / `midi.play_sequence.keycmd`
- [ ] AC-2: 각 case가 wire bytes 생성 (channel은 dispatcher에서 이미 0..15 wire 값으로 변환됨) → `transport.send(bytes)` 호출
- [ ] AC-3: send 성공 시 HC State B `readback_unavailable` envelope 반환 (KeyCmd transport echo 없음). extras: `["operation": op, "via": "midi-keycmd-direct-send"]`
- [ ] AC-4: transport 미초기화 / send 실패 시 → ChannelRouter level의 `available: false` 분기에서 차단되어 여기 도달 안 함 (T4가 처리). 그래도 defensive: `try?` 패턴으로 swallow + State C `.elementNotFound` fallback
- [ ] AC-5: 기존 mappingTable lookup path (`edit.undo`, `transport.toggle_cycle` 등 48 ops) 동작 변경 없음
- [ ] AC-6: `play_sequence.keycmd`는 NoteSequenceParser.parse 호출 (T3 Result API 사용) — `.failure` 시 invalid_params 반환

## 3. TDD Spec (Red Phase)

### 3.1 Test Cases

| # | Test Name | Type | Description | Expected |
|---|-----------|------|-------------|----------|
| 1 | `testKeycmdChannelHandlesSendCCKeycmdOp` | Unit | execute("midi.send_cc.keycmd", params) | transport.send 호출 + State B envelope |
| 2 | `testKeycmdSendCCWireBytesCorrect` | Unit | controller=64, value=100, channel=15 | bytes = [0xBF, 64, 100] |
| 3 | `testKeycmdSendNoteWireBytes` | Unit | note=60, velocity=100, channel=0, duration | bytes = [0x90, 60, 100] (NoteOn) |
| 4 | `testKeycmdSendChordMultipleNotes` | Unit | 3 notes simultaneous | 3 NoteOn bytes |
| 5 | `testKeycmdSendProgramChangeWire` | Unit | program=42, channel=5 | [0xC5, 42] |
| 6 | `testKeycmdSendPitchBendWire` | Unit | value=8192, channel=0 | [0xE0, 0, 64] (mid) |
| 7 | `testKeycmdSendAftertouchWire` | Unit | value=100, channel=0 | [0xD0, 100] |
| 8 | `testKeycmdPlaySequenceCallsParser` | Integration | notes string → ParsedNote들 → 각각 transport.send | parser called + send count match |
| 9 | `testKeycmdPlaySequenceFailureReturnsInvalidParams` | Unit | invalid notes string | `.error(invalid_params)` |
| 10 | `testKeycmdSuccessReturnsStateBEnvelope` | Unit | 정상 send | envelope: `{success:true, verified:false, reason:"readback_unavailable", ...}` |
| 11 | `testKeycmdMappingTableLookupStillWorks` | Regression | execute("edit.undo", params) | 기존 mappingTable path 그대로 |
| 12 | `testKeycmdUnknownKeycmdOpReturnsError` | Unit | execute("midi.unknown_op.keycmd") | 미정의 case |

### 3.2 Test File Location
- `Tests/LogicProMCPTests/MIDIKeyCommandsChannelDirectSendTests.swift` (NEW)
- 기존 `MIDIKeyCommandsChannelTests.swift`에 testKeycmdMappingTableLookupStillWorks regression 추가

### 3.3 Mock/Setup Required
- 기존 `MockKeyCmdTransport` 재사용 (`MIDIKeyCommandsTests.swift:114` 위치, 이미 `transport.send(bytes)` capture pattern 존재 — Phase 4 Loop 1 boomer Q9 검증). 신규 fixture 생성 금지.
- pitch_bend `value` convention: **0..16383 absolute (center=8192)**. PRD §4.3 Tool description에 명시 — Phase 4 Loop 1 tester P1.

## 4. Implementation Guide

### 4.1 Files to Modify
| File | Change Type | Description |
|------|------------|-------------|
| `Sources/LogicProMCP/Channels/MIDIKeyCommandsChannel.swift` | Modify | execute()에 7 신규 case + helper 함수 (wire byte 구성) |
| `Tests/LogicProMCPTests/MIDIKeyCommandsChannelDirectSendTests.swift` | Create | 12 tests |

### 4.2 Implementation Steps (Green Phase)
1. `execute` switch에 7 신규 case prefix `midi.*.keycmd` 처리:
   ```swift
   case "midi.send_cc.keycmd":
       guard let controller = params["controller"].flatMap(UInt8.init),
             let value = params["value"].flatMap(UInt8.init),
             let channel = params["channel"].flatMap(UInt8.init),
             channel <= 15, controller <= 127, value <= 127 else {
           return .error(HonestContract.encodeStateC(error: .invalidParams, hint: "send_cc.keycmd requires controller (0-127), value (0-127), channel (0-15 wire byte)", extras: [:]))
       }
       let bytes: [UInt8] = [0xB0 | (channel & 0x0F), controller, value]
       await transport.send(bytes)
       return .success(HonestContract.encodeStateB(reason: .readbackUnavailable, extras: [
           "operation": "midi.send_cc.keycmd",
           "via": "midi-keycmd-direct-send",
           "controller": Int(controller),
           "value": Int(value),
           "channel_wire": Int(channel),
       ]))
   ```
2. 동일 패턴 6 추가 ops (note/chord/program_change/pitch_bend/aftertouch/play_sequence)
3. `play_sequence.keycmd`는 NoteSequenceParser.parse (T3) 호출:
   ```swift
   case "midi.play_sequence.keycmd":
       guard let notes = params["notes"], !notes.isEmpty else { ... invalid_params }
       switch NoteSequenceParser.parse(notes) {
       case .failure(let err): return .error(HonestContract.encodeStateC(...))
       case .success(let parsed):
           for note in parsed { await transport.send(...) }
           return .success(HonestContract.encodeStateB(reason: .readbackUnavailable, extras: ["operation": "midi.play_sequence.keycmd", "note_count": parsed.count, ...]))
       }
   ```
4. 테스트 12 PASS

### 4.3 Refactor Phase
- wire byte 구성 helper 추출 (`buildCCBytes`, `buildNoteBytes`, ...)

## 5. Edge Cases
- EC-1: `transport.send`이 internal error throw — `try?` 또는 do-catch로 swallow + State C 반환
- EC-2: KeyCmd virtual port published되었으나 Logic이 listening 안 함 — Logic의 응답 unobservable, State B `readback_unavailable`이 정확
- EC-3: SysEx 형식 (transport.send이 SysEx를 byte 배열로 받는지 확인) — KeyCmd 채널은 일반 MIDI byte만 다룸 (SysEx는 별도)

## 6. Review Checklist
- [ ] Red: 12 test FAILED
- [ ] Green: 12 PASSED
- [ ] AC 6건 충족
- [ ] T1/T4 의존성 통합 검증 (특히 T4 bypassReadinessOps와 함께 e2e 테스트)
- [ ] 기존 MIDIKeyCommandsChannel 48 ops mappingTable 동작 regression 0
- [ ] HC envelope shape 검증 (extras 필드 일관성)

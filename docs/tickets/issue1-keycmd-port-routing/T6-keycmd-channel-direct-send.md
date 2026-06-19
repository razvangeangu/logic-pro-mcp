# T6: MIDIKeyCommandsChannel `midi.send_*.keycmd` direct send path

> Historical record. Current release-candidate evidence is in `README.md`, `CHANGELOG.md`, and `docs/live-verify-v3.6.0.md`; published stable evidence remains in `docs/live-verify-v3.5.0.md`; this file remains preserved implementation context.

**PRD Ref**: PRD-issue1-keycmd-port-routing > §4.3 MIDIKeyCommandsChannel change spec, §3 AC-1.1
**Priority**: P1 (High)
**Size**: M (2-4h)
**Status**: Todo
**Depends On**: T1 (HonestContract `.portUnavailable`), T3 (NoteSequenceParser Result API — for play_sequence.keycmd), T4 (ChannelRouter bypassReadinessOps)

---

## 1. Objective
Add 7 new cases (`midi.send_*.keycmd`) to `MIDIKeyCommandsChannel.execute` for direct MIDI transmission via the KeyCmd virtual port. The existing mappingTable lookup path remains unchanged. Responses use the HC State B `readback_unavailable` envelope (no transport echo).

## 2. Acceptance Criteria
- [ ] AC-1: `MIDIKeyCommandsChannel.execute` gains 7 new cases: `midi.send_cc.keycmd` / `midi.send_note.keycmd` / `midi.send_chord.keycmd` / `midi.send_program_change.keycmd` / `midi.send_pitch_bend.keycmd` / `midi.send_aftertouch.keycmd` / `midi.play_sequence.keycmd`
- [ ] AC-2: Each case builds wire bytes (channel is already converted to a 0..15 wire value by the dispatcher) → calls `transport.send(bytes)`
- [ ] AC-3: On successful send, return HC State B `readback_unavailable` envelope (no KeyCmd transport echo). extras: `["operation": op, "via": "midi-keycmd-direct-send"]`
- [ ] AC-4: If transport is uninitialized / send fails → blocked at the ChannelRouter `available: false` branch (handled by T4) before reaching here. Defensive nonetheless: `try?` pattern to swallow + State C `.elementNotFound` fallback
- [ ] AC-5: Existing mappingTable lookup path (`edit.undo`, `transport.toggle_cycle`, etc. — 48 ops) behavior unchanged
- [ ] AC-6: `play_sequence.keycmd` calls `NoteSequenceParser.parse` (T3 Result API) — returns `invalid_params` on `.failure`

## 3. TDD Spec (Red Phase)

### 3.1 Test Cases

| # | Test Name | Type | Description | Expected |
|---|-----------|------|-------------|----------|
| 1 | `testKeycmdChannelHandlesSendCCKeycmdOp` | Unit | execute("midi.send_cc.keycmd", params) | transport.send called + State B envelope |
| 2 | `testKeycmdSendCCWireBytesCorrect` | Unit | controller=64, value=100, channel=15 | bytes = [0xBF, 64, 100] |
| 3 | `testKeycmdSendNoteWireBytes` | Unit | note=60, velocity=100, channel=0, duration | bytes = [0x90, 60, 100] (NoteOn) |
| 4 | `testKeycmdSendChordMultipleNotes` | Unit | 3 notes simultaneous | 3 NoteOn bytes |
| 5 | `testKeycmdSendProgramChangeWire` | Unit | program=42, channel=5 | [0xC5, 42] |
| 6 | `testKeycmdSendPitchBendWire` | Unit | value=8192, channel=0 | [0xE0, 0, 64] (mid) |
| 7 | `testKeycmdSendAftertouchWire` | Unit | value=100, channel=0 | [0xD0, 100] |
| 8 | `testKeycmdPlaySequenceCallsParser` | Integration | notes string → ParsedNotes → transport.send per note | parser called + send count match |
| 9 | `testKeycmdPlaySequenceFailureReturnsInvalidParams` | Unit | invalid notes string | `.error(invalid_params)` |
| 10 | `testKeycmdSuccessReturnsStateBEnvelope` | Unit | successful send | envelope: `{success:true, verified:false, reason:"readback_unavailable", ...}` |
| 11 | `testKeycmdMappingTableLookupStillWorks` | Regression | execute("edit.undo", params) | existing mappingTable path unchanged |
| 12 | `testKeycmdUnknownKeycmdOpReturnsError` | Unit | execute("midi.unknown_op.keycmd") | undefined case error |

### 3.2 Test File Location
- `Tests/LogicProMCPTests/MIDIKeyCommandsChannelDirectSendTests.swift` (NEW)
- Add `testKeycmdMappingTableLookupStillWorks` regression to existing `MIDIKeyCommandsChannelTests.swift`

### 3.3 Mock/Setup Required
- Reuse existing `MockKeyCmdTransport` (located at `MIDIKeyCommandsTests.swift:114`, already has `transport.send(bytes)` capture pattern — Phase 4 Loop 1 boomer Q9 verified). Do not create new fixtures.
- `pitch_bend` `value` convention: **0..16383 absolute (center=8192)**. Specified in PRD §4.3 Tool description — Phase 4 Loop 1 tester P1.

## 4. Implementation Guide

### 4.1 Files to Modify
| File | Change Type | Description |
|------|------------|-------------|
| `Sources/LogicProMCP/Channels/MIDIKeyCommandsChannel.swift` | Modify | Add 7 new cases to `execute()` + helper functions for wire byte construction |
| `Tests/LogicProMCPTests/MIDIKeyCommandsChannelDirectSendTests.swift` | Create | 12 tests |

### 4.2 Implementation Steps (Green Phase)
1. Add 7 new case prefixes `midi.*.keycmd` to the `execute` switch:
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
2. Apply the same pattern to the remaining 6 ops (note/chord/program_change/pitch_bend/aftertouch/play_sequence)
3. `play_sequence.keycmd` calls `NoteSequenceParser.parse` (T3):
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
4. All 12 tests PASS

### 4.3 Refactor Phase
- Extract wire byte construction helpers (`buildCCBytes`, `buildNoteBytes`, ...)

## 5. Edge Cases
- EC-1: `transport.send` throws an internal error — swallow with `try?` or do-catch + return State C
- EC-2: KeyCmd virtual port published but Logic is not listening — Logic's response is unobservable; State B `readback_unavailable` is the accurate response
- EC-3: SysEx format (verify whether `transport.send` accepts SysEx as a byte array) — KeyCmd channel handles only standard MIDI bytes (SysEx is separate)

## 6. Review Checklist
- [ ] Red: 12 tests FAILED
- [ ] Green: 12 PASSED
- [ ] AC 6 items satisfied
- [ ] T1/T4 dependency integration verified (especially e2e with T4 bypassReadinessOps)
- [ ] Existing MIDIKeyCommandsChannel 48-op mappingTable behavior: 0 regressions
- [ ] HC envelope shape verified (extras field consistency)

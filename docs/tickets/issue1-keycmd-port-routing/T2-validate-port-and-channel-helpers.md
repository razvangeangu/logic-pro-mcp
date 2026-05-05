# T2: MIDIDispatcher `validatePort` + `validateMidiChannel` helpers

**PRD Ref**: PRD-issue1-keycmd-port-routing > §3 AC-1.3, AC-2.1-2.5, §4.3 helper sketches
**Priority**: P1 (High — foundational, blocks T5)
**Size**: M (2-4h)
**Status**: Todo
**Depends On**: None

---

## 1. Objective
`MIDIDispatcher` 내부에 두 신규 helper 함수 추가:
- `validatePort(_:) -> Result<String, String>` — port enum validation (`"midi"|"keycmd"`, default `"midi"`)
- `validateMidiChannel(_:) -> Result<UInt8, String>` — 1-based 채널 입력 → wire byte (0..15) + Value case-switch (int/double/string), float reject (1.5 etc.)

## 2. Acceptance Criteria
- [ ] AC-0 (visibility, Phase 4 Loop 1 boomer P1): `validatePort` + `validateMidiChannel`은 `internal static func` 선언 (test 접근). `private`이면 white-box test 컴파일 불가. `@testable import` 사용.
- [ ] AC-1: `validatePort(["port": .string("midi")])` → `.success("midi")`
- [ ] AC-2: `validatePort(["port": .string("keycmd")])` → `.success("keycmd")`
- [ ] AC-3: `validatePort([:])` (missing) → `.success("midi")` (default, backward compat)
- [ ] AC-4: `validatePort(["port": .string("scripter")])` → `.failure(...)` (NG5 — v3.1.5 비지원)
- [ ] AC-5: `validatePort(["port": .string("foo")])` → `.failure("port must be one of: midi, keycmd")`. **`validatePort(["port": .string("")])` (empty string)도 `.failure`** — 명시적 reject (Phase 4 Loop 1 tester P1 — sketch와 test 정합화).
- [ ] AC-6: `validateMidiChannel(["channel": .int(1)])` → `.success(0)` (wire byte 0)
- [ ] AC-7: `validateMidiChannel(["channel": .int(16)])` → `.success(15)` (wire byte 0xF)
- [ ] AC-8: `validateMidiChannel(["channel": .int(0)])` → `.failure("channel must be integer 1..16 (1-based)")`
- [ ] AC-9: `validateMidiChannel(["channel": .int(17)])` → `.failure(...)`
- [ ] AC-10: `validateMidiChannel(["channel": .double(1.0)])` → `.success(0)` (whole-number double accepted)
- [ ] AC-11: `validateMidiChannel(["channel": .double(1.5)])` → `.failure(...)` (fractional reject)
- [ ] AC-12: `validateMidiChannel(["channel": .string("1")])` → `.success(0)` (string-encoded int OK)
- [ ] AC-13: `validateMidiChannel(["channel": .string("1.5")])` → `.failure(...)` (string with fractional)
- [ ] AC-14: `validateMidiChannel([:])` (missing) → `.success(0)` (default = 1-based ch1)

## 3. TDD Spec (Red Phase)

### 3.1 Test Cases

| # | Test Name | Type | Description | Expected |
|---|-----------|------|-------------|----------|
| 1 | `testValidatePortDefaultsToMidi` | Unit | port 미지정 | `.success("midi")` |
| 2 | `testValidatePortAcceptsKeycmd` | Unit | "keycmd" | `.success("keycmd")` |
| 3 | `testValidatePortRejectsScripter` | Unit | "scripter" (NG5) | `.failure` |
| 4 | `testValidatePortRejectsUnknown` | Unit | "foo" | `.failure(hint matches)` |
| 5 | `testValidatePortRejectsEmpty` | Unit | "" | `.failure` |
| 6 | `testValidateChannel1MapsToWire0` | Unit | channel:1 | `.success(0)` |
| 7 | `testValidateChannel16MapsToWire15` | Unit | channel:16 | `.success(15)` |
| 8 | `testValidateChannel0Rejected` | Unit | channel:0 | `.failure(hint)` |
| 9 | `testValidateChannel17Rejected` | Unit | channel:17 | `.failure` |
| 10 | `testValidateChannelMissingDefaultsToWire0` | Unit | channel 미지정 | `.success(0)` |
| 11 | `testValidateChannelWholeDoubleAccepted` | Unit | 1.0 | `.success(0)` |
| 12 | `testValidateChannelFractionalDoubleRejected` | Unit | 1.5 | `.failure` |
| 13 | `testValidateChannelStringIntAccepted` | Unit | "5" | `.success(4)` |
| 14 | `testValidateChannelStringFractionalRejected` | Unit | "1.5" | `.failure` |
| 15 | `testValidateChannelNegativeRejected` | Unit | -1 | `.failure` |
| 16 | `testValidateChannelBoolRejected` | Unit | `.bool(true)` (EC-1) | `.failure` |
| 17 | `testValidateChannelInfinityRejected` | Unit | `.double(Double.infinity)` (EC-4) | `.failure` |
| 18 | `testValidateChannelNaNRejected` | Unit | `.double(.nan)` (EC-4) | `.failure` |

### 3.2 Test File Location
- `Tests/LogicProMCPTests/MIDIDispatcherValidationHelpersTests.swift` (NEW)

### 3.3 Mock/Setup Required
- 없음 (pure helper, params dictionary 입력만)

## 4. Implementation Guide

### 4.1 Files to Modify
| File | Change Type | Description |
|------|------------|-------------|
| `Sources/LogicProMCP/Dispatchers/MIDIDispatcher.swift` | Modify | 2개 helper 추가 (file-private static func) |
| `Tests/LogicProMCPTests/MIDIDispatcherValidationHelpersTests.swift` | Create | 15 unit tests |

### 4.2 Implementation Steps (Green Phase)
1. `validatePort(_ params: [String: Value]) -> Result<String, String>` 추가:
   ```swift
   private static func validatePort(_ params: [String: Value]) -> Result<String, String> {
       // v0.4 정합화: `""` 입력은 default로 처리하지 않고 명시 reject (test #5와 일관)
       guard let raw = params["port"]?.stringValue else {
           return .success("midi") // 미지정 = default
       }
       let validPorts: Set<String> = ["midi", "keycmd"]
       guard validPorts.contains(raw) else {
           return .failure("port must be one of: midi, keycmd")
       }
       return .success(raw)
   }
   ```
2. `validateMidiChannel(_ params: [String: Value]) -> Result<UInt8, String>` 추가:
   ```swift
   private static func validateMidiChannel(_ params: [String: Value]) -> Result<UInt8, String> {
       guard let raw = params["channel"] else {
           return .success(0) // default Ch 1 (wire 0)
       }
       let intCandidate: Int? = {
           switch raw {
           case .int(let n): return n
           case .double(let f): return Int(exactly: f)
           case .string(let s):
               // strict integer string only — reject "1.5"
               guard let i = Int(s) else { return nil }
               return i
           default: return nil
           }
       }()
       guard let v = intCandidate else {
           return .failure("channel must be integer 1..16 (1-based)")
       }
       guard (1...16).contains(v) else {
           return .failure("channel must be integer 1..16 (1-based)")
       }
       return .success(UInt8(v - 1))
   }
   ```
3. 테스트 실행 → all 15 PASS

### 4.3 Refactor Phase
- DispatcherSupport.swift에 helper로 옮길지 검토 (다른 dispatcher 재사용 가능성). 단 v3.1.5 범위에서는 MIDIDispatcher local 유지 (over-engineering 회피).

## 5. Edge Cases
- EC-1: `Value.bool` 입력 (예: `{channel: true}`) — 위 sketch에서 default case → `.failure` ✓
- EC-2: `Value.array` / `Value.object` — default case → `.failure` ✓
- EC-3: 매우 큰 정수 (Int64.max) — `(1...16).contains` guard로 reject ✓
- EC-4: `Value.double(Double.infinity)` / `NaN` — `Int(exactly:)`이 nil 반환 → `.failure` ✓

## 6. Review Checklist
- [ ] Red: 테스트 실행 → FAILED 확인됨 (helper 미구현)
- [ ] Green: 모든 15 test PASSED
- [ ] Refactor: PASSED 유지
- [ ] AC 14건 충족
- [ ] DispatcherSupport.swift `intParam` 등 기존 helper와 충돌 없음
- [ ] 기존 MIDI 테스트 regression 없음

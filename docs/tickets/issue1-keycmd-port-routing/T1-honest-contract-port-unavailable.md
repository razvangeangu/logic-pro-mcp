# T1: HonestContract `.portUnavailable` FailureError + terminalErrorCodes

**PRD Ref**: PRD-issue1-keycmd-port-routing > §4.1 step 7, §10.1 R7, OQ-7
**Priority**: P1 (High — foundational, blocks T4/T6)
**Size**: S (< 2h)
**Status**: Todo
**Depends On**: None

---

## 1. Objective
`HonestContract.FailureError` enum에 `.portUnavailable` case 추가하고 `terminalErrorCodes` set에 등록하여 router fallback chain wrapping을 차단. T4/T6에서 사용할 envelope 표준화.

## 2. Acceptance Criteria
- [ ] AC-1: `HonestContract.FailureError`에 `case portUnavailable = "port_unavailable"` 추가
- [ ] AC-2: `terminalErrorCodes` set에 `"port_unavailable"` 등록 → `isTerminalStateC()` true 반환
- [ ] AC-3: `encodeStateC(error: .portUnavailable, hint: ..., extras: [...])` 호출 시 정상 envelope 생성 (`{success:false, verified:false, error: "port_unavailable", hint: ..., ...extras}`)
- [ ] AC-4: 기존 FailureError case (invalidParams, elementNotFound, axWriteFailed, notImplemented) 동작 변경 없음

## 3. TDD Spec (Red Phase)

### 3.1 Test Cases

| # | Test Name | Type | Description | Expected |
|---|-----------|------|-------------|----------|
| 1 | `testPortUnavailableErrorRawValue` | Unit | `.portUnavailable.rawValue == "port_unavailable"` | rawValue 일치 |
| 2 | `testPortUnavailableInTerminalErrorCodes` | Unit | `HonestContract.terminalErrorCodes.contains("port_unavailable")` | true |
| 3 | `testIsTerminalStateCWithPortUnavailableEnvelope` | Unit | encodeStateC(.portUnavailable) 결과 envelope을 isTerminalStateC()로 검증 | true |
| 4 | `testEncodeStateCPortUnavailableEnvelopeShape` | Unit | envelope JSON에 `error:"port_unavailable"` + hint + extras 포함 | shape 일치 |
| 5 | `testExistingFailureErrorsUnaffected` | Unit | invalidParams/elementNotFound/axWriteFailed/notImplemented rawValue 그대로 | regression |

### 3.2 Test File Location
- `Tests/LogicProMCPTests/HonestContractPortUnavailableTests.swift` (NEW)

### 3.3 Mock/Setup Required
- 없음 (pure enum + static set + static encode 함수 검증)

## 4. Implementation Guide

### 4.1 Files to Modify
| File | Change Type | Description |
|------|------------|-------------|
| `Sources/LogicProMCP/Utilities/HonestContract.swift` | Modify | `FailureError` enum에 case 추가, `terminalErrorCodes` set에 추가 |
| `Tests/LogicProMCPTests/HonestContractPortUnavailableTests.swift` | Create | 5개 unit test |

### 4.2 Implementation Steps (Green Phase)
1. `HonestContract.FailureError` enum에 `case portUnavailable = "port_unavailable"` 추가 (alphabetical 또는 기존 컨벤션 따름)
2. `terminalErrorCodes` static set 정의 위치에 `"port_unavailable"` 추가
3. 테스트 실행 → all PASS

### 4.3 Refactor Phase
- 다른 case와 doc comment 일관성 확인
- public API 변경 (enum case 추가는 minor SemVer OK — PRD OQ-7 결정)

## 5. Edge Cases
- EC-1: external envelope parser가 unknown reason 만났을 때 graceful 처리 가정 (PRD R7) — 외부 영향 없음 검증

## 6. Review Checklist
- [ ] Red: 테스트 실행 → FAILED 확인됨 (case 없음)
- [ ] Green: 테스트 실행 → PASSED 확인됨
- [ ] Refactor: 테스트 PASSED 유지
- [ ] AC 4건 충족
- [ ] 기존 테스트 깨지지 않음 (특히 ChannelRouter terminalState C 테스트)
- [ ] CHANGELOG-prep note: "FailureError +.portUnavailable" entry 추가 예정 (T8에서 통합)

# T4: ChannelRouter `bypassReadinessOps` + available==false `.portUnavailable` 분기

**PRD Ref**: PRD-issue1-keycmd-port-routing > §3 AC-1.7, §4.1 step 6-7, §5 E7
**Priority**: P0 (Blocker — Issue #1 핵심 fix, KeyCmd seeding chicken-and-egg lock-in 해소)
**Size**: M (2-4h)
**Status**: Todo
**Depends On**: T1 (HonestContract `.portUnavailable`)

---

## 1. Objective
ChannelRouter readiness gate에 `bypassReadinessOps: Set<String>` 도입하여 `midi.*.keycmd` 7 ops가 manual_validation_required 채널을 통과 가능하도록. 또한 `available: false` (virtual port 미생성) 분기에서 `.portUnavailable` HC envelope 직접 반환하여 router fallback wrapping 차단.

## 2. Acceptance Criteria
- [ ] AC-0 (visibility): `bypassReadinessOps` Set은 `internal static let` (test 접근). `routingTable`도 `internal` (T5 invariant test 의존). `@testable import LogicProMCP`로 접근.
- [ ] AC-1: `ChannelRouter`에 `bypassReadinessOps: Set<String>` 정적 field 추가, 7 keys 등록 (`midi.send_cc.keycmd`, `midi.send_note.keycmd`, `midi.send_chord.keycmd`, `midi.send_program_change.keycmd`, `midi.send_pitch_bend.keycmd`, `midi.send_aftertouch.keycmd`, `midi.play_sequence.keycmd`)
- [ ] AC-2: `route(operation:params:)`가 readiness gate 평가 시 `bypassReadinessOps.contains(operation)`이면 `ready` 검사 건너뜀
- [ ] AC-3: `bypass` op이라도 `available: false`면 차단 + `.portUnavailable` HC envelope 직접 반환
- [ ] AC-4: 일반 op의 readiness gate 동작 변경 없음 (기존 `health.ready || allowManualValidationChannels` 그대로)
- [ ] AC-5: `.portUnavailable` 반환 envelope에 `hint: health.detail` + `extras: ["operation": op]` 포함
- [ ] AC-6: `.portUnavailable`이 `terminalErrorCodes`에 포함되어 있어 router가 `lastError`로 wrap하지 않고 즉시 반환
- [ ] AC-7: bypass 작동 시나리오: KeyCmd 채널 manual_validation_required (`available: true, ready: false`) + `midi.send_cc.keycmd` op → execute 통과 → MIDIKeyCommandsChannel.execute 도달
- [ ] AC-8: bypass 미작동 시나리오: 일반 `midi.send_cc` (suffix 없음) op → 기존 readiness gate 그대로

## 3. TDD Spec (Red Phase)

### 3.1 Test Cases

| # | Test Name | Type | Description | Expected |
|---|-----------|------|-------------|----------|
| 1 | `testBypassReadinessOpsContainsAllSevenKeycmdOps` | Unit | Set membership for 7 expected keys | all true |
| 2 | `testBypassOpsRouteThroughManualValidationChannel` | Integration | mock channel `available:true, ready:false` + bypass op | execute 호출됨 |
| 3 | `testBypassOpsRejectedWhenChannelUnavailable` | Integration | mock channel `available:false` + bypass op | `.portUnavailable` envelope 반환 |
| 4 | `testNonBypassOpUsesStandardReadinessGate` | Integration | `midi.send_cc` (no suffix) + ready:false channel | gate skip → next channel |
| 5 | `testPortUnavailableEnvelopeIncludesHintFromHealth` | Unit | health.detail 가 envelope hint에 포함 | hint substring match |
| 6 | `testPortUnavailableEnvelopeIncludesOperationInExtras` | Unit | extras["operation"] == op key | match |
| 7 | `testPortUnavailableTerminalDoesNotFallthrough` | Integration | `.portUnavailable` 반환 후 다음 채널 시도 안 됨 | router 즉시 종료 |
| 8 | `testRoutingTableInvariantBypassMatchesKeycmdSuffix` | Unit | 모든 `^midi\..*\.keycmd$` routing key가 bypassReadinessOps에 있음 + bypassReadinessOps 모든 entry가 routingTable에 존재 (양방향 invariant). **T5 완료 후 실행** (T5가 routingTable 14 entries 추가 — Phase 4 Loop 1 tester P1)| invariant 통과 |
| 9 | `testBypassOpsDoesNotAffectOtherChannelsRouting` | Integration | core_midi/applescript 일반 op routing 영향 없음 | regression |

### 3.2 Test File Location
- `Tests/LogicProMCPTests/ChannelRouterBypassReadinessTests.swift` (NEW)

### 3.3 Mock/Setup Required
- `MockChannel(available:Bool, ready:Bool, executeStub: ChannelResult)` 패턴 (기존 ChannelRouterTests 참고)
- `MockHealth(available:Bool, ready:Bool, detail:String)` 

## 4. Implementation Guide

### 4.1 Files to Modify
| File | Change Type | Description |
|------|------------|-------------|
| `Sources/LogicProMCP/Channels/ChannelRouter.swift` | Modify | bypassReadinessOps Set + route() readiness gate 분기 + available==false portUnavailable 분기 |
| `Tests/LogicProMCPTests/ChannelRouterBypassReadinessTests.swift` | Create | 9 tests |

### 4.2 Implementation Steps (Green Phase)
1. `ChannelRouter`에 static field 추가:
   ```swift
   static let bypassReadinessOps: Set<String> = [
       "midi.send_cc.keycmd",
       "midi.send_note.keycmd",
       "midi.send_chord.keycmd",
       "midi.send_program_change.keycmd",
       "midi.send_pitch_bend.keycmd",
       "midi.send_aftertouch.keycmd",
       "midi.play_sequence.keycmd",
   ]
   ```
2. `route(operation:params:)` 내부 readiness gate 분기 (line ~282 근처):
   ```swift
   let isBypass = Self.bypassReadinessOps.contains(operation)
   guard health.available else {
       // bypass든 일반이든 available:false면 portUnavailable
       if isBypass {
           return .error(HonestContract.encodeStateC(
               error: .portUnavailable,
               hint: health.detail,
               extras: ["operation": operation]
           ))
       }
       // 일반 op는 기존 lastError 누적
       lastError = "Channel \(channelID.rawValue) not available"
       continue
   }
   guard isBypass || health.ready || ServerConfig.allowManualValidationChannels else {
       continue
   }
   // execute
   ```
3. terminalErrorCodes 분기는 T1에서 이미 등록되었으므로 자동 작동
4. 테스트 실행 → all 9 PASS

### 4.3 Refactor Phase
- bypassReadinessOps generation 자동화 검토 (routingTable 키에서 suffix 추출). 단 v3.1.5 범위에서는 명시 list 유지 (가독성 + invariant test로 누락 방지)

## 5. Edge Cases
- EC-1: `health.available == nil` (health check 실패) — `health` API 명세 확인 후 nil 케이스 → 보수적으로 차단 + portUnavailable
- EC-2: bypass op이지만 channel routing 자체에 매핑 없음 (오타 등) — routingTable에 entry 없으면 기존 "operation not handled" 에러 (T5에서 routingTable 추가 검증)

## 6. Review Checklist
- [ ] Red: 9 test FAILED 확인
- [ ] Green: 9 PASSED
- [ ] AC 8건 충족
- [ ] 기존 ChannelRouterTests regression 0
- [ ] T1 (HonestContract `.portUnavailable`) 의존성 정확
- [ ] bypassReadinessOps invariant 테스트가 future maintenance 보장

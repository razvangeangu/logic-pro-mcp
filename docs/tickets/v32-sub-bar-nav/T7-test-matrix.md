# T7 — Parameterized 매트릭스 + 통합 회귀 테스트

**Status**: Todo
**의존성**: T1-T6
**Size**: M
**PRD**: AC-7.1~7.5

## 목표

T1-T6 의 unit test 외에 cross-cutting 통합 회귀 + edge case 매트릭스. 1064 → 1074+ tests.

## 매트릭스 (E1-E13 PRD edge case 직접 매핑)

```swift
@Test("transport.goto_position E1-E13 매트릭스", arguments: [
    // 입력, 분기, 기대
    ("position=146.4.4.240", .accept, .dialogPath4Comp),     // E1
    ("position=1.1.1.1", .accept, .dialogPath4Comp),         // E2
    ("position=9999.16.16.999", .accept, .dialogPath4Comp),  // E3
    ("position=146", .reject, .dispatcherInvalidParams),     // E4
    ("position=146.4", .reject, .dispatcherInvalidParams),   // E5
    ("position=146.4.4", .reject, .dispatcherInvalidParams), // E6
    ("position=146.4.4.240.1", .reject, .dispatcherInvalidParams), // E7
    ("position=0.1.1.1", .reject, .dispatcherInvalidParams), // E8
    ("position=10000.1.1.1", .reject, .dispatcherInvalidParams), // E9
    ("position=146.17.4.240", .reject, .dispatcherInvalidParams), // E10
    ("position=00:01:30:00", .accept, .cgEventFallback),     // E11
    ("bar=146", .accept, .dialogPath4CompFromBar),           // E12
    // E13 라이브 검증 (slider partial) — synthetic runtime
])
func transportGotoPosition_matrix(input: String, expected: ...) {
    ...
}
```

(actual implementation은 T1-T6의 helper 사용 — 각 case는 dispatcher가 검증/거부 또는 AX channel이 라우팅)

## 통합 회귀 (cross-ticket)

```swift
@Test
func e2e_gotoMarker_byName_fallbackMarker_routesToTransportWithUncertainty() async {
    // T2 + T4 + T6 통합 시나리오:
    // 1. parser fail → MarkerState `.fallback`
    // 2. goto_marker { name: ... } → cache lookup → transport.goto_position
    // 3. response extras `marker_position_uncertain: true`
}

@Test
func e2e_logicMarkers_resourceIncludesProvenance() async {
    // T3 + T4 + T5 통합:
    // cache에 `.parser` + `.fallback` + `.unknown` 3 markers
    // logic://markers 응답에 모두 position_source / is_canonical 포함
}

@Test
func backwardCompat_v31xCacheSnapshot_decodesAsUnknown_doesNotCrash() async {
    // 기존 cache.json 파일을 v3.2 디코더로 읽어도 crash 없음 (production-realistic)
}
```

## Acceptance Criteria

- **AC-T7.1**: E1-E13 매트릭스 13 cases PASS
- **AC-T7.2**: 3 cross-ticket E2E 시나리오 PASS
- **AC-T7.3**: 1064 + 신규 ≥ 10 = 1074+ tests PASS (`swift test --no-parallel`)
- **AC-T7.4**: `swift build -c release` 0 warnings
- **AC-T7.5**: 한글 주석, 신규 TODO 0
- **AC-T7.6**: parameterized 매트릭스 형식 (case 별 @Test function 분산 X)

## Out of Scope

- live-verify runbook = T9
- docs/API.md = T8

# T3: 통합 회귀 테스트 (caller fallback + behavior change)

**PRD Ref**: PRD-issue9 > §8.2 + Behavior change
**Priority**: P1
**Size**: S (< 30min)
**Status**: Todo
**Depends On**: T1, T2

---

## 1. Objective
- parser nil → caller `\(index+1).1.1.1` fallback 회귀 보호 (이미 existing test `enumerateMarkers_unparseablePosition_usesIndexFallback`).
- 비-bar-aligned 마커 (raw `"146 4 4 240."`)가 `enumerateMarkersFromListWindow`를 통해 `MarkerState.position == "146.4.4.240"`으로 surface — 신규 통합.

## 2. Acceptance Criteria
- [ ] AC-1: 기존 `enumerateMarkers_unparseablePosition_usesIndexFallback` 테스트 PASS (fallback 회귀 보호).
- [ ] AC-2: 신규 통합 테스트 `enumerateMarkers_trailingDotPosition_canonicalizes` — synthetic AX tree에서 `"146 4 4 240."` 입력 → `MarkerState.position == "146.4.4.240"` 검증.
- [ ] AC-3: 한글 주석.

## 3. TDD Spec

```swift
@Test("enumerateMarkers: 영문 12.2 끝 마침표 표기 → canonical position 추출")
func enumerateMarkers_trailingDotPosition_canonicalizes() async {
    // 영문 Logic 12.2 비-bar-aligned 마커 시나리오.
    // raw "146 4 4 240." → "146.4.4.240" canonicalize.
    let builder = FakeAXRuntimeBuilder()
    let app = builder.element(7900)
    let arrange = builder.element(7901)
    let listWin = builder.element(7902)
    _ = makeMarkerListTree(
        builder: builder, appElement: app,
        arrangeWindow: arrange, markerListWindow: listWin,
        rows: [(position: "146 4 4 240.", name: "VOCALS", length: "∞")]
    )
    let runtime = builder.makeLogicRuntime(appElement: app)
    let markers = AXLogicProElements.enumerateMarkers(in: arrange, runtime: runtime)
    #expect(markers.count == 1)
    #expect(markers[0].name == "VOCALS")
    #expect(markers[0].position == "146.4.4.240")
}
```

## 4. Implementation Steps
1. 위 테스트를 `AXMarkers12MarkerListTests.swift`에 추가.
2. `swift test --filter enumerateMarkers_trailingDot` → T1 적용 후 PASS.
3. 기존 fallback 회귀 테스트도 함께 실행 — PASS 유지.

## 5. Review Checklist
- [x] AC-2.7 (PRD US-2 호출자 회귀) 충족
- [x] PRD §8.2 통합 시나리오 추가
- [x] 한글 주석

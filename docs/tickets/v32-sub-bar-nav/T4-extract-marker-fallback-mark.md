# T4 — `extractMarkerPosition` 양쪽 Caller Fallback Site `.fallback` 마킹

**Status**: Todo
**Size**: S
**의존성**: T3
**PRD**: AC-3.1, AC-3.4
**Boomer Phase E P1-4 fix**: Logic 12.2 primary path은 `enumerateMarkersFromListWindow` (L798-800). Legacy ruler path (L708) 만 수정 시 v3.1.11 이후 모든 marker가 `.parser` 로 잘못 마킹됨. **두 사이트 모두 수정**.

## 목표

두 fallback site 모두 `position_source` 명시:

**사이트 1 — Legacy ruler walker** (`AXLogicProElements.swift:708`):
```swift
markers.append(MarkerState(id: index, name: name, position: position ?? "\(index + 1).1.1.1"))
```

**사이트 2 — Logic 12.2 marker list (primary)** (`AXLogicProElements.swift:798-800`):
```swift
let position = parseMarkerListPosition(positionRaw)
    ?? "\(index + 1).1.1.1"
markers.append(MarkerState(id: index, name: name, position: position))
```

→ 두 사이트 모두 parser 성공 시 `.parser`, fallback 시 `.fallback` 명시.

## TDD Red Phase

```swift
@Test
func enumerateMarkers_validParse_marksAsParser() async {
    let builder = FakeAXRuntimeBuilder()
    let app = builder.element(8000)
    let arrange = builder.element(8001)
    let listWin = builder.element(8002)
    _ = makeMarkerListTree(
        builder: builder, appElement: app,
        arrangeWindow: arrange, markerListWindow: listWin,
        rows: [(position: "146 4 4 240", name: "VOCALS", length: "∞")]
    )
    let runtime = builder.makeLogicRuntime(appElement: app)
    let markers = AXLogicProElements.enumerateMarkers(in: arrange, runtime: runtime)
    #expect(markers.count == 1)
    #expect(markers[0].positionSource == .parser)
    #expect(markers[0].position == "146.4.4.240")
}

@Test
func enumerateMarkers_unparseablePosition_marksAsFallback() async {
    let builder = FakeAXRuntimeBuilder()
    let app = builder.element(8010)
    let arrange = builder.element(8011)
    let listWin = builder.element(8012)
    _ = makeMarkerListTree(
        builder: builder, appElement: app,
        arrangeWindow: arrange, markerListWindow: listWin,
        rows: [(position: "abc", name: "X", length: "∞")]
    )
    let runtime = builder.makeLogicRuntime(appElement: app)
    let markers = AXLogicProElements.enumerateMarkers(in: arrange, runtime: runtime)
    #expect(markers.count == 1)
    #expect(markers[0].positionSource == .fallback)
    #expect(markers[0].position == "1.1.1.1") // index+1.1.1.1
}
```

**Red 확인**: 현재 코드는 `MarkerState` init 시 `positionSource` 기본값 `.parser` 사용 → fallback case도 `.parser` 로 마킹 → assertion FAIL.

## Green Phase 구현

**사이트 1** (legacy ruler — `AXLogicProElements.swift:708`):

```swift
let position = extractMarkerPosition(text, runtime: runtime.ax)
let source: PositionSource = position != nil ? .parser : .fallback
markers.append(MarkerState(
    id: index,
    name: name,
    position: position ?? "\(index + 1).1.1.1",
    positionSource: source
))
```

**사이트 2** (Logic 12.2 marker list — `AXLogicProElements.swift:798-800`):

```swift
let parsed = parseMarkerListPosition(positionRaw)
let source: PositionSource = parsed != nil ? .parser : .fallback
markers.append(MarkerState(
    id: index,
    name: name,
    position: parsed ?? "\(index + 1).1.1.1",
    positionSource: source
))
```

기존 `let position = parseMarkerListPosition(positionRaw) ?? "\(index + 1).1.1.1"` 한 줄 → 3 줄로 확장. parser 결과를 두 번 사용 (source 결정 + position 값).

## Refactor Phase

- 한글 주석: `// parser 성공 → .parser, nil → .fallback (manufactured)`
- 단순 변환 — extra logic 추가 0
- AC-4.2 grep 검증

## Acceptance Criteria

- **AC-T4.1**: 2 통합 테스트 PASS (parser 성공 / fallback 케이스)
- **AC-T4.2**: 기존 1064 tests + T3 4 tests = 1070 PASS 유지
- **AC-T4.3**: 변경 라인 ≤ 12 (양쪽 사이트 합산 — boomer P1-4 반영)
- **AC-T4.4**: 한글 주석, 신규 TODO 0
- **AC-T4.5**: enumerator 외 다른 marker 생성 site 없음 확인 (grep `MarkerState(id:`)

## Out of Scope

- resource envelope surface = T5
- goto_marker uncertainty extras = T6

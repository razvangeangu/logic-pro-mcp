# T4 — `extractMarkerPosition` Both Caller Fallback Sites `.fallback` Marking

**Status**: Todo
**Size**: S
**Depends on**: T3
**PRD**: AC-3.1, AC-3.4
**Boomer Phase E P1-4 fix**: The Logic 12.2 primary path is `enumerateMarkersFromListWindow` (L798-800). Fixing only the legacy ruler path (L708) would cause all markers from v3.1.11+ to be incorrectly marked as `.parser`. **Both sites must be fixed**.

## Goal

Explicitly mark `position_source` at both fallback sites:

**Site 1 — Legacy ruler walker** (`AXLogicProElements.swift:708`):
```swift
markers.append(MarkerState(id: index, name: name, position: position ?? "\(index + 1).1.1.1"))
```

**Site 2 — Logic 12.2 marker list (primary)** (`AXLogicProElements.swift:798-800`):
```swift
let position = parseMarkerListPosition(positionRaw)
    ?? "\(index + 1).1.1.1"
markers.append(MarkerState(id: index, name: name, position: position))
```

→ Both sites: mark `.parser` when parser succeeds, `.fallback` when fallback is used.

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

**Red confirmation**: Current code uses `MarkerState` init with default `.parser` → fallback case is also marked `.parser` → assertion FAIL.

## Green Phase Implementation

**Site 1** (legacy ruler — `AXLogicProElements.swift:708`):

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

**Site 2** (Logic 12.2 marker list — `AXLogicProElements.swift:798-800`):

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

Existing `let position = parseMarkerListPosition(positionRaw) ?? "\(index + 1).1.1.1"` one line → expanded to 3 lines. Parser result used twice (source determination + position value).

## Refactor Phase

- Korean comment: `// parser success → .parser, nil → .fallback (manufactured)`
- Simple transformation — no extra logic added
- AC-4.2 grep verification

## Acceptance Criteria

- **AC-T4.1**: 2 integration tests PASS (parser success / fallback case)
- **AC-T4.2**: Existing 1064 tests + T3 4 tests = 1070 PASS maintained
- **AC-T4.3**: Changed lines ≤ 12 (both sites combined — Boomer P1-4 reflected)
- **AC-T4.4**: Korean comments, no new TODOs
- **AC-T4.5**: Confirm no other marker creation sites exist (grep `MarkerState(id:`)

## Out of Scope

- resource envelope surface = T5
- goto_marker uncertainty extras = T6

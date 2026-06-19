# T3: Integration regression test (caller fallback + behavior change)

> Historical record. Current release-candidate evidence is in `README.md`, `CHANGELOG.md`, and `docs/live-verify-v3.6.0.md`; published stable evidence remains in `docs/live-verify-v3.5.0.md`; this file remains preserved implementation context.

**PRD Ref**: PRD-issue9 > §8.2 + Behavior change
**Priority**: P1
**Size**: S (< 30min)
**Status**: Todo
**Depends On**: T1, T2

---

## 1. Objective
- Regression protection for parser nil → caller `\(index+1).1.1.1` fallback (covered by existing test `enumerateMarkers_unparseablePosition_usesIndexFallback`).
- New integration test: non-bar-aligned marker (raw `"146 4 4 240."`) surfaces as `MarkerState.position == "146.4.4.240"` through `enumerateMarkersFromListWindow`.

## 2. Acceptance Criteria
- [ ] AC-1: Existing `enumerateMarkers_unparseablePosition_usesIndexFallback` test PASS (fallback regression protection).
- [ ] AC-2: New integration test `enumerateMarkers_trailingDotPosition_canonicalizes` — `"146 4 4 240."` input in synthetic AX tree → `MarkerState.position == "146.4.4.240"`.
- [ ] AC-3: Korean comments.

## 3. TDD Spec

```swift
@Test("enumerateMarkers: English 12.2 trailing-dot position → canonical position extracted")
func enumerateMarkers_trailingDotPosition_canonicalizes() async {
    // English Logic 12.2 non-bar-aligned marker scenario.
    // raw "146 4 4 240." → canonicalize to "146.4.4.240".
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
1. Add the test above to `AXMarkers12MarkerListTests.swift`.
2. `swift test --filter enumerateMarkers_trailingDot` → PASS after T1 is applied.
3. Run the existing fallback regression test alongside — confirm PASS maintained.

## 5. Review Checklist
- [x] AC-2.7 (PRD US-2 caller regression) satisfied
- [x] PRD §8.2 integration scenario added

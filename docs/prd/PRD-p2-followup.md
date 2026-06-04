# PRD — P2 Follow-up: parameterized + AX assertion backfill + HC addExtras

> Historical record (2026-06-05 docs refresh): latest production-readiness and live E2E evidence is in `README.md`, `CHANGELOG.md`, and `docs/live-verify-v3.4.5-rc5.md`; this file remains preserved implementation context.

**Status**: Draft (v0.3 — boomer round 2 cleanup)
**Size**: M
**Owner**: Isaac
**Started**: 2026-05-07
**Driving**: Post-v3.2.0 ship: convergence of P2 items from the 4-agent review (minimal production code change; test quality + abstraction hygiene).

---

## 1. Goal

Three cleanup tasks with zero production regression risk, immediately after the v3.2.0 release (boomer P2-2 round 1: `mergeMarkerUncertainty` parameterized consolidation dropped — validation fields differ → split retained):

1. `markerState_codableRoundTrip_*` 3 cases → parameterized consolidation (uniform round-trip validation)
2. AX walker integration tests (`AXMarkers12MarkerListTests`) 7 functions — backfill `positionSource` assertions
3. `HonestContract.addExtras(_:)` first-class API addition — elevate `mergeMarkerUncertainty`'s `JSONSerialization` workaround into the HC layer to improve abstraction hygiene

## 2. Non-Goals

- HC contract semantics changes — `success`/`verified`/`reason`/`error` field behavior unchanged.
- Production code behavior changes — `goto_marker` response schema unchanged (`marker_position_uncertain` + `marker_position_source` fields preserved). Only the internal implementation path goes through the HC API.
- AX walker behavior changes — integration test assertion additions only.
- New wire schema fields — out of scope.

## 3. Background

### 3.1 v3.2.0 4-agent review P2 residuals

Two prior /simplify passes and one Phase G review classified the following P2 items as follow-up value:

| # | Item | Source |
|---|------|---------|
| 1 | `mergeMarkerUncertainty` 4-case parameterized | Tester P2-1 (round 1) |
| 2 | Codable round-trip 3-case parameterized | Tester P2-1 (round 1) |
| 3 | AX walker integration test `positionSource` backfill | Tester P2-2 (round 1) |
| 4 | HC `addExtras(_:)` helper | Reuse Agent R1 (round 1) + Quality Agent Q1 (round 1) — leaky abstraction |

### 3.2 Current mergeMarkerUncertainty structure

`Sources/LogicProMCP/Dispatchers/NavigateDispatcher.swift:177-195` — parses raw JSON via `JSONSerialization` → mutates → re-encodes. Bypasses the HC envelope abstraction (the HC body has no extras-merge primitive — each state encoder does an inline dict copy).

### 3.3 HC State A/B/C encoder pattern (HonestContract.swift:73-105)

Each encoder follows the same pattern:
```swift
var dict: [String: Any] = [...top-level keys...]
for (k, v) in extras { dict[k] = v }
return jsonString(dict)
```

The extras-merge already exists inside HC — at encoding time. However, there is **no post-encode merge API** → `mergeMarkerUncertainty` uses `JSONSerialization` externally to work around this.

### 3.4 Current AX walker integration tests

`AXMarkers12MarkerListTests.swift`'s `enumerateMarkers_*` tests (5+ cases) assert `markers[0].name` and `markers[0].position` but **do not assert `positionSource`**. The v3.2 provenance contract is not protected at the integration layer — only at the unit test layer.

## 4. Functional Requirements

### 4.1 Parameterized consolidation (FR-1) — scope reduced (boomer round 1 P2-2)

- **AC-1.1** [DROPPED in v0.2]: `mergeMarkerUncertainty_*` 4-case parameterized consolidation — consistent with boomer P2-2 and the Reuse Agent's prior review: the 4 cases validate different fields/semantics (`!contains`, `contains "success":true`, `contains "verified":false`, exact equality), so grouping them into a single `arguments` matrix would hurt readability. **Retain current 4 individual functions.**
- **AC-1.2**: `markerState_codableRoundTrip_*` 3 individual tests → single `@Test(arguments: [PositionSource.parser, .fallback, .unknown])`. All perform the same round-trip + `positionSource ==` enum-case validation, making consolidation natural. New enum cases automatically expand the test.
- **AC-1.3**: After consolidation, explicitly state the per-case enum value in the `#expect` message — preserving failure diagnostics.

### 4.2 AX walker assertion backfill (FR-2 — boomer round 1 P1)

Explicitly add `markers[i].positionSource` assertions to the following marker-producing `enumerateMarkers_*` functions in `AXMarkers12MarkerListTests.swift` (line numbers identified directly by boomer):

| Function (line) | Marker source | Expected `positionSource` |
|----------------|--------------|--------------------------|
| `enumerateMarkers_logic122_markerListWindow_open_returnsMarkers` (L85) | parser success (Logic 12.2 list window) | `.parser` |
| `enumerateMarkers_listWindow_closed_fallsThroughToRulerStrategy` (L127) | parser success (ruler fallback) | `.parser` |
| `enumerateMarkers_listAndRulerBothPresent_listWins` (L220) | parser success (list wins) | `.parser` |
| `enumerateMarkers_malformedRow_skipsRowKeepsValid` (L252) | parser success — malformed rows skipped, only surviving rows validated | `.parser` |
| `enumerateMarkers_unparseablePosition_usesIndexFallback` (L317) | parser failure → caller fallback | `.fallback` |
| `enumerateMarkers_trailingDotPosition_canonicalizes` (L341) | parser success (English 12.2 trailing dot strip) | `.parser` |
| `enumerateMarkers_koreanWholeBarPosition_canonicalizes` (L361) | parser success (Korean whole-bar) | `.parser` |

- **AC-2.1**: All 7 functions above receive explicit `markers[*].positionSource` assertions.
- **AC-2.2**: Existing assertions (`name`, `position`) are not modified — lines added only.
- **AC-2.3**: Multi-marker scenarios (e.g., `_listAndRulerBothPresent_listWins` list-source markers / `_malformedRow_skipsRowKeepsValid` surviving valid rows) — all asserted markers validated.

### 4.3 HC addExtras helper (FR-3 — boomer round 1 P2-1)

- **AC-3.1**: Add `static func addExtras(_ extras: [String: Any], into rawJSON: String) -> String` to `HonestContract` (boomer P2-1 fix: `requireSuccess: Bool = true` flag removed per YAGNI — current callers: 1 (`mergeMarkerUncertainty`), single policy (State C skip). When a second caller appears, split into a separate method). Semantics:
  - Parse rawJSON as a JSON object
  - Parse failure → return original verbatim (defensive — will not occur on the production happy path)
  - `(parsed["success"] as? Bool) == false` → return original verbatim (preserve HC State C — do not allow caller-side extras to be added to error responses)
  - On guard pass: merge top-level keys → re-encode (sortedKeys)
- **AC-3.2**: `NavigateDispatcher.mergeMarkerUncertainty(into:source:)` delegates to `addExtras`:
  ```swift
  static func mergeMarkerUncertainty(into rawJSON: String, source: PositionSource) -> String {
      HonestContract.addExtras([
          "marker_position_uncertain": true,
          "marker_position_source": source.rawValue,
      ], into: rawJSON)
  }
  ```
- **AC-3.3**: External client response unchanged — JSON output byte-identical (sortedKeys + same key set).
- **AC-3.4**: Existing `mergeMarkerUncertainty_*` 4 individual tests (parameterized consolidation dropped, split retained) — zero regressions.
- **AC-3.5**: HC self-tests added — `addExtras` 4 scenarios (State A merge / State B merge + reason preserved / State C skip / invalid JSON).

### 4.4 Code conventions (FR-4)

- **AC-4.1**: New/modified code uses Korean comments only (no English comments added).
- **AC-4.2**: Zero new TODO/FIXME/XXX entries.
- **AC-4.3**: `HonestContract.addExtras` body ≤ 25 lines.
- **AC-4.4**: SOLID/SRP — `addExtras` is a generic post-encode merge primitive (zero domain knowledge of positionSource or similar).

## 5. Implementation Plan (ticket breakdown v0.2)

| # | Title | Size | Dependencies |
|---|-------|------|--------------|
| T1 | Codable round-trip 3 cases → parameterized | S | — |
| T2 | AX walker 7 integration test positionSource assertion backfill | S | — |
| T3 | HC.addExtras helper + NavigateDispatcher delegation + HC tests | S | — |

> Each ticket is independent (can run in parallel). No dependencies. T2 from v0.1 (`mergeMarkerUncertainty` parameterized) dropped in v0.2 — boomer P2-2.

## 6. Risks & Mitigations

| Risk | Severity | Mitigation |
|------|----------|-----------|
| Parameterized consolidation obscures test intent | Low | Use explicit expectation tuples per row + state scenario in test description |
| `addExtras` introduction changes `mergeMarkerUncertainty`'s sortedKeys behavior | Low | Use `JSONSerialization.WritingOptions` `[.sortedKeys]` with identical options + JSON output byte-equality test |
| HC body change affects other dispatchers | Low | `addExtras` is a new function only; existing `encodeStateA/B/C` signatures unchanged |
| AX walker integration test assertion additions break existing fixtures | Low | Lines added adjacent to existing `position`/`name` assertions (structure unchanged) |

## 7. Tests

- **AC-7.1**: `swift test --no-parallel` → 1081 PASS maintained (or +N — addExtras test 4 scenarios added).
- **AC-7.2**: `swift build -c release` clean (0 warnings).
- **AC-7.3**: 5+ integration tests' `positionSource` validation strengthens the v3.2 provenance contract protection.

## 8. Success Metrics

- Tests: 1081 → 1081-1085 (parameterized conversion: same invocation count or negligible variation + AX assertion line additions: no test count change + HC.addExtras tests: +4)
- Build clean
- `mergeMarkerUncertainty` body ≤ 5 lines (HC delegation)
- `HonestContract.addExtras` body ≤ 25 lines

## Version History

- **v0.1** (2026-05-07): Initial draft.
- **v0.2** (2026-05-07): Boomer round 1 integration — P1 (AC-2.1 explicit 7 functions + lines + expected value table) + P2-1 (`addExtras` `requireSuccess` flag removal — YAGNI) + P2-2 (`mergeMarkerUncertainty` parameterized consolidation dropped — validation fields differ → split retained). Tickets 4 → 3.
- **v0.3** (2026-05-07): Boomer round 2 cleanup — Goal §1 stale 4 items → 3 items sync / AC-3.4 wording (after parameterized → split retained) / AC-2.1 table corrected to actual test function names (verified by boomer codex grep).

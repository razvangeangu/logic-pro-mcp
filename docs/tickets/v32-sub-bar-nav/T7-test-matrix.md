# T7 — Parameterized Matrix + Integration Regression Tests

> Historical record (2026-06-05 docs refresh): latest production-readiness and live E2E evidence is in `README.md`, `CHANGELOG.md`, and `docs/live-verify-v3.4.5-rc5.md`; this file remains preserved implementation context.

**Status**: Todo
**Depends on**: T1-T6
**Size**: M
**PRD**: AC-7.1~7.5

## Goal

Cross-cutting integration regression + edge case matrix beyond the unit tests in T1-T6. 1064 → 1074+ tests.

## Matrix (PRD edge cases E1-E13 directly mapped)

```swift
@Test("transport.goto_position E1-E13 matrix", arguments: [
    // input, branch, expected
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
    // E13 live verification (slider partial) — synthetic runtime
])
func transportGotoPosition_matrix(input: String, expected: ...) {
    ...
}
```

(Actual implementation uses helpers from T1-T6 — each case is validated/rejected by the dispatcher or routed by the AX channel)

## Integration Regression (cross-ticket)

```swift
@Test
func e2e_gotoMarker_byName_fallbackMarker_routesToTransportWithUncertainty() async {
    // T2 + T4 + T6 integrated scenario:
    // 1. parser fail → MarkerState `.fallback`
    // 2. goto_marker { name: ... } → cache lookup → transport.goto_position
    // 3. response extras `marker_position_uncertain: true`
}

@Test
func e2e_logicMarkers_resourceIncludesProvenance() async {
    // T3 + T4 + T5 integrated:
    // cache has `.parser` + `.fallback` + `.unknown` 3 markers
    // logic://markers response includes position_source / is_canonical for all
}

@Test
func backwardCompat_v31xCacheSnapshot_decodesAsUnknown_doesNotCrash() async {
    // Reading an existing cache.json with v3.2 decoder succeeds without crash (production-realistic)
}
```

## Acceptance Criteria

- **AC-T7.1**: E1-E13 matrix 13 cases PASS
- **AC-T7.2**: 3 cross-ticket E2E scenarios PASS
- **AC-T7.3**: 1064 + new ≥ 10 = 1074+ tests PASS (`swift test --no-parallel`)
- **AC-T7.4**: `swift build -c release` 0 warnings
- **AC-T7.5**: Korean comments, no new TODOs
- **AC-T7.6**: Parameterized matrix format (cases not split into individual @Test functions)

## Out of Scope

- live-verify runbook = T9
- docs/API.md = T8

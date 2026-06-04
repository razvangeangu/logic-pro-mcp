# T6 — `goto_marker` Dispatcher: HC Top-Level Extras Merge

> Historical record (2026-06-05 docs refresh): latest production-readiness and live E2E evidence is in `README.md`, `CHANGELOG.md`, and `docs/live-verify-v3.4.5-rc5.md`; this file remains preserved implementation context.

**Status**: Todo
**Depends on**: T2, T4
**Size**: S
**PRD**: AC-3.6
**Boomer Phase E P1-5 fix**: HonestContract JSON shape is **flat top-level** (`{"success":true, "verified":true, ...extras}` per HonestContract.swift:73-105). Nested `{state, extras}` assumption is wrong. State C (success:false) avoids merge — error response preserved.

## Goal

`NavigateDispatcher` `goto_marker` checks cache `position_source`. When `.fallback` or `.unknown`, after calling transport.goto_position, merge `marker_position_uncertain: true` + `marker_position_source: <enum rawValue>` into the response extras.

## TDD Red Phase

```swift
@Test
func gotoMarker_byName_canonicalMarker_noUncertaintyFlag() async throws {
    let cache = StateCache()
    await cache.updateMarkers([
        MarkerState(id: 0, name: "VOCALS", position: "146.4.4.240", positionSource: .parser),
    ])
    // HC State A actual shape — flat top-level
    let stubRouter = stubRouterReturning(#"{"success":true,"verified":true,"requested":"146.4.4.240"}"#)
    let result = await NavigateDispatcher.dispatch(
        command: "goto_marker", params: ["name": "VOCALS"],
        cache: cache, router: stubRouter
    )
    let json = extractText(result)
    #expect(!json.contains("marker_position_uncertain"))
    #expect(!json.contains("marker_position_source"))
    // Existing response preserved
    #expect(json.contains("\"success\":true"))
}

@Test
func gotoMarker_byName_fallbackMarker_mergesUncertaintyAtTopLevel() async throws {
    let cache = StateCache()
    await cache.updateMarkers([
        MarkerState(id: 0, name: "X", position: "1.1.1.1", positionSource: .fallback),
    ])
    let stubRouter = stubRouterReturning(#"{"success":true,"verified":true,"requested":"1.1.1.1"}"#)
    let result = await NavigateDispatcher.dispatch(
        command: "goto_marker", params: ["name": "X"],
        cache: cache, router: stubRouter
    )
    let json = extractText(result)
    // top-level keys added
    #expect(json.contains("\"marker_position_uncertain\":true"))
    #expect(json.contains("\"marker_position_source\":\"fallback\""))
    #expect(json.contains("\"success\":true"))  // existing preserved
}

@Test
func gotoMarker_byName_unknownLegacy_mergesUncertaintyAtTopLevel() async throws {
    let cache = StateCache()
    await cache.updateMarkers([
        MarkerState(id: 0, name: "Legacy", position: "1.1.1.1", positionSource: .unknown),
    ])
    let stubRouter = stubRouterReturning(#"{"success":true,"verified":false,"reason":"readback_unavailable"}"#)
    let result = await NavigateDispatcher.dispatch(
        command: "goto_marker", params: ["name": "Legacy"],
        cache: cache, router: stubRouter
    )
    let json = extractText(result)
    #expect(json.contains("\"marker_position_uncertain\":true"))
    #expect(json.contains("\"marker_position_source\":\"unknown\""))
    #expect(json.contains("\"reason\":\"readback_unavailable\""))  // State B preserved
}

@Test
func gotoMarker_byName_stateC_doesNotMergeUncertainty() async throws {
    // State C error → skip merge — error JSON passed through unchanged
    let cache = StateCache()
    await cache.updateMarkers([
        MarkerState(id: 0, name: "X", position: "1.1.1.1", positionSource: .fallback),
    ])
    let stubRouter = stubRouterReturning(#"{"success":false,"error":"ax_write_failed"}"#)
    let result = await NavigateDispatcher.dispatch(
        command: "goto_marker", params: ["name": "X"],
        cache: cache, router: stubRouter
    )
    let json = extractText(result)
    // State C preserved, uncertainty not merged
    #expect(!json.contains("marker_position_uncertain"))
    #expect(json.contains("\"success\":false"))
}
```

**Red confirmation**: Current `NavigateDispatcher.swift:55` forwards transport.goto_position response as-is → no uncertainty extras included.

## Green Phase Implementation

`Sources/LogicProMCP/Dispatchers/NavigateDispatcher.swift` goto_marker handler:

```swift
case "goto_marker":
    if let name = stringParam(params, "name") {
        let markers = await cache.getMarkers()
        guard let target = markers.first(where: { $0.name == name }) else {
            return toolTextResult("goto_marker: marker '\(name)' not found in cache", isError: true)
        }
        let raw = await router.route(
            operation: "transport.goto_position",
            params: ["position": target.position]
        )
        // v3.2 — surface uncertainty extras when routing fallback/unknown markers.
        if target.positionSource != .parser {
            let merged = mergeMarkerUncertainty(into: raw, source: target.positionSource)
            return toolTextResult(merged)
        }
        return toolTextResult(raw)
    }
    // index branch (existing)
    ...
```

`mergeMarkerUncertainty` helper — merges directly into HC flat top-level shape. State C (`success:false`) passes through unchanged (error response preserved).

```swift
private static func mergeMarkerUncertainty(into rawJSON: String, source: PositionSource) -> String {
    // HC shape (HonestContract.swift:73-105) — flat top-level keys + extras merged.
    // {"success":true, "verified":true|false, "reason":..., ...extras}.
    guard let data = rawJSON.data(using: .utf8),
          var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return rawJSON
    }
    // State C protection — do not add uncertainty to error responses.
    if (object["success"] as? Bool) == false {
        return rawJSON
    }
    object["marker_position_uncertain"] = true
    object["marker_position_source"] = source.rawValue
    guard let encoded = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
          let str = String(data: encoded, encoding: .utf8) else {
        return rawJSON
    }
    return str
}
```

## Refactor Phase

- Korean comments (WHY: add only extras while preserving HC envelope)
- Body ≤ 25 lines
- AC-4.2 grep verification

## Acceptance Criteria

- **AC-T6.1**: 4 integration tests PASS (parser → no flag / fallback → flag / unknown → flag / State C → no merge)
- **AC-T6.2**: Index branch unaffected (existing behavior maintained — name lookup uses cache)
- **AC-T6.3**: HC State C (success:false) raw response not merged (error JSON preserved)
- **AC-T6.4**: HC flat top-level shape (`success`, `verified`, `reason`) preserved + uncertainty key added — Boomer P1-5 fix
- **AC-T6.5**: Korean comments, no new TODOs

## Edge Cases

- Raw JSON parse failure → return original unchanged (defensive — malformed JSON should not occur normally)
- HC State A response may have no extras → optional handling
- If target.position is not 4-component (legacy unknown) → rejected by transport.goto_position validation → State C returned → not merged (correct)

## Out of Scope

- Index branch refactor — existing MIDIKeyCommands routing kept (no cache dependency)
- docs update = T8

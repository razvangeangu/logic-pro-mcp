# T6 — `goto_marker` Dispatcher: HC Top-Level Extras Merge

**Status**: Todo
**의존성**: T2, T4
**Size**: S
**PRD**: AC-3.6
**Boomer Phase E P1-5 fix**: HonestContract JSON shape는 **flat top-level** (`{"success":true, "verified":true, ...extras}` per HonestContract.swift:73-105). nested `{state, extras}` 가정 잘못. State C (success:false) 는 merge 회피 — error 응답 보존.

## 목표

`NavigateDispatcher` `goto_marker` 가 cache의 `position_source` 를 확인. `.fallback` 또는 `.unknown` 일 때 transport.goto_position 호출 후 응답 extras에 `marker_position_uncertain: true` + `marker_position_source: <enum rawValue>` merge.

## TDD Red Phase

```swift
@Test
func gotoMarker_byName_canonicalMarker_noUncertaintyFlag() async throws {
    let cache = StateCache()
    await cache.updateMarkers([
        MarkerState(id: 0, name: "VOCALS", position: "146.4.4.240", positionSource: .parser),
    ])
    // HC State A actual shape — top-level flat
    let stubRouter = stubRouterReturning(#"{"success":true,"verified":true,"requested":"146.4.4.240"}"#)
    let result = await NavigateDispatcher.dispatch(
        command: "goto_marker", params: ["name": "VOCALS"],
        cache: cache, router: stubRouter
    )
    let json = extractText(result)
    #expect(!json.contains("marker_position_uncertain"))
    #expect(!json.contains("marker_position_source"))
    // 기존 응답 보존
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
    // top-level keys 추가
    #expect(json.contains("\"marker_position_uncertain\":true"))
    #expect(json.contains("\"marker_position_source\":\"fallback\""))
    #expect(json.contains("\"success\":true"))  // 기존 보존
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
    #expect(json.contains("\"reason\":\"readback_unavailable\""))  // State B 보존
}

@Test
func gotoMarker_byName_stateC_doesNotMergeUncertainty() async throws {
    // State C error는 merge 회피 — error JSON 그대로
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
    // State C 보존, uncertainty merge 안 함
    #expect(!json.contains("marker_position_uncertain"))
    #expect(json.contains("\"success\":false"))
}
```

**Red 확인**: 현재 `NavigateDispatcher.swift:55` 는 transport.goto_position 응답 그대로 forward → uncertainty extras 미포함.

## Green Phase 구현

`Sources/LogicProMCP/Dispatchers/NavigateDispatcher.swift` `goto_marker` 처리부:

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
        // v3.2 — fallback/unknown 마커 라우팅 시 uncertainty surfacing.
        if target.positionSource != .parser {
            let merged = mergeMarkerUncertainty(into: raw, source: target.positionSource)
            return toolTextResult(merged)
        }
        return toolTextResult(raw)
    }
    // index branch (기존)
    ...
```

`mergeMarkerUncertainty` 헬퍼 — HC top-level flat shape 에 직접 merge. State C (`success:false`) 는 변경 없이 통과 (error 응답 보존).

```swift
private static func mergeMarkerUncertainty(into rawJSON: String, source: PositionSource) -> String {
    // HC shape (HonestContract.swift:73-105) — flat top-level keys + extras 머지.
    // {"success":true, "verified":true|false, "reason":..., ...extras}.
    guard let data = rawJSON.data(using: .utf8),
          var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return rawJSON
    }
    // State C 보호 — error 응답에 uncertainty 추가 안 함.
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

- 한글 주석 (WHY: HC envelope 보존하면서 extras만 추가)
- 본문 ≤ 25 lines
- AC-4.2 grep 검증

## Acceptance Criteria

- **AC-T6.1**: 4 통합 테스트 PASS (parser → no flag / fallback → flag / unknown → flag / State C → no merge)
- **AC-T6.2**: index branch는 영향 0 (기존 동작 유지 — name lookup만 cache 사용)
- **AC-T6.3**: HC State C (success:false) raw 응답은 merge 안 함 (error JSON 보존)
- **AC-T6.4**: HC top-level flat shape (`success`, `verified`, `reason`) 보존 + uncertainty key 추가 — boomer P1-5 fix
- **AC-T6.5**: 한글 주석, 신규 TODO 0

## Edge Cases

- raw JSON parse 실패 시 → 원본 그대로 반환 (defensive — 잘못된 JSON 발생 안 함이 정상)
- HC State A 응답에 extras 없을 수 있음 → optional 처리
- target.position이 4-component 가 아닌 경우 (legacy unknown) → transport.goto_position 검증에서 거부 → State C 반환 → merge 안 함 (정상)

## Out of Scope

- index branch refactor — 기존 MIDIKeyCommands 라우팅 유지 (cache에 의존 안 함)
- docs 갱신 = T8

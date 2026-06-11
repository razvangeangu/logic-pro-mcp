import Foundation
import MCP

struct NavigateDispatcher {
    static let tool = Tool(
        name: "logic_navigate",
        description: "Navigation and markers in Logic Pro. Commands: goto_bar, goto_marker, create_marker, delete_marker, rename_marker, zoom_to_fit, set_zoom, toggle_view. BREAKING since v3.3.0: delete_marker / rename_marker require explicit `index` (Int ≥ 0) — pre-v3.3.0 missing `index` defaulted to 0 and silently mutated marker 0; rename_marker now also rejects empty `name`. Params: goto_bar -> { bar: Int }; goto_marker -> { index: Int } or { name: String }; create_marker -> { name: String }; rename_marker -> { index: Int (required, ≥ 0), name: String (required, non-empty) }; delete_marker -> { index: Int (required, ≥ 0) }; set_zoom -> { level: String } (in|out|fit); toggle_view -> { view: String } (mixer|piano_roll|score|step_editor|library|inspector|automation).",
        inputSchema: commandParamsToolSchema(commandDescription: "Navigation command to execute")
    )

    static func handle(
        command: String,
        params: [String: Value],
        router: ChannelRouter,
        cache: StateCache
    ) async -> CallTool.Result {
        switch command {
        case "goto_bar":
            guard params["bar"] != nil else {
                return MIDIDispatcher.invalidParamsResult(
                    hint: "goto_bar requires explicit 'bar'"
                )
            }
            guard let bar = intParamOrNil(params, "bar") else {
                return MIDIDispatcher.invalidParamsResult(
                    hint: "goto_bar 'bar' must be an integer in 1..9999"
                )
            }
            guard (1...9999).contains(bar) else {
                return MIDIDispatcher.invalidParamsResult(
                    hint: "goto_bar 'bar' must be in 1..9999 (got \(bar))"
                )
            }
            let result = await router.route(
                operation: "transport.goto_position",
                params: ["position": "\(bar).1.1.1"]
            )
            return toolTextResult(result)

        case "goto_marker":
            // v3.1.10 (boomer P1-1) — resolve the target marker from cache and
            // navigate via `transport.goto_position` using its `position`
            // string. Pre-v3.1.10 this routed to `nav.goto_marker` →
            // `MIDIKeyCommandsChannel` CC 38 (Logic's "go to next marker"
            // hotkey), which ignores params entirely and just advances the
            // marker pointer by one — making both index- and name-based
            // goto silent no-ops relative to their parameter.
            //
            let markers = await cache.getMarkers()
            func routeMarkerTarget(_ target: MarkerState) async -> CallTool.Result {
                let result = await router.route(
                    operation: "transport.goto_position",
                    params: ["position": target.position]
                )
                // canonical 마커는 응답 그대로. fallback/unknown 만 uncertainty
                // 머신 가독으로 surface (HC State A/B 한정; State C 보존).
                guard !target.positionSource.isCanonical else {
                    return toolTextResult(result)
                }
                let merged = mergeMarkerUncertainty(
                    into: result.message, source: target.positionSource
                )
                return toolTextResult(merged, isError: !result.isSuccess)
            }
            // H-2 (2026-05-08 enterprise review): pre-fix the cache-cold
            // index-based path fell back to `nav.goto_marker` (CC 38), which
            // is Logic's "go to next marker" hotkey — it advances the marker
            // pointer by one regardless of the requested index. A caller
            // saying "goto_marker { index: 5 }" with a cold cache silently
            // got "go to whatever marker comes next." That violates the
            // target-faithful contract every other dispatcher honors.
            //
            // Fix: when the target can't be resolved against the cache,
            // return State C (`element_not_found`) with a hint pointing the
            // caller at the cache freshness state. The caller can then
            // decide whether to refresh the cache and retry, or accept the
            // failure. No silent wrong-target navigation.
            if params["index"] != nil {
                guard let index = intParamOrNil(params, "index"), index >= 0 else {
                    return MIDIDispatcher.invalidParamsResult(
                        hint: "goto_marker 'index' must be an integer >= 0"
                    )
                }
                if let target = markers.first(where: { $0.id == index }) {
                    return await routeMarkerTarget(target)
                }
                let indexStr = String(index)
                return toolTextResult(
                    HonestContract.encodeStateC(
                        error: .elementNotFound,
                        hint: "goto_marker: marker index \(indexStr) not found in cached marker list (count=\(markers.count)). The marker list cache may be cold (poller hasn't refreshed, or the marker list window is closed on Logic 12.2). Try `system.refresh_cache` and retry, or supply `name` instead. Pre-v3.4.0 this fell back to the legacy CC 38 keycmd which silently advanced to the next marker — this fallback is removed because it ignored the requested index.",
                        extras: [
                            "requested_index": indexStr,
                            "cached_marker_count": markers.count,
                        ]
                    ),
                    isError: true
                )
            }
            let name = stringParam(params, "name")
            if name.isEmpty {
                return toolTextResult("goto_marker requires 'index' or 'name' param", isError: true)
            }
            if let target = markers.first(where: { $0.name.localizedCaseInsensitiveContains(name) }) {
                return await routeMarkerTarget(target)
            }
            return toolTextResult(
                HonestContract.encodeStateC(
                    error: .elementNotFound,
                    hint: "goto_marker: no marker matching name '\(name)' in cached list (count=\(markers.count)). Try `system.refresh_cache` and retry.",
                    extras: [
                        "requested_name": name,
                        "cached_marker_count": markers.count,
                    ]
                ),
                isError: true
            )

        case "create_marker":
            let name = stringParam(params, "name", default: "Marker")
            let result = await router.route(
                operation: "nav.create_marker",
                params: ["name": name]
            )
            return toolTextResult(result)

        case "delete_marker":
            // RB-1.b (2026-05-08 enterprise review): pre-fix `intParam(default: 0)`
            // silently deleted marker 0 when `index` was missing/malformed.
            // Marker mutations are not undoable in the same project session,
            // so missing/negative target now fails closed.
            guard let index = intParamOrNil(params, "index"), index >= 0 else {
                return toolTextResult(
                    "delete_marker requires explicit 'index' (Int ≥ 0)",
                    isError: true
                )
            }
            let result = await router.route(
                operation: "nav.delete_marker",
                params: ["index": String(index)]
            )
            return toolTextResult(result)

        case "rename_marker":
            // RB-1.b — same fail-closed treatment for index, plus reject empty
            // `name` (a blank rename overwrote the marker label silently).
            guard let index = intParamOrNil(params, "index"), index >= 0 else {
                return toolTextResult(
                    "rename_marker requires explicit 'index' (Int ≥ 0)",
                    isError: true
                )
            }
            let name = stringParam(params, "name")
            guard !name.isEmpty else {
                return toolTextResult(
                    "rename_marker requires non-empty 'name'",
                    isError: true
                )
            }
            let result = await router.route(
                operation: "nav.rename_marker",
                params: ["index": String(index), "name": name]
            )
            return toolTextResult(result)

        case "zoom_to_fit":
            let result = await router.route(operation: "nav.zoom_to_fit")
            return toolTextResult(result)

        case "set_zoom":
            // Accept both `level` (docs) and `direction` (common caller term) —
            // matrix tests and real callers drift across both. Silently ignoring
            // a misnamed param was the class of bug that hid 100% false-positive
            // test coverage earlier in the hardening loop.
            guard params["level"] != nil || params["direction"] != nil else {
                return MIDIDispatcher.invalidParamsResult(
                    hint: "set_zoom requires explicit 'level' or 'direction'"
                )
            }
            let level = stringParam(params, "level", "direction", default: "fit")
            switch level {
            case "in":
                let result = await router.route(
                    operation: "nav.set_zoom_level",
                    params: ["level": "8"]
                )
                return toolTextResult(result)
            case "out":
                let result = await router.route(
                    operation: "nav.set_zoom_level",
                    params: ["level": "2"]
                )
                return toolTextResult(result)
            case "fit":
                let result = await router.route(operation: "nav.zoom_to_fit")
                return toolTextResult(result)
            default:
                guard let numericLevel = Int(level),
                      (1...10).contains(numericLevel) else {
                    return MIDIDispatcher.invalidParamsResult(
                        hint: "set_zoom 'level' must be one of: in, out, fit, or integer 1..10"
                    )
                }
                let result = await router.route(
                    operation: "nav.set_zoom_level",
                    params: ["level": String(numericLevel)]
                )
                return toolTextResult(result)
            }

        case "toggle_view":
            guard params["view"] != nil else {
                return MIDIDispatcher.invalidParamsResult(
                    hint: "toggle_view requires explicit 'view'"
                )
            }
            let view = stringParam(params, "view", default: "mixer")
            let operation: String
            switch view {
            case "mixer": operation = "view.toggle_mixer"
            case "piano_roll": operation = "view.toggle_piano_roll"
            case "score": operation = "view.toggle_score_editor"
            case "step_editor": operation = "view.toggle_step_editor"
            case "library": operation = "view.toggle_library"
            case "inspector": operation = "view.toggle_inspector"
            case "automation": operation = "automation.toggle_view"
            default:
                return toolTextResult(
                    "Unknown view: \(view). Available: mixer, piano_roll, score, step_editor, library, inspector, automation",
                    isError: true
                )
            }
            let result = await router.route(operation: operation)
            return toolTextResult(result)

        default:
            return toolTextResult(
                "Unknown navigate command: \(command). Available: goto_bar, goto_marker, create_marker, delete_marker, rename_marker, zoom_to_fit, set_zoom, toggle_view",
                isError: true
            )
        }
    }

    /// goto_marker 응답에 marker provenance uncertainty 를 surface — State A/B
    /// envelope 의 top-level 에 `marker_position_uncertain`/`marker_position_source`
    /// 를 merge 한다. State C (success:false) 는 보존 — `HonestContract.addExtras`
    /// 가 정책 책임.
    static func mergeMarkerUncertainty(into rawJSON: String, source: PositionSource) -> String {
        HonestContract.addExtras([
            "marker_position_uncertain": true,
            "marker_position_source": source.rawValue,
        ], into: rawJSON)
    }
}

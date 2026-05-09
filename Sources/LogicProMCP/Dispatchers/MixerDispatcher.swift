import Foundation
import MCP

struct MixerDispatcher {
    static let tool = commandTool(
        name: "logic_mixer",
        description: "Mixer actions in Logic Pro. Commands: set_volume, set_pan, set_master_volume, set_plugin_param. BREAKING since v3.3.0: every mutating command requires explicit `track` (Int ≥ 0) — pre-v3.3.0 missing `track` defaulted to 0 and silently mutated the first track; this now returns an error. Params: set_volume -> { track: Int (required, ≥ 0), value: Float (0.0..1.0) }; set_pan -> { track: Int (required, ≥ 0), value: Float (-1.0..1.0) }; set_master_volume -> { value: Float (0.0..1.0) }; set_plugin_param -> { track: Int (required, ≥ 0), insert: Int (required, currently only 0), param: Int (required, ≥ 0), value: Float (required) } on the selected track via Scripter.",
        commandDescription: "Mixer command to execute"
    )

    static func handle(
        command: String,
        params: [String: Value],
        router: ChannelRouter,
        cache: StateCache
    ) async -> CallTool.Result {
        switch command {
        case "set_volume":
            // RB-1.a (2026-05-08 enterprise review): pre-fix this defaulted
            // missing `track` to 0, so a malformed caller silently mutated
            // the first track's fader. Mixer writes are not undoable from
            // the operator's seat — missing/invalid target now fails closed.
            guard let index = intParamOrNil(params, "track", "index"), index >= 0 else {
                return toolTextResult(
                    "set_volume requires explicit 'track' (Int ≥ 0)",
                    isError: true
                )
            }
            let volume = doubleParam(params, "value", "volume")
            guard (0.0...1.0).contains(volume) else {
                return toolTextResult(
                    "set_volume 'volume' must be in 0.0..1.0 (got \(volume))",
                    isError: true
                )
            }
            return await routedTextResult(router, operation: "mixer.set_volume", params: [
                "index": String(index),
                "volume": String(volume),
            ])

        case "set_pan":
            // RB-1.a — same fail-closed treatment as set_volume.
            guard let index = intParamOrNil(params, "track", "index"), index >= 0 else {
                return toolTextResult(
                    "set_pan requires explicit 'track' (Int ≥ 0)",
                    isError: true
                )
            }
            let pan = doubleParam(params, "value", "pan")
            guard (-1.0...1.0).contains(pan) else {
                return toolTextResult(
                    "set_pan 'value' must be in -1.0..1.0 (got \(pan))",
                    isError: true
                )
            }
            return await routedTextResult(router, operation: "mixer.set_pan", params: [
                "index": String(index),
                "pan": String(pan),
            ])

        case "set_send":
            return toolTextResult(
                "set_send is not exposed in the production MCP contract because targeted send/bus control is not yet deterministic",
                isError: true
            )

        case "set_output":
            return toolTextResult("set_output is not exposed in the production MCP contract", isError: true)

        case "set_input":
            return toolTextResult("set_input is not exposed in the production MCP contract", isError: true)

        case "set_master_volume":
            let volume = doubleParam(params, "value", "volume")
            guard (0.0...1.0).contains(volume) else {
                return toolTextResult(
                    "set_master_volume 'value' must be in 0.0..1.0 (got \(volume))",
                    isError: true
                )
            }
            return await routedTextResult(router, operation: "mixer.set_master_volume", params: [
                "volume": String(volume),
            ])

        case "toggle_eq":
            return toolTextResult("toggle_eq is not exposed in the production MCP contract", isError: true)

        case "reset_strip":
            return toolTextResult("reset_strip is not exposed in the production MCP contract", isError: true)

        case "insert_plugin", "bypass_plugin":
            // Removed from the public surface: every channel that the router
            // once considered for plugin.insert / plugin.bypass (accessibility,
            // MCU) returns an error, so callers always got a failure dressed
            // up as a feature. Use set_plugin_param on a selected track via
            // Scripter for deterministic plugin parameter control instead.
            return toolTextResult(
                "\(command) is not exposed in the production MCP contract; use set_plugin_param via Scripter on the selected track instead",
                isError: true
            )

        case "set_plugin_param":
            // RB-1.a — pre-fix `track`, `insert`, `param` all defaulted to 0
            // via intParam, and `value` defaulted to 0.0 via doubleParam.
            // A malformed caller could write `value=0.0` to insert 0/param 0
            // of track 0 (often the master/first track) without ever knowing.
            // All four are now explicit-required.
            guard let track = intParamOrNil(params, "track"), track >= 0 else {
                return toolTextResult(
                    "set_plugin_param requires explicit 'track' (Int ≥ 0)",
                    isError: true
                )
            }
            guard let insert = intParamOrNil(params, "insert"), insert >= 0 else {
                return toolTextResult(
                    "set_plugin_param requires explicit 'insert' (Int ≥ 0; currently only 0 supported)",
                    isError: true
                )
            }
            guard insert == 0 else {
                return toolTextResult(
                    "set_plugin_param currently supports only insert: 0 on the selected track via Scripter",
                    isError: true
                )
            }
            guard let paramIndex = intParamOrNil(params, "param"), paramIndex >= 0 else {
                return toolTextResult(
                    "set_plugin_param requires explicit 'param' (Int ≥ 0)",
                    isError: true
                )
            }
            guard params["value"] != nil else {
                return toolTextResult(
                    "set_plugin_param requires explicit 'value'",
                    isError: true
                )
            }
            let value = doubleParam(params, "value")
            let selectResult = await router.route(
                operation: "track.select",
                params: ["index": String(track)]
            )
            guard selectResult.isSuccess else {
                return toolTextResult(selectResult.message, isError: true)
            }
            return await routedTextResult(router, operation: "plugin.set_param", params: [
                "track": String(track),
                "insert": String(insert),
                "param": String(paramIndex),
                "value": String(value),
            ])

        default:
            return toolTextResult(
                "Unknown mixer command: \(command). Available: set_volume, set_pan, set_master_volume, set_plugin_param",
                isError: true
            )
        }
    }
}

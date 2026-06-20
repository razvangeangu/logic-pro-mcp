import Foundation
import MCP

struct TransportDispatcher {
    static let tool = Tool(
        name: "logic_transport",
        description: "Control Logic Pro transport. Commands: play, stop, record, pause, rewind, fast_forward, toggle_cycle, toggle_metronome, set_tempo, goto_position, set_cycle_range, toggle_count_in. Params: set_tempo -> { tempo: Float } (5.0-999.0); goto_position -> { bar: Int (1..9999) } or { position: String } where String is bar.beat.sub.tick (e.g. \"9.1.1.1\") or HH:MM:SS:FF SMPTE (e.g. \"00:00:08:12\"); set_cycle_range -> { start: Int, end: Int }; others -> {}.",
        inputSchema: commandParamsToolSchema(commandDescription: "Transport command to execute")
    )

    static func handle(
        command: String,
        params: [String: Value],
        router: ChannelRouter,
        cache: StateCache
    ) async -> CallTool.Result {
        switch command {
        case "play":
            let result = await router.route(operation: "transport.play")
            return toolTextResult(result)

        case "stop":
            return await verifiedStopResult(router: router, cache: cache)

        case "record":
            let result = await router.route(operation: "transport.record")
            return toolTextResult(result)

        case "pause":
            let result = await router.route(operation: "transport.pause")
            return toolTextResult(result)

        case "rewind":
            let result = await router.route(operation: "transport.rewind")
            return toolTextResult(result)

        case "fast_forward":
            let result = await router.route(operation: "transport.fast_forward")
            return toolTextResult(result)

        case "toggle_cycle":
            let result = await router.route(operation: "transport.toggle_cycle")
            return toolTextResult(result)

        case "toggle_metronome":
            let beforeTransport = await liveTransportState(router: router, cache: cache)
            let result = await router.route(operation: "transport.toggle_metronome")
            return await finalizeToggleMetronomeResult(
                result,
                beforeTransport: beforeTransport,
                router: router,
                cache: cache
            )

        case "toggle_count_in":
            let result = await router.route(operation: "transport.toggle_count_in")
            return toolTextResult(result)

        case "set_tempo":
            guard params["tempo"] != nil || params["bpm"] != nil else {
                return MIDIDispatcher.invalidParamsResult(
                    hint: "set_tempo requires explicit 'tempo' or 'bpm'"
                )
            }
            guard let tempo = doubleParamOrNil(params, "tempo", "bpm") else {
                return MIDIDispatcher.invalidParamsResult(
                    hint: "set_tempo requires numeric 'tempo' or 'bpm'"
                )
            }
            // Logic Pro's tempo range is 5..990 BPM; the schema documents 20..999.
            // Accept a slightly-wider 5..999 to match Logic's actual behavior,
            // reject anything clearly absurd so a typo doesn't silently pass.
            guard (5.0...999.0).contains(tempo) else {
                    return MIDIDispatcher.invalidParamsResult(
                        hint: "set_tempo 'tempo' must be in 5..999 (got \(tempo))"
                    )
            }
            let result = await router.route(
                operation: "transport.set_tempo",
                params: ["bpm": String(tempo)]
            )
            return toolTextResult(result)

        case "goto_position":
            // Reject unknown keys before falling back to defaults. Prior to
            // v3.0.0 a legacy `time` alias was silently accepted; callers that
            // never updated their schema would silently seek to bar 1. Now the
            // tool fails closed and surfaces exactly which key was wrong.
            let allowedKeys: Set<String> = ["bar", "position"]
            let unknownKeys = params.keys.filter { !allowedKeys.contains($0) }
            if !unknownKeys.isEmpty {
                let sorted = unknownKeys.sorted().joined(separator: ", ")
                return toolTextResult(
                    "goto_position got unknown param(s): \(sorted). Allowed: bar, position. The legacy 'time' alias was removed in v3.0.0.",
                    isError: true
                )
            }
            guard params["bar"] != nil || params["position"] != nil else {
                return MIDIDispatcher.invalidParamsResult(
                    hint: "goto_position requires explicit 'bar' or 'position'"
                )
            }
            // intParam coerces int/double/string so `{"bar":"5"}` works too.
            if params["bar"] != nil {
                guard let bar = intParamOrNil(params, "bar") else {
                    return MIDIDispatcher.invalidParamsResult(
                        hint: "goto_position 'bar' must be an integer in 1..9999"
                    )
                }
                guard (1...9999).contains(bar) else {
                    return MIDIDispatcher.invalidParamsResult(
                        hint: "goto_position 'bar' must be in 1..9999 (got \(bar))"
                    )
                }
                let result = await router.route(
                    operation: "transport.goto_position",
                    params: ["position": "\(bar).1.1.1"]
                )
                return await finalizeGotoPositionResult(
                    result,
                    requestedPosition: "\(bar).1.1.1",
                    router: router,
                    cache: cache
                )
            }
            let time = stringParam(params, "position", default: "1.1.1.1")
            // Validate position format before routing. Accept:
            //   Bar/beat: "N.N.N.N" with bar 1..9999, beat 1..16, sub 1..16, tick 1..999
            //   SMPTE:    "HH:MM:SS:FF" with HH 0..23, MM/SS 0..59, FF 0..99
            guard TransportDispatcher.isValidPositionString(time) else {
                return MIDIDispatcher.invalidParamsResult(
                    hint: "goto_position 'position' must be bar.beat.sub.tick (e.g. 1.1.1.1) or HH:MM:SS:FF (got '\(time)')"
                )
            }
            let result = await router.route(
                operation: "transport.goto_position",
                params: ["position": time]
            )
            return await finalizeGotoPositionResult(
                result,
                requestedPosition: time,
                router: router,
                cache: cache
            )

        case "set_cycle_range":
            guard params["start"] != nil, params["end"] != nil else {
                return MIDIDispatcher.invalidParamsResult(
                    hint: "set_cycle_range requires explicit 'start' and 'end'"
                )
            }
            guard let start = intParamOrNil(params, "start"),
                  let end = intParamOrNil(params, "end") else {
                return MIDIDispatcher.invalidParamsResult(
                    hint: "set_cycle_range requires integer 'start' and 'end'"
                )
            }
            // Bounds: same window as goto_position.bar (1..9999).
            // Enforce start <= end so a swapped-argument typo surfaces early.
            guard (1...9999).contains(start), (1...9999).contains(end) else {
                return MIDIDispatcher.invalidParamsResult(
                    hint: "set_cycle_range 'start' and 'end' must be in 1..9999 (got \(start)..\(end))"
                )
            }
            guard start <= end else {
                return MIDIDispatcher.invalidParamsResult(
                    hint: "set_cycle_range 'start' (\(start)) must be <= 'end' (\(end))"
                )
            }
            let result = await router.route(
                operation: "transport.set_cycle_range",
                params: ["start": "\(start).1.1.1", "end": "\(end).1.1.1"]
            )
            return toolTextResult(result)

        default:
            return toolTextResult(
                "Unknown transport command: \(command). Available: play, stop, record, pause, rewind, fast_forward, toggle_cycle, toggle_metronome, set_tempo, goto_position, set_cycle_range, toggle_count_in",
                isError: true
            )
        }
    }

    private static func verifiedStopResult(
        router: ChannelRouter,
        cache: StateCache
    ) async -> CallTool.Result {
        let writeResult = await router.route(operation: "transport.stop")
        guard writeResult.isSuccess else {
            return toolTextResult(writeResult)
        }

        let liveRefresh = await ResourceHandlers.readLiveTransportState(router: router)
        guard let liveState = liveRefresh.state else {
            let cachedState = await cache.getTransport()
            return toolTextResult(HonestContract.encodeStateC(
                error: .readbackUnavailable,
                hint: "transport.stop executed, but live transport state could not be refreshed. Focus Logic's Tracks window, dismiss modal or plugin dialogs, then retry or run logic_system refresh_cache.",
                extras: stopReadbackUnavailableExtras(
                    cachedState: cachedState,
                    refreshError: liveRefresh.errorCode
                )
            ), isError: true)
        }

        await cache.updateTransport(liveState)
        let observedExtras: [String: Any] = [
            "operation": "transport.stop",
            "requested_state": "stopped",
            "verify_source": "ax_transport_state",
            "observed_isPlaying": liveState.isPlaying,
            "observed_isRecording": liveState.isRecording,
            "observed_position": liveState.position,
            "observed_time_position": liveState.timePosition,
        ]

        guard liveState.isPlaying == false, liveState.isRecording == false else {
            return toolTextResult(HonestContract.encodeStateC(
                error: .readbackMismatch,
                hint: "transport.stop executed, but live transport state still reports playback or recording",
                extras: observedExtras.merging(["safe_to_retry": true]) { _, new in new }
            ), isError: true)
        }

        return toolTextResult(HonestContract.encodeStateA(extras: observedExtras))
    }

    private static func stopReadbackUnavailableExtras(
        cachedState: TransportState,
        refreshError: String?
    ) -> [String: Any] {
        [
            "operation": "transport.stop",
            "requested_state": "stopped",
            "verify_source": "cache_only",
            "cached_source": cachedState.lastUpdated > .distantPast ? "cache" : "default",
            "cache_age_sec": cacheAgeExtra(for: cachedState),
            "refresh_error": refreshError ?? "live_transport_read_failed",
            "safe_to_retry": true,
        ]
    }

    private static func cacheAgeExtra(for state: TransportState) -> Any {
        guard state.lastUpdated > .distantPast else {
            return NSNull()
        }
        return max(0, Date().timeIntervalSince(state.lastUpdated))
    }

    /// Accept "bar.beat.sub.tick" (each positive) or "HH:MM:SS:FF" (with
    /// each field within its canonical range). Anything else — including
    /// empty string and malformed tokens like "99:99:99:99" — is rejected.
    static func isValidPositionString(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return false }

        // Bar/beat format.
        let dots = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        if dots.count == 4 {
            guard let bar = Int(dots[0]), (1...9999).contains(bar),
                  let beat = Int(dots[1]), (1...16).contains(beat),
                  let sub = Int(dots[2]), (1...16).contains(sub),
                  let tick = Int(dots[3]), (1...999).contains(tick) else {
                return false
            }
            return true
        }

        // SMPTE format.
        let colons = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        if colons.count == 4 {
            guard let h = Int(colons[0]), (0...23).contains(h),
                  let m = Int(colons[1]), (0...59).contains(m),
                  let sec = Int(colons[2]), (0...59).contains(sec),
                  let f = Int(colons[3]), (0...99).contains(f) else {
                return false
            }
            return true
        }

        return false
    }

    static func finalizeGotoPositionResult(
        _ result: ChannelResult,
        requestedPosition: String,
        router: ChannelRouter,
        cache: StateCache
    ) async -> CallTool.Result {
        guard result.isSuccess else {
            return toolTextResult(result)
        }
        guard channelResultIsUnverified(result) else {
            return toolTextResult(result)
        }
        guard let observedTransport = await liveTransportState(router: router, cache: cache) else {
            return toolTextResult(
                HonestContract.addExtras(
                    ["verification_source": "transport_state"],
                    into: result.message
                ),
                isError: true
            )
        }

        var extras = honestContractExtras(from: result.message)
        extras["verification_source"] = "transport_state"
        extras["requested"] = requestedPosition
        extras["observed"] = observedTransport.position
        extras["observed_time_position"] = observedTransport.timePosition

        if !requestedPosition.contains(":"), observedTransport.position == requestedPosition {
            return toolTextResult(HonestContract.encodeStateA(extras: extras))
        }

        let reason: HonestContract.UncertainReason =
            requestedPosition.contains(":") ? .readbackUnavailable : .readbackMismatch
        return toolTextResult(
            HonestContract.encodeStateB(reason: reason, extras: extras),
            isError: true
        )
    }

    private static func finalizeToggleMetronomeResult(
        _ result: ChannelResult,
        beforeTransport: TransportState?,
        router: ChannelRouter,
        cache: StateCache
    ) async -> CallTool.Result {
        guard result.isSuccess else {
            return toolTextResult(result)
        }
        guard channelResultIsUnverified(result) else {
            return toolTextResult(result)
        }
        guard let beforeTransport,
              let afterTransport = await liveTransportState(router: router, cache: cache) else {
            return toolTextResult(
                HonestContract.addExtras(
                    ["verification_source": "transport_state"],
                    into: result.message
                ),
                isError: true
            )
        }

        var extras = honestContractExtras(from: result.message)
        extras["verification_source"] = "transport_state"
        extras["previous_enabled"] = beforeTransport.isMetronomeEnabled
        extras["requested_enabled"] = !beforeTransport.isMetronomeEnabled
        extras["observed_enabled"] = afterTransport.isMetronomeEnabled

        if beforeTransport.isMetronomeEnabled != afterTransport.isMetronomeEnabled {
            return toolTextResult(HonestContract.encodeStateA(extras: extras))
        }

        return toolTextResult(
            HonestContract.encodeStateB(reason: .readbackMismatch, extras: extras),
            isError: true
        )
    }

    private static func liveTransportState(
        router: ChannelRouter,
        cache: StateCache
    ) async -> TransportState? {
        let readback = await router.route(operation: "transport.get_state")
        guard readback.isSuccess,
              let transport = decodeJSONValue(TransportState.self, from: readback.message) else {
            return nil
        }
        await cache.updateTransport(transport)
        return transport
    }
}

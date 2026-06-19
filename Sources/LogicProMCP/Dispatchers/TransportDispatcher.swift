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
        cache: StateCache,
        sleep: @escaping (UInt64) async -> Void = { try? await Task.sleep(nanoseconds: $0) }
    ) async -> CallTool.Result {
        switch command {
        case "play":
            return await handleVerifiedTransportCommand(
                action: .play,
                router: router,
                sleep: sleep
            )

        case "stop":
            return await handleVerifiedTransportCommand(
                action: .stop,
                router: router,
                sleep: sleep
            )

        case "record":
            return await handleVerifiedTransportCommand(
                action: .record,
                router: router,
                sleep: sleep
            )

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
            let result = await router.route(operation: "transport.toggle_metronome")
            return toolTextResult(result)

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
                return toolTextResult(result)
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
            return toolTextResult(result)

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

    private enum VerifiedTransportAction: String {
        case play
        case stop
        case record

        var operation: String { "transport.\(rawValue)" }

        func matches(_ state: TransportState) -> Bool {
            switch self {
            case .play:
                return state.isPlaying
            case .stop:
                return !state.isPlaying && !state.isRecording
            case .record:
                return state.isPlaying && state.isRecording
            }
        }
    }

    private static func handleVerifiedTransportCommand(
        action: VerifiedTransportAction,
        router: ChannelRouter,
        sleep: @escaping (UInt64) async -> Void
    ) async -> CallTool.Result {
        let beforeState = await readTransportState(router: router)
        if let beforeState, action.matches(beforeState) {
            return toolTextResult(.success(HonestContract.encodeStateA(
                extras: [
                    "operation": action.operation,
                    "verify_source": "transport_state",
                    "write_attempted": false,
                    "unchanged": true,
                    "observed_before": transportStateSummary(beforeState),
                    "observed_after": transportStateSummary(beforeState)
                ]
            )))
        }

        let writeResult = await router.route(operation: action.operation)
        let writePayload = jsonValue(from: writeResult.message)
        var attempts = 0
        var afterState: TransportState?
        for _ in 0..<12 {
            attempts += 1
            if let observed = await readTransportState(router: router) {
                afterState = observed
                if action.matches(observed) {
                    var extras: [String: Any] = [
                        "operation": action.operation,
                        "verify_source": "transport_state",
                        "write_attempted": true,
                        "poll_attempts": attempts,
                        "observed_after": transportStateSummary(observed),
                        "write_result": writePayload
                    ]
                    if let beforeState {
                        extras["observed_before"] = transportStateSummary(beforeState)
                    }
                    if !writeResult.isSuccess {
                        extras["write_result_error"] = writeResult.message
                    }
                    return toolTextResult(.success(HonestContract.encodeStateA(extras: extras)))
                }
            }
            await sleep(100_000_000)
        }

        guard writeResult.isSuccess else {
            return toolTextResult(writeResult)
        }

        var extras: [String: Any] = [
            "operation": action.operation,
            "verify_source": "transport_state",
            "write_attempted": true,
            "poll_attempts": attempts,
            "write_result": writePayload
        ]
        if let beforeState {
            extras["observed_before"] = transportStateSummary(beforeState)
        }
        if let afterState {
            extras["observed_after"] = transportStateSummary(afterState)
            return toolTextResult(.success(HonestContract.encodeStateB(
                reason: .readbackMismatch,
                extras: extras
            )))
        }
        return toolTextResult(.success(HonestContract.encodeStateB(
            reason: .readbackUnavailable,
            extras: extras
        )))
    }

    private static func readTransportState(router: ChannelRouter) async -> TransportState? {
        let result = await router.route(operation: "transport.get_state")
        guard result.isSuccess,
              let dict = jsonValue(from: result.message) as? [String: Any] else {
            return nil
        }
        var state = TransportState()
        if let isPlaying = dict["isPlaying"] as? Bool { state.isPlaying = isPlaying }
        if let isRecording = dict["isRecording"] as? Bool { state.isRecording = isRecording }
        if let isPaused = dict["isPaused"] as? Bool { state.isPaused = isPaused }
        if let isCycleEnabled = dict["isCycleEnabled"] as? Bool { state.isCycleEnabled = isCycleEnabled }
        if let isMetronomeEnabled = dict["isMetronomeEnabled"] as? Bool { state.isMetronomeEnabled = isMetronomeEnabled }
        if let tempo = dict["tempo"] as? Double { state.tempo = tempo }
        if let position = dict["position"] as? String { state.position = position }
        if let timePosition = dict["timePosition"] as? String { state.timePosition = timePosition }
        if let sampleRate = dict["sampleRate"] as? Int { state.sampleRate = sampleRate }
        return state
    }

    private static func transportStateSummary(_ state: TransportState) -> [String: Any] {
        [
            "isPlaying": state.isPlaying,
            "isRecording": state.isRecording,
            "position": state.position,
            "tempo": state.tempo
        ]
    }

    private static func jsonValue(from text: String) -> Any {
        guard let data = text.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data) else {
            return text
        }
        return value
    }
}

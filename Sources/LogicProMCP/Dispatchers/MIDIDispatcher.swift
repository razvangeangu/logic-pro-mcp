import Foundation
import MCP

struct MIDIDispatcher {
    static let tool = commandTool(
        name: "logic_midi",
        description: "MIDI operations in Logic Pro. Commands: send_note, send_chord, send_cc, send_program_change, send_pitch_bend, send_aftertouch, send_sysex, play_sequence, create_virtual_port, step_input, mmc_play, mmc_stop, mmc_record, mmc_locate. Params: send_note/send_chord -> MIDI note payloads; send_cc/program_change/pitch_bend/aftertouch -> controller payloads; send_sysex -> { bytes: [Int] } or { data: String }; play_sequence -> { notes: \"pitch,offsetMs,durMs[,vel[,ch]];...\" } (≤256 events, tight server-side timing); mmc_locate -> { bar: Int } or { time: \"HH:MM:SS:FF\" }; create_virtual_port -> { name: String }. The 7 send-style ops (send_note, send_chord, send_cc, send_program_change, send_pitch_bend, send_aftertouch, play_sequence) accept an optional { port: \"midi\"|\"keycmd\" } selector — default \"midi\" routes to the CoreMIDI virtual port; \"keycmd\" routes to the MIDIKeyCommands KeyCmd virtual port (requires one-time MIDI Learn in Logic). Channel is 1-based (1..16). All other ops reject `port` with invalid_params.",
        commandDescription: "MIDI command to execute"
    )

    static func handle(
        command: String,
        params: [String: Value],
        router: ChannelRouter,
        cache: StateCache
    ) async -> CallTool.Result {
        switch command {
        case "send_note":
            guard params["note"] != nil else {
                return invalidParamsResult(hint: "send_note requires explicit 'note'")
            }
            return await dispatchSendOp(
                baseOp: "midi.send_note",
                params: params,
                additionalParams: [
                    "note": String(intParam(params, "note", default: 60)),
                    "velocity": String(intParam(params, "velocity", default: 100)),
                    "duration_ms": String(intParam(params, "duration_ms", default: 500)),
                ],
                router: router
            )

        case "send_chord":
            guard params["notes"] != nil else {
                return invalidParamsResult(hint: "send_chord requires explicit 'notes'")
            }
            return await dispatchSendOp(
                baseOp: "midi.send_chord",
                params: params,
                additionalParams: [
                    "notes": csvIntListOrStringParam(params, key: "notes"),
                    "velocity": String(intParam(params, "velocity", default: 100)),
                    "duration_ms": String(intParam(params, "duration_ms", default: 500)),
                ],
                router: router
            )

        case "play_sequence":
            // Tight-rhythm sequencer. `notes` is a raw string of
            // "pitch,offsetMs,durMs[,vel[,ch]]" events separated by ';'.
            // Per-event channel lives inside the notes string and is parsed
            // by `NoteSequenceParser` (T3) — there is no top-level channel,
            // so we skip `validateMidiChannel` and only validate `port`.
            switch validatePort(params) {
            case .failure(let msg):
                return invalidParamsResult(hint: msg.message)
            case .success(let port):
                let opKey = port == "midi" ? "midi.play_sequence" : "midi.play_sequence.\(port)"
                return await routedTextResult(router, operation: opKey, params: [
                    "notes": stringParam(params, "notes"),
                ])
            }

        case "send_cc":
            guard params["controller"] != nil, params["value"] != nil else {
                return invalidParamsResult(hint: "send_cc requires explicit 'controller' and 'value'")
            }
            return await dispatchSendOp(
                baseOp: "midi.send_cc",
                params: params,
                additionalParams: [
                    "controller": String(intParam(params, "controller")),
                    "value": String(intParam(params, "value")),
                ],
                router: router
            )

        case "send_program_change":
            guard params["program"] != nil else {
                return invalidParamsResult(hint: "send_program_change requires explicit 'program'")
            }
            return await dispatchSendOp(
                baseOp: "midi.send_program_change",
                params: params,
                additionalParams: [
                    "program": String(intParam(params, "program")),
                ],
                router: router
            )

        case "send_pitch_bend":
            guard params["value"] != nil else {
                return invalidParamsResult(hint: "send_pitch_bend requires explicit 'value'")
            }
            return await dispatchSendOp(
                baseOp: "midi.send_pitch_bend",
                params: params,
                additionalParams: [
                    "value": String(intParam(params, "value")),
                ],
                router: router
            )

        case "send_aftertouch":
            guard params["value"] != nil else {
                return invalidParamsResult(hint: "send_aftertouch requires explicit 'value'")
            }
            return await dispatchSendOp(
                baseOp: "midi.send_aftertouch",
                params: params,
                additionalParams: [
                    "value": String(intParam(params, "value")),
                ],
                router: router
            )

        case "send_sysex":
            // Accept three input shapes so callers can use whichever is ergonomic:
            //   bytes: [0xF0, 0x7E, ..., 0xF7]           (array of ints)
            //   bytes: "F0 7E 7F 06 01 F7"               (hex string, space-sep)
            //   data:  "F0 7E 7F 06 01 F7"               (hex string alias)
            if let reject = rejectIfPortPresent(params, command: command) {
                return reject
            }
            let data: String
            if let arr = params["bytes"]?.arrayValue {
                data = arr.compactMap(\.intValue).map { String(format: "%02X", $0) }.joined(separator: " ")
            } else if let s = params["bytes"]?.stringValue, !s.isEmpty {
                data = s
            } else {
                data = stringParam(params, "data")
            }
            return await routedTextResult(router, operation: "midi.send_sysex", params: ["data": data])

        case "create_virtual_port":
            if let reject = rejectIfPortPresent(params, command: command) {
                return reject
            }
            return await routedTextResult(router, operation: "midi.create_virtual_port", params: [
                "name": stringParam(params, "name", default: "Virtual Port"),
            ])

        case "mmc_play":
            if let reject = rejectIfPortPresent(params, command: command) {
                return reject
            }
            return await routedTextResult(router, operation: "mmc.play")

        case "mmc_stop":
            if let reject = rejectIfPortPresent(params, command: command) {
                return reject
            }
            return await routedTextResult(router, operation: "mmc.stop")

        case "mmc_record":
            if let reject = rejectIfPortPresent(params, command: command) {
                return reject
            }
            return await routedTextResult(router, operation: "mmc.record_strobe")

        case "mmc_locate":
            if let reject = rejectIfPortPresent(params, command: command) {
                return reject
            }
            guard params["bar"] != nil || params["time"] != nil else {
                return invalidParamsResult(hint: "mmc_locate requires explicit 'bar' or 'time'")
            }
            // Prefer `bar` (int) → expand to bar.beat.sub.tick, else SMPTE `time`.
            // intParam handles int/double/string coercion, so a stringified bar
            // ("5") is accepted too.
            if params["bar"] != nil {
                let bar = intParam(params, "bar", default: 1)
                guard (1...9999).contains(bar) else {
                    return toolTextResult("mmc_locate 'bar' must be in 1..9999 (got \(bar))", isError: true)
                }
                return await routedTextResult(router, operation: "transport.goto_position", params: [
                    "position": "\(bar).1.1.1",
                ])
            }
            return await routedTextResult(router, operation: "mmc.locate", params: [
                "time": stringParam(params, "time", default: "00:00:00:00"),
            ])

        case "step_input":
            if let reject = rejectIfPortPresent(params, command: command) {
                return reject
            }
            guard params["note"] != nil, params["duration"] != nil else {
                return invalidParamsResult(hint: "step_input requires explicit 'note' and 'duration'")
            }
            return await routedTextResult(router, operation: "midi.step_input", params: [
                "note": String(intParam(params, "note", default: 60)),
                "duration": stringParam(params, "duration", default: "1/4"),
            ])

        default:
            return toolTextResult(
                "Unknown MIDI command: \(command). Available: send_note, send_chord, send_cc, send_program_change, send_pitch_bend, send_aftertouch, send_sysex, create_virtual_port, step_input, mmc_play, mmc_stop, mmc_record, mmc_locate",
                isError: true
            )
        }
    }

    // MARK: - Send-op dispatch helper (T5)

    /// Common pre-flight + routing path for the 7 `midi.send_*` / `play_sequence`
    /// commands. Validates `port` (default `"midi"`, optional `"keycmd"`) and the
    /// 1-based `channel` (1..16, encoded to wire byte `channel-1`), then forwards
    /// to the operation key `midi.<op>` or `midi.<op>.<port>` so the
    /// ChannelRouter can pick the right transport. `play_sequence` does NOT use
    /// this helper because its per-event channels live inside the notes string;
    /// it inlines just the `validatePort` half above.
    private static func dispatchSendOp(
        baseOp: String,
        params: [String: Value],
        additionalParams: [String: String],
        router: ChannelRouter
    ) async -> CallTool.Result {
        switch validatePort(params) {
        case .failure(let msg):
            return invalidParamsResult(hint: msg.message)
        case .success(let port):
            switch validateMidiChannel(params) {
            case .failure(let msg):
                return invalidParamsResult(hint: msg.message)
            case .success(let wireChannel):
                let opKey = port == "midi" ? baseOp : "\(baseOp).\(port)"
                var allParams = additionalParams
                allParams["channel"] = String(wireChannel)
                return await routedTextResult(router, operation: opKey, params: allParams)
            }
        }
    }

    /// Returns an `invalid_params` result if `params["port"]` is set on a
    /// command that does not support port routing. Used by `mmc_*`,
    /// `send_sysex`, `step_input`, and `create_virtual_port` — these ops live
    /// only on CoreMIDI / MCU / AX, so silently dropping a `port` argument
    /// would mask a setup mistake by the caller.
    private static func rejectIfPortPresent(
        _ params: [String: Value],
        command: String
    ) -> CallTool.Result? {
        guard params["port"] != nil else { return nil }
        return invalidParamsResult(
            hint: "port parameter not supported for \(command)"
        )
    }

    /// Wraps a hint string in a State C `invalid_params` envelope. Centralized
    /// so all dispatch-level rejections (port + channel + record_sequence)
    /// produce the same wire shape.
    static func invalidParamsResult(hint: String) -> CallTool.Result {
        toolTextResult(
            HonestContract.encodeStateC(error: .invalidParams, hint: hint, extras: [:]),
            isError: true
        )
    }

    // MARK: - Validation Helpers (T2)
    // Internal visibility (not private) so `@testable import LogicProMCP` tests
    // can exercise them directly. Production callers stay within this file.

    /// Wraps a validation error message as a Swift `Error`.
    /// Enables `Result<T, ValidationFailure>` while preserving `.failure("literal")`
    /// ergonomics via `ExpressibleByStringLiteral`. Tests read `.message` for
    /// substring assertions; `description` mirrors `message` for logging.
    struct ValidationFailure: Error, Equatable, CustomStringConvertible, ExpressibleByStringLiteral {
        let message: String
        init(_ message: String) { self.message = message }
        init(stringLiteral value: String) { self.message = value }
        var description: String { message }
    }

    /// Validates the `port` parameter for MIDI routing.
    /// - Returns: `.success("midi")` if missing (default for backward compat),
    ///   `.success("midi"|"keycmd")` if explicitly set to a supported value,
    ///   `.failure(...)` for any other string (including `""`, `"scripter"`).
    private static let validPorts: Set<String> = ["midi", "keycmd"]

    internal static func validatePort(_ params: [String: Value]) -> Result<String, ValidationFailure> {
        // Empty string `""` is explicitly rejected (does not fall through to default).
        guard let raw = params["port"]?.stringValue else {
            return .success("midi") // missing = default
        }
        guard Self.validPorts.contains(raw) else {
            return .failure("port must be one of: midi, keycmd")
        }
        return .success(raw)
    }

    /// Validates 1-based MIDI channel input and converts to wire byte (0..15).
    /// - Accepts: `.int(1...16)`, `.double(whole 1.0...16.0)`, `.string` containing strict integer.
    /// - Rejects: `.bool`, fractional/NaN/Infinity doubles, fractional strings,
    ///   out-of-range, and non-numeric kinds (`.array`, `.object`, `.data`, `.null`).
    /// - Missing key returns `.success(0)` (default Ch 1).
    internal static func validateMidiChannel(_ params: [String: Value]) -> Result<UInt8, ValidationFailure> {
        guard let raw = params["channel"] else {
            return .success(0) // default Ch 1 (wire 0)
        }
        let intCandidate: Int? = {
            switch raw {
            case .int(let n): return n
            case .double(let f): return Int(exactly: f)
            case .string(let s):
                // Strict integer parsing — rejects "1.5", "abc", "" etc.
                return Int(s)
            default:
                // .bool, .array, .object, .data, .null → reject
                return nil
            }
        }()
        guard let v = intCandidate else {
            return .failure("channel must be integer 1..16 (1-based)")
        }
        guard (1...16).contains(v) else {
            return .failure("channel must be integer 1..16 (1-based)")
        }
        return .success(UInt8(v - 1))
    }
}

import Testing
import Foundation
import MCP
@testable import LogicProMCP

// T5 — MIDIDispatcher 7-op port consistency + routingTable invariant
// PRD: issue1-keycmd-port-routing AC-1 (7 ops × 2 ports = 14 cases)
//
// Verifies that every "send" operation on MIDIDispatcher honors the same
// `port` switch and the same 1-based channel encoding. Also locks the
// ChannelRouter routingTable to exactly the 14 expected entries (7 base
// ops on coreMIDI + 7 keycmd-suffixed ops on midiKeyCommands).

@Suite("MIDIDispatcher entry-point consistency")
struct MIDIDispatcherEntryPointConsistencyTests {

    /// Minimal positional-arg payload for each send op so the dispatcher's
    /// own input validation passes and we can observe routing only.
    private static func baseParams(for command: String) -> [String: Value] {
        switch command {
        case "send_cc":
            return ["controller": .int(74), "value": .int(127)]
        case "send_note":
            return ["note": .int(60), "velocity": .int(100), "duration_ms": .int(500)]
        case "send_chord":
            return ["notes": .array([.int(60), .int(64), .int(67)]), "velocity": .int(100), "duration_ms": .int(500)]
        case "send_program_change":
            return ["program": .int(8)]
        case "send_pitch_bend":
            return ["value": .int(0)]
        case "send_aftertouch":
            return ["value": .int(64)]
        case "play_sequence":
            return ["notes": .string("60,0,480")]
        default:
            return [:]
        }
    }

    /// Maps each MIDIDispatcher command to the operation key it must produce
    /// for the default ("midi") port.
    private static let defaultOpKey: [String: String] = [
        "send_cc": "midi.send_cc",
        "send_note": "midi.send_note",
        "send_chord": "midi.send_chord",
        "send_program_change": "midi.send_program_change",
        "send_pitch_bend": "midi.send_pitch_bend",
        "send_aftertouch": "midi.send_aftertouch",
        "play_sequence": "midi.play_sequence",
    ]

    private static let allSendCommands: [String] = Array(defaultOpKey.keys)

    // MARK: - 8. All 7 ops × 2 ports = 14 routing cases

    @Test("all 7 send ops accept port param — 14 (op × port) cases route correctly")
    func testAllSendOpsAcceptPortParam() async {
        for command in Self.allSendCommands {
            // Default port (omitted) → coreMIDI / base op
            do {
                let router = ChannelRouter()
                let coreMidi = MockChannel(id: .coreMIDI)
                let keycmd = MockChannel(id: .midiKeyCommands)
                await router.register(coreMidi)
                await router.register(keycmd)

                let result = await MIDIDispatcher.handle(
                    command: command,
                    params: Self.baseParams(for: command),
                    router: router,
                    cache: StateCache()
                )

                #expect(!result.isError!, "\(command) (default port) failed unexpectedly: \(sharedToolText(result))")
                let coreOps = await coreMidi.executedOps
                let keycmdOps = await keycmd.executedOps
                #expect(coreOps.count == 1, "\(command) default → expected 1 coreMIDI op, got \(coreOps.count)")
                #expect(coreOps.first?.0 == Self.defaultOpKey[command],
                        "\(command) default → wrong op key: \(coreOps.first?.0 ?? "nil")")
                #expect(keycmdOps.isEmpty, "\(command) default must not touch keycmd")
            }

            // keycmd port → midiKeyCommands / base op + ".keycmd"
            do {
                let router = ChannelRouter()
                let coreMidi = MockChannel(id: .coreMIDI)
                let keycmd = MockChannel(
                    id: .midiKeyCommands,
                    healthOverride: .healthy(detail: "Mock keycmd OK", verificationStatus: .runtimeReady)
                )
                await router.register(coreMidi)
                await router.register(keycmd)

                var params = Self.baseParams(for: command)
                params["port"] = .string("keycmd")

                let result = await MIDIDispatcher.handle(
                    command: command,
                    params: params,
                    router: router,
                    cache: StateCache()
                )

                #expect(!result.isError!, "\(command) (keycmd port) failed unexpectedly: \(sharedToolText(result))")
                let coreOps = await coreMidi.executedOps
                let keycmdOps = await keycmd.executedOps
                #expect(coreOps.isEmpty, "\(command) keycmd must not touch coreMIDI")
                #expect(keycmdOps.count == 1, "\(command) keycmd → expected 1 keycmd op, got \(keycmdOps.count)")
                let expectedOp = Self.defaultOpKey[command]! + ".keycmd"
                #expect(keycmdOps.first?.0 == expectedOp,
                        "\(command) keycmd → wrong op key: got \(keycmdOps.first?.0 ?? "nil"), expected \(expectedOp)")
            }
        }
    }

    // MARK: - 9. Channel validation is consistent across the 6 channel-bearing ops

    @Test("all channel-bearing send ops validate 1-based channel and emit wire byte ch-1")
    func testAllSendOpsValidateChannel1Based() async {
        // play_sequence does not take a top-level `channel` (channel is per-event in the notes string),
        // so it's excluded from this matrix. The other 6 must all encode 1-based input → wire byte (input - 1).
        let channelBearingCommands = ["send_cc", "send_note", "send_chord",
                                      "send_program_change", "send_pitch_bend", "send_aftertouch"]
        let oneBasedToWire: [(input: Int, wire: String)] = [(1, "0"), (8, "7"), (16, "15")]

        for command in channelBearingCommands {
            for testCase in oneBasedToWire {
                let router = ChannelRouter()
                let coreMidi = MockChannel(id: .coreMIDI)
                await router.register(coreMidi)

                var params = Self.baseParams(for: command)
                params["channel"] = .int(testCase.input)

                let result = await MIDIDispatcher.handle(
                    command: command,
                    params: params,
                    router: router,
                    cache: StateCache()
                )

                #expect(!result.isError!,
                        "\(command) ch=\(testCase.input) failed unexpectedly: \(sharedToolText(result))")
                let ops = await coreMidi.executedOps
                #expect(ops.count == 1)
                #expect(ops.first?.1["channel"] == testCase.wire,
                        "\(command) ch=\(testCase.input) → expected wire \(testCase.wire), got \(ops.first?.1["channel"] ?? "nil")")
            }

            // Out-of-range rejection
            do {
                let router = ChannelRouter()
                let coreMidi = MockChannel(id: .coreMIDI)
                await router.register(coreMidi)

                var params = Self.baseParams(for: command)
                params["channel"] = .int(17)

                let result = await MIDIDispatcher.handle(
                    command: command,
                    params: params,
                    router: router,
                    cache: StateCache()
                )

                #expect(result.isError!, "\(command) ch=17 should reject")
                #expect(sharedToolText(result).contains("invalid_params"))
                #expect(await coreMidi.executedOps.isEmpty)
            }
        }
    }

    // MARK: - 18. ChannelRouter routingTable contains exactly 14 midi keycmd entries

    @Test("ChannelRouter.routingTable has 14 (7 base + 7 keycmd) MIDI send entries")
    func testRoutingTableHasFourteenMidiKeycmdEntries() {
        let table = ChannelRouter.routingTable

        // 7 base ops → [.coreMIDI]
        let baseOps = [
            "midi.send_cc",
            "midi.send_note",
            "midi.send_chord",
            "midi.send_program_change",
            "midi.send_pitch_bend",
            "midi.send_aftertouch",
            "midi.play_sequence",
        ]
        for op in baseOps {
            let chain = table[op]
            #expect(chain != nil, "routingTable missing base op \(op)")
            #expect(chain == [.coreMIDI], "routingTable[\(op)] must be [.coreMIDI], got \(chain ?? [])")
        }

        // 7 keycmd ops → [.midiKeyCommands]
        let keycmdOps = baseOps.map { $0 + ".keycmd" }
        for op in keycmdOps {
            let chain = table[op]
            #expect(chain != nil, "routingTable missing keycmd op \(op)")
            #expect(chain == [.midiKeyCommands],
                    "routingTable[\(op)] must be [.midiKeyCommands], got \(chain ?? [])")
        }

        // No surprise extra `midi.*.keycmd` entries beyond the 7 expected.
        let allKeycmdInTable = Set(table.keys.filter { $0.hasPrefix("midi.") && $0.hasSuffix(".keycmd") })
        #expect(allKeycmdInTable == Set(keycmdOps),
                "routingTable midi.*.keycmd drift — expected exactly 7, got \(allKeycmdInTable.sorted())")
    }
}

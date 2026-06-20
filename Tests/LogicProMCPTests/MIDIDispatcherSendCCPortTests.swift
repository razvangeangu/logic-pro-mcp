import Testing
import Foundation
import MCP
@testable import LogicProMCP

// T5 — MIDIDispatcher port routing for `send_cc` (TDD)
// PRD: issue1-keycmd-port-routing AC-1 / AC-2 / AC-3 / AC-4
//
// Each test exercises send_cc through MIDIDispatcher.handle and inspects
// the operation key + channel byte that were forwarded to the registered
// MockChannel. The router treats `port: "midi"` (or missing) as the legacy
// CoreMIDI route, and `port: "keycmd"` as the new MIDIKeyCommands route.

@Suite("MIDIDispatcher send_cc port routing")
struct MIDIDispatcherSendCCPortTests {

    // MARK: - 1. Default port (missing) → coreMIDI / "midi.send_cc"

    @Test("port missing → routes to midi.send_cc on coreMIDI")
    func testSendCCDefaultPortRoutesToMidiSendCC() async {
        let router = ChannelRouter()
        let coreMidi = MockChannel(id: .coreMIDI)
        let keycmd = MockChannel(id: .midiKeyCommands)
        await router.register(coreMidi)
        await router.register(keycmd)

        let result = await MIDIDispatcher.handle(
            command: "send_cc",
            params: ["controller": .int(74), "value": .int(127), "channel": .int(1)],
            router: router,
            cache: StateCache()
        )

        #expect(!result.isError!)
        let coreOps = await coreMidi.executedOps
        let keycmdOps = await keycmd.executedOps
        #expect(coreOps.count == 1, "expected 1 coreMIDI op, got \(coreOps.count)")
        #expect(coreOps.first?.0 == "midi.send_cc")
        #expect(keycmdOps.isEmpty, "keycmd channel must not be touched on default port")
    }

    // MARK: - 2. Explicit keycmd port → midiKeyCommands / "midi.send_cc.keycmd"

    @Test("port=keycmd → routes to midi.send_cc.keycmd on midiKeyCommands")
    func testSendCCKeycmdPortRoutesToMidiSendCCKeycmd() async {
        let router = ChannelRouter()
        let coreMidi = MockChannel(id: .coreMIDI)
        let keycmd = MockChannel(
            id: .midiKeyCommands,
            healthOverride: .healthy(detail: "Mock keycmd OK", verificationStatus: .runtimeReady)
        )
        await router.register(coreMidi)
        await router.register(keycmd)

        let result = await MIDIDispatcher.handle(
            command: "send_cc",
            params: [
                "controller": .int(74),
                "value": .int(127),
                "channel": .int(1),
                "port": .string("keycmd"),
            ],
            router: router,
            cache: StateCache()
        )

        #expect(!result.isError!)
        let coreOps = await coreMidi.executedOps
        let keycmdOps = await keycmd.executedOps
        #expect(coreOps.isEmpty, "coreMIDI must not be touched when port=keycmd")
        #expect(keycmdOps.count == 1, "expected 1 keycmd op, got \(keycmdOps.count)")
        #expect(keycmdOps.first?.0 == "midi.send_cc.keycmd")
    }

    // MARK: - 3. Invalid port string → invalid_params State C

    @Test("port=foo → invalid_params State C with hint")
    func testSendCCInvalidPortReturnsStateCInvalidParams() async {
        let router = ChannelRouter()
        let coreMidi = MockChannel(id: .coreMIDI)
        let keycmd = MockChannel(id: .midiKeyCommands)
        await router.register(coreMidi)
        await router.register(keycmd)

        let result = await MIDIDispatcher.handle(
            command: "send_cc",
            params: [
                "controller": .int(74),
                "value": .int(127),
                "channel": .int(1),
                "port": .string("foo"),
            ],
            router: router,
            cache: StateCache()
        )

        #expect(result.isError!)
        let text = sharedToolText(result)
        #expect(text.contains("invalid_params"), "expected invalid_params, got: \(text)")
        // Hint must list the supported port values so the LLM agent can self-correct.
        #expect(text.contains("midi"))
        #expect(text.contains("keycmd"))
        #expect(await coreMidi.executedOps.isEmpty)
        #expect(await keycmd.executedOps.isEmpty)
    }

    // MARK: - 4. Scripter port rejected (NG5)

    @Test("port=scripter → invalid_params (NG5: not supported)")
    func testSendCCScripterPortRejected() async {
        let router = ChannelRouter()
        let coreMidi = MockChannel(id: .coreMIDI)
        await router.register(coreMidi)

        let result = await MIDIDispatcher.handle(
            command: "send_cc",
            params: [
                "controller": .int(74),
                "value": .int(127),
                "channel": .int(1),
                "port": .string("scripter"),
            ],
            router: router,
            cache: StateCache()
        )

        #expect(result.isError!)
        let text = sharedToolText(result)
        #expect(text.contains("invalid_params"))
        #expect(await coreMidi.executedOps.isEmpty)
    }

    // MARK: - 5. Channel encoding — channel 16 → wire byte 15

    @Test("channel=16 → wire byte 15 forwarded to channel param")
    func testSendCCChannel16WireByteFifteen() async {
        let router = ChannelRouter()
        let coreMidi = MockChannel(id: .coreMIDI)
        await router.register(coreMidi)

        let result = await MIDIDispatcher.handle(
            command: "send_cc",
            params: ["controller": .int(74), "value": .int(127), "channel": .int(16)],
            router: router,
            cache: StateCache()
        )

        #expect(!result.isError!)
        let ops = await coreMidi.executedOps
        #expect(ops.count == 1)
        #expect(ops.first?.1["channel"] == "15", "channel 16 must encode to wire byte 15, got \(ops.first?.1["channel"] ?? "nil")")
    }

    // MARK: - 6. channel=0 rejected (1-based)

    @Test("channel=0 → invalid_params (1-based)")
    func testSendCCChannel0Rejected() async {
        let router = ChannelRouter()
        let coreMidi = MockChannel(id: .coreMIDI)
        await router.register(coreMidi)

        let result = await MIDIDispatcher.handle(
            command: "send_cc",
            params: ["controller": .int(74), "value": .int(127), "channel": .int(0)],
            router: router,
            cache: StateCache()
        )

        #expect(result.isError!)
        let text = sharedToolText(result)
        #expect(text.contains("invalid_params"))
        #expect(await coreMidi.executedOps.isEmpty)
    }

    // MARK: - 7. channel=1.5 rejected (fractional)

    @Test("channel=1.5 → invalid_params (fractional rejected)")
    func testSendCCFloatChannelRejected() async {
        let router = ChannelRouter()
        let coreMidi = MockChannel(id: .coreMIDI)
        await router.register(coreMidi)

        let result = await MIDIDispatcher.handle(
            command: "send_cc",
            params: ["controller": .int(74), "value": .int(127), "channel": .double(1.5)],
            router: router,
            cache: StateCache()
        )

        #expect(result.isError!)
        let text = sharedToolText(result)
        #expect(text.contains("invalid_params"))
        #expect(await coreMidi.executedOps.isEmpty)
    }
}

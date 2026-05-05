import Testing
import Foundation
import MCP
@testable import LogicProMCP

// T5 — Reject `port` parameter on ops that have no keycmd alternative
// PRD: issue1-keycmd-port-routing AC-5, AC-6 (NG7 + NG8)
//
// `record_sequence` (TrackDispatcher) and the MIDI surface ops that don't
// route through the 7 send-style operations (mmc_*, send_sysex, step_input,
// create_virtual_port) MUST reject any `port` argument with
// `invalid_params`. Silently ignoring `port` here would let a caller assume
// a `port:"keycmd"` request was honored when in fact the op only ever runs
// over CoreMIDI, masking a wiring mistake.

@Suite("MIDIDispatcher port-parameter rejection")
struct MIDIDispatcherRejectionTests {

    // MARK: - 10. record_sequence rejects port

    @Test("record_sequence + port → invalid_params (port not supported)")
    func testRecordSequenceRejectsPortParam() async {
        let router = ChannelRouter()
        let ax = MockChannel(id: .accessibility)
        let coreMidi = MockChannel(id: .coreMIDI)
        await router.register(ax)
        await router.register(coreMidi)
        let cache = StateCache()
        await cache.updateDocumentState(true)

        let result = await TrackDispatcher.handle(
            command: "record_sequence",
            params: [
                "bar": .int(1),
                "notes": .string("60,0,480"),
                "tempo": .double(120),
                "port": .string("keycmd"),
            ],
            router: router,
            cache: cache
        )

        #expect(result.isError == true)
        let text = sharedToolText(result)
        #expect(text.contains("invalid_params"), "expected invalid_params, got: \(text)")
        #expect(text.contains("record_sequence"),
                "hint must mention record_sequence so caller can self-correct, got: \(text)")
        // Must reject before any routing — no AX / CoreMIDI op should fire.
        #expect(await ax.executedOps.isEmpty)
        #expect(await coreMidi.executedOps.isEmpty)
    }

    // MARK: - 11. mmc_play rejects port

    @Test("mmc_play + port → invalid_params")
    func testMmcPlayRejectsPortParam() async {
        let router = ChannelRouter()
        let coreMidi = MockChannel(id: .coreMIDI)
        await router.register(coreMidi)

        let result = await MIDIDispatcher.handle(
            command: "mmc_play",
            params: ["port": .string("keycmd")],
            router: router,
            cache: StateCache()
        )

        #expect(result.isError == true)
        let text = sharedToolText(result)
        #expect(text.contains("invalid_params"))
        #expect(await coreMidi.executedOps.isEmpty)
    }

    // MARK: - 12. mmc_locate rejects port

    @Test("mmc_locate + port → invalid_params")
    func testMmcLocateRejectsPortParam() async {
        let router = ChannelRouter()
        let coreMidi = MockChannel(id: .coreMIDI)
        let mcu = MockChannel(id: .mcu)
        let ax = MockChannel(id: .accessibility)
        await router.register(coreMidi)
        await router.register(mcu)
        await router.register(ax)

        // Both the bar-mode and time-mode branches must reject `port`.
        let barResult = await MIDIDispatcher.handle(
            command: "mmc_locate",
            params: ["bar": .int(5), "port": .string("keycmd")],
            router: router,
            cache: StateCache()
        )
        let timeResult = await MIDIDispatcher.handle(
            command: "mmc_locate",
            params: ["time": .string("01:02:03:04"), "port": .string("midi")],
            router: router,
            cache: StateCache()
        )

        #expect(barResult.isError == true)
        #expect(timeResult.isError == true)
        #expect(sharedToolText(barResult).contains("invalid_params"))
        #expect(sharedToolText(timeResult).contains("invalid_params"))
        #expect(await coreMidi.executedOps.isEmpty)
        #expect(await mcu.executedOps.isEmpty)
        #expect(await ax.executedOps.isEmpty)
    }

    // MARK: - 13. send_sysex rejects port

    @Test("send_sysex + port → invalid_params")
    func testSendSysexRejectsPortParam() async {
        let router = ChannelRouter()
        let coreMidi = MockChannel(id: .coreMIDI)
        await router.register(coreMidi)

        let result = await MIDIDispatcher.handle(
            command: "send_sysex",
            params: ["bytes": .array([.int(240), .int(66), .int(247)]), "port": .string("keycmd")],
            router: router,
            cache: StateCache()
        )

        #expect(result.isError == true)
        #expect(sharedToolText(result).contains("invalid_params"))
        #expect(await coreMidi.executedOps.isEmpty)
    }

    // MARK: - 14. step_input rejects port

    @Test("step_input + port → invalid_params")
    func testStepInputRejectsPortParam() async {
        let router = ChannelRouter()
        let coreMidi = MockChannel(id: .coreMIDI)
        await router.register(coreMidi)

        let result = await MIDIDispatcher.handle(
            command: "step_input",
            params: ["note": .int(60), "duration": .string("1/4"), "port": .string("midi")],
            router: router,
            cache: StateCache()
        )

        #expect(result.isError == true)
        #expect(sharedToolText(result).contains("invalid_params"))
        #expect(await coreMidi.executedOps.isEmpty)
    }

    // MARK: - 15. create_virtual_port rejects port

    @Test("create_virtual_port + port → invalid_params")
    func testCreateVirtualPortRejectsPortParam() async {
        let router = ChannelRouter()
        let coreMidi = MockChannel(id: .coreMIDI)
        await router.register(coreMidi)

        let result = await MIDIDispatcher.handle(
            command: "create_virtual_port",
            params: ["name": .string("Test Port"), "port": .string("keycmd")],
            router: router,
            cache: StateCache()
        )

        #expect(result.isError == true)
        #expect(sharedToolText(result).contains("invalid_params"))
        #expect(await coreMidi.executedOps.isEmpty)
    }

    // mmc_stop / mmc_record reuse the same reject helper — covered by #11 in
    // production code. We add a brief assertion to lock the surface for both.
    @Test("mmc_stop + port → invalid_params")
    func testMmcStopRejectsPortParam() async {
        let router = ChannelRouter()
        let coreMidi = MockChannel(id: .coreMIDI)
        await router.register(coreMidi)

        let result = await MIDIDispatcher.handle(
            command: "mmc_stop",
            params: ["port": .string("midi")],
            router: router,
            cache: StateCache()
        )

        #expect(result.isError == true)
        #expect(sharedToolText(result).contains("invalid_params"))
        #expect(await coreMidi.executedOps.isEmpty)
    }

    @Test("mmc_record + port → invalid_params")
    func testMmcRecordRejectsPortParam() async {
        let router = ChannelRouter()
        let coreMidi = MockChannel(id: .coreMIDI)
        await router.register(coreMidi)

        let result = await MIDIDispatcher.handle(
            command: "mmc_record",
            params: ["port": .string("keycmd")],
            router: router,
            cache: StateCache()
        )

        #expect(result.isError == true)
        #expect(sharedToolText(result).contains("invalid_params"))
        #expect(await coreMidi.executedOps.isEmpty)
    }
}

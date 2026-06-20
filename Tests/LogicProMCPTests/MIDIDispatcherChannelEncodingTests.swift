import Testing
import Foundation
import MCP
@testable import LogicProMCP

// T5 — pitch_bend / aftertouch must use the unified validateMidiChannel path
// PRD: issue1-keycmd-port-routing AC-7
//
// Pre-T5 the pitch_bend and aftertouch case branches forwarded the raw
// `channel` integer through `intParam(...)` directly into the wire payload.
// That path silently corrupted out-of-range channels (e.g. ch=17 became wire
// byte 17, which collides with running-status reserved space) and accepted
// fractional doubles (`Int(1.5) → 1`). Both ops must now reject invalid
// 1-based channel input the same way send_cc does.

@Suite("MIDIDispatcher pitch_bend / aftertouch channel encoding")
struct MIDIDispatcherChannelEncodingTests {

    // MARK: - 16. pitch_bend channel validation (NG3 fix)

    @Test("pitch_bend ch=17 → invalid_params (was: silent UInt8 corruption)")
    func testPitchBendChannelValidation() async {
        let router = ChannelRouter()
        let coreMidi = MockChannel(id: .coreMIDI)
        await router.register(coreMidi)

        let result = await MIDIDispatcher.handle(
            command: "send_pitch_bend",
            params: ["value": .int(0), "channel": .int(17)],
            router: router,
            cache: StateCache()
        )

        #expect(result.isError!,
                "pitch_bend ch=17 must reject — pre-T5 silently emitted wire byte 17")
        let text = sharedToolText(result)
        #expect(text.contains("invalid_params"))
        #expect(await coreMidi.executedOps.isEmpty)
    }

    // MARK: - 17. aftertouch channel validation

    @Test("aftertouch ch=0 → invalid_params (1-based)")
    func testAftertouchChannelValidation() async {
        let router = ChannelRouter()
        let coreMidi = MockChannel(id: .coreMIDI)
        await router.register(coreMidi)

        let result = await MIDIDispatcher.handle(
            command: "send_aftertouch",
            params: ["value": .int(64), "channel": .int(0)],
            router: router,
            cache: StateCache()
        )

        #expect(result.isError!,
                "aftertouch ch=0 must reject — channel is 1-based")
        let text = sharedToolText(result)
        #expect(text.contains("invalid_params"))
        #expect(await coreMidi.executedOps.isEmpty)
    }
}

import Testing
import Foundation
import MCP
@testable import LogicProMCP

// T5 — Backward compatibility regression for the v3.1.4 send_cc call shape
// PRD: issue1-keycmd-port-routing AC-10 (Phase 4 Loop 1 tester P1)
//
// The v3.1.5 port-routing rewrite changes how send_cc internally encodes
// the wire byte (now goes through validateMidiChannel) but MUST NOT change
// the externally observable response for callers that omit `port`. This
// test pins the v3.1.4 fixture: same operation key, same forwarded params,
// and the same response *string* the MockChannel produces ("Mock:
// midi.send_cc"). If the dispatcher accidentally rewrites the operation key
// or wraps the response, this test catches it.

@Suite("Backward compatibility regression — v3.1.4 send_cc call shape")
struct BackwardCompatRegressionTests {

    @Test("send_cc {controller, value, channel} matches prior v3.1.4 wire + response")
    func testBackwardCompatSendCCWithoutPortMatchesPriorBehavior() async {
        let router = ChannelRouter()
        let coreMidi = MockChannel(id: .coreMIDI)
        await router.register(coreMidi)

        let result = await MIDIDispatcher.handle(
            command: "send_cc",
            params: ["controller": .int(74), "value": .int(127), "channel": .int(3)],
            router: router,
            cache: StateCache()
        )

        // The v3.1.4 fixture: dispatcher routes through coreMIDI with wire
        // byte 2 (channel 3 → 3-1) and the response text is "Mock: midi.send_cc"
        // (from MockChannel.execute). Either change is a breaking regression.
        #expect(!result.isError!)
        let ops = await coreMidi.executedOps
        #expect(ops.count == 1)
        #expect(ops[0].0 == "midi.send_cc")
        #expect(ops[0].1["controller"] == "74")
        #expect(ops[0].1["value"] == "127")
        #expect(ops[0].1["channel"] == "2",
                "v3.1.4 wire byte for ch=3 was 2; got \(ops[0].1["channel"] ?? "nil")")

        // Response string-equality with v3.1.4 (MockChannel.execute returns
        // "Mock: <operation>"). Wrapping the response in a State envelope
        // for the back-compat path would break callers parsing the raw text.
        let text = sharedToolText(result)
        #expect(text == "Mock: midi.send_cc",
                "BackwardCompat: response text drifted — got '\(text)', expected 'Mock: midi.send_cc'")
    }
}

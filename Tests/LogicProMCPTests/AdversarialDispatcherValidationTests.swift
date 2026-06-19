import Foundation
import MCP
import Testing
@testable import LogicProMCP

private struct AdversarialDispatcherCase {
    let label: String
    let tool: String
    let command: String
    let params: [String: Value]
    let channelIDs: [ChannelID]
}

private func runAdversarialDispatcherCase(
    _ testCase: AdversarialDispatcherCase
) async -> (CallTool.Result, [MockChannel]) {
    let router = ChannelRouter()
    var channels: [MockChannel] = []
    for id in testCase.channelIDs {
        let channel = MockChannel(id: id)
        await router.register(channel)
        channels.append(channel)
    }
    let cache = StateCache()

    let result: CallTool.Result
    switch testCase.tool {
    case "logic_transport":
        result = await TransportDispatcher.handle(
            command: testCase.command,
            params: testCase.params,
            router: router,
            cache: cache
        )
    case "logic_mixer":
        result = await MixerDispatcher.handle(
            command: testCase.command,
            params: testCase.params,
            router: router,
            cache: cache
        )
    case "logic_midi":
        result = await MIDIDispatcher.handle(
            command: testCase.command,
            params: testCase.params,
            router: router,
            cache: cache
        )
    case "logic_tracks":
        result = await TrackDispatcher.handle(
            command: testCase.command,
            params: testCase.params,
            router: router,
            cache: cache
        )
    case "logic_navigate":
        result = await NavigateDispatcher.handle(
            command: testCase.command,
            params: testCase.params,
            router: router,
            cache: cache
        )
    default:
        Issue.record("Unsupported adversarial tool: \(testCase.tool)")
        result = toolTextResult("unsupported test tool", isError: true)
    }

    return (result, channels)
}

private func expectInvalidParamsWithoutRoute(
    _ testCase: AdversarialDispatcherCase
) async {
    let (result, channels) = await runAdversarialDispatcherCase(testCase)
    let text = sharedToolText(result)
    #expect(
        result.isError == true,
        "\(testCase.label) must reject malformed input before routing; got text=\(text)"
    )
    #expect(
        text.contains("invalid_params"),
        "\(testCase.label) must return a structured invalid_params error; got text=\(text)"
    )
    for channel in channels {
        #expect(
            await channel.executedOps.isEmpty,
            "\(testCase.label) must not invoke router/channel on invalid input"
        )
    }
}

@Suite("Adversarial dispatcher validation")
struct AdversarialDispatcherValidationTests {
    @Test("transport malformed semantic params fail closed")
    func testTransportMalformedParamsRejectBeforeRouting() async {
        let cases: [AdversarialDispatcherCase] = [
            .init(label: "transport.set_tempo string garbage", tool: "logic_transport", command: "set_tempo", params: ["tempo": .string("abc")], channelIDs: [.accessibility]),
            .init(label: "transport.set_tempo bool garbage", tool: "logic_transport", command: "set_tempo", params: ["tempo": .bool(true)], channelIDs: [.accessibility]),
            .init(label: "transport.set_tempo array garbage", tool: "logic_transport", command: "set_tempo", params: ["tempo": .array([.int(120)])], channelIDs: [.accessibility]),
            .init(label: "transport.goto_position bar garbage", tool: "logic_transport", command: "goto_position", params: ["bar": .string("abc")], channelIDs: [.accessibility]),
            .init(label: "transport.set_cycle_range start garbage", tool: "logic_transport", command: "set_cycle_range", params: ["start": .string("abc"), "end": .int(4)], channelIDs: [.accessibility]),
            .init(label: "transport.set_cycle_range end garbage", tool: "logic_transport", command: "set_cycle_range", params: ["start": .int(1), "end": .string("abc")], channelIDs: [.accessibility]),
        ]

        for testCase in cases {
            await expectInvalidParamsWithoutRoute(testCase)
        }
    }

    @Test("mixer malformed numeric params fail closed")
    func testMixerMalformedParamsRejectBeforeRouting() async {
        let cases: [AdversarialDispatcherCase] = [
            .init(label: "mixer.set_volume missing value", tool: "logic_mixer", command: "set_volume", params: ["track": .int(0)], channelIDs: [.accessibility]),
            .init(label: "mixer.set_volume string garbage", tool: "logic_mixer", command: "set_volume", params: ["track": .int(0), "value": .string("abc")], channelIDs: [.accessibility]),
            .init(label: "mixer.set_volume bool garbage", tool: "logic_mixer", command: "set_volume", params: ["track": .int(0), "value": .bool(true)], channelIDs: [.accessibility]),
            .init(label: "mixer.set_pan missing value", tool: "logic_mixer", command: "set_pan", params: ["track": .int(0)], channelIDs: [.accessibility]),
            .init(label: "mixer.set_pan string garbage", tool: "logic_mixer", command: "set_pan", params: ["track": .int(0), "value": .string("abc")], channelIDs: [.accessibility]),
            .init(label: "mixer.set_pan bool garbage", tool: "logic_mixer", command: "set_pan", params: ["track": .int(0), "value": .bool(false)], channelIDs: [.accessibility]),
            .init(label: "mixer.set_master_volume missing value", tool: "logic_mixer", command: "set_master_volume", params: [:], channelIDs: [.mcu]),
            .init(label: "mixer.set_master_volume string garbage", tool: "logic_mixer", command: "set_master_volume", params: ["value": .string("abc")], channelIDs: [.mcu]),
            .init(label: "mixer.set_master_volume bool garbage", tool: "logic_mixer", command: "set_master_volume", params: ["value": .bool(true)], channelIDs: [.mcu]),
        ]

        for testCase in cases {
            await expectInvalidParamsWithoutRoute(testCase)
        }
    }

    @Test("MIDI malformed send params fail closed")
    func testMIDIMalformedSendParamsRejectBeforeRouting() async {
        let cases: [AdversarialDispatcherCase] = [
            .init(label: "midi.send_note note string garbage", tool: "logic_midi", command: "send_note", params: ["note": .string("abc")], channelIDs: [.coreMIDI]),
            .init(label: "midi.send_note note bool garbage", tool: "logic_midi", command: "send_note", params: ["note": .bool(true)], channelIDs: [.coreMIDI]),
            .init(label: "midi.send_note note out of range", tool: "logic_midi", command: "send_note", params: ["note": .int(128)], channelIDs: [.coreMIDI]),
            .init(label: "midi.send_note velocity string garbage", tool: "logic_midi", command: "send_note", params: ["note": .int(60), "velocity": .string("abc")], channelIDs: [.coreMIDI]),
            .init(label: "midi.send_note velocity bool garbage", tool: "logic_midi", command: "send_note", params: ["note": .int(60), "velocity": .bool(true)], channelIDs: [.coreMIDI]),
            .init(label: "midi.send_note velocity out of range", tool: "logic_midi", command: "send_note", params: ["note": .int(60), "velocity": .int(128)], channelIDs: [.coreMIDI]),
            .init(label: "midi.send_note duration string garbage", tool: "logic_midi", command: "send_note", params: ["note": .int(60), "duration_ms": .string("abc")], channelIDs: [.coreMIDI]),
            .init(label: "midi.send_note duration bool garbage", tool: "logic_midi", command: "send_note", params: ["note": .int(60), "duration_ms": .bool(true)], channelIDs: [.coreMIDI]),
            .init(label: "midi.send_chord notes mixed invalid array", tool: "logic_midi", command: "send_chord", params: ["notes": .array([.int(60), .string("bad"), .int(67)])], channelIDs: [.coreMIDI]),
            .init(label: "midi.send_chord notes empty array", tool: "logic_midi", command: "send_chord", params: ["notes": .array([])], channelIDs: [.coreMIDI]),
            .init(label: "midi.send_chord notes out of range array", tool: "logic_midi", command: "send_chord", params: ["notes": .array([.int(60), .int(128)])], channelIDs: [.coreMIDI]),
            .init(label: "midi.send_chord notes string garbage member", tool: "logic_midi", command: "send_chord", params: ["notes": .string("60,bad,67")], channelIDs: [.coreMIDI]),
            .init(label: "midi.send_chord notes bool garbage", tool: "logic_midi", command: "send_chord", params: ["notes": .bool(true)], channelIDs: [.coreMIDI]),
            .init(label: "midi.send_chord velocity garbage", tool: "logic_midi", command: "send_chord", params: ["notes": .string("60,64"), "velocity": .string("abc")], channelIDs: [.coreMIDI]),
            .init(label: "midi.send_chord duration garbage", tool: "logic_midi", command: "send_chord", params: ["notes": .string("60,64"), "duration_ms": .string("abc")], channelIDs: [.coreMIDI]),
            .init(label: "midi.send_cc controller string garbage", tool: "logic_midi", command: "send_cc", params: ["controller": .string("abc"), "value": .int(1)], channelIDs: [.coreMIDI]),
            .init(label: "midi.send_cc controller out of range", tool: "logic_midi", command: "send_cc", params: ["controller": .int(128), "value": .int(1)], channelIDs: [.coreMIDI]),
            .init(label: "midi.send_cc value string garbage", tool: "logic_midi", command: "send_cc", params: ["controller": .int(7), "value": .string("abc")], channelIDs: [.coreMIDI]),
            .init(label: "midi.send_cc value out of range", tool: "logic_midi", command: "send_cc", params: ["controller": .int(7), "value": .int(128)], channelIDs: [.coreMIDI]),
            .init(label: "midi.send_program_change program string garbage", tool: "logic_midi", command: "send_program_change", params: ["program": .string("abc")], channelIDs: [.coreMIDI]),
            .init(label: "midi.send_program_change program out of range", tool: "logic_midi", command: "send_program_change", params: ["program": .int(128)], channelIDs: [.coreMIDI]),
            .init(label: "midi.send_pitch_bend value string garbage", tool: "logic_midi", command: "send_pitch_bend", params: ["value": .string("abc")], channelIDs: [.coreMIDI]),
            .init(label: "midi.send_pitch_bend value negative signed alias", tool: "logic_midi", command: "send_pitch_bend", params: ["value": .int(-1)], channelIDs: [.coreMIDI]),
            .init(label: "midi.send_pitch_bend value over range", tool: "logic_midi", command: "send_pitch_bend", params: ["value": .int(16384)], channelIDs: [.coreMIDI]),
            .init(label: "midi.send_aftertouch value string garbage", tool: "logic_midi", command: "send_aftertouch", params: ["value": .string("abc")], channelIDs: [.coreMIDI]),
            .init(label: "midi.send_aftertouch value out of range", tool: "logic_midi", command: "send_aftertouch", params: ["value": .int(128)], channelIDs: [.coreMIDI]),
            .init(label: "midi.play_sequence notes garbage", tool: "logic_midi", command: "play_sequence", params: ["notes": .string("not,a,sequence")], channelIDs: [.coreMIDI]),
            .init(label: "midi.play_sequence notes bool garbage", tool: "logic_midi", command: "play_sequence", params: ["notes": .bool(true)], channelIDs: [.coreMIDI]),
            .init(label: "midi.send_sysex bytes mixed invalid array", tool: "logic_midi", command: "send_sysex", params: ["bytes": .array([.int(240), .string("bad"), .int(247)])], channelIDs: [.coreMIDI]),
            .init(label: "midi.send_sysex bytes array body status byte", tool: "logic_midi", command: "send_sysex", params: ["bytes": .array([.int(240), .int(125), .int(128), .int(247)])], channelIDs: [.coreMIDI]),
            .init(label: "midi.send_sysex data string body status byte", tool: "logic_midi", command: "send_sysex", params: ["data": .string("F0 7D 80 F7")], channelIDs: [.coreMIDI]),
            .init(label: "midi.send_sysex missing data", tool: "logic_midi", command: "send_sysex", params: [:], channelIDs: [.coreMIDI]),
            .init(label: "midi.mmc_locate time malformed", tool: "logic_midi", command: "mmc_locate", params: ["time": .string("99:99:99:99")], channelIDs: [.coreMIDI]),
            .init(label: "midi.mmc_locate time bool garbage", tool: "logic_midi", command: "mmc_locate", params: ["time": .bool(true)], channelIDs: [.coreMIDI]),
            .init(label: "midi.step_input note string garbage", tool: "logic_midi", command: "step_input", params: ["note": .string("abc"), "duration": .string("1/4")], channelIDs: [.coreMIDI]),
            .init(label: "midi.step_input note out of range", tool: "logic_midi", command: "step_input", params: ["note": .int(128), "duration": .string("1/4")], channelIDs: [.coreMIDI]),
            .init(label: "midi.step_input duration garbage", tool: "logic_midi", command: "step_input", params: ["note": .int(60), "duration": .string("whenever")], channelIDs: [.coreMIDI]),
            .init(label: "midi.step_input duration bool garbage", tool: "logic_midi", command: "step_input", params: ["note": .int(60), "duration": .bool(true)], channelIDs: [.coreMIDI]),
        ]

        for testCase in cases {
            await expectInvalidParamsWithoutRoute(testCase)
        }
    }

    @Test("track malformed params fail closed")
    func testTrackMalformedParamsRejectBeforeRouting() async {
        let cases: [AdversarialDispatcherCase] = [
            .init(label: "tracks.mute enabled string garbage", tool: "logic_tracks", command: "mute", params: ["index": .int(0), "enabled": .string("maybe")], channelIDs: [.mcu]),
            .init(label: "tracks.solo enabled string garbage", tool: "logic_tracks", command: "solo", params: ["index": .int(0), "enabled": .string("maybe")], channelIDs: [.mcu]),
            .init(label: "tracks.arm enabled string garbage", tool: "logic_tracks", command: "arm", params: ["index": .int(0), "enabled": .string("maybe")], channelIDs: [.mcu]),
            .init(label: "tracks.scan_plugin_presets delay string garbage", tool: "logic_tracks", command: "scan_plugin_presets", params: ["submenuOpenDelayMs": .string("abc")], channelIDs: [.accessibility]),
            .init(label: "tracks.scan_library mode unknown", tool: "logic_tracks", command: "scan_library", params: ["mode": .string("filesystem")], channelIDs: [.accessibility]),
            .init(label: "tracks.record_sequence bar garbage", tool: "logic_tracks", command: "record_sequence", params: ["bar": .string("abc"), "notes": .string("60,0,480")], channelIDs: [.accessibility, .coreMIDI]),
            .init(label: "tracks.record_sequence tempo garbage", tool: "logic_tracks", command: "record_sequence", params: ["bar": .int(1), "notes": .string("60,0,480"), "tempo": .string("abc")], channelIDs: [.accessibility, .coreMIDI]),
            .init(label: "tracks.record_sequence notes bool garbage", tool: "logic_tracks", command: "record_sequence", params: ["bar": .int(1), "notes": .bool(true)], channelIDs: [.accessibility, .coreMIDI]),
        ]

        for testCase in cases {
            await expectInvalidParamsWithoutRoute(testCase)
        }
    }

    @Test("navigate malformed params fail closed")
    func testNavigateMalformedParamsRejectBeforeRouting() async {
        let cases: [AdversarialDispatcherCase] = [
            .init(label: "navigate.goto_bar missing bar", tool: "logic_navigate", command: "goto_bar", params: [:], channelIDs: [.accessibility]),
            .init(label: "navigate.goto_bar string garbage", tool: "logic_navigate", command: "goto_bar", params: ["bar": .string("abc")], channelIDs: [.accessibility]),
            .init(label: "navigate.set_zoom string garbage", tool: "logic_navigate", command: "set_zoom", params: ["level": .string("explode")], channelIDs: [.midiKeyCommands]),
            .init(label: "navigate.set_zoom bool garbage", tool: "logic_navigate", command: "set_zoom", params: ["level": .bool(true)], channelIDs: [.midiKeyCommands]),
        ]

        for testCase in cases {
            await expectInvalidParamsWithoutRoute(testCase)
        }
    }
}

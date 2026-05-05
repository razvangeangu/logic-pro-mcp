import Testing
import Foundation
import MCP
@testable import LogicProMCP

// T2 — MIDIDispatcher.validatePort + validateMidiChannel helpers (TDD)
// PRD: issue1-keycmd-port-routing AC-1.3, AC-2.1-2.5

@Suite("MIDIDispatcher validation helpers")
struct MIDIDispatcherValidationHelpersTests {

    // MARK: - validatePort

    @Test("port missing → defaults to midi")
    func testValidatePortDefaultsToMidi() {
        let result = MIDIDispatcher.validatePort([:])
        switch result {
        case .success(let port): #expect(port == "midi")
        case .failure(let err): Issue.record("expected .success(\"midi\"), got .failure(\(err.message))")
        }
    }

    @Test("port=keycmd → success(keycmd)")
    func testValidatePortAcceptsKeycmd() {
        let result = MIDIDispatcher.validatePort(["port": .string("keycmd")])
        switch result {
        case .success(let port): #expect(port == "keycmd")
        case .failure(let err): Issue.record("expected .success(\"keycmd\"), got .failure(\(err.message))")
        }
    }

    @Test("port=midi (explicit) → success(midi)")
    func testValidatePortExplicitMidi() {
        let result = MIDIDispatcher.validatePort(["port": .string("midi")])
        switch result {
        case .success(let port): #expect(port == "midi")
        case .failure(let err): Issue.record("expected .success(\"midi\"), got .failure(\(err.message))")
        }
    }

    @Test("port=scripter → failure (NG5: not supported in v3.1.5)")
    func testValidatePortRejectsScripter() {
        let result = MIDIDispatcher.validatePort(["port": .string("scripter")])
        switch result {
        case .success(let p): Issue.record("expected .failure for scripter, got .success(\(p))")
        case .failure(let err): #expect(err.message.contains("port"))
        }
    }

    @Test("port=foo → failure with hint")
    func testValidatePortRejectsUnknown() {
        let result = MIDIDispatcher.validatePort(["port": .string("foo")])
        switch result {
        case .success(let p): Issue.record("expected .failure for foo, got .success(\(p))")
        case .failure(let err):
            #expect(err.message.contains("midi"))
            #expect(err.message.contains("keycmd"))
        }
    }

    @Test("port=\"\" → failure (empty string explicitly rejected)")
    func testValidatePortRejectsEmpty() {
        let result = MIDIDispatcher.validatePort(["port": .string("")])
        switch result {
        case .success(let p): Issue.record("expected .failure for empty, got .success(\(p))")
        case .failure: break
        }
    }

    // MARK: - validateMidiChannel

    @Test("channel=1 → wire 0")
    func testValidateChannel1MapsToWire0() {
        let result = MIDIDispatcher.validateMidiChannel(["channel": .int(1)])
        switch result {
        case .success(let w): #expect(w == 0)
        case .failure(let err): Issue.record("expected .success(0), got .failure(\(err.message))")
        }
    }

    @Test("channel=16 → wire 15")
    func testValidateChannel16MapsToWire15() {
        let result = MIDIDispatcher.validateMidiChannel(["channel": .int(16)])
        switch result {
        case .success(let w): #expect(w == 15)
        case .failure(let err): Issue.record("expected .success(15), got .failure(\(err.message))")
        }
    }

    @Test("channel=0 → failure (1-based)")
    func testValidateChannel0Rejected() {
        let result = MIDIDispatcher.validateMidiChannel(["channel": .int(0)])
        switch result {
        case .success(let w): Issue.record("expected .failure, got .success(\(w))")
        case .failure(let err): #expect(err.message.contains("1..16"))
        }
    }

    @Test("channel=17 → failure")
    func testValidateChannel17Rejected() {
        let result = MIDIDispatcher.validateMidiChannel(["channel": .int(17)])
        switch result {
        case .success(let w): Issue.record("expected .failure, got .success(\(w))")
        case .failure: break
        }
    }

    @Test("channel missing → wire 0 (default ch1)")
    func testValidateChannelMissingDefaultsToWire0() {
        let result = MIDIDispatcher.validateMidiChannel([:])
        switch result {
        case .success(let w): #expect(w == 0)
        case .failure(let err): Issue.record("expected .success(0), got .failure(\(err.message))")
        }
    }

    @Test("channel=1.0 (whole double) → wire 0")
    func testValidateChannelWholeDoubleAccepted() {
        let result = MIDIDispatcher.validateMidiChannel(["channel": .double(1.0)])
        switch result {
        case .success(let w): #expect(w == 0)
        case .failure(let err): Issue.record("expected .success(0), got .failure(\(err.message))")
        }
    }

    @Test("channel=1.5 → failure (fractional rejected)")
    func testValidateChannelFractionalDoubleRejected() {
        let result = MIDIDispatcher.validateMidiChannel(["channel": .double(1.5)])
        switch result {
        case .success(let w): Issue.record("expected .failure, got .success(\(w))")
        case .failure: break
        }
    }

    @Test("channel=\"5\" (string int) → wire 4")
    func testValidateChannelStringIntAccepted() {
        let result = MIDIDispatcher.validateMidiChannel(["channel": .string("5")])
        switch result {
        case .success(let w): #expect(w == 4)
        case .failure(let err): Issue.record("expected .success(4), got .failure(\(err.message))")
        }
    }

    @Test("channel=\"1.5\" (string fractional) → failure")
    func testValidateChannelStringFractionalRejected() {
        let result = MIDIDispatcher.validateMidiChannel(["channel": .string("1.5")])
        switch result {
        case .success(let w): Issue.record("expected .failure, got .success(\(w))")
        case .failure: break
        }
    }

    @Test("channel=-1 → failure")
    func testValidateChannelNegativeRejected() {
        let result = MIDIDispatcher.validateMidiChannel(["channel": .int(-1)])
        switch result {
        case .success(let w): Issue.record("expected .failure, got .success(\(w))")
        case .failure: break
        }
    }

    @Test("channel=true (bool, EC-1) → failure")
    func testValidateChannelBoolRejected() {
        let result = MIDIDispatcher.validateMidiChannel(["channel": .bool(true)])
        switch result {
        case .success(let w): Issue.record("expected .failure, got .success(\(w))")
        case .failure: break
        }
    }

    @Test("channel=Double.infinity (EC-4) → failure")
    func testValidateChannelInfinityRejected() {
        let result = MIDIDispatcher.validateMidiChannel(["channel": .double(.infinity)])
        switch result {
        case .success(let w): Issue.record("expected .failure, got .success(\(w))")
        case .failure: break
        }
    }

    @Test("channel=Double.nan (EC-4) → failure")
    func testValidateChannelNaNRejected() {
        let result = MIDIDispatcher.validateMidiChannel(["channel": .double(.nan)])
        switch result {
        case .success(let w): Issue.record("expected .failure, got .success(\(w))")
        case .failure: break
        }
    }
}

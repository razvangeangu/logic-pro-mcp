import Foundation
import Testing
import MCP
@testable import LogicProMCP

// T3 — NoteSequenceParser API change: `[ParsedNote]` (silent fall-through)
// → `Result<[ParsedNote], NoteSequenceParseError>` (strict whole-parse-fail).
//
// ch field semantic also moves to 1-based input (1..16 → wire byte 0..15).
// This is a BREAKING change to the parser's contract; the previous "skip
// invalid segments" behavior masked malformed input from callers, and the
// 0-based input convention contradicted the human-facing "Channel 1..16"
// numbering used everywhere else in Logic Pro.
//
// PRD-issue1-keycmd-port-routing §4.3 NoteSequenceParser API, AC-2.1, AC-2.6.

// MARK: - Unit tests (1..11)

@Test func testParseEmptyStringReturnsSuccessEmpty() {
    let result = NoteSequenceParser.parse("")
    switch result {
    case .success(let notes):
        #expect(notes.isEmpty, "empty input should return empty success, got \(notes.count)")
    case .failure(let error):
        Issue.record("expected .success([]), got .failure(\(error))")
    }
}

@Test func testParseValidSegmentChannel1Maps() {
    // ch=1 (1-based) → wire byte 0
    let result = NoteSequenceParser.parse("60,0,500,127,1")
    switch result {
    case .success(let notes):
        #expect(notes.count == 1)
        #expect(notes[0].channel == 0, "ch=1 input must map to wire byte 0, got \(notes[0].channel)")
        #expect(notes[0].pitch == 60)
        #expect(notes[0].velocity == 127)
    case .failure(let error):
        Issue.record("expected .success, got .failure(\(error))")
    }
}

@Test func testParseValidSegmentChannel16Maps() {
    // ch=16 (1-based) → wire byte 15 (0xF)
    let result = NoteSequenceParser.parse("60,0,500,127,16")
    switch result {
    case .success(let notes):
        #expect(notes.count == 1)
        #expect(notes[0].channel == 15, "ch=16 input must map to wire byte 15, got \(notes[0].channel)")
    case .failure(let error):
        Issue.record("expected .success, got .failure(\(error))")
    }
}

@Test func testParseChannel0RejectedWhole() {
    // ch=0 is invalid in the new 1-based contract — entire parse must fail.
    let result = NoteSequenceParser.parse("60,0,500,127,0")
    switch result {
    case .success(let notes):
        Issue.record("expected .failure, got .success(\(notes))")
    case .failure(let error):
        guard case .channelOutOfRange(let segment, let value) = error else {
            Issue.record("expected .channelOutOfRange, got \(error)")
            return
        }
        #expect(value == 0)
        #expect(segment.contains("60,0,500,127,0"))
    }
}

@Test func testParseChannel17RejectedWhole() {
    // ch=17 exceeds 16-channel MIDI limit — entire parse must fail.
    let result = NoteSequenceParser.parse("60,0,500,127,17")
    switch result {
    case .success(let notes):
        Issue.record("expected .failure, got .success(\(notes))")
    case .failure(let error):
        guard case .channelOutOfRange(_, let value) = error else {
            Issue.record("expected .channelOutOfRange, got \(error)")
            return
        }
        #expect(value == 17)
    }
}

@Test func testParseChannelOmittedDefaultsCh1() {
    // Omitted channel defaults to Ch 1 (wire byte 0).
    let result = NoteSequenceParser.parse("60,0,500,127")
    switch result {
    case .success(let notes):
        #expect(notes.count == 1)
        #expect(notes[0].channel == 0, "omitted channel must default to wire byte 0, got \(notes[0].channel)")
    case .failure(let error):
        Issue.record("expected .success, got .failure(\(error))")
    }
}

@Test func testParseInvalidPitchRejectedWhole() {
    // pitch=200 outside 0..127 — entire parse must fail.
    let result = NoteSequenceParser.parse("200,0,500,127,1")
    switch result {
    case .success(let notes):
        Issue.record("expected .failure, got .success(\(notes))")
    case .failure(let error):
        guard case .invalidPitch(let segment) = error else {
            Issue.record("expected .invalidPitch, got \(error)")
            return
        }
        #expect(segment.contains("200"))
    }
}

@Test func testParseInvalidTimingRejectedWhole() {
    // offset=-1 outside [0, ∞) — entire parse must fail.
    let result = NoteSequenceParser.parse("60,-1,500,127,1")
    switch result {
    case .success(let notes):
        Issue.record("expected .failure, got .success(\(notes))")
    case .failure(let error):
        guard case .invalidTiming = error else {
            Issue.record("expected .invalidTiming, got \(error)")
            return
        }
    }
}

@Test func testParseMalformedRejectedWhole() {
    // "60" alone — fewer than 3 required fields.
    let result = NoteSequenceParser.parse("60")
    switch result {
    case .success(let notes):
        Issue.record("expected .failure, got .success(\(notes))")
    case .failure(let error):
        guard case .malformed(let segment) = error else {
            Issue.record("expected .malformed, got \(error)")
            return
        }
        #expect(segment.contains("60"))
    }
}

@Test func testParseMixedValidInvalidWholeFails() {
    // One bad segment poisons the whole batch — strict whole-parse-fail.
    let result = NoteSequenceParser.parse("60,0,500;invalid;70,1000,500")
    switch result {
    case .success(let notes):
        Issue.record("expected .failure, got .success(\(notes))")
    case .failure:
        // Any failure variant acceptable; the contract is "whole batch fails".
        break
    }
}

@Test func testParseMultipleValidSegments() {
    let result = NoteSequenceParser.parse("60,0,500,127,1;72,1000,500,100,2")
    switch result {
    case .success(let notes):
        #expect(notes.count == 2)
        #expect(notes[0].pitch == 60)
        #expect(notes[0].channel == 0, "first note ch=1 → wire 0")
        #expect(notes[1].pitch == 72)
        #expect(notes[1].channel == 1, "second note ch=2 → wire 1")
    case .failure(let error):
        Issue.record("expected .success, got .failure(\(error))")
    }
}

// MARK: - Integration tests (12, 13)

@Test func testRecordSequenceCallSiteHandlesParserFailure() async {
    // Caller (TrackDispatcher.handleRecordSequenceSMF) must surface the new
    // .failure as a toolTextResult error including a hint string. We feed
    // ch=17 (invalid under 1-based) — under the OLD parser this would silently
    // skip the segment, leaving an empty event list and producing the legacy
    // "could not parse any valid notes" wording. Under the NEW parser the
    // .failure must propagate with the parser's error in the message.
    let cache = StateCache()
    await cache.updateDocumentState(true)
    let result = await TrackDispatcher.handle(
        command: "record_sequence",
        params: ["index": .int(0), "notes": .string("60,0,500,127,17")],
        router: ChannelRouter(),
        cache: cache
    )
    #expect(result.isError == true)
    let text = sharedToolText(result)
    // Hint must mention channel range so the LLM agent can self-correct.
    #expect(
        text.lowercased().contains("channel") || text.lowercased().contains("parse"),
        "expected parser error hint in record_sequence response, got: \(text)"
    )
}

@Test func testPlaySequenceCallSiteHandlesParserFailure() async {
    // CoreMIDIChannel.play_sequence must propagate .failure as a ChannelResult
    // .error. ch=0 is invalid under the new 1-based contract.
    //
    // play_sequence's parser guard runs *before* any engine call, so the
    // engine never gets exercised in this code path. We still need a real
    // CoreMIDIEngineProtocol conformer to construct the channel.
    let engine = MockCoreMIDIEngine()
    let channel = CoreMIDIChannel(engine: engine)
    let params: [String: String] = ["notes": "60,0,500,127,0"]
    let result = await channel.execute(operation: "midi.play_sequence", params: params)
    switch result {
    case .success:
        Issue.record("expected .error from invalid notes, got .success")
    case .error(let message):
        #expect(
            message.lowercased().contains("channel")
                || message.lowercased().contains("parse")
                || message.lowercased().contains("invalid")
                || message.contains("notes"),
            "expected parser error hint in play_sequence error, got: \(message)"
        )
    }
}

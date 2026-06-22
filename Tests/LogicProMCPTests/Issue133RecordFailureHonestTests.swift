import Foundation
import Testing
import MCP
@testable import LogicProMCP

// #133 — "live-record failure path leaves an invalid raw MP4".
//
// The capture-finalize side (the demo harness writing the .mp4) is handled
// elsewhere (re-homed in PR #124's helper). The SERVER-side contract that
// guards #133 is that `record_sequence` must FAIL CLOSED: when a record /
// import does not actually land a verified take, the result must be a typed,
// honest State-C error (`isError == true`, `success == false`, `verified ==
// false`) — never a bare/partial success the demo could mistake for a good
// take. A false success is exactly what let a failed live-record flow
// downstream and produce an invalid raw MP4.
//
// The existing TrackDispatcherRecordSequenceTests cover the
// `failure_stage: "midi.import_file"` branch (import channel returns an
// error, incl. the #140 dialog_not_found flag lift). These cases lock the two
// failure shapes those tests do NOT exercise:
//
//   1. PHANTOM SUCCESS — the import handler reports `.success` but live AX
//      shows no new-track delta (`failure_stage: "track_creation"`). This is
//      the most dangerous #133 shape: the import "succeeded" yet nothing
//      landed, so a naive caller would treat it as a good take.
//   2. A typed readback_mismatch import error must be lifted to the top-level
//      `import_error` and still read as a hard failure (no success leakage).

private actor Issue133MockChannel: Channel {
    nonisolated let id: ChannelID
    let importResult: ChannelResult

    init(id: ChannelID, importResult: ChannelResult) {
        self.id = id
        self.importResult = importResult
    }

    func start() async throws {}
    func stop() async {}

    func execute(operation: String, params: [String: String]) async -> ChannelResult {
        if operation == "midi.import_file" {
            return importResult
        }
        // transport.goto_position (playhead reset) is a precondition; succeed.
        return .success("ok")
    }

    func healthCheck() async -> ChannelHealth { .healthy(detail: "mock") }
}

private func issue133NoteSpec() -> Value {
    .string("60,0,500,100,1")
}

private func issue133JSONObject(_ result: CallTool.Result) -> [String: Any] {
    let text = sharedToolText(result)
    let data = Data(text.utf8)
    return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
}

@Test func testRecordSequenceFailsClosedOnPhantomTrackCreation() async throws {
    // Import handler claims success, but live AX never shows a new track
    // (track header count stays flat: 3 -> 3). Under #133 this must be a hard
    // typed failure routed through the `track_creation` stage — NOT a success,
    // because no take actually landed. If a future change let this path leak a
    // success (or drop the typed error), a failed live-record could again be
    // mistaken for a good take and finalize an invalid MP4.
    let cache = StateCache()
    await cache.updateDocumentState(true)

    let router = ChannelRouter()
    let ax = Issue133MockChannel(id: .accessibility, importResult: .success("imported"))
    await router.register(ax)

    let result = await TrackDispatcher.handleRecordSequenceSMF(
        params: [
            "notes": issue133NoteSpec(),
            "bar": .int(1),
        ],
        router: router,
        cache: cache,
        // Flat count: import "succeeded" but no track delta ever appears.
        trackHeaderCount: { 3 },
        trackNameAt: { _ in nil },
        readRegions: { .success([]) },
        settleReadback: {}
    )

    // Fail-closed: hard error, not a success the demo could finalize.
    let isError = try #require(result.isError)
    #expect(isError)

    let object = issue133JSONObject(result)
    let success = try #require(object["success"] as? Bool)
    #expect(!success)
    let verified = try #require(object["verified"] as? Bool)
    #expect(!verified)
    #expect(object["error"] as? String == "import_failure")
    #expect(object["failure_stage"] as? String == "track_creation")
    #expect(object["track_count_before"] as? Int == 3)
    #expect(object["track_count_after"] as? Int == 3)
    // The take never landed, so the success-only provenance fields must be
    // absent — their presence is what a caller keys off to treat a take as
    // good. Absence is the #133 tripwire.
    #expect(object["created_track"] == nil)
    #expect(object["verify_source"] == nil)
    #expect(object["recorded_to_track"] == nil)
}

@Test func testRecordSequenceFailsClosedOnReadbackMismatchImportError() async throws {
    // A different typed import failure than the dialog_not_found case already
    // covered: the import channel returns a readback_mismatch State C. The
    // dispatcher must lift the typed code to top-level `import_error` and still
    // present a hard failure — never absorb it into a success.
    let cache = StateCache()
    await cache.updateDocumentState(true)

    let importEnvelope = HonestContract.encodeStateC(
        error: .readbackMismatch,
        hint: "midi.import_file: imported region did not match expected payload",
        extras: [
            "requested": "/tmp/LogicProMCP/seq.mid",
            "missing_element": "imported_region",
        ]
    )

    let router = ChannelRouter()
    let ax = Issue133MockChannel(id: .accessibility, importResult: .error(importEnvelope))
    await router.register(ax)

    let result = await TrackDispatcher.handleRecordSequenceSMF(
        params: [
            "notes": issue133NoteSpec(),
            "bar": .int(1),
        ],
        router: router,
        cache: cache
    )

    let isError = try #require(result.isError)
    #expect(isError)

    let object = issue133JSONObject(result)
    let success = try #require(object["success"] as? Bool)
    #expect(!success)
    let verified = try #require(object["verified"] as? Bool)
    #expect(!verified)
    #expect(object["error"] as? String == "import_failure")
    #expect(object["failure_stage"] as? String == "midi.import_file")
    // Typed inner error is lifted, not swallowed.
    #expect(object["import_error"] as? String == "readback_mismatch")
    #expect(object["missing_element"] as? String == "imported_region")
    // No success-provenance leakage on a failed take.
    #expect(object["created_track"] == nil)
    #expect(object["verify_source"] == nil)
}

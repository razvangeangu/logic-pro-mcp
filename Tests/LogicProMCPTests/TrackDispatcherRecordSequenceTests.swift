import Foundation
import Testing
import MCP
@testable import LogicProMCP

// v3.1.2 P0-2 regression — record_sequence used to verify track creation by
// polling `cache.getTracks().count` for 2s. The StatePoller runs every 3s
// (ServerConfig.statePollingIntervalNs), so the cache literally could not
// reflect the new track inside the verification window — every successful
// import false-failed on the first call (witnessed live 3×).
//
// The fix moves verification to a direct AX read (`allTrackHeaders().count`),
// removing the cache from the verification critical path entirely. These
// tests cover the dispatcher's new error-message wording (so the cache-poll
// path can never silently regress back) and verify the cache contents do not
// influence the verification outcome.

private actor RecordingMockChannel: Channel {
    nonisolated let id: ChannelID
    var importCalls: Int = 0
    let importResult: ChannelResult

    init(id: ChannelID, importResult: ChannelResult) {
        self.id = id
        self.importResult = importResult
    }

    func start() async throws {}
    func stop() async {}

    func execute(operation: String, params: [String: String]) async -> ChannelResult {
        if operation == "midi.import_file" {
            importCalls += 1
            return importResult
        }
        // transport.goto_position is a precondition; succeed silently.
        return .success("ok")
    }

    func healthCheck() async -> ChannelHealth { .healthy(detail: "mock") }
}

private func minimalNoteSpec() -> Value {
    .string("60,0,500,100,1")
}

@Test func testRecordSequenceUsesLiveAXNotCache() async {
    // Pre-fill the cache with 2 tracks so that under the OLD cache-poll
    // verification, `tracksBefore = 2` and `tracksAfter` would also stay 2
    // (no live import in this test sandbox), producing the legacy
    // "new track never appeared" error within 2s.
    //
    // Under the NEW live-AX verification, the cache count is irrelevant —
    // verification reads AXLogicProElements.allTrackHeaders() directly. In a
    // headless sandbox that returns 0, so we expect the new error wording
    // ("live AX still shows N tracks") rather than the old wording. That
    // wording change is the regression tripwire: if anyone reverts the fix,
    // this test fails immediately.
    let cache = StateCache()
    await cache.updateTracks([
        TrackState(id: 0, name: "Old A", type: .softwareInstrument),
        TrackState(id: 1, name: "Old B", type: .softwareInstrument),
    ])
    // record_sequence requires hasDocument == true to even reach the AX
    // verification path; default is true but make the precondition explicit.
    await cache.updateDocumentState(true)

    let router = ChannelRouter()
    let ax = RecordingMockChannel(
        id: .accessibility,
        importResult: .success("imported")
    )
    await router.register(ax)

    let result = await TrackDispatcher.handleRecordSequenceSMF(
        params: [
            "notes": minimalNoteSpec(),
            "bar": .int(1),
        ],
        router: router,
        cache: cache
    )
    let text = sharedToolText(result)

    // Either the new error wording (sandbox path, AX returns 0 tracks) or a
    // success (would only happen if a real Logic Pro session is running
    // headlessly during the test — extremely unlikely on CI). Both prove the
    // cache count (which we seeded at 2) is no longer the verification
    // signal. The OLD code would have produced "tracks before: 2, after: 2".
    #expect(
        !text.contains("tracks before: 2, after: 2"),
        "regression: legacy cache-poll error wording must never resurface — got: \(text)"
    )
    #expect(
        text.contains("live AX") || text.contains("created_track"),
        "expected new live-AX error wording or a success payload, got: \(text)"
    )
}

@Test func testRecordSequenceRejectsImportFailureWithImportHandlerWording() async {
    // If the import channel itself fails (State C from AX), the dispatcher
    // must surface that error and never run the verification path. This
    // protects against a future regression where the verification logic
    // accidentally swallows the import failure.
    let cache = StateCache()
    await cache.updateDocumentState(true)

    let router = ChannelRouter()
    let ax = RecordingMockChannel(
        id: .accessibility,
        importResult: .error("State C: ax_write_failed")
    )
    await router.register(ax)

    let result = await TrackDispatcher.handleRecordSequenceSMF(
        params: [
            "notes": minimalNoteSpec(),
            "bar": .int(1),
        ],
        router: router,
        cache: cache
    )
    let text = sharedToolText(result)
    #expect(
        text.contains("midi.import_file"),
        "import-failure path must surface the import handler error, got: \(text)"
    )
}

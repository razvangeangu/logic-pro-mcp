import Foundation
import Testing
@testable import LogicProMCP

/// #110: project.save is an export/bounce prerequisite and must not report
/// success without read-back. `AppleScriptChannel.verifiedSaveResult` decides
/// the HC verdict from the front document's `.logicx` package mtime — the
/// authoritative file evidence — so a confirmed write is verified State A even
/// when `save front document` times out its AppleEvent reply (-1712).
@Suite("Issue110 save verification")
struct Issue110SaveVerifyTests {
    private func obj(_ r: ChannelResult) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(r.message.utf8))) as? [String: Any]
    }

    private let scriptOK = ChannelResult.success("{\"result\":\"\"}")
    private let scriptTimeout = ChannelResult.error("AppleScript error: AppleEvent timed out (-1712)")

    @Test("verified State A when the package mtime advances past the save start")
    func verifiedWhenWritten() {
        let started = Date()
        let result = AppleScriptChannel.verifiedSaveResult(
            scriptOK,
            documentPath: "/Users/x/Song.logicx",
            beforeMtime: started.addingTimeInterval(-60),
            afterMtime: started.addingTimeInterval(0.4),
            saveStartedAt: started
        )
        #expect(result.isSuccess)
        let o = obj(result)
        #expect(o?["verified"] as? Bool == true)
        #expect(o?["verify_source"] as? String == "file_mtime")
        #expect(o?["document_path"] as? String == "/Users/x/Song.logicx")
    }

    @Test("a -1712 reply timeout is still verified State A when the file was written")
    func timeoutButWrittenIsVerified() {
        let started = Date()
        let result = AppleScriptChannel.verifiedSaveResult(
            scriptTimeout, // save front document timed out its reply…
            documentPath: "/Users/x/Song.logicx",
            beforeMtime: started.addingTimeInterval(-60),
            afterMtime: started.addingTimeInterval(0.6), // …but the package was written
            saveStartedAt: started
        )
        #expect(result.isSuccess)
        #expect(obj(result)?["verified"] as? Bool == true)
    }

    @Test("errored script + no write surfaces the error verbatim (terminal)")
    func erroredAndNotWrittenFailsClosed() {
        let started = Date()
        let result = AppleScriptChannel.verifiedSaveResult(
            scriptTimeout,
            documentPath: "/Users/x/Song.logicx",
            beforeMtime: started.addingTimeInterval(-60),
            afterMtime: started.addingTimeInterval(-60), // unchanged
            saveStartedAt: started
        )
        #expect(!result.isSuccess)
        #expect(result.message.contains("1712"))
    }

    @Test("State B (no false success) when success but mtime did not advance")
    func successButNotWrittenIsStateB() {
        let started = Date()
        let result = AppleScriptChannel.verifiedSaveResult(
            scriptOK,
            documentPath: "/Users/x/Song.logicx",
            beforeMtime: started.addingTimeInterval(-60),
            afterMtime: started.addingTimeInterval(-60),
            saveStartedAt: started
        )
        #expect(result.isSuccess)
        #expect(obj(result)?["verified"] as? Bool == false)
    }

    @Test("untitled document (no path) stays an honest State B")
    func untitledStaysStateB() {
        let result = AppleScriptChannel.verifiedSaveResult(
            scriptOK, documentPath: nil, beforeMtime: nil, afterMtime: nil, saveStartedAt: Date()
        )
        #expect(result.isSuccess)
        let o = obj(result)
        #expect(o?["verified"] as? Bool == false)
        #expect((o?["reason_detail"] as? String)?.contains("untitled") == true)
    }
}

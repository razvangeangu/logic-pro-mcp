import Foundation
import Testing
@testable import LogicProMCP

actor AppleScriptRecorder {
    private var scripts: [String] = []
    private var result: ChannelResult = .success("{\"result\":\"OK\"}")

    func run(_ source: String) -> ChannelResult {
        scripts.append(source)
        return result
    }

    func setResult(_ result: ChannelResult) {
        self.result = result
    }

    func snapshot() -> [String] {
        scripts
    }
}

actor TransportActionRecorder {
    private var actions: [String] = []
    private var result: ChannelResult = .success("{\"result\":\"OK\"}")

    func run(_ action: String) -> ChannelResult {
        actions.append(action)
        return result
    }

    func setResult(_ result: ChannelResult) {
        self.result = result
    }

    func snapshot() -> [String] {
        actions
    }
}

final class OpenFileRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var openedPaths: [String] = []
    var result = true

    func open(_ path: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        openedPaths.append(path)
        return result
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return openedPaths
    }
}

private func makeAppleScriptRuntime(
    isRunning: Bool = true,
    scriptRecorder: AppleScriptRecorder = AppleScriptRecorder(),
    openRecorder: OpenFileRecorder = OpenFileRecorder(),
    transportRecorder: TransportActionRecorder = TransportActionRecorder(),
    fileExists: @escaping @Sendable (String) -> Bool = { _ in true },
    fileModificationDate: @escaping @Sendable (String) -> Date? = { _ in Date.distantFuture },
    currentDocumentPath: @escaping @Sendable () async -> String? = { nil }
) -> AppleScriptChannel.Runtime {
    AppleScriptChannel.Runtime(
        isLogicProRunning: { isRunning },
        openFile: { path in
            openRecorder.open(path)
        },
        runScript: { source in
            if !isRunning && source.contains("return name") {
                return .error("Logic Pro is not running")
            }
            return await scriptRecorder.run(source)
        },
        executeTransportAction: { action in
            await transportRecorder.run(action)
        },
        fileExists: fileExists,
        fileModificationDate: fileModificationDate,
        currentDocumentPath: currentDocumentPath
    )
}

@Test func testAppleScriptHealthReflectsRunningState() async {
    let available = AppleScriptChannel(runtime: makeAppleScriptRuntime(isRunning: true))
    let unavailable = AppleScriptChannel(runtime: makeAppleScriptRuntime(isRunning: false))

    let healthy = await available.healthCheck()
    #expect(healthy.available)
    #expect(healthy.detail == "AppleScript ready")

    let missing = await unavailable.healthCheck()
    #expect(missing.available == false)
    #expect(missing.detail.contains("not running"))
}

@Test func testAppleScriptUnsupportedOperationFails() async {
    let channel = AppleScriptChannel(runtime: makeAppleScriptRuntime())
    let result = await channel.execute(operation: "project.export", params: [:])
    #expect(!result.isSuccess)
    #expect(result.message.contains("Unsupported AppleScript operation"))
}

@Test func testAppleScriptProjectOpenRequiresPath() async {
    let channel = AppleScriptChannel(runtime: makeAppleScriptRuntime())
    let result = await channel.execute(operation: "project.open", params: [:])
    #expect(!result.isSuccess)
    #expect(result.message.contains("Missing 'path'"))
}

@Test func testAppleScriptProjectOpenUsesInjectedWorkspaceOpenResult() async {
    let openRecorder = OpenFileRecorder()
    let scriptRecorder = AppleScriptRecorder()
    let path = "/tmp/session.logicx"
    let channel = AppleScriptChannel(
        runtime: makeAppleScriptRuntime(
            scriptRecorder: scriptRecorder,
            openRecorder: openRecorder
        )
    )

    let opened = await channel.execute(operation: "project.open", params: ["path": path])
    #expect(opened.isSuccess)
    // v3.1.1 (P2-2) — successes from mutating ops are now wrapped in a
    // Honest Contract State B envelope (`verified:false /
    // readback_unavailable`). The legacy free-text "Opened: <path>" is
    // preserved inside `raw` for diagnostic continuity.
    #expect(opened.message.contains("\"success\":true"))
    #expect(opened.message.contains("\"verified\":false"))
    #expect(opened.message.contains("\"reason\":\"readback_unavailable\""))
    #expect(opened.message.contains("\"operation\":\"project.open\""))
    #expect(opened.message.contains("\"method\":\"applescript\""))
    #expect(opened.message.contains("Opened: \\/tmp\\/session.logicx"))
    #expect(openRecorder.snapshot() == [path])
    let scripts = await scriptRecorder.snapshot()
    #expect(scripts.count == 1)
    #expect(scripts[0].contains("path of front document as text"))
    #expect(scripts[0].contains(path))

    await scriptRecorder.setResult(.error("front document never changed"))
    let verifyFailed = await channel.execute(operation: "project.open", params: ["path": path])
    #expect(!verifyFailed.isSuccess)
    #expect(verifyFailed.message.contains("Failed to verify opened project"))
    #expect(verifyFailed.message.contains(path))

    openRecorder.result = false
    let failed = await channel.execute(operation: "project.open", params: ["path": path])
    #expect(!failed.isSuccess)
    #expect(failed.message == "Failed to open: \(path)")
}

@Test func testAppleScriptProjectOpenRetriesAfterClosingCurrentDocument() async {
    let openRecorder = OpenFileRecorder()
    let path = "/tmp/reopen.logicx"
    let channel = AppleScriptChannel(
        runtime: .init(
            isLogicProRunning: { true },
            openFile: { openRecorder.open($0) },
            runScript: { source in
                if source.contains("close front document") {
                    return .success("OK")
                }
                if source.contains("return path of front document as text") {
                    return .success("/tmp/other.logicx")
                }
                if source.contains("path of front document as text") {
                    return openRecorder.snapshot().count == 1
                        ? .error("front document never changed")
                        : .success("opened")
                }
                return .success("OK")
            },
            executeTransportAction: { _ in .success("OK") }
        )
    )

    let result = await channel.execute(operation: "project.open", params: ["path": path])
    #expect(result.isSuccess)
    // v3.1.1 (P2-2) — wrapped HC State B envelope; raw legacy text inside.
    #expect(result.message.contains("\"success\":true"))
    #expect(result.message.contains("\"verified\":false"))
    #expect(result.message.contains("\"operation\":\"project.open\""))
    #expect(result.message.contains("Opened: \\/tmp\\/reopen.logicx"))
    #expect(openRecorder.snapshot() == [path, path])
}

@Test func testAppleScriptProjectOpenDoesNotPreemptivelyCloseCurrentDocument() async {
    let openRecorder = OpenFileRecorder()
    let path = "/tmp/failed.logicx"
    let recorder = AppleScriptRecorder()
    await recorder.setResult(.error("Timed out waiting for Logic Pro to open the requested project"))
    let channel = AppleScriptChannel(
        runtime: .init(
            isLogicProRunning: { true },
            openFile: { openRecorder.open($0) },
            runScript: { source in
                if source.contains("return path of front document as text") {
                    return .success("")
                }
                return await recorder.run(source)
            },
            executeTransportAction: { _ in .success("OK") }
        )
    )

    let result = await channel.execute(operation: "project.open", params: ["path": path])
    #expect(!result.isSuccess)
    #expect(result.message.contains("Failed to verify opened project"))
    let scripts = await recorder.snapshot()
    #expect(!scripts.contains(where: { $0.contains("close front document") }))
}

@Test func testAppleScriptProjectOpenRestoresPreviousSavedProjectAfterRetryFailure() async {
    let openRecorder = OpenFileRecorder()
    let path = "/tmp/failed.logicx"
    let previous = "/tmp/previous.logicx"
    let recorder = AppleScriptRecorder()
    await recorder.setResult(.error("Timed out waiting for Logic Pro to open the requested project"))
    let channel = AppleScriptChannel(
        runtime: .init(
            isLogicProRunning: { true },
            openFile: { openRecorder.open($0) },
            runScript: { source in
                if source.contains("return path of front document as text") {
                    return .success(previous)
                }
                if source.contains("close front document") {
                    return .success("OK")
                }
                return await recorder.run(source)
            },
            executeTransportAction: { _ in .success("OK") }
        )
    )

    let result = await channel.execute(operation: "project.open", params: ["path": path])
    #expect(!result.isSuccess)
    #expect(openRecorder.snapshot() == [path, path, previous])
}

@Test func testAppleScriptProjectCommandsGenerateExpectedScripts() async {
    let recorder = AppleScriptRecorder()
    let channel = AppleScriptChannel(runtime: makeAppleScriptRuntime(scriptRecorder: recorder))

    let newProject = await channel.execute(operation: "project.new", params: [:])
    let saveProject = await channel.execute(operation: "project.save", params: [:])
    let saveAsProject = await channel.execute(
        operation: "project.save_as",
        params: ["path": "/tmp/export.logicx"]
    )
    let closeDefault = await channel.execute(operation: "project.close", params: [:])
    let closeAsk = await channel.execute(operation: "project.close", params: ["saving": "ask"])
    let closeNo = await channel.execute(operation: "project.close", params: ["saving": "no"])

    #expect(newProject.isSuccess)
    #expect(saveProject.isSuccess)
    #expect(saveAsProject.isSuccess)
    #expect(closeDefault.isSuccess)
    #expect(closeAsk.isSuccess)
    #expect(closeNo.isSuccess)

    let scripts = await recorder.snapshot()
    #expect(scripts.count == 6)
    #expect(scripts[0].contains("make new document"))
    #expect(scripts[0].contains("return name of newDocument"))
    #expect(scripts[1].contains("save front document"))
    #expect(scripts[2].contains("save front document in (POSIX file"))
    #expect(scripts[2].contains("/tmp/export.logicx"))
    #expect(scripts[3].contains("close front document saving yes"))
    #expect(scripts[4].contains("close front document saving ask"))
    #expect(scripts[5].contains("close front document saving no"))
}

@Test func testAppleScriptSaveAsReturnsVerifiedWhenPackageExists() async throws {
    let recorder = AppleScriptRecorder()
    let channel = AppleScriptChannel(
        runtime: makeAppleScriptRuntime(
            scriptRecorder: recorder,
            fileExists: { $0 == "/tmp/export.logicx" }
        )
    )

    let result = await channel.execute(
        operation: "project.save_as",
        params: ["path": "/tmp/export.logicx"]
    )

    #expect(result.isSuccess)
    let obj = try JSONSerialization.jsonObject(
        with: Data(result.message.utf8), options: []
    ) as! [String: Any]
    #expect((obj["success"] as? Bool)!)
    #expect((obj["verified"] as? Bool)!)
    #expect(obj["observed"] as? String == "/tmp/export.logicx")
}

@Test func testAppleScriptSaveAsErrorsWhenPackageMissingAfterScriptSuccess() async throws {
    let channel = AppleScriptChannel(
        runtime: makeAppleScriptRuntime(fileExists: { _ in false })
    )

    let result = await channel.execute(
        operation: "project.save_as",
        params: ["path": "/tmp/missing.logicx"]
    )

    #expect(!result.isSuccess)
    let obj = try JSONSerialization.jsonObject(
        with: Data(result.message.utf8), options: []
    ) as! [String: Any]
    #expect(!((obj["success"] as? Bool)!))
    #expect(obj["error"] as? String == "readback_mismatch")
}

@Test func testAppleScriptSaveAsErrorsWhenExistingPackageMtimeDoesNotAdvance() async throws {
    let staleDate = Date(timeIntervalSince1970: 1_000)
    let channel = AppleScriptChannel(
        runtime: makeAppleScriptRuntime(
            fileExists: { $0 == "/tmp/export.logicx" },
            fileModificationDate: { _ in staleDate }
        )
    )

    let result = await channel.execute(
        operation: "project.save_as",
        params: ["path": "/tmp/export.logicx"]
    )

    #expect(!result.isSuccess)
    let obj = try JSONSerialization.jsonObject(
        with: Data(result.message.utf8), options: []
    ) as! [String: Any]
    #expect(!((obj["success"] as? Bool)!))
    #expect(obj["error"] as? String == "readback_mismatch")
    #expect((obj["hint"] as? String)?.contains("modification time did not advance") == true)
    #expect(obj["observed"] as? String == "/tmp/export.logicx")
}

@Test func testAppleScriptTransportCommandsGenerateExpectedScripts() async {
    let recorder = TransportActionRecorder()
    let channel = AppleScriptChannel(runtime: makeAppleScriptRuntime(transportRecorder: recorder))

    let operations = [
        "transport.play": "play",
        "transport.stop": "stop",
        "transport.record": "record",
    ]

    for (operation, action) in operations {
        let result = await channel.execute(operation: operation, params: [:])
        #expect(result.isSuccess)
        let actions = await recorder.snapshot()
        #expect(actions.last == action)
    }
}

@Test func testAppleScriptTransportRejectsUnsupportedPauseCommand() async {
    let channel = AppleScriptChannel(runtime: makeAppleScriptRuntime())

    let pause = await channel.execute(operation: "transport.pause", params: [:])
    #expect(!pause.isSuccess)
    #expect(pause.message.contains("Unsupported AppleScript operation"))
}

@Test func testAppleScriptExecutePropagatesScriptErrors() async {
    let recorder = AppleScriptRecorder()
    await recorder.setResult(.error("AppleScript error: boom"))
    let channel = AppleScriptChannel(runtime: makeAppleScriptRuntime(scriptRecorder: recorder))

    let result = await channel.execute(operation: "project.save", params: [:])
    #expect(!result.isSuccess)
    #expect(result.message.contains("boom"))
}

@Test func testAppleScriptStartAndStopDoNotThrow() async throws {
    let channel = AppleScriptChannel(runtime: makeAppleScriptRuntime())
    try await channel.start()
    await channel.stop()
}

@Test func testAppleScriptEscapeJSONEscapesControlCharacters() {
    let escaped = AppleScriptChannel.escapeJSON("Quote\" Slash\\ New\nLine\rCarriage\tTab")
    #expect(escaped == "Quote\\\" Slash\\\\ New\\nLine\\rCarriage\\tTab")
}

@Test func testAppleScriptExecuteReturnsInjectedJSONResult() async {
    let recorder = AppleScriptRecorder()
    await recorder.setResult(.success("{\"result\":\"hello\"}"))
    let channel = AppleScriptChannel(runtime: makeAppleScriptRuntime(scriptRecorder: recorder))

    let result = await channel.execute(operation: "project.save", params: [:])

    #expect(result.isSuccess)
    // v3.1.1 (P2-2) — `project.save` is a mutating op so the response is now
    // wrapped in HC State B. The original `{"result":"hello"}` payload is
    // preserved verbatim inside the `raw` field of the envelope.
    #expect(result.message.contains("\"success\":true"))
    #expect(result.message.contains("\"verified\":false"))
    #expect(result.message.contains("\"operation\":\"project.save\""))
    #expect(result.message.contains("\"method\":\"applescript\""))
    #expect(result.message.contains("\"raw\":\"{\\\"result\\\":\\\"hello\\\"}\""))
}

@Test func testAppleScriptExecuteAppleScriptSurfacesCompileErrors() async {
    let result = await AppleScriptChannel.executeAppleScript("this is not valid AppleScript")
    #expect(!result.isSuccess)
    #expect(result.message.contains("AppleScript error"))
}

// MARK: - v3.1.8 (Issue #7) — currentDocumentPath static helper

@Test func testCurrentDocumentPath_parseEmpty_returnsNil() {
    let parsed = AppleScriptChannel.parseCurrentDocumentPath(
        from: .success("{\"result\":\"\"}")
    )
    #expect(parsed == nil)
}

@Test func testCurrentDocumentPath_parseTrimmed_returnsTrimmed() {
    let parsed = AppleScriptChannel.parseCurrentDocumentPath(
        from: .success("{\"result\":\"  /Users/x/A.logicx \\n\"}")
    )
    #expect(parsed == "/Users/x/A.logicx")
}

@Test func testCurrentDocumentPath_parseError_returnsNil() {
    let parsed = AppleScriptChannel.parseCurrentDocumentPath(
        from: .error("AppleScript error: TCC denied")
    )
    #expect(parsed == nil)
}

@Test func testCurrentDocumentPathScript_isStableShape() {
    let script = AppleScriptChannel.currentDocumentPathScript()
    #expect(script.contains("path of front document"))
    #expect(script.contains("count of documents"))
}

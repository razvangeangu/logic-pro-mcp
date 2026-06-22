import Foundation
import Testing
@testable import LogicProMCP

/// v3.1.1 (P2-2) — verify every mutating AppleScript op exits through the
/// Honest Contract State B envelope wrapper. Pre-3.1.1 returned plain
/// `{"result":"..."}` JSON which gave clients no way to distinguish
/// "verified" from "fire-and-forget"; the wire format now matches AX / MCU /
/// MIDI Key Commands.

private func parseEnvelope(_ message: String) -> [String: Any]? {
    guard let data = message.data(using: .utf8),
          let raw = try? JSONSerialization.jsonObject(with: data) else { return nil }
    return raw as? [String: Any]
}

/// Local copy of the file-private helper in AppleScriptChannelTests.swift.
/// Same shape — kept in lock-step. Centralising into AccessibilityTestSupport
/// would be a bigger refactor than the P2-2 patch warrants and the original
/// file's helper is `private` (not `internal`), so it cannot be reused.
private func makeAppleScriptRuntime(
    isRunning: Bool = true,
    scriptRecorder: AppleScriptRecorder = AppleScriptRecorder(),
    openRecorder: OpenFileRecorder = OpenFileRecorder(),
    transportRecorder: TransportActionRecorder = TransportActionRecorder(),
    currentDocumentPath: @escaping @Sendable () async -> String? = { nil }
) -> AppleScriptChannel.Runtime {
    AppleScriptChannel.Runtime(
        isLogicProRunning: { isRunning },
        openFile: { path in openRecorder.open(path) },
        runScript: { source in
            if !isRunning && source.contains("return name") {
                return .error("Logic Pro is not running")
            }
            return await scriptRecorder.run(source)
        },
        executeTransportAction: { action in
            await transportRecorder.run(action)
        },
        currentDocumentPath: currentDocumentPath
    )
}

@Test func testAppleScriptProjectNewReturnsHCEnvelope() async {
    let recorder = AppleScriptRecorder()
    await recorder.setResult(.success("{\"result\":\"Untitled\"}"))
    let channel = AppleScriptChannel(runtime: makeAppleScriptRuntime(scriptRecorder: recorder))

    let result = await channel.execute(operation: "project.new", params: [:])
    #expect(result.isSuccess)
    guard let env = parseEnvelope(result.message) else {
        Issue.record("response is not valid JSON")
        return
    }
    #expect((env["success"] as? Bool)!)
    #expect(!((env["verified"] as? Bool)!))
    #expect(env["reason"] as? String == "readback_unavailable")
    #expect(env["operation"] as? String == "project.new")
    #expect(env["method"] as? String == "applescript")
    #expect(env["raw"] as? String == "{\"result\":\"Untitled\"}")
}

@Test func testAppleScriptProjectCloseEnvelopeIncludesSavingExtra() async {
    let recorder = AppleScriptRecorder()
    let channel = AppleScriptChannel(runtime: makeAppleScriptRuntime(scriptRecorder: recorder))

    let result = await channel.execute(operation: "project.close", params: ["saving": "no"])
    #expect(result.isSuccess)
    guard let env = parseEnvelope(result.message) else {
        Issue.record("response is not valid JSON")
        return
    }
    #expect(env["operation"] as? String == "project.close")
    #expect(env["saving"] as? String == "no")
    #expect(!((env["verified"] as? Bool)!))
}

@Test func testAppleScriptTransportStopReturnsHCEnvelope() async {
    let transportRecorder = TransportActionRecorder()
    let channel = AppleScriptChannel(
        runtime: makeAppleScriptRuntime(transportRecorder: transportRecorder)
    )

    let result = await channel.execute(operation: "transport.stop", params: [:])
    #expect(result.isSuccess)
    guard let env = parseEnvelope(result.message) else {
        Issue.record("response is not valid JSON")
        return
    }
    #expect(env["operation"] as? String == "transport.stop")
    #expect(env["method"] as? String == "applescript")
    #expect(!((env["verified"] as? Bool)!))
}

@Test func testAppleScriptErrorPathStaysFreeText() async {
    // Errors must NOT be re-wrapped — the router treats `ChannelResult.error`
    // as the terminal failure signal and re-encoding into HC State C here
    // would break the existing terminal-state detector.
    let recorder = AppleScriptRecorder()
    await recorder.setResult(.error("AppleScript error: boom"))
    // #144: a titled (but non-existent on-disk) front document reaches the
    // script — its error surfaces verbatim with no mtime evidence — instead of
    // short-circuiting on the untitled fail-fast (which is its own typed State C).
    let channel = AppleScriptChannel(
        runtime: makeAppleScriptRuntime(
            scriptRecorder: recorder,
            currentDocumentPath: { "/Users/x/Song.logicx" }
        )
    )

    let result = await channel.execute(operation: "project.save", params: [:])
    #expect(!result.isSuccess)
    #expect(result.message.contains("boom"))
    // No HC envelope on the error path.
    #expect(parseEnvelope(result.message) == nil)
}

@Test func testAppleScriptWrapperSkipsAlreadyEnvelopedSuccess() async {
    // A future refactor may have a script body produce an HC envelope
    // directly. The wrapper must detect that and not double-wrap.
    let alreadyEnveloped = HonestContract.encodeStateA(extras: ["custom": "ok"])
    let recorder = AppleScriptRecorder()
    await recorder.setResult(.success(alreadyEnveloped))
    // #144: titled front document so the save reaches the script whose body
    // already produced an HC envelope; the untitled fail-fast must not preempt
    // the no-double-wrap passthrough being asserted here.
    let channel = AppleScriptChannel(
        runtime: makeAppleScriptRuntime(
            scriptRecorder: recorder,
            currentDocumentPath: { "/Users/x/Song.logicx" }
        )
    )

    let result = await channel.execute(operation: "project.save", params: [:])
    #expect(result.isSuccess)
    #expect(result.message == alreadyEnveloped, "must not double-wrap an HC envelope")
}

@Test func testHonestContractEnvelopeDetectorRecognisesAllStates() {
    let stateA = HonestContract.encodeStateA(extras: ["x": 1])
    let stateB = HonestContract.encodeStateB(reason: .readbackUnavailable)
    let stateC = HonestContract.encodeStateC(error: .axWriteFailed, hint: "nope")
    #expect(HonestContractEnvelopeDetector.isAlreadyEnvelope(stateA))
    #expect(HonestContractEnvelopeDetector.isAlreadyEnvelope(stateB))
    #expect(HonestContractEnvelopeDetector.isAlreadyEnvelope(stateC))
    #expect(!HonestContractEnvelopeDetector.isAlreadyEnvelope("plain text"))
    #expect(!HonestContractEnvelopeDetector.isAlreadyEnvelope("{\"result\":\"hello\"}"))
    #expect(!HonestContractEnvelopeDetector.isAlreadyEnvelope("{\"success\":true}"))
}

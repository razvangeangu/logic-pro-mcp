import Foundation
import MCP
import Testing
@testable import LogicProMCP

/// #112: the server-side command deadline turns a wedged/occluded Logic session
/// (AX ops blocking past the client tools/call timeout, stalling the stdio loop)
/// into a typed `operation_timeout` State C instead of a bare hang.
@Suite("Issue112 command deadline")
struct Issue112CommandDeadlineTests {
    private func text(_ result: CallTool.Result) -> String {
        if case .text(let t, _, _) = result.content.first { return t }
        return ""
    }

    private func json(_ result: CallTool.Result) -> [String: Any]? {
        guard let data = text(result).data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    @Test("fast work passes through unchanged")
    func fastWorkPassesThrough() async {
        let result = await LogicProServer.runWithDeadline(tool: "logic_transport", command: "stop", deadlineOverride: 5.0) {
            toolTextResult("{\"verified\":true,\"operation\":\"transport.stop\"}")
        }
        #expect(result.isError != true)
        #expect(json(result)?["verified"] as? Bool == true)
    }

    @Test("work that exceeds the deadline returns typed operation_timeout")
    func slowWorkTimesOut() async {
        let result = await LogicProServer.runWithDeadline(tool: "logic_tracks", command: "rename", deadlineOverride: 0.15) {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3s — far past the 0.15s deadline
            return toolTextResult("{\"verified\":true}") // must NOT win
        }
        #expect(result.isError == true)
        let obj = json(result)
        #expect(obj?["error"] as? String == "operation_timeout")
        #expect(obj?["operation"] as? String == "logic_tracks.rename")
        #expect(obj?["timeout_sec"] as? Double == 0.15)
        #expect((obj?["hint"] as? String)?.isEmpty == false)
    }

    @Test("operation_timeout is a terminal error code")
    func timeoutIsTerminal() {
        #expect(HonestContract.terminalErrorCodes.contains(HonestContract.FailureError.operationTimeout.rawValue))
        #expect(HonestContract.FailureError.operationTimeout.rawValue == "operation_timeout")
    }

    @Test("deadline tiers: fast commands short, long/medium commands generous")
    func deadlineTiers() {
        // Fast tier — far above the sub-second healthy completion time.
        #expect(LogicProServer.commandDeadlineSeconds(tool: "logic_transport", command: "stop") == 25)
        #expect(LogicProServer.commandDeadlineSeconds(tool: "logic_mixer", command: "set_volume") == 25)
        #expect(LogicProServer.commandDeadlineSeconds(tool: "logic_tracks", command: "mute") == 25)
        // Long tier — full Library walks / SMF import / guarded export.
        #expect(LogicProServer.commandDeadlineSeconds(tool: "logic_tracks", command: "scan_library") == 300)
        #expect(LogicProServer.commandDeadlineSeconds(tool: "logic_midi", command: "import_file") == 300)
        #expect(LogicProServer.commandDeadlineSeconds(tool: "logic_project", command: "bounce") == 300)
        // Medium tier — multi-step menu/library navigation.
        #expect(LogicProServer.commandDeadlineSeconds(tool: "logic_tracks", command: "set_instrument") == 90)
        #expect(LogicProServer.commandDeadlineSeconds(tool: "logic_plugins", command: "insert_verified") == 90)
    }

    @Test("the deadline timeout result is shaped like a State C envelope")
    func timeoutResultShape() {
        let result = LogicProServer.deadlineTimeoutResult(tool: "logic_navigate", command: "create_marker", seconds: 25)
        #expect(result.isError == true)
        let obj = json(result)
        #expect(obj?["success"] as? Bool == false)
        #expect(obj?["error"] as? String == "operation_timeout")
        #expect(obj?["operation"] as? String == "logic_navigate.create_marker")
    }
}

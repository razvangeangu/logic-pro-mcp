import Foundation
import MCP
import Testing
@testable import LogicProMCP

// H-1 (2026-05-08 enterprise review): pre-fix `ProjectDispatcher.handle`
// emitted `[AUDIT] project.<command> executed` before parameter
// validation, before the destructive-confirmation gate, and before any
// route was attempted. Enterprise audit pipelines treated rejected calls
// the same as successful executions.
//
// The fix splits the audit signal into three machine-filterable phases:
//   - `rejected` — validation refused the call (no side effect)
//   - `confirmation_required` — destructive policy gated, awaiting confirm
//   - `executed` — route was actually invoked
//
// These tests pin each phase by injecting `Log.output` and grepping the
// captured stderr stream for the exact `[AUDIT]` substring. Helper
// `captureAuditLines` filters down to the `project` subsystem so other
// log noise (e.g. cache invalidation `INFO`) doesn't leak into the
// assertion.
//
// v3.4.1 (CI hotfix): the entire suite is `@Suite(.serialized)` and the
// capture is **synchronous lock-guarded** (not actor-based fire-and-forget).
// Pre-fix the suite used `Task { await capture.append(line) }` for each
// log line and a 30 ms post-test sleep to drain pending Tasks. Under
// parallel `swift test` on macos-15 / Xcode 16.4 runners, the 30 ms drain
// was insufficient — three tests' Task chains could outrun snapshot, plus
// `Log.output` is a static mutation that races between concurrent suites.
// `.serialized` gives single-test ordering within this suite; the lock
// gives ordering within a single test's emit chain. Together they make
// the suite robust to runner timing.

private final class AuditCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    func append(_ s: String) {
        lock.lock(); defer { lock.unlock() }
        lines.append(s)
    }
    func snapshot() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return lines
    }
}

@MainActor
private func captureAuditLines(during body: () async -> Void) async -> [String] {
    let capture = AuditCapture()
    let previousOutput = Log.output
    let previousLevel = Log.minLevel

    // Coverage runs gate at INFO by default; force-set so all three phases emit.
    Log.setLevel(.info)
    Log.output = { line in
        // We only care about [AUDIT] lines on the project subsystem.
        // Synchronous capture — no Task hop — so the line is recorded
        // before `Log.info(...)` returns. This eliminates the race where
        // a fire-and-forget Task could land after the test's snapshot.
        if line.contains("[AUDIT]") {
            capture.append(line)
        }
    }
    defer {
        Log.output = previousOutput
        Log.setLevel(previousLevel)
        Log.resetForTests()
    }

    Log.resetForTests()
    await body()
    return capture.snapshot()
}

private func projectAudits(_ lines: [String]) -> [String] {
    lines.filter { $0.contains("[project]") || $0.contains("\"subsystem\":\"project\"") }
}

@Suite(.serialized)
struct ProjectAuditPhaseTests {

@Test func testProjectOpenWithMissingPathLogsRejected() async {
    let captured = await captureAuditLines {
        let result = await ProjectDispatcher.handle(
            command: "open",
            params: [:],
            router: ChannelRouter(),
            cache: StateCache()
        )
        #expect(result.isError == true)
    }
    let audits = projectAudits(captured)
    #expect(audits.contains { $0.contains("project.open rejected") })
    #expect(!audits.contains { $0.contains("project.open executed") })
}

@Test func testProjectOpenWithInvalidPathLogsRejected() async {
    let captured = await captureAuditLines {
        let result = await ProjectDispatcher.handle(
            command: "open",
            params: ["path": .string("/tmp/nonexistent.logicx")],
            router: ChannelRouter(),
            cache: StateCache()
        )
        #expect(result.isError == true)
    }
    let audits = projectAudits(captured)
    #expect(audits.contains { $0.contains("project.open rejected") })
    #expect(!audits.contains { $0.contains("project.open executed") })
}

@Test func testProjectOpenWithoutConfirmLogsConfirmationRequired() async throws {
    // Use a path that passes the existing-package safety check. open
    // requires confirmation by destructive policy, so without `confirmed:true`
    // the dispatcher should emit `confirmation_required` and NOT `executed`.
    // `AppleScriptSafety.isValidExistingProjectPackage` requires a `.logicx`
    // directory containing `Resources/ProjectInformation.plist` and at
    // least one `Alternatives/*/ProjectData` file.
    let fm = FileManager.default
    let tmpDir = fm.temporaryDirectory
        .appendingPathComponent("audit-confirm-\(UUID().uuidString).logicx")
    let resourcesDir = tmpDir.appendingPathComponent("Resources", isDirectory: true)
    let altDir = tmpDir.appendingPathComponent("Alternatives", isDirectory: true)
        .appendingPathComponent("000", isDirectory: true)
    try fm.createDirectory(at: resourcesDir, withIntermediateDirectories: true)
    try fm.createDirectory(at: altDir, withIntermediateDirectories: true)
    try Data().write(to: resourcesDir.appendingPathComponent("ProjectInformation.plist"))
    try Data().write(to: altDir.appendingPathComponent("ProjectData"))
    defer { try? fm.removeItem(at: tmpDir) }

    let captured = await captureAuditLines {
        _ = await ProjectDispatcher.handle(
            command: "open",
            params: ["path": .string(tmpDir.path)],
            router: ChannelRouter(),
            cache: StateCache()
        )
    }
    let audits = projectAudits(captured)
    #expect(audits.contains { $0.contains("project.open confirmation_required") })
    #expect(!audits.contains { $0.contains("project.open executed") })
    #expect(!audits.contains { $0.contains("project.open rejected") })
}

@Test func testProjectSaveAlwaysLogsExecuted() async {
    // `save` has no validation gate, no confirmation requirement → goes
    // straight to executed.
    let captured = await captureAuditLines {
        _ = await ProjectDispatcher.handle(
            command: "save",
            params: [:],
            router: ChannelRouter(),
            cache: StateCache()
        )
    }
    let audits = projectAudits(captured)
    #expect(audits.contains { $0.contains("project.save executed") })
    #expect(!audits.contains { $0.contains("project.save rejected") })
    #expect(!audits.contains { $0.contains("project.save confirmation_required") })
}

@Test func testProjectIsRunningEmitsNoAuditLine() async {
    // L0 read-only commands must NOT pollute the audit log.
    let captured = await captureAuditLines {
        _ = await ProjectDispatcher.handle(
            command: "is_running",
            params: [:],
            router: ChannelRouter(),
            cache: StateCache(),
            isLogicProRunning: { false }
        )
    }
    let audits = projectAudits(captured)
    #expect(audits.allSatisfy { !$0.contains("project.is_running") })
}

@Test func testProjectQuitWithoutConfirmLogsConfirmationRequired() async {
    let captured = await captureAuditLines {
        _ = await ProjectDispatcher.handle(
            command: "quit",
            params: [:],
            router: ChannelRouter(),
            cache: StateCache(),
            isLogicProRunning: { true }
        )
    }
    let audits = projectAudits(captured)
    #expect(audits.contains { $0.contains("project.quit confirmation_required") })
    #expect(!audits.contains { $0.contains("project.quit executed") })
}

}  // end @Suite(.serialized) struct ProjectAuditPhaseTests

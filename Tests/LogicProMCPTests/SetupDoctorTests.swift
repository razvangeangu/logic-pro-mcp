import Foundation
import Testing
@testable import LogicProMCP

private actor DoctorMockMainServer: ServerStarting {
    func start() async throws {}
}

private func doctorRuntime(
    executablePath: String? = "/usr/local/bin/LogicProMCP",
    exists: Bool = true,
    executable: Bool = true,
    logicRunning: Bool = true,
    visibleWindow: Bool = true,
    commandHandler: @escaping (String, [String]) -> SetupDoctor.CommandOutput? = { executable, arguments in
        if executable == "/usr/bin/codesign" {
            return .init(exitCode: 0, stdout: "", stderr: "")
        }
        if executable == "/usr/bin/xattr" {
            return .init(exitCode: 1, stdout: "", stderr: "No such xattr")
        }
        if executable == "/usr/bin/env", arguments == ["claude", "mcp", "list"] {
            return .init(exitCode: 0, stdout: "logic-pro  LogicProMCP\n", stderr: "")
        }
        if executable == "/usr/bin/env", arguments == ["brew", "list", "--versions", "logic-pro-mcp"] {
            return .init(exitCode: 0, stdout: "logic-pro-mcp 3.6.0\n", stderr: "")
        }
        return nil
    }
) -> SetupDoctor.Runtime {
    SetupDoctor.Runtime(
        resolveExecutablePath: { _ in executablePath },
        fileExists: { _ in exists },
        isExecutableFile: { _ in executable },
        logicProRunning: { logicRunning },
        logicProHasVisibleWindow: { visibleWindow },
        runCommand: commandHandler
    )
}

private func allApprovals() -> [ManualValidationChannel: ManualValidationApproval] {
    Dictionary(uniqueKeysWithValues: ManualValidationChannel.allCases.map {
        ($0, ManualValidationApproval(approvedAt: Date(timeIntervalSince1970: 0), note: "test"))
    })
}

private func issue26RepositoryRootURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

@Test func testSetupDoctorJSONContractStableCheckIDsAndOKAggregation() throws {
    let report = SetupDoctor.generate(
        arguments: ["LogicProMCP", "doctor", "--json"],
        permissionStatus: .init(accessibility: true, automationLogicPro: true),
        approvals: allApprovals(),
        runtime: doctorRuntime()
    )

    #expect(report.schema == "logic_pro_mcp_doctor.v1")
    #expect(report.status == .ok)
    #expect(report.installSource == .homebrew)

    let ids = report.checks.map(\.id)
    #expect(ids == [
        "binary.path",
        "binary.executable",
        "binary.version",
        "install.source",
        "release.signature",
        "release.quarantine",
        "mcp.claude_code_registration",
        "permissions.accessibility",
        "permissions.automation_logic_pro",
        "logic.application_state",
        "channels.manual_validation",
    ])

    let json = encodeJSON(report)
    let object = try #require(sharedJSONObject(json))
    #expect(object["schema"] as? String == "logic_pro_mcp_doctor.v1")
    #expect(object["status"] as? String == "ok")
    #expect(object["install_source"] as? String == "homebrew")
    #expect((object["checks"] as? [[String: Any]])?.count == ids.count)
}

@Test func testSetupDoctorReportsActionableRemediationForNonPassStates() {
    let report = SetupDoctor.generate(
        arguments: ["LogicProMCP", "doctor", "--json"],
        permissionStatus: .init(accessibilityState: .notGranted, automationState: .notVerifiable),
        approvals: [:],
        runtime: doctorRuntime(
            executablePath: nil,
            exists: false,
            executable: false,
            logicRunning: false,
            visibleWindow: false,
            commandHandler: { _, _ in nil }
        )
    )

    #expect(report.status == .failed)
    for check in report.checks where check.status != .pass {
        #expect(check.remediation.type != .none, "\(check.id) has no remediation type")
        #expect(!check.remediation.value.isEmpty, "\(check.id) has no remediation value")
    }
}

@Test func testMainEntrypointDoctorJSONDoesNotStartServerAndWritesStdout() async throws {
    let store = ManualValidationStore(
        fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("doctor-cli-\(UUID().uuidString)")
            .appendingPathExtension("json")
    )
    try await store.approve(.midiKeyCommands, note: "test")
    try await store.approve(.scripter, note: "test")

    var stdout = ""
    var stderr = ""
    let exitCode = await MainEntrypoint.run(
        arguments: ["LogicProMCP", "doctor", "--json"],
        permissionCheck: { .init(accessibility: true, automationLogicPro: true) },
        serverFactory: {
            Issue.record("Server should not start for doctor")
            return DoctorMockMainServer()
        },
        approvalStoreFactory: { store },
        doctorRuntime: doctorRuntime(),
        writeStdout: { stdout += $0 },
        writeStderr: { stderr += $0 }
    )

    #expect(exitCode == 0)
    #expect(stderr.isEmpty)
    let json = try #require(sharedJSONObject(stdout))
    #expect(json["schema"] as? String == "logic_pro_mcp_doctor.v1")
    #expect(json["status"] as? String == "ok")
}

@Test func testMainEntrypointDoctorHumanOutputIncludesStableIDs() async {
    var stdout = ""
    let exitCode = await MainEntrypoint.run(
        arguments: ["LogicProMCP", "doctor"],
        permissionCheck: { .init(accessibility: true, automationLogicPro: true) },
        serverFactory: { DoctorMockMainServer() },
        approvalStoreFactory: {
            ManualValidationStore(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("doctor-human-\(UUID().uuidString)")
                    .appendingPathExtension("json")
            )
        },
        doctorRuntime: doctorRuntime(),
        writeStdout: { stdout += $0 },
        writeStderr: { _ in }
    )

    #expect(exitCode == 0)
    #expect(stdout.contains("Logic Pro MCP doctor"))
    #expect(stdout.contains("binary.path"))
    #expect(stdout.contains("mcp.claude_code_registration"))
}

@Test func testSetupDocsContainEveryDoctorRemediationAnchor() throws {
    let setup = try String(
        contentsOf: issue26RepositoryRootURL().appendingPathComponent("docs/SETUP.md"),
        encoding: .utf8
    )

    for anchor in SetupDoctor.remediationAnchorsByCheckID.values.sorted() {
        let id = anchor.replacingOccurrences(of: "docs/SETUP.md#", with: "")
        #expect(setup.contains("id=\"\(id)\""), "Missing remediation anchor \(anchor)")
    }
}

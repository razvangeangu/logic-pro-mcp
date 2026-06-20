import Darwin
import Foundation

enum SetupDoctor {
    enum CheckStatus: String, Codable, Sendable {
        case pass
        case warn
        case fail
        case manual
        case skipped
    }

    enum ReportStatus: String, Codable, Sendable {
        case ok
        case degraded
        case failed
        case manualActionRequired = "manual_action_required"
    }

    enum InstallSource: String, Codable, Sendable {
        case homebrew
        case releaseBinary = "release_binary"
        case sourceBuild = "source_build"
        case unknown
    }

    enum RemediationType: String, Codable, Sendable {
        case command
        case docs
        case systemSettings = "system_settings"
        case manual
        case none
    }

    struct Remediation: Codable, Equatable, Sendable {
        let type: RemediationType
        let value: String
    }

    struct Check: Codable, Equatable, Sendable {
        let id: String
        let domain: String
        let status: CheckStatus
        let summary: String
        let evidence: [String: String]
        let remediation: Remediation
    }

    struct Report: Codable, Equatable, Sendable {
        let schema: String
        let status: ReportStatus
        let version: String
        let installSource: InstallSource
        let checks: [Check]

        enum CodingKeys: String, CodingKey {
            case schema
            case status
            case version
            case installSource = "install_source"
            case checks
        }
    }

    struct CommandOutput: Equatable, Sendable {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    struct Runtime: @unchecked Sendable {
        let resolveExecutablePath: (String?) -> String?
        let fileExists: (String) -> Bool
        let isExecutableFile: (String) -> Bool
        let logicProRunning: () -> Bool
        let logicProHasVisibleWindow: () -> Bool
        let runCommand: (String, [String]) -> CommandOutput?

        static let production = Runtime(
            resolveExecutablePath: { raw in
                resolveProductionExecutablePath(raw)
            },
            fileExists: { path in
                FileManager.default.fileExists(atPath: path)
            },
            isExecutableFile: { path in
                FileManager.default.isExecutableFile(atPath: path)
            },
            logicProRunning: {
                ProcessUtils.isLogicProRunning
            },
            logicProHasVisibleWindow: {
                ProcessUtils.hasVisibleWindow()
            },
            runCommand: { executable, arguments in
                runProductionCommand(executable: executable, arguments: arguments, timeout: 1.5)
            }
        )
    }

    static let schema = "logic_pro_mcp_doctor.v1"

    static let remediationAnchorsByCheckID: [String: String] = [
        "binary.path": "docs/SETUP.md#doctor-binarypath",
        "binary.executable": "docs/SETUP.md#doctor-binaryexecutable",
        "binary.version": "docs/SETUP.md#doctor-binaryversion",
        "install.source": "docs/SETUP.md#doctor-installsource",
        "release.signature": "docs/SETUP.md#doctor-releasesignature",
        "release.quarantine": "docs/SETUP.md#doctor-releasequarantine",
        "mcp.claude_code_registration": "docs/SETUP.md#doctor-mcpclaude-code-registration",
        "permissions.accessibility": "docs/SETUP.md#doctor-permissionsaccessibility",
        "permissions.automation_logic_pro": "docs/SETUP.md#doctor-permissionsautomation-logic-pro",
        "logic.application_state": "docs/SETUP.md#doctor-logicapplication-state",
        "channels.manual_validation": "docs/SETUP.md#doctor-channelsmanual-validation",
    ]

    static func generate(
        arguments: [String],
        permissionStatus: PermissionChecker.PermissionStatus,
        approvals: [ManualValidationChannel: ManualValidationApproval],
        runtime: Runtime = .production
    ) -> Report {
        let executablePath = runtime.resolveExecutablePath(arguments.first)
        let installSource = detectInstallSource(executablePath: executablePath, runtime: runtime)
        var checks: [Check] = []

        checks.append(binaryPathCheck(executablePath: executablePath, runtime: runtime))
        checks.append(binaryExecutableCheck(executablePath: executablePath, runtime: runtime))
        checks.append(binaryVersionCheck())
        checks.append(installSourceCheck(installSource: installSource, executablePath: executablePath))
        checks.append(releaseSignatureCheck(executablePath: executablePath, runtime: runtime))
        checks.append(releaseQuarantineCheck(executablePath: executablePath, runtime: runtime))
        checks.append(claudeRegistrationCheck(runtime: runtime))
        checks.append(accessibilityPermissionCheck(permissionStatus))
        checks.append(automationPermissionCheck(permissionStatus))
        checks.append(logicApplicationStateCheck(runtime: runtime))
        checks.append(manualValidationCheck(approvals: approvals))

        return Report(
            schema: schema,
            status: aggregateStatus(checks),
            version: ServerConfig.serverVersion,
            installSource: installSource,
            checks: checks
        )
    }

    static func renderHuman(_ report: Report) -> String {
        var lines: [String] = [
            "Logic Pro MCP doctor",
            "schema: \(report.schema)",
            "status: \(report.status.rawValue)",
            "version: \(report.version)",
            "install_source: \(report.installSource.rawValue)",
            "",
        ]
        for check in report.checks {
            lines.append("[\(check.status.rawValue)] \(check.id) - \(check.summary)")
            if check.remediation.type != .none {
                lines.append("  remediation: \(check.remediation.value)")
            }
        }
        return lines.joined(separator: "\n")
    }

    static func shouldExitWithFailure(_ report: Report) -> Bool {
        report.status == .failed
    }

    private static func aggregateStatus(_ checks: [Check]) -> ReportStatus {
        if checks.contains(where: { $0.status == .fail }) {
            return .failed
        }
        if checks.contains(where: { $0.status == .manual }) {
            return .manualActionRequired
        }
        if checks.contains(where: { $0.status == .warn || $0.status == .skipped }) {
            return .degraded
        }
        return .ok
    }

    private static func binaryPathCheck(executablePath: String?, runtime: Runtime) -> Check {
        guard let executablePath, runtime.fileExists(executablePath) else {
            return check(
                id: "binary.path",
                domain: "binary",
                status: .fail,
                summary: "LogicProMCP binary could not be resolved from argv0 or PATH.",
                evidence: ["argv0_resolved": executablePath ?? "<nil>"],
                remediationType: .docs
            )
        }
        return check(
            id: "binary.path",
            domain: "binary",
            status: .pass,
            summary: "LogicProMCP binary path resolved.",
            evidence: ["path": executablePath],
            remediationType: .none
        )
    }

    private static func binaryExecutableCheck(executablePath: String?, runtime: Runtime) -> Check {
        guard let executablePath, runtime.fileExists(executablePath) else {
            return check(
                id: "binary.executable",
                domain: "binary",
                status: .skipped,
                summary: "Executable bit could not be checked because the binary path is missing.",
                evidence: [:],
                remediationType: .docs
            )
        }
        let executable = runtime.isExecutableFile(executablePath)
        return check(
            id: "binary.executable",
            domain: "binary",
            status: executable ? .pass : .fail,
            summary: executable ? "Binary has executable permission." : "Binary is not executable.",
            evidence: ["path": executablePath, "executable": String(executable)],
            remediationType: executable ? .none : .command,
            remediationValueOverride: executable ? nil : "chmod +x \(executablePath)"
        )
    }

    private static func binaryVersionCheck() -> Check {
        check(
            id: "binary.version",
            domain: "binary",
            status: ServerConfig.serverVersion.isEmpty ? .fail : .pass,
            summary: "Server version is available.",
            evidence: ["version": ServerConfig.serverVersion],
            remediationType: ServerConfig.serverVersion.isEmpty ? .docs : .none
        )
    }

    private static func installSourceCheck(installSource: InstallSource, executablePath: String?) -> Check {
        let status: CheckStatus = installSource == .unknown ? .warn : .pass
        return check(
            id: "install.source",
            domain: "install",
            status: status,
            summary: installSource == .unknown ? "Install source is unknown or manual." : "Install source detected as \(installSource.rawValue).",
            evidence: ["install_source": installSource.rawValue, "path": executablePath ?? "<nil>"],
            remediationType: installSource == .unknown ? .docs : .none
        )
    }

    private static func releaseSignatureCheck(executablePath: String?, runtime: Runtime) -> Check {
        guard let executablePath, runtime.fileExists(executablePath) else {
            return check(
                id: "release.signature",
                domain: "release",
                status: .skipped,
                summary: "Signature verification skipped because the binary path is missing.",
                evidence: [:],
                remediationType: .docs
            )
        }
        guard let output = runtime.runCommand("/usr/bin/codesign", ["--verify", "--strict", "--verbose=2", executablePath]) else {
            return check(
                id: "release.signature",
                domain: "release",
                status: .warn,
                summary: "codesign verification could not be executed.",
                evidence: ["path": executablePath],
                remediationType: .docs
            )
        }
        return check(
            id: "release.signature",
            domain: "release",
            status: output.exitCode == 0 ? .pass : .warn,
            summary: output.exitCode == 0 ? "Binary signature verifies." : "Binary signature did not verify.",
            evidence: [
                "path": executablePath,
                "exit_code": String(output.exitCode),
                "stderr": output.stderr.trimmingCharacters(in: .whitespacesAndNewlines),
            ],
            remediationType: output.exitCode == 0 ? .none : .docs
        )
    }

    private static func releaseQuarantineCheck(executablePath: String?, runtime: Runtime) -> Check {
        guard let executablePath, runtime.fileExists(executablePath) else {
            return check(
                id: "release.quarantine",
                domain: "release",
                status: .skipped,
                summary: "Quarantine check skipped because the binary path is missing.",
                evidence: [:],
                remediationType: .docs
            )
        }
        guard let output = runtime.runCommand("/usr/bin/xattr", ["-p", "com.apple.quarantine", executablePath]) else {
            return check(
                id: "release.quarantine",
                domain: "release",
                status: .warn,
                summary: "xattr quarantine check could not be executed.",
                evidence: ["path": executablePath],
                remediationType: .docs
            )
        }
        let quarantined = output.exitCode == 0
        return check(
            id: "release.quarantine",
            domain: "release",
            status: quarantined ? .warn : .pass,
            summary: quarantined ? "Binary has a macOS quarantine attribute." : "Binary is not quarantined.",
            evidence: ["path": executablePath, "quarantined": String(quarantined)],
            remediationType: quarantined ? .command : .none,
            remediationValueOverride: quarantined ? "xattr -d com.apple.quarantine \(executablePath)" : nil
        )
    }

    private static func claudeRegistrationCheck(runtime: Runtime) -> Check {
        guard let output = runtime.runCommand("/usr/bin/env", ["claude", "mcp", "list"]) else {
            return check(
                id: "mcp.claude_code_registration",
                domain: "mcp",
                status: .manual,
                summary: "Claude Code registration could not be checked because the Claude CLI was not available.",
                evidence: [:],
                remediationType: .manual
            )
        }
        let combined = "\(output.stdout)\n\(output.stderr)"
        let registered = output.exitCode == 0
            && combined.localizedCaseInsensitiveContains("logic-pro")
            && combined.localizedCaseInsensitiveContains("LogicProMCP")
        return check(
            id: "mcp.claude_code_registration",
            domain: "mcp",
            status: registered ? .pass : .warn,
            summary: registered ? "Claude Code MCP registration found." : "Claude Code MCP registration was not found.",
            evidence: ["exit_code": String(output.exitCode)],
            remediationType: registered ? .none : .command,
            remediationValueOverride: registered ? nil : "claude mcp add --scope user logic-pro -- LogicProMCP"
        )
    }

    private static func accessibilityPermissionCheck(_ status: PermissionChecker.PermissionStatus) -> Check {
        check(
            id: "permissions.accessibility",
            domain: "permissions",
            status: status.accessibility ? .pass : .fail,
            summary: status.accessibility ? "Accessibility permission is granted." : "Accessibility permission is not granted.",
            evidence: ["state": status.accessibilityState.rawValue],
            remediationType: status.accessibility ? .none : .systemSettings
        )
    }

    private static func automationPermissionCheck(_ status: PermissionChecker.PermissionStatus) -> Check {
        let checkStatus: CheckStatus
        switch status.automationState {
        case .granted:
            checkStatus = .pass
        case .notGranted:
            checkStatus = .fail
        case .notVerifiable:
            checkStatus = .manual
        }
        return check(
            id: "permissions.automation_logic_pro",
            domain: "permissions",
            status: checkStatus,
            summary: automationSummary(for: status.automationState),
            evidence: ["state": status.automationState.rawValue],
            remediationType: status.automationState == .granted ? .none : .systemSettings
        )
    }

    private static func logicApplicationStateCheck(runtime: Runtime) -> Check {
        let running = runtime.logicProRunning()
        let visible = running && runtime.logicProHasVisibleWindow()
        let status: CheckStatus = running ? (visible ? .pass : .warn) : .manual
        return check(
            id: "logic.application_state",
            domain: "logic",
            status: status,
            summary: logicApplicationSummary(running: running, visible: visible),
            evidence: ["running": String(running), "visible_window": String(visible)],
            remediationType: running ? (visible ? .none : .manual) : .manual
        )
    }

    private static func manualValidationCheck(approvals: [ManualValidationChannel: ManualValidationApproval]) -> Check {
        let missing = ManualValidationChannel.allCases
            .filter { approvals[$0] == nil }
            .map(\.rawValue)
        return check(
            id: "channels.manual_validation",
            domain: "channels",
            status: missing.isEmpty ? .pass : .manual,
            summary: missing.isEmpty
                ? "Manual-validation channels have operator approvals."
                : "Manual-validation channels need operator approval or an explicit decision to skip.",
            evidence: ["missing": missing.joined(separator: ",")],
            remediationType: missing.isEmpty ? .none : .command,
            remediationValueOverride: missing.isEmpty ? nil : "LogicProMCP --approve-channel MIDIKeyCommands && LogicProMCP --approve-channel Scripter"
        )
    }

    private static func detectInstallSource(executablePath: String?, runtime: Runtime) -> InstallSource {
        if let executablePath, executablePath.contains("/.build/") || executablePath.contains(".build/") {
            return .sourceBuild
        }

        if let brew = runtime.runCommand("/usr/bin/env", ["brew", "list", "--versions", "logic-pro-mcp"]),
           brew.exitCode == 0,
           brew.stdout.contains("logic-pro-mcp") {
            return .homebrew
        }

        guard let executablePath else { return .unknown }
        if executablePath.hasPrefix("/usr/local/bin/") || executablePath.hasPrefix("/opt/homebrew/bin/") {
            return .releaseBinary
        }
        return .unknown
    }

    private static func automationSummary(for state: PermissionChecker.CheckState) -> String {
        switch state {
        case .granted:
            return "Automation permission for Logic Pro is granted."
        case .notGranted:
            return "Automation permission for Logic Pro is not granted."
        case .notVerifiable:
            return "Automation permission could not be verified because Logic Pro is not running."
        }
    }

    private static func logicApplicationSummary(running: Bool, visible: Bool) -> String {
        if visible {
            return "Logic Pro is running with a visible window."
        }
        if running {
            return "Logic Pro is running, but no visible project window was detected."
        }
        return "Logic Pro is not running; live setup checks need manual validation."
    }

    private static func check(
        id: String,
        domain: String,
        status: CheckStatus,
        summary: String,
        evidence: [String: String],
        remediationType: RemediationType,
        remediationValueOverride: String? = nil
    ) -> Check {
        let value = remediationValueOverride ?? defaultRemediationValue(for: id, type: remediationType)
        return Check(
            id: id,
            domain: domain,
            status: status,
            summary: summary,
            evidence: evidence,
            remediation: Remediation(type: remediationType, value: value)
        )
    }

    private static func defaultRemediationValue(for id: String, type: RemediationType) -> String {
        switch type {
        case .none:
            return ""
        case .systemSettings:
            if id == "permissions.accessibility" {
                return "System Settings > Privacy & Security > Accessibility"
            }
            if id == "permissions.automation_logic_pro" {
                return "System Settings > Privacy & Security > Automation > Logic Pro"
            }
            return remediationAnchorsByCheckID[id] ?? "docs/SETUP.md#doctor"
        case .command, .docs, .manual:
            return remediationAnchorsByCheckID[id] ?? "docs/SETUP.md#doctor"
        }
    }

    private static func resolveProductionExecutablePath(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }

        if raw.contains("/") {
            let url: URL
            if raw.hasPrefix("/") {
                url = URL(fileURLWithPath: raw)
            } else {
                url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                    .appendingPathComponent(raw)
            }
            return url.standardizedFileURL.path
        }

        guard let output = runProductionCommand(
            executable: "/usr/bin/which",
            arguments: [raw],
            timeout: 1.0
        ), output.exitCode == 0 else {
            return nil
        }
        let path = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    private static func runProductionCommand(
        executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) -> CommandOutput? {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        let stdin = Pipe()
        stdin.fileHandleForWriting.closeFile()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        let group = DispatchGroup()
        group.enter()
        process.terminationHandler = { _ in group.leave() }

        do {
            try process.run()
        } catch {
            return nil
        }

        if group.wait(timeout: .now() + timeout) == .timedOut {
            if process.isRunning {
                process.terminate()
            }
            if group.wait(timeout: .now() + 0.2) == .timedOut, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                _ = group.wait(timeout: .now() + 0.2)
            }
            return nil
        }

        let stdoutText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return CommandOutput(exitCode: process.terminationStatus, stdout: stdoutText, stderr: stderrText)
    }
}

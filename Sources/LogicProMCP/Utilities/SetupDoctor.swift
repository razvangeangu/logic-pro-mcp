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

    /// Result of inspecting the Claude Code config for a logic-pro registration.
    /// This is a pure config read — it never spawns the registered server, so the
    /// doctor's read-only / run-before-startup contract is honored (no CoreMIDI
    /// ports, no health sweep, no SIGKILL of an indirectly-spawned server).
    enum ClaudeRegistration: Equatable, Sendable {
        /// A logic-pro-style MCP entry resolving to a LogicProMCP binary was found.
        /// `command` is the registered command string for evidence.
        case registered(command: String)
        /// The config was read successfully but no matching registration exists.
        case notRegistered
        /// The config file is absent / unreadable / not valid JSON.
        /// `reason` is a short human-readable explanation for the evidence dict.
        case configUnavailable(reason: String)
    }

    struct Runtime: @unchecked Sendable {
        let resolveExecutablePath: (String?) -> String?
        let fileExists: (String) -> Bool
        let isExecutableFile: (String) -> Bool
        let logicProRunning: () -> Bool
        let logicProHasVisibleWindow: () -> Bool
        let runCommand: (String, [String]) -> CommandOutput?
        let readClaudeRegistration: () -> ClaudeRegistration

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
                runProductionCommand(executable: executable, arguments: arguments, timeout: 1.5)?.output
            },
            readClaudeRegistration: {
                readProductionClaudeRegistration()
            }
        )
    }

    static let schema = "logic_pro_mcp_doctor.v1"

    static let remediationAnchorsByCheckID: [String: String] = [
        "binary.path": "docs/SETUP.md#doctor-binarypath",
        "binary.executable": "docs/SETUP.md#doctor-binaryexecutable",
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
        // Honest reporting: this echoes the version compiled into the running
        // doctor process, not the version of the binary at binary.path. It cannot
        // detect a stale/mismatched install, so it never fails — the summary states
        // exactly what it reports and the remediation is unconditionally .none
        // rather than carrying a dead .fail branch + unreachable docs anchor.
        check(
            id: "binary.version",
            domain: "binary",
            status: .pass,
            summary: "Running server version: \(ServerConfig.serverVersion).",
            evidence: ["version": ServerConfig.serverVersion],
            remediationType: .none
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
        // Distinguish three outcomes instead of folding everything but exit 0 into
        // .pass. xattr exits non-zero both when the attribute is absent (exit 1,
        // "No such xattr") AND on permission-denied or other errors; collapsing all
        // of those to "not quarantined" would let the doctor affirm a clean state it
        // never verified.
        let trimmedStderr = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedStdout = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let evidence: [String: String] = [
            "path": executablePath,
            "exit_code": String(output.exitCode),
            "stderr": trimmedStderr,
        ]
        if output.exitCode == 0 {
            return check(
                id: "release.quarantine",
                domain: "release",
                status: .warn,
                summary: "Binary has a macOS quarantine attribute.",
                evidence: evidence,
                remediationType: .command,
                remediationValueOverride: "xattr -d com.apple.quarantine \(executablePath)"
            )
        }
        let attributeAbsent = output.exitCode == 1
            && trimmedStdout.isEmpty
            && trimmedStderr.localizedCaseInsensitiveContains("No such xattr")
        if attributeAbsent {
            return check(
                id: "release.quarantine",
                domain: "release",
                status: .pass,
                summary: "Binary is not quarantined.",
                evidence: evidence,
                remediationType: .none
            )
        }
        return check(
            id: "release.quarantine",
            domain: "release",
            status: .warn,
            summary: "Quarantine state could not be determined.",
            evidence: evidence,
            remediationType: .docs
        )
    }

    private static func claudeRegistrationCheck(runtime: Runtime) -> Check {
        // Read-only registration detection: inspect the Claude Code config file
        // directly instead of shelling out to `claude mcp list`. `claude mcp list`
        // health-checks every registered MCP server, which spawns the registered
        // LogicProMCP binary over stdio (creating CoreMIDI virtual ports + AX
        // pollers) — a real side effect that violates the doctor's documented
        // "read-only / run-before-startup" contract, and one the old 1.5s SIGKILL
        // could orphan. Reading the config is fast, non-mutating, and spawns nothing.
        switch runtime.readClaudeRegistration() {
        case let .registered(command):
            return check(
                id: "mcp.claude_code_registration",
                domain: "mcp",
                status: .pass,
                summary: "Claude Code MCP registration found.",
                evidence: ["registered": "true", "command": command],
                remediationType: .none
            )
        case .notRegistered:
            return check(
                id: "mcp.claude_code_registration",
                domain: "mcp",
                status: .warn,
                summary: "Claude Code MCP registration was not found.",
                evidence: ["registered": "false"],
                remediationType: .command,
                remediationValueOverride: "claude mcp add --scope user logic-pro -- LogicProMCP"
            )
        case let .configUnavailable(reason):
            return check(
                id: "mcp.claude_code_registration",
                domain: "mcp",
                status: .manual,
                summary: "Claude Code registration could not be checked because the Claude config could not be read.",
                evidence: ["reason": reason],
                remediationType: .manual
            )
        }
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
        // Match a real `.build` path component (SwiftPM's canonical build dir),
        // not a bare substring — a path like `/Users/x/my.build/release/LogicProMCP`
        // must NOT be misclassified as source_build.
        if let executablePath, URL(fileURLWithPath: executablePath).pathComponents.contains(".build") {
            return .sourceBuild
        }

        // Probe brew at canonical absolute paths instead of resolving via PATH.
        // A launchd/minimal-supervisor env often has a stripped PATH without
        // /opt/homebrew/bin, which would otherwise make a genuine Homebrew install
        // fall through to .releaseBinary based purely on ambient PATH.
        for brewPath in ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"] {
            if let brew = runtime.runCommand(brewPath, ["list", "--versions", "logic-pro-mcp"]),
               brew.exitCode == 0,
               brew.stdout.contains("logic-pro-mcp") {
                return .homebrew
            }
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
        )?.output, output.exitCode == 0 else {
            return nil
        }
        let path = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    /// Outcome of running an external command, distinguishing the failure modes
    /// so callers can message truthfully (timeout vs. could-not-spawn) rather than
    /// collapsing both into a bare `nil`.
    enum ProductionCommandResult: Equatable, Sendable {
        case completed(CommandOutput)
        /// The process did not finish within the timeout (terminated/killed).
        case timedOut
        /// The process could not be launched (e.g. executable not found).
        case spawnFailed(String)

        /// Convenience accessor for callers that only need the successful output.
        var output: CommandOutput? {
            if case let .completed(value) = self { return value }
            return nil
        }
    }

    private static func runProductionCommand(
        executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) -> ProductionCommandResult? {
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

        // Drain both pipes CONCURRENTLY with the child. Reading only after the
        // process exits deadlocks when the child writes more than the OS pipe
        // buffer (~16-64KB): its write() blocks, the child never exits, the
        // termination handler never fires, and the timeout becomes the only exit
        // path. Accumulating into thread-safe buffers from readabilityHandler
        // removes that buffer-full deadlock and makes the timeout the only failure
        // path. The buffer is a Sendable reference type so the @Sendable handler
        // can mutate it safely.
        let stdoutBuffer = PipeDrainBuffer()
        let stderrBuffer = PipeDrainBuffer()

        let group = DispatchGroup()

        group.enter()
        stdout.fileHandleForReading.readabilityHandler = { fileHandle in
            let chunk = fileHandle.availableData
            if chunk.isEmpty {
                fileHandle.readabilityHandler = nil
                group.leave()
                return
            }
            stdoutBuffer.append(chunk)
        }
        group.enter()
        stderr.fileHandleForReading.readabilityHandler = { fileHandle in
            let chunk = fileHandle.availableData
            if chunk.isEmpty {
                fileHandle.readabilityHandler = nil
                group.leave()
                return
            }
            stderrBuffer.append(chunk)
        }

        group.enter()
        process.terminationHandler = { _ in group.leave() }

        do {
            try process.run()
        } catch {
            // The readers never received data; clear them and balance the group so
            // it cannot leak. terminationHandler will not fire because run() threw.
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            group.leave() // termination handler
            group.leave() // stdout reader
            group.leave() // stderr reader
            return .spawnFailed(String(describing: error))
        }

        if group.wait(timeout: .now() + timeout) == .timedOut {
            if process.isRunning {
                process.terminate()
            }
            if group.wait(timeout: .now() + 0.2) == .timedOut, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                _ = group.wait(timeout: .now() + 0.5)
            }
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            return .timedOut
        }

        let stdoutText = String(data: stdoutBuffer.snapshot(), encoding: .utf8) ?? ""
        let stderrText = String(data: stderrBuffer.snapshot(), encoding: .utf8) ?? ""
        return .completed(
            CommandOutput(exitCode: process.terminationStatus, stdout: stdoutText, stderr: stderrText)
        )
    }

    /// Thread-safe Data accumulator for concurrent pipe draining. Reference type so
    /// the `@Sendable` readabilityHandler can mutate shared state without capturing
    /// a non-Sendable closure.
    private final class PipeDrainBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func append(_ chunk: Data) {
            lock.lock()
            data.append(chunk)
            lock.unlock()
        }

        func snapshot() -> Data {
            lock.lock()
            defer { lock.unlock() }
            return data
        }
    }

    /// Production reader for the Claude Code registration. Parses ~/.claude.json
    /// directly (top-level `mcpServers` plus every `projects.<path>.mcpServers`)
    /// and reports registration when a logic-pro-style entry resolves to a
    /// LogicProMCP binary. This spawns nothing — honoring the read-only contract.
    static func readProductionClaudeRegistration(
        configURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude.json")
    ) -> ClaudeRegistration {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return .configUnavailable(reason: "config file not found at \(configURL.path)")
        }
        let data: Data
        do {
            data = try Data(contentsOf: configURL)
        } catch {
            return .configUnavailable(reason: "config file could not be read: \(String(describing: error))")
        }
        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: data)
        } catch {
            return .configUnavailable(reason: "config file is not valid JSON: \(String(describing: error))")
        }
        guard let object = root as? [String: Any] else {
            return .configUnavailable(reason: "config root is not a JSON object")
        }

        var serverScopes: [[String: Any]] = []
        if let top = object["mcpServers"] as? [String: Any] {
            serverScopes.append(top)
        }
        if let projects = object["projects"] as? [String: Any] {
            for case let project as [String: Any] in projects.values {
                if let scoped = project["mcpServers"] as? [String: Any] {
                    serverScopes.append(scoped)
                }
            }
        }

        for scope in serverScopes {
            for (name, rawEntry) in scope {
                guard let entry = rawEntry as? [String: Any] else { continue }
                let nameMatches = name.localizedCaseInsensitiveContains("logic-pro")
                let command = (entry["command"] as? String) ?? ""
                let commandMatches = command
                    .localizedCaseInsensitiveContains("LogicProMCP")
                if nameMatches && commandMatches {
                    return .registered(command: command)
                }
            }
        }
        return .notRegistered
    }

    // MARK: - Test seams

    /// Test-only access to the production subprocess runner so the concurrent-drain
    /// and timeout/spawn-failure distinction can be exercised against real children.
    static func runProductionCommandForTesting(
        executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) -> ProductionCommandResult? {
        runProductionCommand(executable: executable, arguments: arguments, timeout: timeout)
    }

    /// Test-only access to the config-based registration reader against a custom URL.
    static func readClaudeRegistrationForTesting(configURL: URL) -> ClaudeRegistration {
        readProductionClaudeRegistration(configURL: configURL)
    }
}

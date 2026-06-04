import AppKit
import Foundation

/// Channel that controls Logic Pro via AppleScript.
/// Very narrow scope: app lifecycle operations only (new, open, close project).
/// AppleScript is slow and modal, so it is used only when no better channel exists.
actor AppleScriptChannel: Channel {
    let id: ChannelID = .appleScript

    struct Runtime: Sendable {
        let isLogicProRunning: @Sendable () -> Bool
        let openFile: @Sendable (String) -> Bool
        let runScript: @Sendable (String) async -> ChannelResult
        let executeTransportAction: @Sendable (String) async -> ChannelResult
        let fileExists: @Sendable (String) -> Bool
        let fileModificationDate: @Sendable (String) -> Date?

        init(
            isLogicProRunning: @escaping @Sendable () -> Bool,
            openFile: @escaping @Sendable (String) -> Bool,
            runScript: @escaping @Sendable (String) async -> ChannelResult,
            executeTransportAction: @escaping @Sendable (String) async -> ChannelResult,
            fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
            fileModificationDate: @escaping @Sendable (String) -> Date? = {
                (try? FileManager.default.attributesOfItem(atPath: $0)[.modificationDate]) as? Date
            }
        ) {
            self.isLogicProRunning = isLogicProRunning
            self.openFile = openFile
            self.runScript = runScript
            self.executeTransportAction = executeTransportAction
            self.fileExists = fileExists
            self.fileModificationDate = fileModificationDate
        }

        static let production = Runtime(
            isLogicProRunning: { ProcessUtils.isLogicProRunning },
            openFile: { AppleScriptSafety.openFile(at: $0) },
            runScript: { source in
                await AppleScriptChannel.executeAppleScript(source)
            },
            executeTransportAction: { action in
                switch action {
                case "stop":
                    return await AppleScriptChannel.executeAppleScript(
                        AppleScriptChannel.transportScript(action: action)
                    )
                case "record":
                    return await AppleScriptChannel.executeAppleScript(
                        AppleScriptChannel.transportScript(action: action)
                    )
                default:
                    return .error("Unsupported transport action: \(action)")
                }
            }
        )
    }

    private let runtime: Runtime

    init(runtime: Runtime = .production) {
        self.runtime = runtime
    }

    func start() async throws {
        Log.info("AppleScript channel started", subsystem: "appleScript")
    }

    func stop() async {
        Log.info("AppleScript channel stopped", subsystem: "appleScript")
    }

    func execute(operation: String, params: [String: String]) async -> ChannelResult {
        switch operation {
        case "project.new":
            let raw = await runScript(newProjectScript())
            return Self.wrapMutatingResult(raw, operation: operation)

        case "project.open":
            guard let path = params["path"] else {
                return .error("Missing 'path' parameter for project.open")
            }
            let raw = await openProjectViaWorkspace(path: path)
            return Self.wrapMutatingResult(raw, operation: operation, extras: ["path": path])

        case "project.close":
            let saving = params["saving"] ?? "yes"
            let raw = await runScript(closeProjectScript(saving: saving))
            return Self.wrapMutatingResult(raw, operation: operation, extras: ["saving": saving])

        case "project.save":
            let raw = await runScript(saveProjectScript())
            return Self.wrapMutatingResult(raw, operation: operation)

        case "project.save_as":
            guard let path = params["path"] else {
                return .error("Missing 'path' parameter for project.save_as")
            }
            let saveStartedAt = Date()
            let candidatePaths = Self.saveAsCandidatePaths(path: path)
            let preexistingPaths = Set(candidatePaths.filter(runtime.fileExists))
            let beforeModificationDates = candidatePaths.reduce(into: [String: Date]()) { dates, candidate in
                if runtime.fileExists(candidate), let date = runtime.fileModificationDate(candidate) {
                    dates[candidate] = date
                }
            }
            let raw = await runScript(saveProjectAsScript(path: path))
            return Self.wrapSaveAsResult(
                raw,
                path: path,
                saveStartedAt: saveStartedAt,
                preexistingPaths: preexistingPaths,
                beforeModificationDates: beforeModificationDates,
                fileExists: runtime.fileExists,
                fileModificationDate: runtime.fileModificationDate
            )

        // Transport fallbacks — AppleScript is only authoritative for commands
        // confirmed to exist in Logic Pro's scripting dictionary.
        case "transport.stop":
            let action = operation.replacingOccurrences(of: "transport.", with: "")
            guard AppleScriptSafety.isAllowedTransportAction(action) else {
                return .error("Transport action not in whitelist: \(action)")
            }
            let raw = await runtime.executeTransportAction(action)
            return Self.wrapMutatingResult(raw, operation: operation)

        case "transport.record":
            let action = operation.replacingOccurrences(of: "transport.", with: "")
            guard AppleScriptSafety.isAllowedTransportAction(action) else {
                return .error("Transport action not in whitelist: \(action)")
            }
            let raw = await runtime.executeTransportAction(action)
            return Self.wrapMutatingResult(raw, operation: operation)

        case "transport.play", "transport.pause":
            return .error("Unsupported AppleScript operation: \(operation)")

        default:
            return .error("Unsupported AppleScript operation: \(operation)")
        }
    }

    /// v3.1.1 (P2-2) — wrap a successful AppleScript-driven mutation in a
    /// Honest Contract State B envelope so the wire format matches the AX /
    /// MCU channels. AppleScript mutations cannot read back the resulting
    /// state via the same script path (we'd need a follow-up `tell ... return
    /// ...` round-trip plus a deterministic schema), so all successes here
    /// are `verified:false / readback_unavailable`. Errors stay as
    /// `ChannelResult.error` — the router treats those as terminal.
    static func wrapMutatingResult(
        _ result: ChannelResult,
        operation: String,
        extras: [String: Any] = [:]
    ) -> ChannelResult {
        guard result.isSuccess else { return result }
        // If the script body already produced an HC envelope (open-project's
        // verifyOpenedProject path returns plain "Opened: <path>" but a future
        // refactor could return an HC envelope directly), leave it alone.
        if HonestContractEnvelopeDetector.isAlreadyEnvelope(result.message) {
            return result
        }
        var merged: [String: Any] = [
            "operation": operation,
            "method": "applescript",
            "raw": result.message
        ]
        for (k, v) in extras { merged[k] = v }
        return .success(HonestContract.encodeStateB(
            reason: .readbackUnavailable, extras: merged
        ))
    }

    static func wrapSaveAsResult(
        _ result: ChannelResult,
        path: String,
        saveStartedAt: Date,
        preexistingPaths: Set<String>,
        beforeModificationDates: [String: Date],
        fileExists: @Sendable (String) -> Bool,
        fileModificationDate: @Sendable (String) -> Date?
    ) -> ChannelResult {
        guard result.isSuccess else { return result }
        if HonestContractEnvelopeDetector.isAlreadyEnvelope(result.message) {
            return result
        }

        let observedPath = saveAsCandidatePaths(path: path).first(where: fileExists)

        var extras: [String: Any] = [
            "operation": "project.save_as",
            "method": "applescript",
            "path": path,
            "raw": result.message
        ]

        guard let observedPath else {
            return .error(HonestContract.encodeStateC(
                error: .readbackMismatch,
                hint: "project.save_as completed but no .logicx package was observed at the requested path",
                extras: extras
            ))
        }

        let afterModificationDate = fileModificationDate(observedPath)
        if let afterModificationDate {
            extras["observed_mtime"] = iso8601String(afterModificationDate)
        }
        if let beforeModificationDate = beforeModificationDates[observedPath] {
            extras["previous_mtime"] = iso8601String(beforeModificationDate)
        }
        if preexistingPaths.contains(observedPath) {
            guard let beforeModificationDate = beforeModificationDates[observedPath],
                  let afterModificationDate,
                  afterModificationDate > beforeModificationDate ||
                    afterModificationDate >= saveStartedAt else {
                return .error(HonestContract.encodeStateC(
                    error: .readbackMismatch,
                    hint: "project.save_as completed but the existing .logicx package modification time did not advance",
                    extras: extras.merging(["observed": observedPath]) { _, new in new }
                ))
            }
        } else if afterModificationDate == nil {
            return .error(HonestContract.encodeStateC(
                error: .readbackMismatch,
                hint: "project.save_as completed but no modification time could be read from the new .logicx package",
                extras: extras.merging(["observed": observedPath]) { _, new in new }
            ))
        }

        return .success(HonestContract.encodeStateA(
            extras: extras.merging(["observed": observedPath]) { _, new in new }
        ))
    }

    static func saveAsCandidatePaths(path: String) -> [String] {
        path.hasSuffix(".logicx") ? [path] : [path, path + ".logicx"]
    }

    private static func iso8601String(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    func healthCheck() async -> ChannelHealth {
        if runtime.isLogicProRunning() {
            return .healthy(detail: "AppleScript ready")
        }
        let probe = await runScript(readinessProbeScript())
        switch probe {
        case .success:
            return .healthy(detail: "AppleScript ready")
        case .error(let message):
            return .unavailable(message)
        }
    }

    // MARK: - Script execution

    private func runScript(_ source: String) async -> ChannelResult {
        await runtime.runScript(source)
    }

    static func executeAppleScript(_ source: String) async -> ChannelResult {
        await Task.detached(priority: .userInitiated) {
            // Primary path: in-process NSAppleScript via main thread (inherits TCC permissions)
            let inProcessResult: ChannelResult? = ProcessUtils.runAppKit {
                let script = NSAppleScript(source: source)
                var errorInfo: NSDictionary?
                let result = script?.executeAndReturnError(&errorInfo)
                if let errorInfo {
                    let message = (errorInfo[NSAppleScript.errorMessage] as? String)
                        ?? "NSAppleScript error \(errorInfo[NSAppleScript.errorNumber] ?? -1)"
                    Log.error("NSAppleScript error: \(message)", subsystem: "appleScript")
                    return ChannelResult.error("AppleScript error: \(message)")
                }
                let output = result?.stringValue ?? ""
                return ChannelResult.success("{\"result\":\"\(AppleScriptChannel.escapeJSON(output))\"}")
            } ?? nil
            if let inProcessResult {
                return inProcessResult
            }

            // Fallback: osascript child process (for environments where main thread is unavailable)
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            let stdin = Pipe()
            stdin.fileHandleForWriting.closeFile()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", shellCommand(for: source)]
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = stderr

            do {
                try process.run()
            } catch {
                Log.error("AppleScript shell spawn failed: \(error)", subsystem: "appleScript")
                return ChannelResult.error("AppleScript error: \(error)")
            }

            process.waitUntilExit()
            let stderrOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if process.terminationStatus != 0 {
                let message = stderrOutput.isEmpty ? "osascript exited with status \(process.terminationStatus)" : stderrOutput
                Log.error("AppleScript error: \(message)", subsystem: "appleScript")
                return ChannelResult.error("AppleScript error: \(message)")
            }

            let rawOutput = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let output = normalizedAppleScriptResult(rawOutput)
            return ChannelResult.success("{\"result\":\"\(AppleScriptChannel.escapeJSON(output))\"}")
        }.value
    }

    // MARK: - Script templates

    private func newProjectScript() -> String {
        """
        tell application "Logic Pro"
            activate
            set newDocument to make new document
            delay 0.2
            return name of newDocument
        end tell
        """
    }

    private func openProjectViaWorkspace(path: String) async -> ChannelResult {
        // Use Launch Services via open(1) instead of AppleScript string interpolation
        // to completely prevent injection attacks (PRD §6.3)
        guard runtime.openFile(path) else {
            return .error("Failed to open: \(path)")
        }

        let initialVerification = await runScript(verifyOpenedProjectScript(path: path))
        switch initialVerification {
        case .success:
            return .success("Opened: \(path)")
        case .error(let initialMessage):
            // Retry once after a best-effort close only if Logic is still sitting on
            // a different front document. This avoids dropping the current session
            // before we've even tried the Launch Services open path.
            guard runtime.isLogicProRunning() else {
                return .error("Failed to verify opened project: \(path). \(initialMessage)")
            }

            let previousDocumentPath = await logicCurrentDocumentPath()
            if let previousDocumentPath,
               projectPathsMatch(previousDocumentPath, path) {
                return .success("Opened: \(path)")
            }

            if previousDocumentPath != nil {
                _ = await runScript(closeCurrentProjectIfAnyScript(saving: "no"))
            }

            guard runtime.openFile(path) else {
                if let previousDocumentPath,
                   !projectPathsMatch(previousDocumentPath, path) {
                    _ = runtime.openFile(previousDocumentPath)
                }
                return .error("Failed to open after closing current project: \(path)")
            }

            let retryVerification = await runScript(verifyOpenedProjectScript(path: path))
            switch retryVerification {
            case .success:
                return .success("Opened: \(path)")
            case .error(let retryMessage):
                if let currentDocumentPath = await logicCurrentDocumentPath(),
                   projectPathsMatch(currentDocumentPath, path) {
                    return .success("Opened: \(path)")
                }
                if let previousDocumentPath,
                   !projectPathsMatch(previousDocumentPath, path) {
                    _ = runtime.openFile(previousDocumentPath)
                }
                return .error("Failed to verify opened project: \(path). \(retryMessage)")
            }
        }
    }

    private func closeProjectScript(saving: String) -> String {
        let saveClause = closeProjectSaveClause(saving: saving)
        return """
        tell application "Logic Pro"
            close front document \(saveClause)
        end tell
        """
    }

    private func closeCurrentProjectIfAnyScript(saving: String) -> String {
        let saveClause = closeProjectSaveClause(saving: saving)
        return """
        tell application "Logic Pro"
            if (count of documents) > 0 then
                close front document \(saveClause)
            end if
        end tell
        """
    }

    static func currentDocumentPathScript() -> String {
        """
        tell application "Logic Pro"
            if (count of documents) > 0 then
                try
                    return path of front document as text
                on error
                    return ""
                end try
            end if
            return ""
        end tell
        """
    }

    /// v3.1.8 (Issue #7) — file-scoped helper for `LogicProjectFileReader` so it
    /// can resolve the open project's path without instantiating a channel.
    /// Returns nil when no document is open, TCC is denied, or AppleScript
    /// fails for any reason.
    @Sendable
    static func currentDocumentPath() async -> String? {
        let result = await Self.executeAppleScript(currentDocumentPathScript())
        return Self.parseCurrentDocumentPath(from: result)
    }

    static func parseCurrentDocumentPath(from result: ChannelResult) -> String? {
        guard result.isSuccess else { return nil }
        let raw = Self.appleScriptResultText(from: result)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? nil : raw
    }

    private func logicCurrentDocumentPath() async -> String? {
        let result = await runScript(Self.currentDocumentPathScript())
        return Self.parseCurrentDocumentPath(from: result)
    }

    private func projectPathsMatch(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalizedProjectPath(lhs)
        let right = normalizedProjectPath(rhs)
        if left == right { return true }
        if left.hasPrefix("/private"), String(left.dropFirst(8)) == right { return true }
        if right.hasPrefix("/private"), left == String(right.dropFirst(8)) { return true }
        return false
    }

    private func normalizedProjectPath(_ path: String) -> String {
        let normalized = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        if normalized.hasSuffix("/") {
            return String(normalized.dropLast())
        }
        return normalized
    }

    static func appleScriptResultText(from result: ChannelResult) -> String? {
        guard result.isSuccess else { return nil }
        let message = result.message
        guard let data = message.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let value = object["result"]
        else {
            return message
        }
        return value
    }

    private func closeProjectSaveClause(saving: String) -> String {
        switch saving.lowercased() {
        case "no", "false":
            return "saving no"
        case "ask":
            return "saving ask"
        default:
            return "saving yes"
        }
    }

    private func saveProjectScript() -> String {
        """
        tell application "Logic Pro"
            save front document
        end tell
        """
    }

    private func readinessProbeScript() -> String {
        """
        tell application "Logic Pro"
            return name
        end tell
        """
    }

    private func verifyOpenedProjectScript(path: String) -> String {
        // Normalize path to resolve /private/Users vs /Users symlink differences
        let normalizedPath = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        let escapedPath = normalizedPath
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
        return """
        tell application "Logic Pro"
            repeat 25 times
                if (count of documents) > 0 then
                    try
                        set docPath to path of front document as text
                        -- Normalize: strip trailing slash for comparison
                        if docPath ends with "/" then set docPath to text 1 thru -2 of docPath
                        set expectedPath to "\(escapedPath)"
                        if expectedPath ends with "/" then set expectedPath to text 1 thru -2 of expectedPath
                        if docPath is expectedPath then return "opened"
                        -- Also check without /private prefix
                        if docPath starts with "/private" and (text 9 thru -1 of docPath) is expectedPath then return "opened"
                        if expectedPath starts with "/private" and docPath is (text 9 thru -1 of expectedPath) then return "opened"
                    end try
                end if
                delay 0.2
            end repeat
            error "Timed out waiting for Logic Pro to open the requested project"
        end tell
        """
    }

    private func saveProjectAsScript(path: String) -> String {
        let escapedPath = path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
        return """
        tell application "Logic Pro"
            save front document in (POSIX file "\(escapedPath)")
        end tell
        """
    }

    private static func transportScript(action: String) -> String {
        "tell application id \"\(ServerConfig.logicProBundleID)\" to \(action)"
    }

    // MARK: - Helpers

    static func escapeJSON(_ string: String) -> String {
        // RFC 8259 forbids unescaped U+0000..U+001F bytes inside a JSON
        // string. Pre-v3.1.5 we only handled the common whitespace trio,
        // so AppleScript outputs that legitimately contain other control
        // bytes (e.g. the U+001F / U+001E delimiters used by the new
        // markers / projectInfo / tracks helpers) round-tripped as raw
        // bytes and broke `JSONSerialization` parsing. Escape every
        // control character as a `\u00XX` sequence so the wrapper is
        // always valid JSON.
        var result = ""
        result.reserveCapacity(string.count)
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\\": result.append("\\\\")
            case "\"": result.append("\\\"")
            case "\n": result.append("\\n")
            case "\r": result.append("\\r")
            case "\t": result.append("\\t")
            case "\u{08}": result.append("\\b")
            case "\u{0C}": result.append("\\f")
            default:
                if scalar.value < 0x20 {
                    result.append(String(format: "\\u%04X", scalar.value))
                } else {
                    result.append(Character(scalar))
                }
            }
        }
        return result
    }

    private static func normalizedAppleScriptResult(_ raw: String) -> String {
        let sanitized = String(
            raw.unicodeScalars.filter { scalar in
                !CharacterSet.controlCharacters.contains(scalar) || scalar == "\n" || scalar == "\r" || scalar == "\t"
            }
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "OK" : sanitized
    }

    private static func shellCommand(for source: String) -> String {
        let lines = source
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let args = lines.map { "-e \(shellQuote($0))" }.joined(separator: " ")
        return "osascript \(args)"
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

}

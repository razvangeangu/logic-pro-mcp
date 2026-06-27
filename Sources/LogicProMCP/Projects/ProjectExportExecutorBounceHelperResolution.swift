import Darwin
import Foundation

struct ProjectExportBounceHelperResult: Sendable, Equatable {
    let artifactPath: String?
    let error: String?
    let bounceFired: Bool

    static func success(_ path: String, bounceFired: Bool = true) -> ProjectExportBounceHelperResult {
        ProjectExportBounceHelperResult(artifactPath: path, error: nil, bounceFired: bounceFired)
    }

    static func failure(_ error: String, bounceFired: Bool = false) -> ProjectExportBounceHelperResult {
        ProjectExportBounceHelperResult(artifactPath: nil, error: error, bounceFired: bounceFired)
    }
}

extension ProjectExportExecutor {
    private static let trustedCliclickPaths = [
        "/opt/homebrew/bin/cliclick",
        "/usr/local/bin/cliclick",
        "/usr/bin/cliclick",
    ]

    static func commandExists(
        _ command: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isExecutable: @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.contains("/") {
            return isExecutable(trimmed)
        }

        let pathSeparator = ":"
        let searchPath = environment["PATH"] ?? "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        for entry in searchPath.split(separator: Character(pathSeparator)) {
            guard !entry.isEmpty else { continue }
            let candidate = URL(fileURLWithPath: String(entry))
                .appendingPathComponent(trimmed)
                .path
            if isExecutable(candidate) {
                return true
            }
        }
        return false
    }

    static func resolveTrustedCliclick(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isExecutable: @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        attributesOfItem: @Sendable (String) throws -> [FileAttributeKey: Any] = {
            try FileManager.default.attributesOfItem(atPath: $0)
        }
    ) -> String? {
        let candidates = ([environment["LOGIC_PRO_MCP_CLICLICK"]] + trustedCliclickPaths).compactMap { $0 }
        for candidate in candidates {
            let normalized = URL(fileURLWithPath: candidate).standardizedFileURL.path
            guard normalized.hasPrefix("/") else { continue }
            let parent = URL(fileURLWithPath: normalized).deletingLastPathComponent().path
            guard trustedCliclickPaths.contains(normalized) else { continue }
            guard let attrs = try? attributesOfItem(parent),
                  let permissions = attrs[.posixPermissions] as? NSNumber,
                  permissions.intValue & 0o022 == 0 else { continue }
            if isExecutable(normalized) {
                return normalized
            }
        }
        return nil
    }


    static func currentExecutablePath() -> String? {
        var size: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &size)
        guard size > 0 else { return nil }

        var buffer = [CChar](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&buffer, &size) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    static func effectiveExecutablePath(
        overrideExecutablePath: String?,
        commandLineExecutablePath: String?,
        processExecutablePath: String?
    ) -> String? {
        for candidate in [overrideExecutablePath, processExecutablePath] {
            guard let candidate = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !candidate.isEmpty else { continue }
            return URL(fileURLWithPath: candidate).standardizedFileURL.path
        }
        guard let commandLineExecutablePath = commandLineExecutablePath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !commandLineExecutablePath.isEmpty,
              commandLineExecutablePath.hasPrefix("/") || commandLineExecutablePath.contains("/")
        else {
            return nil
        }
        return URL(fileURLWithPath: commandLineExecutablePath).standardizedFileURL.path
    }

    static func bounceHelperCandidatePaths(
        environment: [String: String],
        currentDirectoryPath: String,
        executablePath: String?,
        fileExists: @Sendable (String) -> Bool,
        resolveSymlinks: @Sendable (String) -> String = { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
    ) -> [String] {
        var candidates: [String] = []

        func appendCandidate(_ candidate: String?) {
            guard let candidate = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !candidate.isEmpty else { return }
            let normalized = URL(fileURLWithPath: candidate).standardizedFileURL.path
            if !candidates.contains(normalized) {
                candidates.append(normalized)
            }
        }

        appendCandidate(environment["LOGIC_PRO_MCP_BOUNCE_HELPER"])
        if let shareDir = environment["LOGIC_PRO_MCP_SHARE_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !shareDir.isEmpty {
            let shareURL = URL(fileURLWithPath: shareDir).standardizedFileURL
            if shareURL.pathExtension == "py" {
                appendCandidate(shareURL.path)
            } else {
                appendCandidate(shareURL.appendingPathComponent("logic_bounce.py").path)
                appendCandidate(shareURL.appendingPathComponent("Scripts/logic_bounce.py").path)
            }
        }

        if let executablePath {
            let executableDir = URL(fileURLWithPath: resolveSymlinks(executablePath))
                .deletingLastPathComponent()
            appendCandidate(executableDir.appendingPathComponent("Scripts/logic_bounce.py").path)
            appendCandidate(
                executableDir
                    .appendingPathComponent("share/logic-pro-mcp/logic_bounce.py")
                    .path
            )
            appendCandidate(
                executableDir
                    .appendingPathComponent("share/logic-pro-mcp/Scripts/logic_bounce.py")
                    .path
            )
            appendCandidate(
                executableDir
                    .deletingLastPathComponent()
                    .appendingPathComponent("share/logic-pro-mcp/logic_bounce.py")
                    .path
            )
            appendCandidate(
                executableDir
                    .deletingLastPathComponent()
                    .appendingPathComponent("share/logic-pro-mcp/Scripts/logic_bounce.py")
                    .path
            )
            for repoCandidate in repositoryBounceHelperCandidatePaths(
                executablePath: executablePath,
                fileExists: fileExists,
                resolveSymlinks: resolveSymlinks
            ) {
                appendCandidate(repoCandidate)
            }
        } else {
            let repoRoot = URL(fileURLWithPath: currentDirectoryPath).standardizedFileURL
            let packageSwift = repoRoot.appendingPathComponent("Package.swift").path
            let helper = repoRoot.appendingPathComponent("Scripts/logic_bounce.py").path
            if fileExists(packageSwift), fileExists(helper) {
                appendCandidate(helper)
            }
        }

        return candidates
    }

    static func repositoryBounceHelperCandidatePaths(
        executablePath: String,
        fileExists: @Sendable (String) -> Bool,
        resolveSymlinks: @Sendable (String) -> String = { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
    ) -> [String] {
        var candidates: [String] = []
        var current = URL(fileURLWithPath: resolveSymlinks(executablePath))
            .deletingLastPathComponent()

        while true {
            let packageSwift = current.appendingPathComponent("Package.swift").path
            let helper = current.appendingPathComponent("Scripts/logic_bounce.py").path
            if fileExists(packageSwift), fileExists(helper) {
                candidates.append(helper)
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                break
            }
            current = parent
        }

        return candidates
    }

    static func resolveBounceHelperPath(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath,
        executablePath: String? = nil,
        commandLineExecutablePath: String? = CommandLine.arguments.first,
        processExecutablePath: String? = currentExecutablePath(),
        fileExists: @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        // Injectable so unit tests stay fully hermetic: the real
        // `resolvingSymlinksInPath()` performs filesystem I/O (realpath/lstat) on
        // the caller-supplied executable path, which on some CI runners stalls for
        // minutes on certain prefixes (e.g. a real `/opt/homebrew`). Tests inject
        // an identity closure so resolution never touches the disk.
        resolveSymlinks: @Sendable (String) -> String = { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
    ) -> String? {
        let effectiveExecutablePath = effectiveExecutablePath(
            overrideExecutablePath: executablePath,
            commandLineExecutablePath: commandLineExecutablePath,
            processExecutablePath: processExecutablePath
        )
        let candidates = bounceHelperCandidatePaths(
            environment: environment,
            currentDirectoryPath: currentDirectoryPath,
            executablePath: effectiveExecutablePath,
            fileExists: fileExists,
            resolveSymlinks: resolveSymlinks
        )
        for candidate in candidates where fileExists(candidate) {
            return candidate
        }
        return candidates.first
    }
}

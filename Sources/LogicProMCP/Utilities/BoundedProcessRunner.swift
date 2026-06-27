import Foundation

/// Runs child processes with a hard timeout and concurrent stdout/stderr drain.
///
/// This is the only safe pattern for production subprocesses in the server:
/// reading pipes after `waitUntilExit()` can deadlock once a child fills an OS
/// pipe buffer, and cooperative Swift task cancellation cannot kill a blocked
/// external process.
enum BoundedProcessRunner {
    static let defaultOutputLimitBytes = 1_048_576

    struct Output: Equatable, Sendable {
        let exitCode: Int32
        let stdout: String
        let stderr: String
        let stdoutTruncated: Bool
        let stderrTruncated: Bool
    }

    enum Result: Equatable, Sendable {
        case completed(Output)
        case timedOut
        case spawnFailed(String)

        var output: Output? {
            if case let .completed(value) = self { return value }
            return nil
        }
    }

    static func run(
        executable: String,
        arguments: [String],
        timeout: TimeInterval,
        outputLimitBytes: Int = defaultOutputLimitBytes
    ) -> Result {
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

        let maxBytes = max(0, outputLimitBytes)
        let stdoutBuffer = PipeDrainBuffer(maxBytes: maxBytes)
        let stderrBuffer = PipeDrainBuffer(maxBytes: maxBytes)
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
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            group.leave()
            group.leave()
            group.leave()
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

        let stdoutSnapshot = stdoutBuffer.snapshot()
        let stderrSnapshot = stderrBuffer.snapshot()
        return .completed(
            Output(
                exitCode: process.terminationStatus,
                stdout: String(data: stdoutSnapshot.data, encoding: .utf8) ?? "",
                stderr: String(data: stderrSnapshot.data, encoding: .utf8) ?? "",
                stdoutTruncated: stdoutSnapshot.truncated,
                stderrTruncated: stderrSnapshot.truncated
            )
        )
    }

    private struct PipeDrainSnapshot {
        let data: Data
        let truncated: Bool
    }

    private final class PipeDrainBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private let maxBytes: Int
        private var data = Data()
        private var truncated = false

        init(maxBytes: Int) {
            self.maxBytes = maxBytes
        }

        func append(_ chunk: Data) {
            lock.lock()
            defer { lock.unlock() }

            let remaining = maxBytes - data.count
            if remaining > 0 {
                data.append(contentsOf: chunk.prefix(remaining))
            }
            if chunk.count > max(remaining, 0) {
                truncated = true
            }
        }

        func snapshot() -> PipeDrainSnapshot {
            lock.lock()
            defer { lock.unlock() }
            return PipeDrainSnapshot(data: data, truncated: truncated)
        }
    }
}

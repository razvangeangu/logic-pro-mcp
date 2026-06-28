import AVFoundation
import Darwin
import Foundation
import MCP
import Testing
@testable import LogicProMCP

// MARK: - Fixture helpers

/// Write a real, non-silent stereo WAV at `url` so AudioAnalyzer verification
/// can PASS (exists + non-zero + non-silent + sane duration). Uses the same
/// AVAudioFile path AudioAnalyzerTests relies on so the executor is exercised
/// against the real analyzer, not a stub.
@discardableResult
func writeToneWav(at url: URL, durationSeconds: Double = 0.2) throws -> URL {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let sampleRate = 44_100.0
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
    let frameCount = AVAudioFrameCount(sampleRate * durationSeconds)
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
    buffer.frameLength = frameCount
    let channelData = buffer.floatChannelData!
    for channel in 0..<2 {
        for frame in 0..<Int(frameCount) {
            channelData[channel][frame] = Float(sin(2.0 * Double.pi * 440.0 * Double(frame) / sampleRate) * 0.5)
        }
    }
    try file.write(from: buffer)
    return url
}

/// Write a fully-silent WAV (all zeros) so AudioAnalyzer flags `near_silent_output`.
@discardableResult
func writeSilentWav(at url: URL, durationSeconds: Double = 0.2) throws -> URL {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let sampleRate = 44_100.0
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
    let frameCount = AVAudioFrameCount(sampleRate * durationSeconds)
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
    buffer.frameLength = frameCount
    try file.write(from: buffer)
    return url
}

/// Thread-safe boolean flag so a `@Sendable` bounce side-effect closure can
/// record whether it fired without a data race on a captured `var`.
final class BoolFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

func makeExecTempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("logicpromcp-export-exec-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func makeLogicxProject(in dir: URL, named name: String) throws -> URL {
    let url = dir.appendingPathComponent(name).appendingPathExtension("logicx")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Deterministic artifact path the planner resolves for a project display name +
/// kind under an output root. Sanitization replaces spaces/illegal chars with '-'.
func plannedArtifactPath(outputRoot: URL, displayName: String, kind: String) -> String {
    let sanitized = displayName.unicodeScalars.map { scalar -> Character in
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return allowed.contains(scalar) ? Character(scalar) : Character("-")
    }
    let safe = String(sanitized).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return outputRoot.appendingPathComponent("\(safe.isEmpty ? "project" : safe)-\(kind).wav")
        .standardizedFileURL.path
}

func withBounceHelperOverride<T>(
    _ helperPath: String,
    body: () async throws -> T
) async rethrows -> T {
    let key = "LOGIC_PRO_MCP_BOUNCE_HELPER"
    let previous = getenv(key).map { String(cString: $0) }
    setenv(key, helperPath, 1)
    defer {
        if let previous {
            setenv(key, previous, 1)
        } else {
            unsetenv(key)
        }
    }
    return try await body()
}

// MARK: - Configurable fake channel

/// A router channel that records ops and (a) reports success/failure per op and
/// (b) runs a side-effect closure on success (used to simulate a bounce writing
/// the artifact file). Lets the export state machine be driven headless.
actor FakeExportChannel: Channel {
    nonisolated let id: ChannelID
    private let onExecute: @Sendable (String, [String: String]) async -> ChannelResult
    private(set) var ops: [String] = []

    init(id: ChannelID, onExecute: @escaping @Sendable (String, [String: String]) async -> ChannelResult) {
        self.id = id
        self.onExecute = onExecute
    }

    func start() async throws {}

    func stop() async {}

    func execute(operation: String, params: [String: String]) async -> ChannelResult {
        ops.append(operation)
        return await onExecute(operation, params)
    }

    func healthCheck() async -> ChannelHealth { .healthy(detail: "fake") }
}

/// Router wired so `project.open` (AppleScript) and `project.bounce`
/// (MIDIKeyCommands) resolve to fakes. `bounceSideEffect` runs on each
/// successful bounce - production-equivalent of Logic writing the file.
func makeExportRouter(
    openSucceeds: Bool = true,
    bounceSucceeds: Bool = true,
    openSideEffect: @escaping @Sendable () -> Void = {},
    bounceSideEffect: @escaping @Sendable () -> Void = {}
) async -> ChannelRouter {
    let router = ChannelRouter()
    let appleScript = FakeExportChannel(id: .appleScript) { op, _ in
        if op == "project.open" {
            openSideEffect()
        }
        return openSucceeds
            ? ChannelResult.success("opened via \(op)")
            : ChannelResult.error("open boom")
    }
    let keyCmd = FakeExportChannel(id: .midiKeyCommands) { op, _ in
        if op == "project.bounce" {
            guard bounceSucceeds else { return .error("bounce boom") }
            bounceSideEffect()
            return .success("bounced")
        }
        return .success("ok")
    }
    await router.register(appleScript)
    await router.register(keyCmd)
    return router
}

/// Options that never sleep, poll quickly, and analyze with the real analyzer.
func fastOptions(
    identity: @escaping @Sendable () async -> String?
) -> ProjectExportExecutor.Options {
    ProjectExportExecutor.Options(
        identityReadback: identity,
        analyze: { path, policy in AudioAnalyzer.analyzeFile(path: path, policy: policy) },
        fileManager: .default,
        pollAttempts: 5,
        pollIntervalNanos: 1_000,
        sleep: { _ in },
        minimumDurationSeconds: 0.05
    )
}

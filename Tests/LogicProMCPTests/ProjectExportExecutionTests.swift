import AVFoundation
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
private func writeToneWav(at url: URL, durationSeconds: Double = 0.2) throws -> URL {
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
private func writeSilentWav(at url: URL, durationSeconds: Double = 0.2) throws -> URL {
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
    try file.write(from: buffer) // floatChannelData defaults to 0.0
    return url
}

/// Thread-safe boolean flag so a `@Sendable` bounce side-effect closure can
/// record whether it fired without a data race on a captured `var`.
private final class BoolFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.lock(); value = true; lock.unlock() }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

private func makeExecTempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("logicpromcp-export-exec-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func makeLogicxProject(in dir: URL, named name: String) throws -> URL {
    let url = dir.appendingPathComponent(name).appendingPathExtension("logicx")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Deterministic artifact path the planner resolves for a project display name +
/// kind under an output root. Sanitization replaces spaces/illegal chars with '-'.
private func plannedArtifactPath(outputRoot: URL, displayName: String, kind: String) -> String {
    let sanitized = displayName.unicodeScalars.map { scalar -> Character in
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return allowed.contains(scalar) ? Character(scalar) : Character("-")
    }
    let safe = String(sanitized).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return outputRoot.appendingPathComponent("\(safe.isEmpty ? "project" : safe)-\(kind).wav")
        .standardizedFileURL.path
}

// MARK: - Configurable fake channel

/// A router channel that records ops and (a) reports success/failure per op and
/// (b) runs a side-effect closure on success (used to simulate a bounce writing
/// the artifact file). Lets the export state machine be driven headless.
private actor FakeExportChannel: Channel {
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
/// successful bounce — production-equivalent of Logic writing the file.
private func makeExportRouter(
    openSucceeds: Bool = true,
    bounceSucceeds: Bool = true,
    bounceSideEffect: @escaping @Sendable () -> Void = {}
) async -> ChannelRouter {
    let router = ChannelRouter()
    let appleScript = FakeExportChannel(id: .appleScript) { op, _ in
        openSucceeds ? .success("opened via \(op)") : .error("open boom")
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
private func fastOptions(
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

// MARK: - Tests

@Suite("Project export guarded execution")
struct ProjectExportExecutionTests {

    @Test("full run opens, verifies identity, bounces, and records each artifact as State A")
    func fullRunVerifiesAndRecords() async throws {
        let projDir = try makeExecTempDir()
        let outputRoot = try makeExecTempDir()
        let project = try makeLogicxProject(in: projDir, named: "Run Song")
        let bouncePath = plannedArtifactPath(outputRoot: outputRoot, displayName: "Run Song", kind: "bounce")

        let router = await makeExportRouter(bounceSideEffect: {
            try? writeToneWav(at: URL(fileURLWithPath: bouncePath))
        })
        let options = fastOptions(identity: { project.path })

        let run = await ProjectExportExecutor.run(
            params: [
                "projects": .array([.string(project.path)]),
                "output_root": .string(outputRoot.path),
                "artifacts": .array([.string("bounce")]),
                "confirmed": .bool(true),
            ],
            router: router,
            resume: false,
            options: options
        )

        #expect(run.schema == "logic_pro_mcp_export_run.v1")
        #expect(run.confirmed)
        #expect(run.status == "completed")
        #expect(run.artifactsTotal == 1)
        #expect(run.artifactsVerified == 1)
        #expect(run.artifactsFailed == 0)
        #expect(run.artifactsUncertain == 0)

        let runProject = try #require(run.projects.first)
        #expect(runProject.opened)
        #expect(runProject.identityVerified)
        #expect(runProject.observedProjectPath == project.path)

        let artifact = try #require(runProject.artifacts.first)
        #expect(artifact.state == "A")
        #expect(artifact.verified)
        #expect(artifact.bounceFired)
        #expect(artifact.error == nil)
        let evidence = try #require(artifact.evidence)
        #expect(evidence.exists)
        #expect(evidence.fileSizeBytes > 0)
        #expect(evidence.durationSeconds > 0.1)
        #expect(evidence.verificationStatus == "pass")
        #expect(evidence.source == "audio_analyzer")
        // The artifact file actually exists on disk — State A is not fabricated.
        #expect(FileManager.default.fileExists(atPath: bouncePath))
    }

    @Test("resume skips already-present+verified artifacts and produces only the rest")
    func resumeSkipsVerifiedAndCompletesRest() async throws {
        let projDir = try makeExecTempDir()
        let outputRoot = try makeExecTempDir()
        let project = try makeLogicxProject(in: projDir, named: "Resume Song")
        let bouncePath = plannedArtifactPath(outputRoot: outputRoot, displayName: "Resume Song", kind: "bounce")
        let stemPath = plannedArtifactPath(outputRoot: outputRoot, displayName: "Resume Song", kind: "stem")

        // Pre-stage the bounce artifact as a verifiable file — it must be SKIPPED.
        try writeToneWav(at: URL(fileURLWithPath: bouncePath))

        // The bounce route writes whichever artifact is still missing (the stem).
        let router = await makeExportRouter(bounceSideEffect: {
            try? writeToneWav(at: URL(fileURLWithPath: stemPath))
        })
        let options = fastOptions(identity: { project.path })

        let run = await ProjectExportExecutor.run(
            params: [
                "projects": .array([.string(project.path)]),
                "output_root": .string(outputRoot.path),
                // skip_existing so the already-present bounce is not a fail_if_exists collision.
                "collision_policy": .string("skip_existing"),
                "artifacts": .array([.string("bounce"), .string("stem")]),
                "confirmed": .bool(true),
            ],
            router: router,
            resume: true,
            options: options
        )

        #expect(run.mode == "resume")
        #expect(run.status == "completed")
        #expect(run.artifactsTotal == 2)
        #expect(run.artifactsSkipped == 1)
        #expect(run.artifactsVerified == 1)

        let artifacts = try #require(run.projects.first?.artifacts)
        let bounce = try #require(artifacts.first { $0.kind == "bounce" })
        let stem = try #require(artifacts.first { $0.kind == "stem" })
        // The already-present bounce was skipped (State A, no bounce fired).
        #expect(bounce.state == "A")
        #expect(bounce.verified)
        #expect(!bounce.bounceFired)
        #expect(bounce.reason == "skipped_already_verified")
        // The missing stem was produced (State A, bounce fired).
        #expect(stem.state == "A")
        #expect(stem.verified)
        #expect(stem.bounceFired)
    }

    @Test("identity mismatch fails closed and never bounces the wrong project")
    func identityMismatchFailsClosed() async throws {
        let projDir = try makeExecTempDir()
        let outputRoot = try makeExecTempDir()
        let project = try makeLogicxProject(in: projDir, named: "Identity Song")
        let bouncePath = plannedArtifactPath(outputRoot: outputRoot, displayName: "Identity Song", kind: "bounce")

        let bounceFired = BoolFlag()
        let router = await makeExportRouter(bounceSideEffect: {
            bounceFired.set()
            try? writeToneWav(at: URL(fileURLWithPath: bouncePath))
        })
        // Front document reports a DIFFERENT project than the one we planned.
        let options = fastOptions(identity: { "/Users/someone/OtherProject.logicx" })

        let run = await ProjectExportExecutor.run(
            params: [
                "projects": .array([.string(project.path)]),
                "output_root": .string(outputRoot.path),
                "artifacts": .array([.string("bounce")]),
                "confirmed": .bool(true),
            ],
            router: router,
            resume: false,
            options: options
        )

        #expect(run.status == "failed")
        #expect(run.artifactsFailed == 1)
        #expect(run.artifactsVerified == 0)

        let runProject = try #require(run.projects.first)
        #expect(runProject.opened)
        #expect(!runProject.identityVerified)

        let artifact = try #require(runProject.artifacts.first)
        #expect(artifact.state == "C")
        #expect(!artifact.verified)
        #expect(!artifact.bounceFired)
        let error = try #require(artifact.error)
        #expect(error.contains("project_identity_mismatch"))
        // Critically: no bounce was triggered and no file was written.
        #expect(!bounceFired.isSet)
        #expect(!FileManager.default.fileExists(atPath: bouncePath))
    }

    @Test("missing artifact after bounce gives State B (uncertain), not State A")
    func missingArtifactGivesStateB() async throws {
        let projDir = try makeExecTempDir()
        let outputRoot = try makeExecTempDir()
        let project = try makeLogicxProject(in: projDir, named: "Missing Song")

        // Bounce SUCCEEDS at the channel level but writes NOTHING — the artifact
        // never appears. Must NOT be reported as verified.
        let router = await makeExportRouter(bounceSideEffect: { /* intentionally empty */ })
        let options = fastOptions(identity: { project.path })

        let run = await ProjectExportExecutor.run(
            params: [
                "projects": .array([.string(project.path)]),
                "output_root": .string(outputRoot.path),
                "artifacts": .array([.string("bounce")]),
                "confirmed": .bool(true),
            ],
            router: router,
            resume: false,
            options: options
        )

        #expect(run.status == "failed") // nothing reached State A
        #expect(run.artifactsUncertain == 1)
        #expect(run.artifactsVerified == 0)
        let artifact = try #require(run.projects.first?.artifacts.first)
        #expect(artifact.state == "B")
        #expect(!artifact.verified)
        #expect(artifact.bounceFired)
        #expect(artifact.reason == "artifact_not_observed_within_poll_window")
    }

    @Test("silent artifact after bounce gives State B (uncertain), not State A")
    func silentArtifactGivesStateB() async throws {
        let projDir = try makeExecTempDir()
        let outputRoot = try makeExecTempDir()
        let project = try makeLogicxProject(in: projDir, named: "Silent Song")
        let bouncePath = plannedArtifactPath(outputRoot: outputRoot, displayName: "Silent Song", kind: "bounce")

        // Bounce writes a fully-silent WAV — present + non-zero but analysis fails.
        let router = await makeExportRouter(bounceSideEffect: {
            try? writeSilentWav(at: URL(fileURLWithPath: bouncePath))
        })
        let options = fastOptions(identity: { project.path })

        let run = await ProjectExportExecutor.run(
            params: [
                "projects": .array([.string(project.path)]),
                "output_root": .string(outputRoot.path),
                "artifacts": .array([.string("bounce")]),
                "confirmed": .bool(true),
            ],
            router: router,
            resume: false,
            options: options
        )

        #expect(run.artifactsUncertain == 1)
        #expect(run.artifactsVerified == 0)
        let artifact = try #require(run.projects.first?.artifacts.first)
        #expect(artifact.state == "B")
        #expect(!artifact.verified)
        #expect(artifact.bounceFired)
        let reason = try #require(artifact.reason)
        #expect(reason.contains("artifact_unverified"))
        #expect(reason.contains("near_silent_output"))
        let evidence = try #require(artifact.evidence)
        #expect(evidence.silenceRatio >= 0.98)
    }

    @Test("fail_if_exists never overwrites an existing artifact (fails closed)")
    func failIfExistsNeverOverwrites() async throws {
        let projDir = try makeExecTempDir()
        let outputRoot = try makeExecTempDir()
        let project = try makeLogicxProject(in: projDir, named: "Collide Song")
        let bouncePath = plannedArtifactPath(outputRoot: outputRoot, displayName: "Collide Song", kind: "bounce")

        // Pre-existing artifact + default fail_if_exists policy => would_overwrite.
        try writeToneWav(at: URL(fileURLWithPath: bouncePath))
        let originalSize = (try FileManager.default.attributesOfItem(atPath: bouncePath)[.size] as? NSNumber)?.int64Value ?? 0

        let bounceFired = BoolFlag()
        let router = await makeExportRouter(bounceSideEffect: {
            bounceFired.set()
            // If this ran it would overwrite with a longer file — prove it doesn't.
            try? writeToneWav(at: URL(fileURLWithPath: bouncePath), durationSeconds: 1.0)
        })
        let options = fastOptions(identity: { project.path })

        let run = await ProjectExportExecutor.run(
            params: [
                "projects": .array([.string(project.path)]),
                "output_root": .string(outputRoot.path),
                "artifacts": .array([.string("bounce")]),
                // fail_if_exists is the default, set explicitly for clarity.
                "collision_policy": .string("fail_if_exists"),
                "confirmed": .bool(true),
            ],
            router: router,
            resume: false,
            options: options
        )

        #expect(run.status == "failed")
        #expect(run.artifactsFailed == 1)
        #expect(run.artifactsVerified == 0)
        let artifact = try #require(run.projects.first?.artifacts.first)
        #expect(artifact.state == "C")
        #expect(!artifact.verified)
        let error = try #require(artifact.error)
        #expect(error.contains("overwrite_blocked"))
        // No bounce fired and the original file is byte-for-byte untouched.
        #expect(!bounceFired.isSet)
        let afterSize = (try FileManager.default.attributesOfItem(atPath: bouncePath)[.size] as? NSNumber)?.int64Value ?? -1
        #expect(afterSize == originalSize)
    }

    @Test("confirmed:false fails closed with confirmation_required and no side effects")
    func confirmedFalseFailsClosed() async throws {
        let projDir = try makeExecTempDir()
        let outputRoot = try makeExecTempDir()
        let project = try makeLogicxProject(in: projDir, named: "Unconfirmed Song")
        let bouncePath = plannedArtifactPath(outputRoot: outputRoot, displayName: "Unconfirmed Song", kind: "bounce")

        let anyChannelOp = BoolFlag()
        let router = await makeExportRouter(bounceSideEffect: {
            anyChannelOp.set()
            try? writeToneWav(at: URL(fileURLWithPath: bouncePath))
        })
        let options = fastOptions(identity: { project.path })

        let run = await ProjectExportExecutor.run(
            params: [
                "projects": .array([.string(project.path)]),
                "output_root": .string(outputRoot.path),
                "artifacts": .array([.string("bounce")]),
                // confirmed omitted entirely => treated as false.
            ],
            router: router,
            resume: false,
            options: options
        )

        #expect(run.status == "confirmation_required")
        #expect(!run.confirmed)
        #expect(run.artifactsFailed == 1)
        #expect(run.artifactsVerified == 0)
        #expect(run.nextSafeAction == "retry_with_confirmed_true")
        let artifact = try #require(run.projects.first?.artifacts.first)
        #expect(artifact.state == "C")
        #expect(artifact.error == "confirmation_required")
        // No bounce ran and no artifact was written.
        #expect(!anyChannelOp.isSet)
        #expect(!FileManager.default.fileExists(atPath: bouncePath))
    }

    @Test("open failure fails closed and never bounces")
    func openFailureFailsClosed() async throws {
        let projDir = try makeExecTempDir()
        let outputRoot = try makeExecTempDir()
        let project = try makeLogicxProject(in: projDir, named: "Unopenable Song")

        let bounceFired = BoolFlag()
        let router = await makeExportRouter(openSucceeds: false, bounceSideEffect: { bounceFired.set() })
        let options = fastOptions(identity: { project.path })

        let run = await ProjectExportExecutor.run(
            params: [
                "projects": .array([.string(project.path)]),
                "output_root": .string(outputRoot.path),
                "artifacts": .array([.string("bounce")]),
                "confirmed": .bool(true),
            ],
            router: router,
            resume: false,
            options: options
        )

        #expect(run.status == "failed")
        let runProject = try #require(run.projects.first)
        #expect(!runProject.opened)
        #expect(!runProject.identityVerified)
        let artifact = try #require(runProject.artifacts.first)
        #expect(artifact.state == "C")
        let error = try #require(artifact.error)
        #expect(error.contains("open_failed"))
        #expect(!bounceFired.isSet)
    }

    // MARK: - Dispatcher integration

    @Test("dispatcher export_run returns HC-truthful isError on a failed run")
    func dispatcherExportRunIsErrorOnFailure() async throws {
        let projDir = try makeExecTempDir()
        let outputRoot = try makeExecTempDir()
        let project = try makeLogicxProject(in: projDir, named: "Dispatch Song")

        // Identity mismatch => failed run => isError must be true on the wire.
        let router = await makeExportRouter()
        let options = fastOptions(identity: { "/Users/elsewhere/Wrong.logicx" })
        let cache = StateCache()

        let result = await ProjectDispatcher.handle(
            command: "export_run",
            params: [
                "projects": .array([.string(project.path)]),
                "output_root": .string(outputRoot.path),
                "artifacts": .array([.string("bounce")]),
                "confirmed": .bool(true),
            ],
            router: router,
            cache: cache,
            exportOptions: options
        )

        // isError is Bool?; force-unwrap so a nil/false would FAIL (the
        // `== true` form is a swift-testing dead assertion, issue #92).
        #expect(try #require(result.isError))
        let text = sharedToolText(result)
        #expect(text.contains("\"schema\":\"logic_pro_mcp_export_run.v1\""))
        #expect(text.contains("\"status\":\"failed\""))
    }

    @Test("dispatcher export_run rejects invalid params before any execution")
    func dispatcherExportRunRejectsInvalidParams() async throws {
        let router = await makeExportRouter()
        let cache = StateCache()
        let options = fastOptions(identity: { nil })

        // Missing output_root => planner throws => rejected invalid_params.
        let result = await ProjectDispatcher.handle(
            command: "export_run",
            params: [
                "projects": .array([.string("/tmp/nope.logicx")]),
                "confirmed": .bool(true),
            ],
            router: router,
            cache: cache,
            exportOptions: options
        )

        #expect(try #require(result.isError))
        #expect(sharedToolText(result).contains("invalid_params"))
    }

    @Test("dispatcher export_run returns confirmation_required HC envelope when confirmed omitted")
    func dispatcherExportRunConfirmationRequired() async throws {
        let projDir = try makeExecTempDir()
        let outputRoot = try makeExecTempDir()
        let project = try makeLogicxProject(in: projDir, named: "Gate Song")

        let router = await makeExportRouter()
        let options = fastOptions(identity: { project.path })
        let cache = StateCache()

        let result = await ProjectDispatcher.handle(
            command: "export_run",
            params: [
                "projects": .array([.string(project.path)]),
                "output_root": .string(outputRoot.path),
                "artifacts": .array([.string("bounce")]),
            ],
            router: router,
            cache: cache,
            exportOptions: options
        )

        #expect(try #require(result.isError))
        let text = sharedToolText(result)
        #expect(text.contains("\"status\":\"confirmation_required\""))
        #expect(text.contains("\"confirmed\":false"))
    }
}

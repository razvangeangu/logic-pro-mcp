import AVFoundation
import Foundation
import MCP
import Testing
@testable import LogicProMCP

private func writeAudioFixture(
    named name: String,
    sampleRate: Double = 44_100,
    durationSeconds: Double = 0.1,
    channels: AVAudioChannelCount = 2,
    sample: (Int) -> Float
) throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("logicpromcp-audio-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent(name)
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)!
    let frameCount = AVAudioFrameCount(sampleRate * durationSeconds)
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
    buffer.frameLength = frameCount
    let channelData = buffer.floatChannelData!
    for channel in 0..<Int(channels) {
        for frame in 0..<Int(frameCount) {
            channelData[channel][frame] = sample(frame)
        }
    }
    try file.write(from: buffer)
    return url
}

@Test func testAudioAnalyzerValidWAVSchemaAndMeasurements() throws {
    let url = try writeAudioFixture(named: "tone.wav") { frame in
        Float(sin(2.0 * Double.pi * 440.0 * Double(frame) / 44_100.0) * 0.5)
    }

    let result = AudioAnalyzer.analyzeFile(
        path: url.path,
        policy: .init(
            minimumDurationSeconds: 0.05,
            maximumDurationDriftSeconds: nil,
            expectedDurationSeconds: nil,
            minimumFileSizeBytes: 128,
            maximumPeakDbfs: -0.1,
            nearSilenceThresholdDbfs: -60,
            maximumSilenceRatio: 0.98,
            expectedSampleRate: 44_100,
            expectedChannelCount: 2,
            outputRoot: url.deletingLastPathComponent().path
        )
    )

    #expect(result.schema == "logic_pro_mcp_audio_analysis.v1")
    #expect(result.exists)
    #expect(result.format == "wav")
    #expect(result.sampleRate == 44_100)
    #expect(result.channelCount == 2)
    #expect(result.durationSeconds >= 0.09)
    #expect(result.peakDbfs < 0)
    #expect(result.loudnessMethod == "rms_estimate")
    #expect(result.verification.status == .pass)
}

@Test func testAudioAnalyzerRejectsUnsafeAndUnsupportedPaths() throws {
    let relative = AudioAnalyzer.analyzeFile(path: "relative.wav")
    #expect(relative.verification.status == .fail)
    #expect(relative.verification.reasons.contains("unsafe_path"))

    let traversal = AudioAnalyzer.analyzeFile(path: "/tmp/../evil.wav")
    #expect(traversal.verification.status == .fail)
    #expect(traversal.verification.reasons.contains("unsafe_path"))

    let iCloud = AudioAnalyzer.analyzeFile(path: "/Users/test/Library/Mobile Documents/song.wav")
    #expect(iCloud.verification.status == .fail)
    #expect(iCloud.verification.reasons.contains("unsafe_path"))

    let txtURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("logicpromcp-audio-\(UUID().uuidString).txt")
    try Data("not audio".utf8).write(to: txtURL)
    let unsupported = AudioAnalyzer.analyzeFile(path: txtURL.path)
    #expect(unsupported.verification.status == .fail)
    #expect(unsupported.verification.reasons.contains("unsupported_format"))
}

@Test func testAudioAnalyzerPolicyFlagsSilenceClippingAndDuration() throws {
    let silent = try writeAudioFixture(named: "silent.wav") { _ in 0.0 }
    let silentResult = AudioAnalyzer.analyzeFile(path: silent.path)
    #expect(silentResult.verification.status == .fail)
    #expect(silentResult.verification.reasons.contains("near_silent_output"))

    let clipped = try writeAudioFixture(named: "clipped.wav") { _ in 1.0 }
    let clippedResult = AudioAnalyzer.analyzeFile(
        path: clipped.path,
        policy: .init(
            minimumDurationSeconds: 1.0,
            maximumDurationDriftSeconds: nil,
            expectedDurationSeconds: nil,
            minimumFileSizeBytes: nil,
            maximumPeakDbfs: -0.1,
            nearSilenceThresholdDbfs: -60,
            maximumSilenceRatio: 0.98,
            expectedSampleRate: nil,
            expectedChannelCount: nil,
            outputRoot: nil
        )
    )
    #expect(clippedResult.verification.status == .fail)
    #expect(clippedResult.verification.reasons.contains("peak_above_threshold"))
    #expect(clippedResult.verification.reasons.contains("duration_below_minimum"))

    let quiet = try writeAudioFixture(named: "quiet.wav") { _ in 0.01 }
    let quietResult = AudioAnalyzer.analyzeFile(
        path: quiet.path,
        policy: .init(
            minimumDurationSeconds: nil,
            maximumDurationDriftSeconds: nil,
            expectedDurationSeconds: nil,
            minimumFileSizeBytes: nil,
            maximumPeakDbfs: nil,
            nearSilenceThresholdDbfs: -30,
            maximumSilenceRatio: 0.98,
            expectedSampleRate: nil,
            expectedChannelCount: nil,
            outputRoot: nil
        )
    )
    #expect(quietResult.silenceRatio == 1.0)
    #expect(quietResult.verification.reasons.contains("near_silent_output"))
}

@Test func testAudioAnalyzerRejectsOutputRootEscapesAndZeroLength() throws {
    let outside = try writeAudioFixture(named: "outside.wav") { _ in 0.25 }
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("logicpromcp-approved-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let escaped = AudioAnalyzer.analyzeFile(
        path: outside.path,
        policy: .init(
            minimumDurationSeconds: nil,
            maximumDurationDriftSeconds: nil,
            expectedDurationSeconds: nil,
            minimumFileSizeBytes: nil,
            maximumPeakDbfs: nil,
            nearSilenceThresholdDbfs: -60,
            maximumSilenceRatio: 0.98,
            expectedSampleRate: nil,
            expectedChannelCount: nil,
            outputRoot: root.path
        )
    )
    #expect(escaped.verification.status == .fail)
    #expect(escaped.verification.reasons.contains("unsafe_path"))

    let zero = root.appendingPathComponent("zero.wav")
    FileManager.default.createFile(atPath: zero.path, contents: Data())
    let zeroResult = AudioAnalyzer.analyzeFile(path: zero.path)
    #expect(zeroResult.verification.status == .fail)
    #expect(zeroResult.verification.reasons.contains("zero_length_file"))
}

@Test func testAudioDispatcherAnalyzeFileReturnsJSONAndErrorsOnFailedVerification() throws {
    let silent = try writeAudioFixture(named: "dispatcher-silent.wav") { _ in 0.0 }
    let result = AudioDispatcher.handle(
        command: "analyze_file",
        params: ["path": .string(silent.path)]
    )
    #expect(try #require(result.isError))
    let json = try #require(sharedJSONObject(sharedToolText(result)))
    #expect(json["schema"] as? String == "logic_pro_mcp_audio_analysis.v1")
    let verification = try #require(json["verification"] as? [String: Any])
    #expect(verification["status"] as? String == "fail")
}

import Foundation
import MCP

struct AudioDispatcher {
    static let tool = commandTool(
        name: "logic_audio",
        description: "Read-only audio artifact analysis for post-bounce/export verification. Commands: analyze_file. Params: analyze_file -> { path: absolute audio file path, output_root?: absolute allowlist root, min_duration_seconds?: number, expected_duration_seconds?: number, max_duration_drift_seconds?: number, min_file_size_bytes?: int, max_peak_dbfs?: number, near_silence_dbfs?: number, max_silence_ratio?: number, expected_sample_rate?: int, expected_channel_count?: int }. Returns schema logic_pro_mcp_audio_analysis.v1 and never mutates files or Logic Pro.",
        commandDescription: "Audio command to execute"
    )

    static func handle(
        command: String,
        params: [String: Value],
        runtime: AudioAnalyzer.Runtime = .production
    ) -> CallTool.Result {
        switch command {
        case "analyze_file":
            let path = stringParam(params, "path")
            guard !path.isEmpty else {
                let result = AudioAnalyzer.analyzeFile(path: "", policy: .default, runtime: runtime)
                return toolTextResult(encodeJSON(result), isError: true)
            }

            let policy = policy(from: params)
            let result = AudioAnalyzer.analyzeFile(path: path, policy: policy, runtime: runtime)
            return toolTextResult(
                encodeJSON(result),
                isError: result.verification.status == .fail
            )

        default:
            return toolTextResult(
                "Unknown audio command: \(command). Available: analyze_file",
                isError: true
            )
        }
    }

    private static func policy(from params: [String: Value]) -> AudioAnalyzer.AnalysisPolicy {
        var policy = AudioAnalyzer.AnalysisPolicy.default
        policy.minimumDurationSeconds = doubleParamOrNil(params, "min_duration_seconds", "minimum_duration_seconds")
        policy.expectedDurationSeconds = doubleParamOrNil(params, "expected_duration_seconds")
        policy.maximumDurationDriftSeconds = doubleParamOrNil(params, "max_duration_drift_seconds", "maximum_duration_drift_seconds")
        policy.minimumFileSizeBytes = intParamOrNil(params, "min_file_size_bytes", "minimum_file_size_bytes")
        policy.maximumPeakDbfs = doubleParamOrNil(params, "max_peak_dbfs", "maximum_peak_dbfs")
        policy.expectedSampleRate = intParamOrNil(params, "expected_sample_rate")
        policy.expectedChannelCount = intParamOrNil(params, "expected_channel_count")
        policy.outputRoot = params["output_root"]?.stringValue

        if let nearSilence = doubleParamOrNil(params, "near_silence_dbfs", "near_silence_threshold_dbfs") {
            policy.nearSilenceThresholdDbfs = nearSilence
        }
        if let maxSilenceRatio = doubleParamOrNil(params, "max_silence_ratio", "maximum_silence_ratio") {
            policy.maximumSilenceRatio = min(max(maxSilenceRatio, 0.0), 1.0)
        }
        return policy
    }
}

# PRD: Audio Analysis Foundation

**Issue**: #29 Export verification: post-bounce audio analysis
**Status**: Approved / Implemented
**Date**: 2026-06-20
**Size**: M

## Problem

LogicProMCP can drive export workflows, but it did not have a local, machine-checkable way to inspect the bounced audio artifact afterward. Users need a read-only verification surface that can confirm an exported file exists, decodes, is not silent, and roughly matches expected export constraints without claiming higher precision than the implementation supports.

## Goals

- Add a read-only `logic_audio` MCP tool with `analyze_file`.
- Return a stable JSON schema for local audio artifacts.
- Enforce path safety: absolute paths only, no traversal, no iCloud paths, and optional `output_root` allowlisting after symlink resolution.
- Measure file size, duration, sample rate, channel count, frame count, peak dBFS, RMS dBFS, silence ratio, and non-silent duration.
- Evaluate caller-provided verification policy and fail closed with structured reasons.
- Document that loudness is an RMS estimate, not true LUFS/true-peak/spectral analysis.

## Non-Goals

- Starting, controlling, or mutating Logic Pro.
- Performing the bounce/export action itself.
- Claiming integrated LUFS, true peak, spectral centroid, or frequency peak accuracy before those analyzers exist.
- Reading cloud-only or remote placeholder files.

## Acceptance Criteria

- `logic_audio analyze_file` is listed in the server tool catalog and dispatches without requiring the server to start transports.
- Unsafe paths, missing files, directories, unsupported formats, and zero-byte files return schema-valid failures.
- A valid WAV fixture returns schema `logic_pro_mcp_audio_analysis.v1` with pass/fail verification.
- Silent, clipped, too-short, size-mismatched, sample-rate-mismatched, and channel-count-mismatched outputs can be detected through policy reasons.
- Public README/API/architecture docs describe the new surface and its honesty limits.

## Verification

- `swift test --filter AudioAnalyzer`
- `swift test --filter LogicProServerTransport`
- `swift test --filter LogicProServerHandler`
- `swift test --filter EndToEnd`
- `swift test --filter VersionConsistency`

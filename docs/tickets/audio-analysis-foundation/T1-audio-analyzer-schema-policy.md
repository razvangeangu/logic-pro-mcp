# T1: Audio Analyzer Schema And Policy

**Status**: Done
**Issue**: #29

## Scope

Implement the read-only audio artifact analyzer behind `logic_audio analyze_file`.

## Acceptance Criteria

- Absolute-path validation rejects relative paths, traversal, iCloud paths, missing files, directories, unsupported extensions, and zero-byte files.
- Optional `output_root` is enforced after symlink resolution.
- Successful analysis returns `logic_pro_mcp_audio_analysis.v1`.
- Measurements include duration, sample rate, channels, frame count, file size, RMS dBFS, peak dBFS, silence ratio, and non-silent duration.
- Verification policies emit structured fail reasons instead of free-form success claims.

## Verification

- `swift test --filter AudioAnalyzer`

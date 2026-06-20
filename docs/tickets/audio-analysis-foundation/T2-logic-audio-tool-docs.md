# T2: logic_audio Tool And Public Docs

**Status**: Done
**Issue**: #29

## Scope

Expose the analyzer through the MCP tool catalog and document the public API.

## Acceptance Criteria

- `logic_audio` is registered with the server tool list and dispatcher switch.
- Help text and server catalog counts include ten tools.
- README, API docs, architecture docs, and consistency tests mention the read-only audio surface.
- Public docs state that loudness is an RMS estimate and true peak/LUFS/spectral claims are not made.

## Verification

- `swift test --filter LogicProServerTransport`
- `swift test --filter LogicProServerHandler`
- `swift test --filter EndToEnd`
- `swift test --filter VersionConsistency`
